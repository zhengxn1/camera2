# 美颜无日志运行探针技术规格书

## 目标
- 不返工当前美颜预览/保存管线。
- 只补充运行时探针，解决“源码和编译产物里有日志，但真机运行看不到 Beauty 日志”导致无法定位的问题。
- 一次运行后能判断问题卡在 JS 设置、RN prop、native view 生命周期、MultiCam session、前置 sample、Metal 预览条件、还是 Xcode/设备日志显示链路。
- 同时定位美颜开启后的三类现象：卡顿、多层画面、人物/画面拉伸变形。

## 影响范围
| 文件 | 原因 |
|---|---|
| `src/components/CameraSurface.tsx` | JS 侧打印一次传给 native 的美颜开关和四个参数，确认设置状态不是在前端丢失。 |
| `native/LocalPods/DualCamera/DualCameraView.m` | 在 view init、layoutMode、frontBeautyEnabled 和四个滑杆 setter 中加入无条件轻量日志，确认 RN prop 进入 native。 |
| `native/LocalPods/DualCamera/DualCameraView+Session.m` | 在 session 选择、MultiCam 配置完成、fallback 进入处输出一次美颜相关状态，确认当前是不是 MultiCam 路径。 |
| `native/LocalPods/DualCamera/DualCameraView+Capture.m` | 在前置 sample 首帧和每 60 帧输出一次状态，确认前置帧是否进入美颜链路。 |
| `native/LocalPods/DualCamera/DualCameraView+Layout.m` | 把 `shouldShowBeautyPreview == NO` 的原因也打印出来，避免提前 return 导致完全没日志。 |
| `native/LocalPods/DualCamera/DualCameraView+Composition.m` | 保留现有 `BeautyFaceDiag`，只在必要时补充“函数是否被调用”的入口日志。 |
| `ios/LocalPods/DualCamera/*` 对应文件 | 同步 canonical native 源码到 Xcode 实际编译副本。 |

## 契约设计
- **日志前缀**：统一使用 `[BeautyProbe]`，现有 `[BeautyLayoutDiag]`、`[BeautyPreviewDiag]`、`[BeautyRenderDiag]`、`[BeautyFaceDiag]` 保留。
- **日志通道**：native 使用 `NSLog`，JS 使用 `console.log`。如 Xcode 仍不显示 `NSLog`，下一步再改为 `RCTLogInfo` 或 `os_log` 双写。
- **状态字段**：
  - JS：`enabled/smooth/whiten/even/plump/layoutMode`
  - native prop：`enabled/smooth/whiten/even/plump`
  - session：`usingMultiCam/isConfigured/isRunning/currentLayout/metalDevice`
  - sample：`frontSampleCount/latestFrontFrame/frontBeautyEnabled`
  - preview gate：`enabled/hasMetal/usingMultiCam/layoutContainsFront/latestFrontFrame/frontViewHidden`
- **问题标签**：
  - `[BeautyProbe][LayerConflict]`：`frontPreviewLayer` 和 `beautyPreviewView` 同时可见，或 `frontPreviewView.subviews.count > 1`。
  - `[BeautyProbe][AspectMismatch]`：`frontPreviewView.bounds`、`beautyPreviewView.frame`、`beautyPreviewView.drawableSize`、`frontFrame.extent` 的宽高比明显不一致。
  - `[BeautyProbe][FrameGap]`：前置 sample 间隔超过正常帧率阈值，提示采集/处理链路卡顿。
  - `[BeautyProbe][SlowRender]`：Metal 渲染或美颜处理耗时过高。
  - `[BeautyProbe][PlumpDuringLayout]`：布局拖动期间仍在执行丰盈形变，可能导致人脸局部拉伸。

## 实施步骤
1. 在 JS `CameraSurface` 加一次节流日志，确认每次打开相机和调参数时前端状态正确。
2. 在 native view `commonInit` 和所有美颜 prop setter 加 `[BeautyProbe]`，不依赖美颜预览是否成功。
3. 在 `shouldShowBeautyPreview` 拆出失败原因日志，重点解决当前 `!shouldShow` 直接 return 导致没有 `BeautyPreviewDiag` 的问题。
4. 在前置 `captureOutput` 路径加首帧/低频日志，确认前置帧是否进入 `beautifiedFrontImage`。
5. 在布局/预览更新处检测层级冲突，打印 `frontPreviewLayer.hidden`、`beautyPreviewView.hidden`、`beautyPreviewView.superview`、`frontPreviewView.subviews.count`。
6. 在渲染处检测前置帧、目标 drawable、前置 view 的宽高比是否明显不一致，打印 `[AspectMismatch]`。
7. 在前置 sample 路径记录帧间隔，超过 120ms 打印 `[FrameGap]`；在美颜/渲染耗时超过 33ms 时打印 `[SlowRender]`。
8. 在丰盈形变路径确认布局拖动时是否跳过 plump，未跳过时打印 `[PlumpDuringLayout]`。
9. 同步修改 `native/LocalPods/DualCamera` 与 `ios/LocalPods/DualCamera`。
10. 编译后验证构建产物中包含 `[BeautyProbe]`，再真机运行并按 `Beauty` 过滤日志。

## 验证方式
- `rg "BeautyProbe|BeautyLayoutDiag|BeautyPreviewDiag|BeautyRenderDiag|BeautyFaceDiag" native/LocalPods/DualCamera ios/LocalPods/DualCamera src`
- `diff -q native/LocalPods/DualCamera/DualCameraView.m ios/LocalPods/DualCamera/DualCameraView.m`
- `diff -q native/LocalPods/DualCamera/DualCameraView+Layout.m ios/LocalPods/DualCamera/DualCameraView+Layout.m`
- `diff -q native/LocalPods/DualCamera/DualCameraView+Capture.m ios/LocalPods/DualCamera/DualCameraView+Capture.m`
- `diff -q native/LocalPods/DualCamera/DualCameraView+Session.m ios/LocalPods/DualCamera/DualCameraView+Session.m`
- `diff -q native/LocalPods/DualCamera/DualCameraView+Composition.m ios/LocalPods/DualCamera/DualCameraView+Composition.m`
- `npx tsc --noEmit`
- `xcodebuild -workspace ios/KIRO.xcworkspace -scheme KIRO -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `strings DerivedData/.../KIRO.app/KIRO.debug.dylib | rg "BeautyProbe"`

## 回滚方案
- 删除新增 `[BeautyProbe]` 日志，不触碰美颜算法、Metal 预览、布局或保存逻辑。
- 若定位到具体根因，再单独开一份修复规格，避免诊断代码和功能修复混在一起。

## 目标编辑文件清单
- `src/components/CameraSurface.tsx`
- `native/LocalPods/DualCamera/DualCameraView.m`
- `native/LocalPods/DualCamera/DualCameraView+Session.m`
- `native/LocalPods/DualCamera/DualCameraView+Capture.m`
- `native/LocalPods/DualCamera/DualCameraView+Layout.m`
- `native/LocalPods/DualCamera/DualCameraView+Composition.m`
- `ios/LocalPods/DualCamera/DualCameraView.m`
- `ios/LocalPods/DualCamera/DualCameraView+Session.m`
- `ios/LocalPods/DualCamera/DualCameraView+Capture.m`
- `ios/LocalPods/DualCamera/DualCameraView+Layout.m`
- `ios/LocalPods/DualCamera/DualCameraView+Composition.m`
