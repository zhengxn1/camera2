# 双摄拍照后置模糊与美颜误判修复规格书

## 目标
- 确认并修复双摄拍照保存时“上半部分后置画面模糊、像被美颜处理”的问题。
- 保证美颜只作用于前置画面：前置独立图、合成图里的前置区域、前置视频帧可以美颜；后置独立图、合成图里的后置区域、后置视频帧绝不进入美颜处理。
- 让双摄拍照保存质量从低清视频帧升级为高质量照片帧；视频录制仍保留实时视频帧合成。
- 增加明确日志，能一次判断当前运行包是否包含最新 native 代码、后置是否进了美颜、照片来源是高质量 PhotoOutput 还是 fallback 视频帧。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h` | 增加双摄照片捕获上下文、前后置 photo result 缓存、超时/回退状态。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.h` | 声明新的双摄高质量照片捕获/合成辅助方法。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m` | 将双摄拍照从 `latestFrontFrame/latestBackFrame` 视频帧优先，改为 `AVCapturePhotoOutput` 前后置照片优先；保留视频帧 fallback；补充质量与路由日志。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.h` | 保持 cameraSource-aware 美颜接口，必要时补充照片来源参数。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m` | 继续强制只对 front 调用美颜；后置 path 输出 `beauty=never`；避免合成后整体调色/柔化。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m` | 复查录制合成后是否还有全画面滤镜或曝光调整；保持后置不美颜。 |
| `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.h` | 若照片三份保存仍需要 `uris`，保持事件声明兼容。 |
| `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.m` | 若高质量双摄照片生成三张，事件继续返回 `uri` + `uris`。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView_Internal.h` | 同步 Xcode 当前编译副本。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Capture.h` | 同步 Xcode 当前编译副本。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Capture.m` | 同步 Xcode 当前编译副本。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.h` | 同步 Xcode 当前编译副本。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.m` | 同步 Xcode 当前编译副本。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Recording.m` | 同步 Xcode 当前编译副本。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraEventEmitter.h` | 同步 Xcode 当前编译副本。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraEventEmitter.m` | 同步 Xcode 当前编译副本。 |
| `my-app/src/hooks/useDualCameraSession.ts` | 确认照片 `uris` 保存逻辑仍兼容三份保存。 |
| `.ai/project.md` | 记录本次照片质量与美颜路由结论。 |

## 当前判断
- 截图不能直接证明后置被美颜。当前源码里后置路径已经有 `cameraSource=back beauty=never` 保护，`beautifiedImage` 对非 front 会直接返回原图。
- 截图更符合“双摄拍照使用视频帧保存”的表现：`internalTakePhoto` 在双摄布局下会进入 `captureWysiwygDualPhotoWithCanvasSize`，该方法读取 `latestFrontFrame/latestBackFrame`，这些帧来自 `AVCaptureVideoDataOutput`，不是高质量 `AVCapturePhotoOutput`。
- `AVCaptureVideoDataOutput` 的帧适合实时预览/录制合成，但不适合拍显示器细字、强背光、高反差场景的静态照片。上半部分显示器过亮、文字细、容易触发自动曝光和运动/刷新模糊，所以保存图会显得“糊”和“发白”。
- 截图里只看到 `[BeautyJS]`，没有当前 native 代码应打印的 `[BeautyRoute]` 或 `[BeautyProcess]`，因此还要先确认真机运行的是最新 native 构建。否则会把旧包行为误认为当前代码行为。

## 契约设计
- **数据**：
  - 新增内部照片来源枚举语义：`photoOutput`、`videoFrameFallback`。
  - 双摄照片上下文保存：layout snapshot、canvas size、save mode、front photo image、back photo image、timeout timer。
  - 事件继续兼容旧字段：`uri` 指向合成图；`uris.combined/front/back` 用于三份保存。
- **接口**：
  - JS/Native public prop 不变。
  - `onPhotoSaved` payload 不破坏旧逻辑。
  - 日志契约：
    - `[PhotoQuality] output=front source=photoOutput size=...`
    - `[PhotoQuality] output=back source=photoOutput size=...`
    - `[PhotoQuality] output=combined source=photoOutput layout=...`
    - fallback 时必须打印 `[PhotoQuality] fallback source=videoFrame reason=...`
    - 后置必须打印 `[BeautyRoute] source=photo output=back cameraSource=back beauty=never`
