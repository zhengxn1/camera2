# 前置美颜预览布局版本修复技术规格书

## 目标
- 修复美颜开启后前置预览在上下分屏卡顿、左右分屏出现左右两幅画面、画中画出现大中小嵌套的问题。
- 不重写美颜算法，不重做三份保存，不改变当前 JS UI 和参数协议。
- 只收敛原生预览层生命周期：让 Metal 美颜预览帧只能在“当前布局、当前尺寸、当前镜像状态”下显示；布局变化时立即回退原始 `AVCaptureVideoPreviewLayer`，等待新美颜帧稳定后再切回 Metal 层。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h` | 增加美颜预览帧的布局版本、尺寸、布局模式、镜像元数据，以及渲染队列/防重入状态。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | 初始化新增状态；布局/比例/PiP/翻转/美颜开关变化时让旧美颜预览帧失效。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Layout.m` | 修改 `shouldShowBeautyPreview` 和渲染闸门，只显示当前版本帧；布局变化期间隐藏 Metal 层并显示原始前置预览层。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m` | 异步生成美颜预览帧时捕获布局版本和目标尺寸；处理完成后只发布仍然匹配当前版本的结果。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Gestures.m` | PiP 拖动/缩放时标记布局变化，避免拖动过程中旧 Metal 帧嵌套显示。 |
| `my-app/ios/LocalPods/DualCamera/...` | 同步上述 native LocalPods 修改到 Xcode 实际编译副本。 |
| `my-app/.ai/project.md` | 记录本次架构约束和验证结果。 |

## 契约设计
- **数据**：
  - 新增 `beautyLayoutGeneration: NSInteger`，每次前置预览区域可能变化时递增。
  - 新增 `latestBeautyPreviewGeneration: NSInteger`，记录当前 `latestBeautyPreviewFrame` 对应的布局版本。
  - 新增 `latestBeautyPreviewLayoutMode: NSString *`，记录生成美颜预览帧时的布局。
  - 新增 `latestBeautyPreviewTargetSize: CGSize`，记录生成美颜预览帧时的 drawable/目标尺寸。
  - 新增 `latestBeautyPreviewMirrored: BOOL`，记录生成帧时的前置镜像状态。
  - 可选新增 `beautyRenderingInFlight: BOOL` 和 `beautyRenderQueue`，用于避免主线程连续同步渲染。
- **接口**：
  - JS/native props 不变：`frontBeautyEnabled`、`frontBeautySmooth`、`frontBeautyWhiten`、`frontBeautyEven`、`frontBeautyPlump` 继续沿用。
  - 保存事件、拍照、录制协议不变。
- **界面**：
  - 布局切换、比例拖动、PiP 拖动/缩放时，短暂显示原始前置预览；新版本美颜帧到达后自动切回美颜预览。
  - 不允许同时显示原始前置预览层和 Metal 美颜层。
  - 不允许 Metal 美颜层显示旧布局帧。

## 根因判断
1. 当前 `shouldShowBeautyPreview` 只判断 `latestBeautyPreviewFrame != nil`，没有判断该帧是否对应当前 `layoutMode`、`frontPreviewView.bounds`、`drawableSize`、`pipMainIsBack`、`sxBackOnTop`、镜像状态。
2. `scheduleFrontBeautyProcessingIfNeeded` 使用当时的 `beautyPreviewTargetSize` 生成预览帧，但结果发布时没有检查布局是否已经变化。
3. `renderBeautyPreviewIfNeeded` 会把任意 `latestBeautyPreviewFrame` 拉伸到当前 drawable。布局切换后，旧的上下分屏/PiP 尺寸帧可能被拉伸进左右分屏或 PiP 区域，表现为左右两幅画面、画中画多层嵌套。
4. `renderBeautyPreviewIfNeeded` 仍在主线程取 drawable 并调用 Core Image render；布局变化期间频繁执行会造成前置预览卡顿。
5. PiP 拖动/缩放目前主要更新 view frame，但没有让旧美颜帧立即失效，所以拖动过程中最容易出现残影和嵌套。

## 实施步骤
1. 在 `DualCameraView_Internal.h` 增加美颜预览元数据：
   - `beautyLayoutGeneration`
   - `latestBeautyPreviewGeneration`
   - `latestBeautyPreviewLayoutMode`
   - `latestBeautyPreviewTargetSize`
   - `latestBeautyPreviewMirrored`
   - 可选 `beautyRenderQueue`、`beautyRenderingInFlight`
2. 在 `DualCameraView.m` 增加一个内部方法或内联逻辑：布局相关属性变化时执行 `invalidateBeautyPreviewForLayoutChange`：
   - `beautyLayoutGeneration += 1`
   - `beautyLayoutChanging = YES`
   - `lastBeautyLayoutChangeTime = CACurrentMediaTime()`
   - `latestBeautyPreviewFrame = nil`
   - `latestBeautyPreviewGeneration = -1`
   - 主线程上隐藏 `beautyPreviewView`，显示 `frontPreviewLayer`
