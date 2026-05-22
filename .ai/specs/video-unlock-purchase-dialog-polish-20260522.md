# 视频解锁购买弹窗优化 技术规格书

## 目标
- 修正视频解锁弹窗的价格展示约束，确保只使用 StoreKit `displayPrice`，并把弹窗视觉改为更接近 iOS 常见内购/功能解锁弹窗的浅色卡片设计。

## 关键判断
- 每个国家/地区的金额和币种应由 App Store Connect 的内购定价以及用户当前 App Store storefront 决定。
- iOS StoreKit 2 的 `Product.displayPrice` 是本地化后的展示价格，前端不能硬拼 `US$`、`¥`、`$` 或固定金额。
- 如果测试环境一直显示 `US$0.99`，优先检查 Sandbox Apple ID 地区、Xcode StoreKit Configuration storefront、以及 App Store Connect 该 IAP 的区域价格配置。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/src/components/VideoUnlockSheet.tsx` | 调整弹窗结构、图标结构、文案和价格按钮展示 |
| `my-app/src/styles.ts` | 重做购买弹窗浅色 iOS 风格、无锁图标、按钮和恢复购买样式 |
| `.ai/project.md` | 记录本次购买弹窗优化 |

## 实施步骤
1. 价格展示：
   - 保持 `product.displayPrice` 作为唯一价格来源。
   - 按钮文案使用 `立即解锁 ${product.displayPrice}`，避免任何固定币种或金额。
2. 视觉设计：
   - 卡片改为白色/近白色背景，搭配半透明黑色遮罩。
   - 图标参考用户图 2：白色圆形底、黑色线框双分屏录像图标、`REC` 标记；不出现锁。
   - 标题和正文改为黑/灰文字，整体更像 iOS 常见购买弹窗。
   - CTA 保留醒目的黄色按钮，恢复购买改为低优先级灰色文字。
3. 约束：
   - 不改 StoreKit 原生购买逻辑。
   - 不新增图片资源，图标继续用 React Native View/Text 绘制，避免资源体积和适配问题。

## 验证方式
- 在 `my-app/` 执行 `npx tsc --noEmit`。
- 人工检查：
  - 购买按钮不包含任何硬编码 `US$0.99`。
  - 不同地区应显示 StoreKit 返回的 `displayPrice`。
  - 图标不含锁，弹窗背景为浅色，层级和文字可读。

## 回滚方案
- 恢复 `VideoUnlockSheet.tsx` 的旧图标结构和旧文案。
- 恢复 `styles.ts` 中 `unlock*` 样式为旧灰色卡片。

## 目标编辑文件清单
- `my-app/src/components/VideoUnlockSheet.tsx`
- `my-app/src/styles.ts`
- `.ai/project.md`
