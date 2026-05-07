# Realtime Recording Stability And Aspect Spec

## 背景

当前双摄录制已从双 `AVCaptureMovieFileOutput` 二次合成切到 `AVCaptureVideoDataOutput + AVCaptureAudioDataOutput + AVAssetWriter` 实时合成。用户反馈两个问题：

1. 点击结束录制时，有时候保存成功，有时候失败，错误表现为 `The operation could not be completed`。
2. 成片整体固定为 9:16，切换 `1:1`、`3:4` 等比例不生效。

本 spec 只设计修复方案，不直接写实现代码。

## 代码分析结论

### 1. 录制失败的主要风险点

当前 `finishRealtimeRecording` 在停止时立即：

- 设置 `realtimeFinishRequested = YES`
- 设置 `isDualRecordingActive = NO`
- 取出 writer/input/path
- 清空 `self.realtimeAssetWriter/realtimeVideoInput/realtimeAudioInput/realtimePixelBufferAdaptor`
- 调用 `markAsFinished`
- 调用 `finishWriting`

这条路径有几个问题：

1. Writer 是懒启动的。
   - `ensureRealtimeWriterStartedAtTime` 由音频或视频 sample 触发。
   - 如果用户开始录制后很快停止，writer 可能还是 `AVAssetWriterStatusUnknown`。
   - 当前这种情况会直接报 `No video frames were recorded.`。

2. 音频可能先启动 writer。
   - `appendRealtimeAudioSampleBuffer` 和 `appendRealtimeVideoFrameAtTime` 都会调用 `ensureRealtimeWriterStartedAtTime`。
   - 如果第一个到达的是音频，writer session 会以音频时间戳启动。
   - 但视频合成要求 front/back 两路最新帧都存在；在两路帧没准备好时，`compositedImageForLayoutState` 返回 nil。
   - 结果可能出现 writer 已经写过音频，但没有成功写入任何视频帧。结束时带视频 input 的 mp4 容易失败。

3. 没有记录已写入视频帧数量。
   - 当前只记录 dropped frame。
   - 停止时无法区分“writer 已启动但没有视频帧”、“writer 已写过视频帧”、“writer 已失败”。

4. append 失败没有统一转入失败状态。
   - 视频 append 失败只 `NSLog`，没有取消 writer 或上报明确错误。
   - 音频 append 的返回值没有检查。

5. 停止流程缺少状态机。
   - 现在使用多个 BOOL 拼状态：`isDualRecordingActive/realtimeWriterStarted/realtimeFinishRequested`。
   - 缺少明确状态：idle / prepared / writing / finishing / failed。
   - 连续点击停止、快速开始后停止、sample callback 和 stop callback 交错时，容易进入不可预期状态。

6. `finishWriting` 前过早清空 self 上的 writer/input 引用。
   - block 内虽然捕获了局部变量，通常可工作，但状态观察、错误恢复、重复 stop 防抖都会变困难。
   - 更稳妥的是进入 finishing 状态后保留上下文，finish callback 完成后统一清理。

### 2. 比例不生效的直接原因

当前实时录制输出尺寸写死：

```objc
- (CGSize)realtimeRecordingOutputSize {
  return CGSizeMake(1080, 1920);
}
```

所以无论 JS 传入 `saveAspectRatio` 是 `9:16`、`3:4` 还是 `1:1`，视频 writer 都永远创建 1080x1920 的像素缓冲池和视频轨。

同时：

- `App.js` 已经把 `saveAspectRatio={saveAspectRatio}` 传给 `NativeDualCameraView`。
- `DualCameraView.m` 的拍照路径使用了 `saveAspectRatio`。
- 旧的 `compositeDualVideosForCurrentLayout` 也有按 `saveAspectRatio` 算 canvas 的逻辑。
- 新的实时录制路径没有使用 `saveAspectRatio`。

因此该问题不是 JS 没传值，而是实时录制输出尺寸没有接入该属性。

### 3. 额外发现：预览布局迁移不完整

当前 `updateLayout` 中已有 `currentLayoutStateForCanvasSize` 和 `rectsForLayoutState` helper，但 `updateLayout` 仍在手写 LR/SX/PiP 布局。

更严重的是，`pip_circle` 分支引用了 `frontRect.size.width` 和 `backRect.size.width`，但 `updateLayout` 作用域里没有定义 `frontRect/backRect`。这属于编译级风险，必须在同一次修复中处理。

## 推荐修复方案

### 目标

只做稳定性和比例修复，不扩大到滤镜、码率配置、Metal 优化或 UI 大改。

### 1. 引入明确的实时录制状态机

新增枚举：

```objc
typedef NS_ENUM(NSInteger, DualCameraRealtimeRecordingState) {
  DualCameraRealtimeRecordingStateIdle,
  DualCameraRealtimeRecordingStatePrepared,
  DualCameraRealtimeRecordingStateWriting,
  DualCameraRealtimeRecordingStateFinishing,
  DualCameraRealtimeRecordingStateFailed
};
```

替代主要状态判断：

