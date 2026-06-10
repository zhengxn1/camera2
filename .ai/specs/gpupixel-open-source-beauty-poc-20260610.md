# GPUPixel 开源美颜 POC 技术规格书

## 目标
- 放弃商业美颜 SDK，基于 Apache-2.0 开源项目 GPUPixel 做最小可行 POC：只处理前置画面，后置画面保持原样，验证实时预览、拍照、录像输出能否接入现有双摄合成管线。

## 选型结论
- 首选：GPUPixel。
- 原因：官方仓库和文档说明其基于 C++11/OpenGL ES，支持 iOS/Android/macOS 等平台，内置美白、磨皮、美颜、美型相关滤镜，并支持 YUV/RGBA 输入输出。
- 不选商业 SDK：BytePlus、Tencent、Banuba 等效果更成熟，但需要商业授权和 license，不符合当前预算。
- 不选纯自研作为第一步：Vision/MediaPipe 只能解决人脸点位，皮肤 mask、GPU 磨皮、肤色、锐化仍需自研，周期更长。

## 官方资料
- GPUPixel GitHub：https://github.com/pixpark/gpupixel
- GPUPixel Integration：https://gpupixel.pixpark.net/guide/integrated
- GPUPixel Beauty Effects：https://gpupixel.pixpark.net/call/beauty_effects
- GPUPixel Filter List：https://gpupixel.pixpark.net/reference/filter-list
- MediaPipe Face Landmarker iOS 备选：https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/ios

## POC 范围
- 只接 iOS 原生层。
- 只处理前置 camera frame。
- 后置 frame 不进入 GPUPixel。
- 第一版只映射现有 UI 参数：
  - `smooth` -> GPUPixel 磨皮/美颜强度。
  - `brighten` -> 美白/提亮强度。
  - `tone` -> 轻量肤色或白皙强度。
  - `sharpness` 暂不接入 GPUPixel，保留现有 UI 但可以映射为空操作。
- 美型、瘦脸、大眼、口红、腮红先不接。
- Android 不在本次范围。

## 影响范围
| 文件 | 原因 |
|---|---|
| my-app/plugin/withDualCamera.js | 预构建时复制/注入 GPUPixel framework、系统 framework、Podfile 配置 |
| my-app/native/LocalPods/DualCamera/DualCamera.podspec | 声明 vendored framework、系统 framework、C++/ObjC++ 编译配置 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m | 如需直接调用 GPUPixel，需要改为 `.mm` 或抽离到 ObjC++ 适配器 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m | 捕获前置 pixel buffer 的入口，验证是否可在合成前处理 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m | 录像实时合成路径需要复用同一前置美颜输出 |
| my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h | 增加 GPUPixel 适配器属性或前置美颜状态缓存 |
| my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h | 新增 ObjC/ObjC++ 适配器公开接口 |
| my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm | 新增 GPUPixel 初始化、参数更新、前置帧处理逻辑 |
| my-app/src/components/BeautyPanel.tsx | 如 GPUPixel 参数范围不同，做 UI 数值映射或禁用未支持项 |
| my-app/App.tsx | 保持只在前置存在且参数大于 0 时启用美颜 |

## 外部依赖放置方案
- 在仓库内新增三方目录，避免依赖远端下载：
  - `my-app/native/ThirdParty/GPUPixel/ios/gpupixel.framework`
- `withDualCamera.js` 在 prebuild 时复制到：
  - `my-app/ios/LocalPods/DualCamera/Frameworks/gpupixel.framework`
- `DualCamera.podspec` 通过 `vendored_frameworks` 引用该 framework，并声明 `AVFoundation`、`CoreMedia` 等系统依赖。
- 如果 GPUPixel 官方 framework 只支持真机或架构不完整，先停止实现并记录缺失架构，不做源码大规模引入。

## 技术接入方案
1. 新增 `GPUPixelBeautyAdapter`。
   - 对外暴露：
     - `enabled`
     - `smooth`
     - `brighten`
     - `tone`
     - `processPixelBuffer` 或 `processCIImage`
   - 内部负责 GPUPixel source/filter/sink 链路初始化和复用。
2. 前置帧处理点。
   - 在前置 frame 进入 `compositedImageForLayoutState` 前处理。
   - POC 优先尝试 `CVPixelBuffer -> GPUPixel raw input -> raw output -> CIImage`。
   - 如果 raw output 成本太高，再评估 `CVPixelBuffer -> OpenGL texture -> GPUPixel texture -> CIImage`。
3. 参数更新。
   - JS 仍通过 `frontBeautySmooth/Brighten/Tone` 传给原生。
   - 原生 setter 只更新 adapter 参数，不在 setter 中重建滤镜链。
4. 输出一致性。
   - 预览、拍照、录像都必须复用同一处理后的前置帧来源。
   - 如果第一版只能做到预览，必须明确标记为未通过 POC，不进入主分支。
5. 失败降级。
   - GPUPixel 初始化失败或处理失败时，直接返回原始前置 frame。
   - 不影响后置、不影响拍照/录像主流程。

## 性能约束
- 美颜关闭时不得进入 GPUPixel 处理链。
- 美颜参数全 0 时直接返回原始前置 frame。
- GPUPixel filter/source/sink 必须复用，不能逐帧创建。
- 帧处理不得阻塞 AVCapture 回调队列；如果需要同步等待输出，必须记录耗时并设置超时/降级。
- POC 真机目标：打开美颜后预览无明显掉帧；录制开始不新增明显卡顿。

## 风险点
- GPUPixel 是 C++/OpenGL ES，现有项目主要是 Objective-C/Core Image；需要 ObjC++ 适配层。
- iOS OpenGL ES 已不再是 Apple 推荐方向，但仍可用；长期最好迁移 Metal 或商业/自研 Metal 管线。
- framework 架构、bitcode、模拟器支持、EAS 构建兼容性需要真机和云构建验证。
- 人脸检测能力可能依赖 GPUPixel 编译选项或额外模型/库，POC 第一版先验证美颜滤镜链，不保证美型。

## 验证方式
- Windows 本地：
  - `cd my-app && npx tsc --noEmit`
  - 检查 config plugin/podspec 语法。
- macOS/EAS：
  - `npx expo prebuild --platform ios --clean`
  - `pod install`
  - Xcode 真机编译。
- 真机人工验收：
  - 默认美颜关闭，预览不卡。
  - 打开美颜后只前置变化，后置保持原样。
  - 双摄上下/左右/画中画均不崩溃。
  - 拍照保存和预览一致。
  - 录像保存和预览一致。

## 回滚方案
- 删除 GPUPixel framework 与 `GPUPixelBeautyAdapter.*`。
- 恢复 podspec/config plugin 中的 framework 注入。
- 保留当前 Core Image 轻量美颜作为降级方案。

## 阶段拆分
1. 依赖接入验证：把 GPUPixel framework 放入本地 pod 并通过 iOS 编译。
2. Adapter 空实现：美颜开启时仍返回原始前置 frame，验证桥接和生命周期。
3. 前置单帧美颜：只处理预览路径，观察性能和画质。
4. 输出一致：接入拍照/录像合成路径。
5. 参数映射：把 UI 参数映射到 GPUPixel 滤镜。

## 本规格书不直接改代码
- 这是接入方案和 POC 范围说明。正式实施前需要先确认 GPUPixel framework 文件来源和目标 iOS 架构。
