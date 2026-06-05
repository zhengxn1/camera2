# App Logo 更换规格书
# spec_id: app-logo-replace-20260509

## 目标
将 app logo 更换为 `assets/icon.png`

## 当前状态
- Expo managed workflow
- `app.json` 已配置 `"icon": "./assets/icon.png"`
- `assets/icon.png` 文件已存在（用户提供的新 logo）

## 修改清单

### 1. 验证 app.json 配置
**文件**: `my-app/app.json`
**当前值**: `"icon": "./assets/icon.png"` ✅ 已正确配置
**操作**: 无需修改

### 2. iOS 原生项目配置
**文件**: `my-app/ios/myapp/Images.xcassets/AppIcon.appiconset/`
**操作**: 确认 `Contents.json` 引用正确的 icon 源
**注意**: Expo 项目在 `npx expo prebuild` 后会自动从 `assets/icon.png` 生成 iOS App Icon

### 3. Android 原生项目配置
**文件**: `my-app/android/app/src/main/res/mipmap-*/ic_launcher.png`
**操作**: 确认 adaptive icon 配置正确
**注意**: Expo 项目 adaptive icon 使用 `assets/adaptive-icon.png`

### 4. Splash Screen 确认
**文件**: `my-app/app.json`
**当前值**: `"image": "./assets/splash-icon.png"`
**操作**: 如需同时更新启动图，确认 `assets/splash-icon.png` 已更新

## 目标文件清单

| 文件路径 | 操作 |
|---------|------|
| `my-app/app.json` | 确认（已正确） |
| `my-app/ios/myapp/Images.xcassets/AppIcon.appiconset/Contents.json` | 确认 |
| `my-app/android/app/src/main/res/mipmap-*/ic_launcher.png` | 确认 |
| `my-app/assets/icon.png` | 用户已提供 |

## 执行步骤

1. **验证 assets/icon.png 存在且有效**
2. **运行 `cd my-app && npx expo prebuild`** (如需重建原生项目)
3. **Xcode Clean + Build** 验证 iOS icon 生效

## 备注
- 这是纯配置/验证任务，无代码修改
- Expo 会自动处理 icon 的多尺寸生成
- 如使用 eas build，需要先 `eas icon:add` 或手动上传
