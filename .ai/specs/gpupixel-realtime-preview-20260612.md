# GPUPixel 实时预览修复技术规格书

## 目标
- 让前置美颜开启后实时预览也显示 GPUPixel/Core Image 美颜效果，解决“保存后有、实时没有”的问题。

## 影响范围
| 文件 | 原因 |
|---|---|
| my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h | 增加实时美颜预览覆盖层和节流状态 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Layout.m | 创建、布局、隐藏美颜预览覆盖层 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m | 在前置 sampleBuffer 到达时异步渲染美颜预览帧 |
| my-app/native/LocalPods/DualCamera/DualCameraView.m | 美颜开关变化时同步显示/隐藏覆盖层 |

## 实施步骤
1. 在 front preview view 上新增一个 `UIImageView` 覆盖层，默认隐藏，contentMode 使用 aspect fill。
2. 前置 sampleBuffer 到达且美颜开启时，节流到约 15fps 后投递到 `realtimeRenderQueue`。
3. 在渲染队列复用 `beautifiedFrontImage:` 生成美颜图，再按预览镜像配置做水平翻转。
4. 用 `CIContext` 生成 `CGImage`，主线程更新覆盖层图片并显示；关闭美颜时隐藏覆盖层。
5. 保持原有 `AVCaptureVideoPreviewLayer` 作为底层实时预览和 fallback。

## 验证方式
- `cd my-app && npx tsc --noEmit`
- `cd my-app && node -c plugin/withDualCamera.js`
- iOS 真机/Xcode 验证：打开前置/双摄前置画面，开启美颜后实时预览应立即变化；关闭美颜后恢复原始预览。

## 回滚方案
- 删除新增覆盖层、节流状态和前置 sampleBuffer 预览渲染逻辑，恢复仅保存/录像走美颜合成。

## 目标编辑文件清单
- my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h
- my-app/native/LocalPods/DualCamera/DualCameraView+Layout.m
- my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m
- my-app/native/LocalPods/DualCamera/DualCameraView.m
