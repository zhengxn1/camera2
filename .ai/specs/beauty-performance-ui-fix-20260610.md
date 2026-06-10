# 美颜性能与 UI 修正技术规格书

## 目标
- 修复美颜默认开启导致的卡顿和前置过糊，确保后置不参与美颜，并让美颜弹框正确覆盖焦距控件，同时替换美颜入口图标。

## 影响范围
| 文件 | 原因 |
|---|---|
| my-app/App.tsx | 调整美颜启用条件、浮层顺序和焦距层显示条件 |
| my-app/src/components/BeautyPanel.tsx | 默认美颜值归零，并降低滑杆向原生透传频率 |
| my-app/src/components/CameraControlsOverlay.tsx | 支持美颜面板打开时隐藏焦距与分割交互 |
| my-app/src/components/BottomBar.tsx | 替换美颜入口为简化美女头像线条图标 |
| my-app/src/styles.ts | 新增/调整美颜图标与弹框层级样式 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m | 降低临时 Core Image 美颜磨皮强度，减少糊感 |

## 实施步骤
1. 将默认美颜参数全部改为 0，打开面板不立即启用滤镜。
2. 在 JS 层仅当前置画面存在且参数大于 0 时启用前置美颜；后置保持不处理。
3. 美颜面板打开时隐藏 `CameraControlsOverlay` 的焦距按钮和分割拖拽控件，并调整渲染顺序/层级。
4. 将当前圆脸闪光图标换为原创简化美女头像线条图标。
5. 降低 `CINoiseReduction` 的噪声级别上限，并提高保留锐度。
6. 运行 TypeScript 检查。

## 验证方式
- 在 `my-app/` 执行 `npx tsc --noEmit`。
- 真机人工检查：默认无美颜卡顿、前置不再明显发糊、后置无美颜、美颜弹框盖住/隐藏焦距控件、入口图标更新。

## 回滚方案
- 恢复上述目标文件到本规格书变更前状态。

## 目标编辑文件清单
- my-app/App.tsx
- my-app/src/components/BeautyPanel.tsx
- my-app/src/components/CameraControlsOverlay.tsx
- my-app/src/components/BottomBar.tsx
- my-app/src/styles.ts
- my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m
