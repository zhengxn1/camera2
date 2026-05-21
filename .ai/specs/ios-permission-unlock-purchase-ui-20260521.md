# iOS 授权与视频解锁购买 UI 任务书

## 目标
- 将相机权限、相册权限、视频解锁购买、支付等待状态和购买后按钮状态统一调整为中文 iOS 风格体验，并删除支付调试残留。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/App.tsx` | 购买弹窗开关、购买/恢复触发时机、支付等待状态承接、删除调试日志 |
| `my-app/src/components/PermissionGate.tsx` | 相机权限页改为 iOS 风格中文授权弹窗 |
| `my-app/src/components/MediaPermissionBanner.tsx` | 相册权限提示由横幅改为 iOS 风格中文授权弹窗 |
| `my-app/src/components/VideoUnlockSheet.tsx` | 视频解锁弹窗重做布局、中文文案、价格加载与购买等待状态 |
| `my-app/src/components/BottomBar.tsx` | 拍照/视频模式中文化，视频解锁后快门红色可拍摄状态，优化未解锁按钮样式 |
| `my-app/src/components/CameraSurface.tsx` | 原生相机模块加载提示中文化 |
| `my-app/src/components/RecordingIndicator.tsx` | 录制状态提示中文化 |
| `my-app/src/components/SettingsPopup.tsx` | 设置按钮、设置弹窗标题和比例设置文案中文化 |
| `my-app/src/components/AudioLevelIndicator.tsx` | 音频指示文字中文化 |
| `my-app/src/hooks/useMediaPermission.ts` | 相册权限失败提示中文化 |
| `my-app/src/hooks/useDualCameraSession.ts` | 拍照、录像、保存、相机错误等用户提示中文化 |
| `my-app/src/hooks/useVideoUnlock.ts` | 删除调试日志和多余 Alert，补充中文状态提示和商品价格加载状态 |
| `my-app/src/constants.ts` | 右侧布局模式 accessibility label 中文化 |
| `my-app/src/native.ts` | 原生模块诊断文案中文化或限制为开发错误信息 |
| `my-app/src/styles.ts` | 新增/调整 iOS 风格弹窗、解锁卡片、等待态、快门按钮样式 |
| `my-app/native/LocalPods/DualCamera/VideoUnlockModule.swift` | 删除 StoreKit 调试 `NSLog`，保留必要错误返回 |

## 实施步骤
1. 统一中文文案
   - 全 app 用户可见按钮、提示、弹窗、accessibility label 改为中文。
   - 修复现有乱码文案，例如 `瑙ｉ攣...`、`鎭㈠...`、`鈫?`。
   - `Photo` 改为 `拍照`，`Video` 改为 `视频`。

2. 相机权限弹窗
   - `PermissionGate` 的 `not_determined` 状态改为 iOS 风格居中授权卡片。
   - 背景保持黑色或相机风格暗底，卡片使用圆角、留白、主按钮。
   - 文案：
     - 标题：`需要相机权限`
     - 说明：`请允许访问前后摄像头，用于分屏预览、拍照和视频录制。`
     - 按钮：`允许访问相机`
   - `denied` 状态文案：
     - 标题：`权限未开启`
     - 说明：`请在系统设置中开启相机权限。`

3. 相册权限弹窗
   - 移除当前底部横幅式 `MediaPermissionBanner` 视觉，改为与相机权限一致的 iOS 风格弹窗。
   - 文案：
     - 标题：`需要相册权限`
     - 说明：`请允许访问相册，用于保存照片和视频。`
     - 按钮：`允许访问相册`
   - `useMediaPermission.ensure()` 拒绝权限后的 Alert 改中文；如已有可见权限弹窗，避免重复弹出多余 Alert。

4. 视频解锁弹窗布局
   - 将 `VideoUnlockSheet` 从底部 sheet 改为居中 iOS 风格购买卡片。
   - 外层为暗色遮罩，内层为圆角半透明卡片，右上角关闭按钮。
   - 卡片内容顺序：
     1. 视频解锁图标
     2. 标题：`解锁视频录制`
     3. 说明：`解锁2K视频录制 · 一次购买，终身使用\n记录精彩瞬间`
     4. 分隔线
     5. 主购买按钮
     6. 恢复购买按钮
   - 关闭按钮文案或 accessibility label 使用中文；视觉上可用 `×` 图标。

5. 价格展示
   - 购买按钮价格必须使用 StoreKit 返回的 `product.displayPrice`。
   - 不在前端写死 `US$0.99`、`¥6.00` 或任何固定币种。
   - 商品未加载完成时，购买按钮显示 `正在获取价格...` 并禁用。
   - 商品加载成功后，购买按钮显示 `立即解锁 - {displayPrice}`。
   - 商品加载失败时，显示中文错误态，例如 `暂时无法获取价格，请稍后再试`，并禁止发起购买。

6. 支付等待状态
   - 点击购买后不要立即关闭解锁弹窗。
   - `purchasing=true` 时保持弹窗可见，禁用关闭、购买、恢复按钮。
   - 显示 `ActivityIndicator` 和等待文案：
     - 发起购买后：`正在连接 App Store...`
     - 等待 StoreKit 返回或交易校验时：`正在确认购买，请稍候...`
   - 支付成功后自动关闭弹窗并刷新 `unlocked`。
   - 用户取消支付不弹错误，只恢复可操作状态。
   - pending 状态中文提示：`购买正在等待确认，完成后将自动解锁。`

7. 解锁后快门状态
   - 未解锁且处于视频模式时，快门按钮使用更精致的 iOS 风格锁定状态，避免当前粗糙锁图标。
   - 支付完成并处于视频模式时，快门按钮显示红色可录制状态。
   - 拍照模式快门保持原白色样式不变。
   - 录像中沿用红色停止样式，不破坏现有录制开始/停止状态。

8. 删除多余弹窗和日志
   - 删除 `App.tsx` 和 `useVideoUnlock.ts` 中支付调试 `console.log` / `console.warn`。
   - 删除 `VideoUnlockModule.swift` 中 `[VideoUnlock]` 调试 `NSLog`。
   - 保留真正失败时的 Promise reject 和必要前端中文错误提示。
   - 支付成功不再额外弹出成功 Alert；通过 UI 状态变化体现已解锁。
   - 恢复购买仅在结果需要用户知道时提示：
     - `已恢复购买`
     - `未找到可恢复的购买记录`

## 验证方式
- 在 `my-app/` 下运行项目现有类型检查或构建检查；若无专用脚本，至少执行 `npm run` 查看可用脚本后选择合适验证命令。
- 使用 iOS 真机或 StoreKit 测试环境手动验证：
  1. 首次启动显示中文 iOS 风格相机权限弹窗。
  2. 保存照片/视频前显示中文 iOS 风格相册权限弹窗。
  3. 未解锁时点击视频拍摄，显示新解锁弹窗。
  4. 商品价格按当前 App Store 地区显示，不写死币种。
  5. 输入 Apple ID 密码后等待期间弹窗内有加载提示，不出现空等。
  6. 支付成功后弹窗关闭，视频快门变红色可拍摄，拍照快门仍为白色。
  7. 取消支付不出现错误弹窗。
  8. Xcode / Metro 日志中不再出现 `[VideoUnlock]` 调试流水日志。

## 回滚方案
- 如 UI 或支付状态出现异常，回滚本任务涉及文件即可恢复旧授权提示、旧购买 sheet 和旧支付状态逻辑。
- `VideoUnlockModule.swift` 仅删除日志，不改变 StoreKit 购买、恢复和权益校验核心逻辑；如需排查支付，可临时恢复少量定向日志。

## 目标编辑文件清单
- `my-app/App.tsx`
- `my-app/src/components/PermissionGate.tsx`
- `my-app/src/components/MediaPermissionBanner.tsx`
- `my-app/src/components/VideoUnlockSheet.tsx`
- `my-app/src/components/BottomBar.tsx`
- `my-app/src/components/CameraSurface.tsx`
- `my-app/src/components/RecordingIndicator.tsx`
- `my-app/src/components/SettingsPopup.tsx`
- `my-app/src/components/AudioLevelIndicator.tsx`
- `my-app/src/hooks/useMediaPermission.ts`
- `my-app/src/hooks/useDualCameraSession.ts`
- `my-app/src/hooks/useVideoUnlock.ts`
- `my-app/src/constants.ts`
- `my-app/src/native.ts`
- `my-app/src/styles.ts`
- `my-app/native/LocalPods/DualCamera/VideoUnlockModule.swift`
