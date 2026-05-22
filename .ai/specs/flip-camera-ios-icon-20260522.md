# 翻转摄像头 iOS 图标优化 技术规格书

## 目标
- 将底部翻转摄像头按钮从大圆环式翻转图标改为更接近 iOS 相机的“小相机 + 翻转提示”图标，降低廉价感和错乱感。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/src/components/BottomBar.tsx` | 替换 `FlipIcon` 内部结构 |
| `my-app/src/styles.ts` | 重写翻转图标样式 |
| `.ai/project.md` | 记录本次 UI 变更 |

## 实施步骤
1. 保留翻转按钮外层尺寸、点击事件、无障碍标签和激活态。
2. `FlipIcon` 改为相机轮廓主体、镜头点和两枚小翻转箭头。
3. 删除当前大圆环弧线和端帽样式，避免小尺寸下变成白色断环。
4. 图标颜色默认白色半透明，激活态沿用浅蓝。

## 验证方式
- 在 `my-app/` 执行 `npx tsc --noEmit`。
- 搜索确认旧 `flipIconArc*` / `flipIconCap*` 样式不再使用。

## 回滚方案
- 恢复 `FlipIcon` 的双弧线结构和 `flipIconArc*` / `flipIconCap*` 样式。

## 目标编辑文件清单
- `my-app/src/components/BottomBar.tsx`
- `my-app/src/styles.ts`
- `.ai/project.md`
