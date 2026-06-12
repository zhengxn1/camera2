# GPUPixel 实时预览与保存隔离修复技术规格书

## 目标
- 先停止保存/录像合成路径的美颜处理，只保留实时预览调试路径。
- 修正实时美颜覆盖层与 `AVCaptureVideoPreviewLayer` 的层级关系，避免美颜图被原始预览层盖住。

## 官方 SDK 结论
- GPUPixel iOS 接入要求 Objective-C 调 C++ 的源文件使用 `.mm`，并通过 `<gpupixel/gpupixel.h>` 引入头文件。
- 当前本地 framework 暴露的是 `SourceRawData`、`BeautyFaceFilter`、`SinkRawData`、`SinkView`。
- 官方自定义输出文档说明 `SinkRawData` 是在 source 执行 `ProcessData` 后通过 `GetRgbaBuffer()` 拉取结果的输出模式；保存路径已经证明这条 raw pipeline 是可用的。
- 当前实时预览失败的首要怀疑点不是 GPUPixel raw pipeline，而是 UIKit view 覆盖层被手动添加的 `AVCaptureVideoPreviewLayer` 压住。

## 影响范围
| 文件 | 原因 |
|---|---|
| my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m | 注释掉保存/录像合成路径的前置美颜 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Layout.m | 提供统一方法把美颜覆盖层放到前置预览最上层 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Layout.h | 声明覆盖层层级方法 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Session.m | 添加 preview layer 时放到底层，避免盖住美颜覆盖层 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m | 使用统一层级方法显示实时美颜覆盖层 |

## 实施步骤
1. 在 `compositedImageForLayoutState` 中注释掉 `front = [self beautifiedFrontImage:front];`，保存/录像不再自动美颜。
2. 新增 `bringFrontBeautyPreviewToFront`，在 layout/update/removePreviewLayers 后维持覆盖层在前。
3. `frontPreviewLayer` 改为插入到 front preview view 的底层，而不是追加到最上层。
4. 实时美颜渲染成功后调用统一层级方法。

## 验证方式
- `cd my-app && npx tsc --noEmit`
- `cd my-app && node -c plugin/withDualCamera.js`
- `git diff --check`
- iOS 真机/Xcode 验证：保存结果不再美颜；开启美颜后实时前置预览能看到覆盖层效果。

## 回滚方案
- 恢复 `front = [self beautifiedFrontImage:front];` 并移除 preview layer 层级调整。

## 目标编辑文件清单
- my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m
- my-app/native/LocalPods/DualCamera/DualCameraView+Layout.m
- my-app/native/LocalPods/DualCamera/DualCameraView+Layout.h
- my-app/native/LocalPods/DualCamera/DualCameraView+Session.m
- my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m
