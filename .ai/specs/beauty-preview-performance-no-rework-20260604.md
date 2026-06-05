# 前置美颜预览性能与变形修复技术规格书

## 目标
- 不返工当前美颜 UI、保存三份逻辑、前置美颜参数和整体 Core Image/Vision 管线。
- 修复美颜开启后预览卡顿、拖动布局时人脸变形、以及用户感知的“多层/残影”问题。
- 保持预览和保存使用同一套美颜参数与同一套处理函数，但不再在采集回调中同步处理全分辨率美颜帧。

## 影响范围
| 文件 | 原因 |
|---|---|
| `native/LocalPods/DualCamera/DualCameraView_Internal.h` | 增加 raw front frame、preview beauty frame、beauty processing queue、节流/忙碌状态、预览目标尺寸等状态。 |
| `native/LocalPods/DualCamera/DualCameraView.m` | 初始化新的 beauty 队列和状态，布局变化时延长 plump 跳过窗口。 |
| `native/LocalPods/DualCamera/DualCameraView+Capture.m` | 前置 sample 回调只保存 raw frame 并调度异步美颜，不再同步执行全分辨率 `beautifiedFrontImage`。 |
| `native/LocalPods/DualCamera/DualCameraView+Composition.m` | 支持预览低分辨率处理模式；布局变化期间稳定跳过 plump；Vision 检测不阻塞采集线程。 |
| `native/LocalPods/DualCamera/DualCameraView+Layout.m` | 渲染 Metal 预览时使用已处理好的 preview beauty frame；主线程只做 view/drawable 管理，避免重处理。 |
| `native/LocalPods/DualCamera/DualCameraView+Recording.m` | 录制/保存路径按需要在 render queue 使用美颜帧或同步处理，但不能阻塞 capture callback。 |
| `ios/LocalPods/DualCamera/*` 对应文件 | 同步 canonical native 源码到 Xcode 实际编译副本。 |

## 契约设计
- **数据**：
  - `latestRawFrontFrame`：采集线程保存的原始前置帧。
  - `latestFrontFrame`：保存/录制可使用的已美颜前置帧，兼容现有代码。
  - `latestBeautyPreviewFrame`：预览专用已美颜帧，尺寸按预览目标降采样。
  - `beautyProcessingInFlight`：防止堆积任务；新帧到来时只保留最新帧。
  - `lastBeautyStableLayoutTime`：布局变化后的稳定时间点，用于跳过 plump。
- **接口**：
  - JS/native prop 不变：`frontBeautyEnabled`、`frontBeautySmooth`、`frontBeautyWhiten`、`frontBeautyEven`、`frontBeautyPlump`。
  - 事件结构不变，照片/视频保存逻辑不变。
- **界面**：
  - 不改 UI。
  - 美颜预览仍显示在 `frontPreviewView` 内的 Metal layer。

## 实施步骤
1. 将 `captureOutput` 中的前置帧处理改为轻量路径：立即保存 raw front frame，不在采集回调里同步跑 `beautifiedFrontImage`。
2. 新增串行 `beautyProcessingQueue`：
   - 前置 sample 到来后，如果当前没有 beauty 任务在跑，取最新 raw frame 进入处理。
   - 如果任务正在跑，只更新 latest raw frame，不排队多个旧任务。
3. 预览美颜使用降采样目标：
   - 以 `beautyPreviewView.drawableSize` 为目标，最长边限制在 720 或 960。
   - 先把 raw frame 按预览尺寸 prepared，再跑美颜，降低 Vision/Core Image 压力。
4. 保存/录制路径不阻塞采集：
   - 录制优先使用最近的 `latestFrontFrame`。
   - 如果保存照片时需要最高质量，可以在拍照/保存队列里对单张 raw frame 做高质量美颜。
5. 将 `renderBeautyPreviewIfNeeded` 改为只渲染 `latestBeautyPreviewFrame`，不在主线程里重新做 `preparedCameraImage` + 美颜。
6. 修正 plump 布局策略：
   - 布局比例拖动期间和最后一次布局变化后至少 0.8 秒内，预览跳过 plump。
   - 不在 `beautifiedFrontImage` 内直接清空 `beautyLayoutChanging`；由布局稳定计时统一清理。
7. 保留 `[BeautyProbe]`，但节流日志，避免日志本身影响性能。
8. 同步修改 `native/LocalPods/DualCamera` 与 `ios/LocalPods/DualCamera`。

## 验证方式
- `npx tsc --noEmit`
- `diff -q native/LocalPods/DualCamera/DualCameraView+Capture.m ios/LocalPods/DualCamera/DualCameraView+Capture.m`
- `diff -q native/LocalPods/DualCamera/DualCameraView+Composition.m ios/LocalPods/DualCamera/DualCameraView+Composition.m`
- `diff -q native/LocalPods/DualCamera/DualCameraView+Layout.m ios/LocalPods/DualCamera/DualCameraView+Layout.m`
- `xcodebuild -workspace ios/KIRO.xcworkspace -scheme KIRO -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 真机日志验证：
  - 首屏不再出现持续 `beautyMs > 100ms`。
  - 稳定后 `FrameGap` 不应持续出现。
  - 稳定后 `renderMs` 应大多低于 16-25ms，偶发低于 33ms。
  - 拖动布局时不再出现 `[BeautyProbe][PlumpDuringLayout]`。
  - 不应出现 `[BeautyProbe][LayerConflict]` 和 `[BeautyProbe][AspectMismatch]`。

## 回滚方案
- 回滚本规格涉及的异步 beauty queue 和 preview frame 改动，恢复当前同步 capture 回调处理。
- 保留或删除 `[BeautyProbe]` 均可，不影响业务功能。

## 目标编辑文件清单
- `native/LocalPods/DualCamera/DualCameraView_Internal.h`
- `native/LocalPods/DualCamera/DualCameraView.m`
- `native/LocalPods/DualCamera/DualCameraView+Capture.m`
- `native/LocalPods/DualCamera/DualCameraView+Composition.m`
- `native/LocalPods/DualCamera/DualCameraView+Layout.m`
- `native/LocalPods/DualCamera/DualCameraView+Recording.m`
- `ios/LocalPods/DualCamera/DualCameraView_Internal.h`
- `ios/LocalPods/DualCamera/DualCameraView.m`
- `ios/LocalPods/DualCamera/DualCameraView+Capture.m`
- `ios/LocalPods/DualCamera/DualCameraView+Composition.m`
- `ios/LocalPods/DualCamera/DualCameraView+Layout.m`
- `ios/LocalPods/DualCamera/DualCameraView+Recording.m`