- `Idle`：未录制
- `Prepared`：writer 已创建，等待第一帧视频
- `Writing`：至少成功写入一帧视频
- `Finishing`：已收到停止，等待 writer 完成
- `Failed`：writer 或 append 出错，等待清理

保留 `isDualRecordingActive` 可以作为对外兼容布尔值，但内部判断以枚举为准。

### 2. 只允许视频帧启动 writer

修改规则：

- `appendRealtimeAudioSampleBuffer` 不再调用 `ensureRealtimeWriterStartedAtTime`。
- 音频样本只有在状态为 `Writing` 后才 append。
- `appendRealtimeVideoFrameAtTime` 在拿到可合成的 front/back 帧后，才调用 `startWriting/startSessionAtSourceTime`。
- 第一帧视频 append 成功后，状态进入 `Writing`，并记录 `realtimeWrittenVideoFrameCount += 1`。

这样可以避免“音频先启动、视频 0 帧”的不稳定 mp4。

### 3. 停止时按状态处理

`finishRealtimeRecording` 规则：

- `Idle`：忽略重复 stop。
- `Prepared`：说明还没有成功写入视频帧，直接 `cancelWriting`，上报“录制时间太短或视频帧尚未准备好”。
- `Writing`：进入 `Finishing`，`markAsFinished` 后 `finishWriting`。
- `Finishing`：忽略重复 stop。
- `Failed`：取消 writer 并清理。

停止时不要立刻清空 writer/input/adaptor。应在 `finishWriting` callback 或 cancel 后统一调用 `resetRealtimeRecordingContext`。

### 4. 检查 append 返回值

- 视频 append 失败：记录 writer error，进入 `Failed`，停止继续写入。
- 音频 append 失败：如果 writer 已 failed，进入 `Failed`；否则只计数并继续。
- 如果 `writer.status == AVAssetWriterStatusFailed`，停止所有 append 并上报 `writer.error.localizedDescription`。

### 5. 输出尺寸按 saveAspectRatio 计算

替换固定尺寸：

```objc
- (CGSize)realtimeRecordingOutputSizeForAspectRatio:(NSString *)aspectRatio {
  CGFloat refW = 1080.0;
  if ([aspectRatio isEqualToString:@"9:16"]) return CGSizeMake(1080, 1920);
  if ([aspectRatio isEqualToString:@"3:4"]) return CGSizeMake(1080, 1440);
  if ([aspectRatio isEqualToString:@"1:1"]) return CGSizeMake(1080, 1080);
  return CGSizeMake(1080, 1920);
}
```

在 `startRealtimeRecordingWithCanvasSize` 中冻结：

- `realtimeRecordingAspectRatio = self.saveAspectRatio ?: @"9:16"`
- `realtimeOutputSize = [self realtimeRecordingOutputSizeForAspectRatio:realtimeRecordingAspectRatio]`

后续创建 writer、pixel buffer pool、layout state 都使用冻结的 `realtimeOutputSize`，不要在录制中继续读取可变的 `self.saveAspectRatio`。

### 6. 统一 preview 和 recording 的布局 helper

`updateLayout` 应真正使用 `rectsForLayoutState`：

- 先计算 `canvas = [self canvasBoundsForAspectRatio]`
- 对 helper 传入 `canvas.size`
- helper 返回的是 canvas-local rect
- updateLayout 负责把 rect origin 加上 canvas origin

这样：

- 比例切换时预览画布和录制画布都来自同一个 aspect policy。
- PiP 圆角用 helper 返回的小窗 rect，不再引用未定义的 `frontRect/backRect`。

### 7. JS 状态同步建议

当前 `App.js` 在调用 `DualCameraModule.startRecording()` 后立即 `setRecording(true)`。这会导致原生还没有真正写入第一帧时，UI 已经进入录制状态。

为了稳定交互，建议新增原生事件：

- `onRecordingStarted`
- `onRecordingStopping` 可选

短期如果不加事件，至少要：

- stop 按钮点击后立即禁用，直到 `onRecordingFinished/onRecordingError`。
- 避免用户连续多次触发 `stopRecording`。

## 验证矩阵

### 录制稳定性

- 开始录制后 0.2 秒内停止：应失败但错误明确，不应返回通用 `The operation could not be completed`。
- 开始录制后 1 秒停止：应稳定成功。
- 连续点击停止按钮：只处理一次，不重复 `finishWriting`。
- 前后摄像头帧未准备好时点击录制：应等待第一帧视频，不应音频先生成坏文件。
- writer append 失败：应 emit 明确错误并清理状态。

### 比例

- `9:16`：输出 `1080x1920`。
- `3:4`：输出 `1080x1440`。
- `1:1`：输出 `1080x1080`。
- 录制中切换比例按钮不可见或不生效，成片使用开始录制时冻结的比例。

### 布局

- `pip_circle` 可以编译，不再引用未定义变量。
- LR/SX/PiP 的预览矩形来自同一 helper。
- PiP 圆角只作用于小窗，不影响主画面。

## Target File List

- `my-app/native/LocalPods/DualCamera/DualCameraView.m`
- `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.h`
- `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.m`
- `my-app/App.js`
