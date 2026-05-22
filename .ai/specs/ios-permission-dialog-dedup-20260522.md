# iOS 权限弹窗去重 技术规格书

## 目标
- 减少相机/相册授权时的重复弹窗：iOS 系统授权弹窗由系统展示，应用只在拒绝、不可用或保存授权失败后展示自定义提示；自定义提示统一调整为图 5 的浅色 iOS 弹窗风格。

## 结论
- iOS 首次相机授权由 `AVCaptureDevice requestAccessForMediaType` 触发系统弹窗，样式不可自定义，只能通过 `NSCameraUsageDescription` 配置说明文案。
- iOS 首次相册写入授权由 `expo-media-library` 的 `requestPermission` 触发系统弹窗，样式不可自定义，只能通过 `photosPermission` / `savePhotosPermission` 配置说明文案。
- 当前自定义 `PermissionGate` 和 `MediaPermissionBanner` 属于应用内前置说明，和系统弹窗连用会形成重复感。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/App.tsx` | 首次相机未决定时自动触发系统授权；移除常驻相册权限前置遮罩 |
| `my-app/src/hooks/useCameraPermission.ts` | 增加请求中状态，避免重复拉起系统相机弹窗 |
| `my-app/src/hooks/useMediaPermission.ts` | 只在保存需要时请求相册权限，失败后返回状态供 UI 展示，不再额外弹 RN Alert |
| `my-app/src/components/PermissionGate.tsx` | 改为请求中/拒绝/不可用提示，去掉首次授权前置按钮卡 |
| `my-app/src/components/MediaPermissionBanner.tsx` | 保留为相册拒绝后的自定义提示，采用图 5 浅色 iOS 风格 |
| `my-app/src/styles.ts` | 新增/调整权限弹窗样式 |
| `.ai/project.md` | 记录本次权限链路变更 |

## 实施步骤
1. 相机权限：
   - `useCameraPermission` 增加 `requesting` 状态。
   - `request` 内部在已有授权、请求中、模块缺失时直接返回，防止重复调用。
   - `App.tsx` 在 `cameraStatus === 'not_determined'` 且未请求中时自动调用 `requestCamera()`，让 iOS 直接展示系统弹窗。
2. 相机自定义提示：
   - `PermissionGate` 的 `not_determined` 状态改为“正在请求相机权限”的等待态。
   - `denied/unavailable` 状态显示浅色 iOS 弹窗风格卡片。
3. 相册权限：
   - 移除 `App.tsx` 里 `!media.granted` 的常驻 `MediaPermissionBanner`。
   - `useMediaPermission.ensure()` 在拍照/录制保存前触发系统授权；拒绝后设置 `blocked=true`。
   - `MediaPermissionBanner` 只在 `media.blocked` 时显示，支持关闭和再次请求。
4. 样式：
   - 权限提示卡采用图 5 风格：浅灰半透明卡片、大圆角、黑色文字、底部两个灰色胶囊按钮。
   - 避免全屏深色自定义授权卡与系统授权弹窗连续出现。

## 验证方式
- 在 `my-app/` 执行 `npx tsc --noEmit`。
- 人工检查：
  - 首次打开未授权相机时，应直接出现 iOS 系统相机授权弹窗，背后仅显示等待态。
  - 拒绝相机后，应显示应用自定义浅色提示卡。
  - 进入相机预览后，不应常驻相册授权遮罩；首次保存照片/视频时才出现 iOS 系统相册授权弹窗。
  - 拒绝相册授权后，才显示应用自定义浅色提示卡。

## 回滚方案
- 恢复 `App.tsx` 中的手动 `PermissionGate` 请求按钮和常驻 `MediaPermissionBanner` 挂载。
- 恢复 `useMediaPermission.ensure()` 的 `Alert.alert` 兜底提示。

## 目标编辑文件清单
- `my-app/App.tsx`
- `my-app/src/hooks/useCameraPermission.ts`
- `my-app/src/hooks/useMediaPermission.ts`
- `my-app/src/components/PermissionGate.tsx`
- `my-app/src/components/MediaPermissionBanner.tsx`
- `my-app/src/styles.ts`
- `.ai/project.md`
