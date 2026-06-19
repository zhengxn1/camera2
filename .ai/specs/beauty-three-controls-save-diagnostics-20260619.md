# 美颜三项收口与保存一致性诊断技术规格书

## 目标
- 美颜只保留磨皮、提亮、美白三项；美颜面板改为半透明且图标换成魔法棒；为预览、拍照保存和录制保存增加分源日志，深排保存无美颜问题。

## 影响范围
| 文件 | 原因 |
|---|---|
| my-app/App.tsx | 更新美颜状态字段、活跃判断和传给原生的 props |
| my-app/src/components/BeautyPanel.tsx | 将美颜项收口为磨皮/提亮/美白 |
| my-app/src/components/BottomBar.tsx | 将美颜入口图标改为魔法棒样式 |
| my-app/src/components/CameraSurface.tsx | 将前置美白 prop 传给原生视图 |
| my-app/src/native.ts | 更新 NativeDualCameraViewProps 的美颜字段 |
| my-app/src/styles.ts | 调整半透明面板和魔法棒图标样式 |
| my-app/native/LocalPods/DualCamera/DualCameraView.h | 将 frontBeautyTone 收口为 frontBeautyWhiten |
| my-app/native/LocalPods/DualCamera/DualCameraView.m | 更新美白 setter 和原生日志 |
| my-app/native/LocalPods/DualCamera/DualCameraViewManager.m | 更新 RN prop 桥接 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m | 增加拍照/录制入口日志 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Composition.h | 增加带 source 的前置美颜处理入口 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m | 拆分提亮/美白处理并增加保存合成日志 |
| my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h | 将 tone/sharpness 收口为 whiten |
| my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm | 将 GPUPixel SetWhite 改为美白参数并补充日志 |

## 实施步骤
1. 前端 `BeautySettings` 改为 `smooth/brighten/whiten` 三项，面板仅渲染三项。
2. 将 RN 原生 prop 改为 `frontBeautyWhiten`，原生属性和 GPUPixel adapter 同步改名。
3. `beautifiedFrontImage` 增加 source 参数，日志区分 preview/save/recording。
4. GPUPixel 仅处理磨皮和美白；提亮在 GPUPixel/Core Image 后统一用 Core Image 亮度处理。
5. 拍照、录制、保存合成入口打印关键日志，帮助判断保存是否走 WYSIWYG 合成路径。

## 验证方式
- `cd my-app && npx tsc --noEmit`
- `git diff --check`
- iOS 真机人工验证：美颜面板只显示三项，面板半透明；预览、拍照保存、双摄录制保存中前置美颜一致，后置不被美颜；Xcode 日志包含 `[BeautyJS]`、`[BeautyNative]`、`[BeautyCapture]`、`[BeautySave]`、`[BeautyProcess]`。

## 回滚方案
- 回退目标编辑文件到修改前状态。

## 目标编辑文件清单
- my-app/App.tsx
- my-app/src/components/BeautyPanel.tsx
- my-app/src/components/BottomBar.tsx
- my-app/src/components/CameraSurface.tsx
- my-app/src/native.ts
- my-app/src/styles.ts
- my-app/native/LocalPods/DualCamera/DualCameraView.h
- my-app/native/LocalPods/DualCamera/DualCameraView.m
- my-app/native/LocalPods/DualCamera/DualCameraViewManager.m
- my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m
- my-app/native/LocalPods/DualCamera/DualCameraView+Composition.h
- my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m
- my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h
- my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm
