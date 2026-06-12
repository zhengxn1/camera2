# fmt Xcode 26 当前编译失败修复技术规格书

## 目标
- 修复 Xcode 26.x 下 `fmt` v11.0.2 编译失败，消除 `format-inl.h` 的 `Call to consteval function ... is not a constant expression` 和 `base.h` 的 `constexpr function never produces a constant expression`。
- 修复必须只作用于 `fmt` Pod，不全局降级 C++ 标准，不影响 React Native、DualCamera、GPUPixel 或其它 Pods。
- 让修复同时覆盖当前本地 `ios/Podfile` 和后续 Expo prebuild 通过 `plugin/withDualCamera.js` 重新生成 Podfile 的场景。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/plugin/withDualCamera.js` | 这是项目生成 iOS Podfile 的长期入口，需要把 fmt 兼容补丁写进 config plugin，避免 prebuild 后丢失。 |
| `my-app/ios/Podfile` | 这是当前 Xcode 实际构建读取的 Podfile；虽然 `ios/` 被 git ignore，但本机需要同步修复后重新 `pod install`。 |

## 根因分析
- 当前 `fmt` 版本是 `11.0.2`，Xcode 26.x 使用 Apple Clang + iOS SDK 26.x 编译时，`fmt` 在 C++20 下会启用 `FMT_USE_CONSTEVAL`，`FMT_STRING(...)` 会走 `basic_format_string` 的 `consteval` 构造器。
- 报错 `format-inl.h: Call to consteval function ... is not a constant expression` 是因为 `fmt` v11 的 `FMT_STRING_IMPL` 生成的匿名 `FMT_COMPILE_STRING` 在当前 Apple Clang 下不能作为稳定常量表达式。
- 报错 `base.h: constexpr function never produces a constant expression` 是错误使用 `FMT_USE_CONSTEXPR=0` 造成的副作用：`fmt/base.h` 里的 `ignore_unused` 被变成非 constexpr，但 `is_constant_evaluated` 仍声明为 constexpr，导致编译器直接报错。
- 旧规格中的 `FMT_DISABLE_CONSTEXPR_CHECK` 不适用于当前 `fmt` 11.0.2，本地头文件没有这个宏；继续使用它不会真正解决当前错误。

## 契约设计
- **数据**：无运行时数据变更。
- **接口**：无 JS/native API 变更。
- **界面**：无 UI 变更。
- **构建契约**：
  - 只对 target 名称为 `fmt` 的 Pod target 设置：
    - `CLANG_CXX_LANGUAGE_STANDARD = c++17`
    - `GCC_TREAT_WARNINGS_AS_ERRORS = NO`
    - `GCC_PREPROCESSOR_DEFINITIONS += FMT_USE_NONTYPE_TEMPLATE_ARGS=0`
  - 禁止设置 `FMT_USE_CONSTEXPR=0`。
  - 禁止修改 `ios/Pods/fmt/include/fmt/*.h` 这类第三方源码头文件。
  - 禁止对所有 Pods 全局设置 C++17，避免影响 React Native/GPUPixel。

## 实施步骤
1. 在 `my-app/plugin/withDualCamera.js` 的 Podfile patch 逻辑中，即使 `DualCamera` pod 已存在，也继续检查并注入 fmt 兼容块。
2. fmt 兼容块必须插入现有 `post_install do |installer| ... end` 的末尾、`end` 前。
3. fmt 兼容块只遍历 `installer.pods_project.targets` 中 `target.name == 'fmt'` 的 target。
4. 移除任何已经加入的 `FMT_USE_CONSTEXPR=0`。
5. 在当前本机 `my-app/ios/Podfile` 同步同样的 fmt 兼容块。
6. 运行 `cd my-app/ios && pod install`，让 `ios/Pods/Pods.xcodeproj` 重新生成 fmt target build settings。
7. 如 Xcode 仍缓存旧参数，执行 `xcodebuild clean` 或删除当前项目 DerivedData 后重建。

## 验证方式
- `node -c plugin/withDualCamera.js`
- `cd my-app/ios && pod install`
- 静态确认 fmt target：
  - `ruby -e "require 'xcodeproj'; p=Xcodeproj::Project.open('ios/Pods/Pods.xcodeproj'); t=p.targets.find{|x|x.name=='fmt'}; t.build_configurations.each{|c| puts [c.name, c.build_settings['CLANG_CXX_LANGUAGE_STANDARD'], c.build_settings['GCC_PREPROCESSOR_DEFINITIONS'].inspect].join(' | ')}"`
  - 预期 Debug/Release 都是 `c++17`，并且只包含 `FMT_USE_NONTYPE_TEMPLATE_ARGS=0`，不能包含 `FMT_USE_CONSTEXPR=0`。
- `xcodebuild -project ios/Pods/Pods.xcodeproj -target fmt -configuration Debug -sdk iphoneos CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -workspace ios/KIRO.xcworkspace -scheme KIRO -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 回滚方案
- 回滚 `my-app/plugin/withDualCamera.js` 中的 fmt 兼容块。
- 删除 `my-app/ios/Podfile` 中对应 fmt 兼容块。
- 重新运行 `cd my-app/ios && pod install`。

## 目标编辑文件清单
- `my-app/plugin/withDualCamera.js`
- `my-app/ios/Podfile`