3. 所有会改变前置预览区域的路径都调用失效逻辑：
   - `setLayoutMode`
   - `setDualLayoutRatio`
   - `setPipSize`
   - `setPipPositionX`
   - `setPipPositionY`
   - `setSaveAspectRatio`
   - `dc_flipCamera` 中切换 `sxBackOnTop` / `pipMainIsBack`
   - `layoutSubviews` 中当 `frontPreviewView.bounds` 实际变化时
   - PiP pan/pinch 更新期间
4. `scheduleFrontBeautyProcessingIfNeeded` 捕获当前版本快照：
   - `generation = beautyLayoutGeneration`
   - `layoutMode = currentLayout`
   - `targetSize = beautyPreviewTargetSize`
   - `mirrored = frontPreviewMirrored`
   - 后台处理完成后，只有这些值仍匹配当前状态才写入 `latestBeautyPreviewFrame` 和对应元数据；不匹配则丢弃结果并等待下一帧。
5. `shouldShowBeautyPreview` 改成严格闸门：
   - 美颜开启、Metal 可用、MultiCam 双摄、布局包含前置。
   - `latestBeautyPreviewFrame != nil`。
   - `latestBeautyPreviewGeneration == beautyLayoutGeneration`。
   - `latestBeautyPreviewLayoutMode == currentLayout`。
   - `latestBeautyPreviewTargetSize` 与当前 `beautyPreviewView.drawableSize` 或 `frontPreviewView.bounds * scale` 误差小于 2px。
   - `latestBeautyPreviewMirrored == frontPreviewMirrored`。
   - `beautyLayoutChanging` 且距离最后变化不足 0.3-0.5 秒时返回 NO。
6. `updateBeautyPreviewVisibility` 调整顺序：
   - 先计算当前 drawable/target size。
   - 如果 `shouldShowBeautyPreview == NO`，隐藏 `beautyPreviewView`，显示 `frontPreviewLayer`。
   - 只有通过严格闸门后才隐藏原始前置预览层并显示 Metal 美颜层。
   - PiP 圆形时同步 `beautyPreviewView.layer.cornerRadius` 和 `frontPreviewView.layer.cornerRadius`，并保持 `clipsToBounds/masksToBounds`。
7. `renderBeautyPreviewIfNeeded` 增加二次校验：
   - 取帧后再次检查 generation/layout/target/mirror，失败则不渲染并隐藏 Metal 层。
   - 布局变化窗口内不渲染旧帧。
   - 至少保证渲染防重入，避免多个主线程 render 堆积。
8. 保持保存链路独立：
   - `captureWysiwygDualPhotoWithCanvasSize` 和录制仍可用 `latestRawFrontFrame` 做高质量同步/异步美颜。
   - 不把低分辨率 `latestBeautyPreviewFrame` 用于照片或视频保存。
9. 同步 `native/LocalPods/DualCamera` 到 `ios/LocalPods/DualCamera`，保持 canonical 源码和实际编译源码一致。

## 验证方式
- 静态检查：
  - `rg "beautyLayoutGeneration|latestBeautyPreviewGeneration|latestBeautyPreviewTargetSize|latestBeautyPreviewLayoutMode|latestBeautyPreviewMirrored" native/LocalPods/DualCamera ios/LocalPods/DualCamera`
  - `diff -qr native/LocalPods/DualCamera ios/LocalPods/DualCamera`
- 编译检查：
  - `npx tsc --noEmit`
  - `xcodebuild -workspace ios/KIRO.xcworkspace -scheme KIRO -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 真机检查：
  - 上下分屏：前置不再明显卡顿；拖动比例时可短暂回原始预览，但不出现残影。
  - 左右分屏：前置区域只显示一幅当前画面，不出现左右两幅画面。
  - 方形/圆形 PiP：不出现大中小嵌套；拖动/缩放时不保留旧 PiP 画面。
  - 翻转前后置：Metal 美颜层跟随前置区域，不跑到后置层。
  - 拍照/录像保存：合成和前置独立仍有美颜，后置独立不受影响。
- 日志检查：
  - 新增 `[BeautyProbe][PreviewVersion]` 日志，包含 `currentGen/latestGen/layout/target/currentTarget/show/dropReason`。
  - 出现旧帧时必须能看到 `dropReason=staleGeneration` 或 `targetMismatch`，且不会显示旧帧。

## 回滚方案
- 如新闸门导致美颜预览长期不显示，可临时只回滚 `shouldShowBeautyPreview` 的严格尺寸判断，保留 generation 判断。
- 如渲染队列改动引入风险，先保留主线程 render，但必须保留 generation/target 闸门和布局变化期间隐藏 Metal 层。
- 保存链路不参与本次修改，若预览修复失败不需要回滚照片/视频保存逻辑。

## 目标编辑文件清单
- `my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Layout.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Gestures.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView_Internal.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraView.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Layout.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Capture.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Gestures.m`
- `my-app/.ai/project.md`
