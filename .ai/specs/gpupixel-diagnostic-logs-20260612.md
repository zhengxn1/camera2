# GPUPixel 诊断日志技术规格书

## 目标
- 为 GPUPixel 美颜 POC 增加最小诊断日志，定位“日志没打印”时到底是未编入、未启用、参数未触发、管线初始化失败还是输出失败。

## 影响范围
| 文件 | 原因 |
|---|---|
| my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm | 补充 GPUPixel 编译可用性、启用状态、管线初始化和失败原因日志 |
| my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m | 在 GPUPixel 返回 nil 后记录一次 Core Image fallback 提示 |

## 实施步骤
1. 兼容 `<gpupixel/gpupixel.h>` 和 `"gpupixel.h"` 两种头文件检测方式。
2. 初始化时打印 GPUPixel 是否被编译进当前 DualCamera pod。
3. 美颜启用和参数变化时打印节流后的状态日志。
4. GPUPixel 处理失败时按原因打印一次或低频日志，成功时打印 raw pipeline 激活日志。
5. 调用方在 fallback 到 Core Image 时仅打印一次提示。

## 验证方式
- `cd my-app && npx tsc --noEmit`
- `cd my-app && node -c plugin/withDualCamera.js`
- iOS 真机/Xcode 验证：重新 prebuild 或重新执行 config plugin/pod install 后观察 `[DualCamera][GPUPixel]` 日志。

## 回滚方案
- 删除新增日志属性和 NSLog，不改变原有 Core Image fallback 行为。

## 目标编辑文件清单
- my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm
- my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m
