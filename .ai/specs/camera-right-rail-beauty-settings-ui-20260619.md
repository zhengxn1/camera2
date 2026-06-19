# 相机右侧栏与美颜设置 UI 调整规格书

## 目标
- 按用户截图重排相机右侧内容，补齐中文标签，并把设置入口从左上角迁移到右侧设置图标。
- 将美颜设置弹窗调整为截图里的半透明底部浮层样式：标题居中、右侧重置、上方滑杆、下方三项美颜卡片。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/App.tsx` | 将右侧设置按钮事件传入底部控制组件，保留设置弹窗状态控制。 |
| `my-app/src/components/BottomBar.tsx` | 右侧工具栏增加标签和设置入口，调整美颜/模式按钮渲染。 |
| `my-app/src/components/SettingsPopup.tsx` | 移除左上角设置按钮，只保留弹窗内容。 |
| `my-app/src/components/BeautyPanel.tsx` | 调整美颜面板结构，配合截图样式。 |
| `my-app/src/styles.ts` | 调整右侧栏、设置图标、美颜底部弹窗和按钮样式。 |
| `.ai/project.md` | 记录本次前端 UI 调整。 |

## 实施步骤
1. 在 `BottomBar` 增加 `onSettingsOpen`、`settingsActive`、`settingsDisabled` 入参，并在右侧栏底部渲染设置按钮。
2. 右侧模式按钮改为图标在上、中文标签在下，选中态统一使用粉色，标签按截图文案展示。
3. `SettingsPopup` 删除内置左上角打开按钮，保留遮罩和设置面板，由右侧栏按钮触发。
4. 美颜底部浮层使用半透明圆角面板，滑杆位于面板内，三项美颜按钮为描边卡片，选中态粉色。
5. 运行 TypeScript 检查和 lint 诊断，修复新增错误。

## 验证方式
- `cd my-app && npx tsc --noEmit`
- 使用 `ReadLints` 检查改动文件。
- 人工检查：右侧栏应依次显示「画中画方形 / 画中画圆形 / 左右布局 / 上下布局 / 美颜 / 设置」，左上角不再出现设置按钮。

## 回滚方案
- 回退上述目标文件即可恢复原 UI 入口和美颜面板样式。

## 目标编辑文件清单
- `my-app/App.tsx`
- `my-app/src/components/BottomBar.tsx`
- `my-app/src/components/SettingsPopup.tsx`
- `my-app/src/components/BeautyPanel.tsx`
- `my-app/src/styles.ts`
- `.ai/project.md`
