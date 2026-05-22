# 视频解锁价格重试与图标清理 技术规格书

## 目标
- 说明并修复视频解锁弹窗价格获取失败后的体验：保留 StoreKit `displayPrice` 作为唯一价格来源，增加打开弹窗时重新拉取价格和失败后的手动重试；同时按无背景方案清理顶部图标。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/App.tsx` | 打开购买弹窗时触发一次价格刷新，并向弹窗传入重试回调 |
| `my-app/src/hooks/useVideoUnlock.ts` | 抽出可复用的产品加载函数，暴露 `refreshProduct` |
| `my-app/src/components/VideoUnlockSheet.tsx` | 去掉 icon 背景和 `REC` 文案，价格失败时显示重试按钮 |
| `my-app/src/native.ts` | 更新 `VideoUnlockApi` 类型不涉及；无需修改 |
| `my-app/src/styles.ts` | 调整无背景图标和价格重试按钮样式 |
| `.ai/project.md` | 记录本次变更 |

## 实施步骤
1. `useVideoUnlock`：
   - 新增 `refreshProduct()`，内部调用 `VideoUnlockModule.getProduct()`。
   - 初始加载继续调用同一函数。
   - 失败时保持“暂时无法获取价格”用户文案，不硬编码任何价格。
2. `App.tsx`：
   - 用户点击锁定视频快门打开购买弹窗前，调用 `videoUnlock.refreshProduct()`。
   - 将 `refreshProduct` 传给 `VideoUnlockSheet`。
3. `VideoUnlockSheet`：
   - 去掉白色圆形 icon 背景。
   - 去掉 `REC` 字样，改为录制圆点，避免右侧错乱。
   - `productError` 出现时显示“重新获取价格”按钮。
4. `styles.ts`：
   - 删除/废弃圆形 icon plate 的视觉承托。
   - 调整 recorder 图标为干净线框。
   - 新增价格重试按钮样式。

## 验证方式
- 在 `my-app/` 执行 `npx tsc --noEmit`。
- 搜索确认没有硬编码 `US$` 或 `0.99`。

## 回滚方案
- 恢复 `useVideoUnlock` 只在 mount 时加载产品。
- 恢复购买弹窗白色 icon 背景和无重试按钮状态。

## 目标编辑文件清单
- `my-app/App.tsx`
- `my-app/src/hooks/useVideoUnlock.ts`
- `my-app/src/components/VideoUnlockSheet.tsx`
- `my-app/src/styles.ts`
- `.ai/project.md`