- **界面**：
  - 不改 UI。
  - 不改美颜滑杆。
  - 不改三份保存入口。

## 实施步骤
1. 在 `internalTakePhoto` 中区分照片和视频：
   - 双摄拍照优先启动 front/back 两个 `AVCapturePhotoOutput`。
   - 单摄继续使用现有 `AVCapturePhotoOutput`。
   - 实时视频录制继续使用 `AVCaptureVideoDataOutput`，不跟照片改造绑定。
2. 新增双摄照片捕获上下文：
   - 拍照前冻结当前 layout/orientation/mirror/save mode。
   - 分别标记 front/back photo output 的回调结果。
   - 两路都返回后进入同一个合成函数。
3. 合成高质量双摄照片：
   - front photo 转 `CIImage` 后按 `cameraSource=front` 进入美颜。
   - back photo 转 `CIImage` 后按 `cameraSource=back` 保持原图。
   - 复用当前 `layoutStateSnapshotForCanvasSize` 和 `compositedImageForLayoutState`，保证布局、比例、镜像与现有保存语义一致。
4. 三份保存：
   - `combined`：高质量前后置 photo 合成。
   - `front`：高质量 front photo，按前置保存语义镜像/美颜。
   - `back`：高质量 back photo，禁止美颜。
   - 当前保存模式是 `combined` 时只发合成图；`all3` 时发三张。
5. fallback 策略：
   - 如果某一路 `AVCapturePhotoOutput` 不可用、回调失败或超时，再退回当前 `latestFrontFrame/latestBackFrame` 视频帧路径。
   - fallback 必须打印原因，不能静默降级。
6. 清理误导性路径：
   - 确认照片合成后没有全画面 `CIColorControls`、曝光、柔化、GPUPixel 后处理。
   - 录制路径如果保留 post composite 调整，也必须为 disabled 或仅日志说明 `beauty=not_applied`。
7. 同步 native 源头和 Xcode 编译副本：
   - 先改 `native/LocalPods/DualCamera`。
   - 再同步到 `ios/LocalPods/DualCamera`。
   - 不允许只改一边。

## 验证方式
- 静态检查：
  - `rg "PhotoQuality|BeautyRoute|cameraSource:@\"back\"|captureWysiwygDualPhotoWithCanvasSize|AVCapturePhotoOutput" native/LocalPods/DualCamera ios/LocalPods/DualCamera`
  - `diff -qr native/LocalPods/DualCamera ios/LocalPods/DualCamera`
- TypeScript：
  - `npx tsc --noEmit`
- iOS 编译：
  - `xcodebuild -workspace ios/KIRO.xcworkspace -scheme KIRO -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 真机验证：
  - Xcode 控制台必须出现 `[PhotoQuality] output=back source=photoOutput`。
  - Xcode 控制台必须出现 `[BeautyRoute] source=photo output=back cameraSource=back beauty=never`。
  - 拍同一台显示器：后置上半部分文字清晰度应明显高于旧版视频帧保存。
  - 如果仍过曝但不糊，说明是自动曝光/对焦问题，不是美颜问题；后续单独做后置 AE/AF 锁定或点击对焦。
  - 美颜开启时：前置区域有效，后置区域无磨皮/美白/泛白处理。
  - 美颜关闭时：前置和后置都走原始图。

## 回滚方案
- 如果双路 `AVCapturePhotoOutput` 在 MultiCam 真机不稳定：
  - 保留 fallback 视频帧路径。
  - 用 feature flag 临时关闭高质量双摄照片。
  - 不回滚后置美颜隔离日志和 `cameraSource` 防线。

## 目标编辑文件清单
- `my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m`
- `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.h`
- `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView_Internal.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Capture.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Capture.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Recording.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraEventEmitter.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraEventEmitter.m`
- `my-app/src/hooks/useDualCameraSession.ts`
- `.ai/project.md`
