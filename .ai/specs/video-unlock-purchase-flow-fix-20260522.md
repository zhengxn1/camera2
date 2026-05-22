# 视频解锁购买流程修复技术规格书

## 目标
- 修复视频解锁内购首次展示旧价格、购买确认后可能再次触发购买的问题。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/App.tsx` | 打开解锁弹窗前先刷新商品价格和权益状态，避免旧价格直接展示和点击。 |
| `my-app/src/hooks/useVideoUnlock.ts` | 管理商品刷新代次、购买中锁、权益刷新和购买前商品校验。 |
| `my-app/src/components/VideoUnlockSheet.tsx` | 价格刷新期间禁用购买，显示稳定的等待状态。 |
| `my-app/src/native.ts` | 扩展原生购买接口类型，支持按商品 ID 购买和交易状态返回。 |
| `my-app/native/LocalPods/DualCamera/VideoUnlockModule.swift` | 缓存当前商品、防重复购买、按商品 ID 购买、处理未完成交易和权益兜底。 |
| `.ai/project.md` | 记录本次支付链路修复。 |

## 实施步骤
1. 前端打开付费弹窗时先刷新权益，仍未解锁再显示弹窗并刷新商品。
2. `refreshProduct` 开始时清空旧商品，使用请求序号避免慢请求覆盖新结果。
3. 购买前要求当前商品存在且不在刷新中，并把商品 ID 传给原生层。
4. 购买过程中用 ref 锁避免重复点击或重复调用。
5. 原生层缓存 StoreKit 商品，购买时校验商品 ID，优先处理当前未完成权益，防止重复购买。
6. 购买成功、恢复成功或交易更新后确保 transaction finish，并返回最新解锁状态。

## 验证方式
- 在 `my-app/` 执行 `npx tsc --noEmit`。
- iOS 真机/TestFlight 人工验证：首次打开付费弹窗不显示旧价格，价格加载完成前按钮不可点；购买确认完成后弹窗关闭并解锁视频录制；重复点击不会再次弹出系统购买页。

## 回滚方案
- 还原上述目标文件到变更前版本。

## 目标编辑文件清单
- `my-app/App.tsx`
- `my-app/src/hooks/useVideoUnlock.ts`
- `my-app/src/components/VideoUnlockSheet.tsx`
- `my-app/src/native.ts`
- `my-app/native/LocalPods/DualCamera/VideoUnlockModule.swift`
- `.ai/project.md`
