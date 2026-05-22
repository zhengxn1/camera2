# StoreKit ViewBridge 购买崩溃排查修复 技术规格书

## 目标
- 修复点击视频解锁购买后出现 `com.apple.ViewBridge Code=18 NSViewBridgeErrorCanceled` 并疑似崩溃的问题，降低 StoreKit 购买弹窗桥接和线程风险。

## 排查结论
- `NSViewBridgeErrorCanceled` 常见于 StoreKit/系统远程视图被取消或断开，本身不一定是根因。
- 当前高风险改动是上一版将 `purchaseVideoUnlock()` 改为带 `productID` 参数的 React Native 原生桥接方法，并在普通 `Task` 中调用 `Product.purchase()`。
- 该产品 ID 在 native 内固定为 `com.zhengning.dualcamera.unlock`，前端传参校验不是必要路径，反而增加桥接签名风险。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/native/LocalPods/DualCamera/VideoUnlockModule.swift` | 恢复无参数购买入口，购买 UI 在主线程发起，promise 回调保持稳定 |
| `my-app/native/LocalPods/DualCamera/VideoUnlockModuleBridge.m` | 恢复无参数 RN bridge 方法签名 |
| `my-app/src/hooks/useVideoUnlock.ts` | 前端购买调用恢复为无参数 |
| `my-app/src/native.ts` | 原生购买接口类型恢复为无参数 |
| `.ai/project.md` | 记录本次崩溃排查修复 |

## 实施步骤
1. `VideoUnlockModuleBridge.m` 将 `purchaseVideoUnlock:(NSString *)productID resolver:rejecter:` 改回 `purchaseVideoUnlock:rejecter:`。
2. `VideoUnlockModule.swift` 删除 `productID` 参数和前置 productID 校验，继续使用 native 固定产品 ID。
3. 将 `Product.purchase()` 所在异步块改为 `Task { @MainActor in ... }`，确保系统购买 UI 从主线程发起。
4. `useVideoUnlock.ts` 调用 `VideoUnlockModule.purchaseVideoUnlock()`，不再传 `product.id`。
5. `native.ts` 同步类型定义。

## 验证方式
- 在 `my-app/` 执行 `npx tsc --noEmit`。
- 本地无法在 Windows 验证 iOS StoreKit 弹窗；需 iOS 真机或 TestFlight 复测点击购买。

## 回滚方案
- 恢复上一版带 `productID` 参数的 bridge 和前端调用。

## 目标编辑文件清单
- `my-app/native/LocalPods/DualCamera/VideoUnlockModule.swift`
- `my-app/native/LocalPods/DualCamera/VideoUnlockModuleBridge.m`
- `my-app/src/hooks/useVideoUnlock.ts`
- `my-app/src/native.ts`
- `.ai/project.md`
