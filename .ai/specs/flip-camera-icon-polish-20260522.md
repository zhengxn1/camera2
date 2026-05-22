# 翻转摄像头图标优化 技术规格书

## 目标
- 将底部翻转摄像头按钮从文字箭头替换为更精致的扁椭圆双弧形旋转图标。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/src/components/BottomBar.tsx` | 替换翻转按钮内部图标结构 |
| `my-app/src/styles.ts` | 新增翻转图标弧线、端点和激活态样式 |
| `.ai/project.md` | 记录本次 UI 变更 |

## 实施步骤
1. 在 `BottomBar.tsx` 新增 `FlipIcon` 小组件，用 View 绘制上下两段旋转弧线。
2. 保持翻转按钮外层交互和 accessibility 不变。
3. 图标比例做成横向略扁，不使用过圆的正圆造型。
4. 激活态沿用现有蓝色按钮状态，并让图标线条同步变亮。

## 验证方式
- 在 `my-app/` 执行 `npx tsc --noEmit`。
- 人工检查：底部翻转按钮显示双弧形旋转图标，不再显示 `↔` 文本。

## 回滚方案
- 恢复 `BottomBar.tsx` 中翻转按钮的 `<Text>↔</Text>`。
- 删除 `styles.ts` 中新增的 `flipIcon*` 样式。

## 目标编辑文件清单
- `my-app/src/components/BottomBar.tsx`
- `my-app/src/styles.ts`
- `.ai/project.md`
