# 前置美颜保存同步与滑块修复技术规格书

## 目标
- 让保存后的照片/双摄录制与当前前置预览使用同一套前置美颜效果，并修复美颜滑块拖动不稳定的问题。

## 影响范围
| 文件 | 原因 |
|---|---|
| my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m | 恢复保存/录制合成链路的前置美颜，仅处理 front 帧并补充日志 |
| my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm | 接入清晰参数到 GPUPixel，补充磨皮/清晰调试日志 |
| my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h | 暴露 sharpness 参数 |
| my-app/native/LocalPods/DualCamera/DualCameraView.m | 将 frontBeautySharpness 同步给 GPUPixel adapter |
| my-app/src/components/BeautyPanel.tsx | 修复滑块拖动命中/移动更新不稳定 |

## 实施步骤
1. 在保存/录制合成中只对前置帧调用 `beautifiedFrontImage`，后置帧保持原始输入。
2. 增加低频日志，记录 layout、front/back 是否存在、保存链路是否应用前置美颜。
3. 为 GPUPixel adapter 增加 `sharpness` 属性，将清晰映射到 `SetSharpen`，并记录 smooth/sharpness 实际映射值。
4. 改造美颜滑块触摸热区，确保按下和拖动都稳定更新数值。

## 验证方式
- `cd my-app && npx tsc --noEmit`
- iOS 真机人工验证：前置预览、保存照片、双摄录制里只有前置有美颜；后置单摄不被美颜；滑块可按住连续拖动。

## 回滚方案
- 回退上述目标文件到修改前状态。

## 目标编辑文件清单
- my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m
- my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm
- my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h
- my-app/native/LocalPods/DualCamera/DualCameraView.m
- my-app/src/components/BeautyPanel.tsx
