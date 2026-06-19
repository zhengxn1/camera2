# 保存美颜不生效修复技术规格书

## 目标
- 修复真机保存照片/视频时前置美颜不生效的问题。
- 保证前置画面在以下保存结果中都应用当前美颜参数：双摄合成照片、前置独立照片、双摄合成视频、前置独立视频。
- 后置画面保持原始画面，不进入美颜管线。
- 不重做预览架构，不改 UI，不改 GPUPixel framework 构建方式；只修保存链路和实际 iOS 编译副本不一致。

## 当前判断
- `native/LocalPods/DualCamera` 与 `ios/LocalPods/DualCamera` 当前不一致。
- Xcode 实际编译的是 `ios/LocalPods/DualCamera`，但该目录仍保留旧逻辑：
  - `DualCameraView+Composition.m` 中保存/录像合成路径的 `front = [self beautifiedFrontImage:front]` 被注释，注释说明是“临时停用保存/录像合成路径的美颜”。
  - `DualCameraViewManager.m` / `DualCameraView.h` / `DualCameraView.m` 仍使用旧字段 `frontBeautyTone`、`frontBeautySharpness`，而 JS 当前传入的是 `frontBeautyWhiten`。
- 因此即使 JS 参数正确，真机保存路径仍可能走旧字段或 raw 前置帧。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.h` | 声明带 `source` 的保存美颜/合成方法，供拍照和录像路径输出可诊断日志。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m` | 恢复并统一保存合成路径的前置美颜处理；只对 front slot 生效，back 不处理。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m` | 拍照保存必须调用带 `source:@"photo"` 的合成入口；单前且美颜开启时不能绕到 raw `AVCapturePhotoOutput` 保存。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m` | 实时录像保存必须调用带 `source:@"recording"` 的合成入口；独立前置 writer 若存在，也要使用同一前置美颜处理。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView.h` | 统一 native prop 为 `frontBeautySmooth`、`frontBeautyBrighten`、`frontBeautyWhiten`。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | 统一参数存储、GPUPixel adapter 参数传递和诊断日志。 |
| `my-app/native/LocalPods/DualCamera/DualCameraViewManager.m` | 接收 JS 当前传入的 `frontBeautyWhiten`，删除旧 `tone/sharpness` 接口依赖。 |
| `my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h` | 统一 adapter 参数名，确保 `whiten` 被接收。 |
| `my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm` | 保存链路调用失败时必须有明确日志，并降级到 Core Image 而不是静默 raw。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.h` | 与 canonical native 文件保持一致，确保 Xcode 当前编译副本生效。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.m` | 同上。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Capture.m` | 同上。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Recording.m` | 同上。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView.h` | 同上。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView.m` | 同上。 |
| `my-app/ios/LocalPods/DualCamera/DualCameraViewManager.m` | 同上。 |
| `my-app/ios/LocalPods/DualCamera/GPUPixelBeautyAdapter.h` | 同上。 |
| `my-app/ios/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm` | 同上。 |
| `my-app/src/hooks/useDualCameraSession.ts` | 如果当前 JS 仍只处理单 `uri`，需恢复兼容 `uris` 的保存逻辑，避免三份保存回退。但本次不改 UI。 |

## 契约设计
- **数据**
  - JS 到 Native 的美颜参数只保留：
    - `frontBeautyEnabled: boolean`
    - `frontBeautySmooth: number`
    - `frontBeautyBrighten: number`
    - `frontBeautyWhiten: number`
  - Native 判断保存美颜是否启用：
    - `frontBeautyEnabled == YES`
    - 且 `smooth/brighten/whiten` 至少一个大于 0。
  - 废弃保存链路里的 `frontBeautyTone`、`frontBeautySharpness`。

- **保存处理**
  - 建立唯一前置保存处理入口：
    - `beautifiedFrontImage:image source:source`
  - 所有保存合成中的 front slot 都必须走该入口：
    - `source=photo`
    - `source=recording`
    - `source=warmup`
    - 如有三份保存独立前置：`source=photo_front` / `source=recording_front`
  - 该入口不负责镜像、裁剪、布局；镜像和布局仍由 `preparedCameraImage` 和 layout state 处理，避免人物拉伸或方向回退。
  - back slot 禁止调用该入口。

- **降级策略**
  - 优先走 GPUPixel。
  - GPUPixel 返回 nil 或不可用时，必须走 Core Image fallback。
  - 只有在 `frontBeautyEnabled == NO` 或三项参数全 0 时才允许返回 raw。
  - fallback 也要有可见效果，不能只打印日志。

- **日志**
  - 每次拍照开始打印：
    - `[BeautyCapture] photo layout=... useWysiwygFrames=... enabled=... smooth=... brighten=... whiten=...`
  - 每次录像开始打印：
    - `[BeautyCapture] video layout=... realtime=... enabled=... smooth=... brighten=... whiten=...`
  - 每个保存源首次处理打印：
    - `[BeautySave] source=... layout=... front=... back=... shouldBeautifyFront=... enabled=... smooth=... brighten=... whiten=...`
    - `[BeautyProcess] source=... pipeline=gpupixel|coreimage|raw reason=... input=... output=...`
  - 如果 Xcode 里看不到这些日志，说明当前运行的 app 没有编译到本次 iOS LocalPods 代码，优先清理 DerivedData / Clean Build Folder / 重新 pod install。

## 实施步骤
1. 以 `native/LocalPods/DualCamera` 为 canonical，把当前已经存在的新参数、新日志、新保存入口整理完整。
2. 将 `ios/LocalPods/DualCamera` 中所有旧 `tone/sharpness` 字段替换为 `whiten`，并恢复保存/录像合成路径的前置美颜调用。
3. 在 `DualCameraView+Composition.m` 中保留带 `source` 的 `compositedImageForLayoutState:front:back:highQuality:source:`，旧无 `source` 方法只委托到它。
4. 在 `DualCameraView+Capture.m` 中：
   - WYSIWYG 拍照调用 `source:@"photo"`；
   - 单前且美颜开启时使用 WYSIWYG frame 保存，不走 raw `AVCapturePhotoOutput`；
   - PhotoOutput delegate 路径仅用于无美颜单摄 raw 保存。
5. 在 `DualCameraView+Recording.m` 中：
   - 实时合成录像调用 `source:@"recording"`；
   - warmup 调用 `source:@"warmup"`；
   - 如仓库当前恢复了三份 writer，独立前置 writer 必须先调用 `beautifiedFrontImage:source:@"recording_front"`，后置 writer 保持 raw。
6. 不要直接全量复制整个 `ios/LocalPods/DualCamera` 目录覆盖 framework；只同步目标编辑文件清单中的源码文件，避免误删 `Frameworks/gpupixel.framework`。
7. 更新 `.ai/project.md` 追加一条变更记录，说明保存美颜链路已同步到 iOS 实际编译副本。

## 验证方式
- 静态检查：
  - `rg "frontBeautyTone|frontBeautySharpness" native/LocalPods/DualCamera ios/LocalPods/DualCamera` 应无命中。
  - `rg "frontBeautyWhiten|BeautySave|BeautyProcess|source:@\"photo\"|source:@\"recording\"" native/LocalPods/DualCamera ios/LocalPods/DualCamera`
  - `diff -qr native/LocalPods/DualCamera ios/LocalPods/DualCamera` 只允许 framework 签名/资源等非本次源码差异；本次目标源码文件不应有差异。
- JS 编译：
  - `npx tsc --noEmit`
- 插件检查：
  - `node -c plugin/withDualCamera.js`
- iOS 编译：
  - `cd ios && pod install`
  - `xcodebuild -workspace ios/KIRO.xcworkspace -scheme KIRO -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 真机验证：
  - Xcode 控制台必须看到 `[BeautyCapture]`、`[BeautySave]`、`[BeautyProcess]`。
  - 前置美颜参数设到明显值后拍照，合成图和前置独立图应有美颜；后置独立图无美颜。
  - 录制视频后，合成视频和前置独立视频应有美颜；后置独立视频无美颜。
  - 关闭美颜或三项参数归零后，保存结果恢复 raw。

## 回滚方案
- 若修复后保存性能明显下降：
  - 保留参数同步和日志；
  - 临时只关闭视频逐帧 GPUPixel，视频 fallback 到 Core Image 轻量处理；
  - 照片保存仍保留完整 GPUPixel/CI 美颜。
- 若 GPUPixel 在保存线程崩溃：
  - 在 adapter 层禁用 GPUPixel 保存调用，强制走 Core Image fallback；
  - 不回滚 JS 参数和保存链路入口。

## 目标编辑文件清单
- `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView.m`
- `my-app/native/LocalPods/DualCamera/DualCameraViewManager.m`
- `my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h`
- `my-app/native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Capture.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Recording.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraView.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraViewManager.m`
- `my-app/ios/LocalPods/DualCamera/GPUPixelBeautyAdapter.h`
- `my-app/ios/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm`
- `my-app/src/hooks/useDualCameraSession.ts`
- `.ai/project.md`
