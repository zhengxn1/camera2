# 前置美颜误作用后置排查与隔离技术规格书

## 目标
- 确保美颜只作用于真实前置摄像头帧，不作用于后置摄像头帧。
- 明确保存链路中美颜发生的位置：必须在前置单路帧进入合成前处理，禁止对最终合成图整帧处理。
- 修复/防止后置保存结果看起来也被美颜的问题。
- 补齐保存输出身份日志，能从 Xcode 控制台直接判断每个保存文件是 `combined`、`front` 还是 `back`，以及是否应用了美颜。

## 当前判断
- 当前 `DualCameraView+Composition.m` 的美颜调用位于 `compositedImageForLayoutState:front:back:highQuality:source:` 内：
  - 先判断 `shouldBeautifyFront`；
  - 再执行 `front = [self beautifiedFrontImage:front source:composeLogKey]`；
  - 最后才分别执行 `preparedCameraImage:back...` 和 `preparedCameraImage:front...` 并合成。
- 因此当前设计上美颜是“合成前的前置帧处理”，不是“合成后的整帧滤镜”。
- 后置也有美颜感的风险点不是 `CIColorControls` 直接作用于合成图，而是：
  1. `beautifiedFrontImage` 只看方法名，不携带相机身份；任何调用者传入后置帧都会被处理。
  2. `compositedImageForLayoutState` 有兜底逻辑：`layout=back && !back` 时 `back = front`，`layout=front && !front` 时 `front = back`，这会模糊“画面槽位”和“真实相机身份”。
  3. 当前保存事件仍只发送单 `uri`，仓库中的 native 代码没有真正发 `uris.combined/front/back`；如果真机出现三份保存，可能是 Xcode 当前运行包或 ignored `ios/` 副本与 Git tracked native 不一致。
  4. `realtimeOutputAdjustedImage` 是合成后对整帧视频做曝光调整，虽然不是美颜，但会影响前后置整个合成视频，可能被误认为后置也变了。
  5. 日志只有 `front=1 back=1 shouldBeautifyFront=1`，没有记录“被处理的 CIImage 来自哪个 AVCaptureOutput”，无法证明传入 `front` 参数的一定是真前置帧。

## 影响范围
| 文件 | 原因 |
|---|---|
| `my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h` | 增加前/后置帧身份字段或轻量帧容器，保存最新帧时记录相机来源、序号、时间戳。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m` | 在 `AVCaptureVideoDataOutput` 回调中记录 frame source；拍照保存时输出 combined/front/back 身份日志。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.h` | 声明明确的前置专用处理入口，避免通用 `CIImage` 被误处理。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m` | 将美颜入口改成带相机身份校验；去掉可能让后置帧进入前置处理的隐式兜底；合成后禁止再做美颜。 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m` | 录像合成、warmup、后续三份 writer 必须传递/记录帧身份；确认合成后只允许非美颜的编码色彩处理。 |
| `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.h` | 如恢复三份保存，声明 `uris` 事件接口。 |
| `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.m` | 如恢复三份保存，发送 `uri` + `uris`，并明确每个保存输出身份。 |
| `my-app/src/hooks/useDualCameraSession.ts` | 已兼容 `uris`，但需要确认空列表/重复 uri 处理和日志命名不误导用户。 |
| `.ai/project.md` | 记录本次前置美颜隔离修复。 |

## 契约设计
- **数据**
  - Native 内部区分两个概念：
    - `cameraSource`: 真实相机来源，只能是 `front` 或 `back`。
    - `layoutSlot`: 合成布局槽位，可以是 `frontSlot` 或 `backSlot`，由布局决定显示在哪里。
  - 美颜只能在 `cameraSource == front` 时执行。
  - `layoutSlot == frontSlot` 不能作为美颜依据；后续任何翻转、PiP 主副切换、上下/左右交换都不能改变真实相机来源。

- **接口**
  - 保留旧事件兼容：
    - `uri` 继续指向默认/合成文件。
  - 如果保存三份，事件必须包含：
    - `uris.combined`
    - `uris.front`
    - `uris.back`
  - 如果当前 native 尚未实现三份输出，不要在 JS 伪造三份；只保存 native 实际返回的文件。

- **处理顺序**
  - 正确顺序必须是：
    1. 采集前置/后置 raw frame；
    2. 仅对真实前置 raw frame 执行美颜；
    3. 按布局进行镜像、裁剪、缩放；
    4. 合成 combined；
    5. 写 JPEG/视频帧。
  - 禁止顺序：
    - 先合成 combined 再整体美颜；
    - 根据布局槽位名字处理美颜；
    - 后置独立输出复用已经美颜过的 combined 或 front frame。

- **日志**
  - 每次保存至少打印：
    - `[BeautyRoute] source=photo|recording output=combined layout=... frontCamera=front backCamera=back beautifyFront=... beautifyBack=0`
    - `[BeautyRoute] output=front cameraSource=front beauty=applied|skipped reason=...`
    - `[BeautyRoute] output=back cameraSource=back beauty=never`
  - 如果发现 `output=back` 出现 `beauty=applied`，视为代码错误，应直接阻断保存或降级为 raw back。

## 实施步骤
1. 在保存最新帧时记录真实相机来源：
   - `frontVideoDataOutput` 产生的帧标记为 `front`；
   - `backVideoDataOutput` 产生的帧标记为 `back`。
2. 重命名或新增前置专用入口，例如：
   - `beautifiedImage:image cameraSource:source usage:usage`
   - 内部只有 `cameraSource == front` 才允许调用 GPUPixel/Core Image。
3. 修改 `compositedImageForLayoutState`：
   - 不再只用 `hasFrontFrame && layout != back` 判断；
   - 明确对“真实前置帧”处理；
   - 删除或收紧 `back = front` / `front = back` 兜底，至少在美颜开启时禁止兜底导致相机身份混淆。
4. 检查 `realtimeOutputAdjustedImage`：
   - 保留它作为视频整体曝光/色彩输出处理时，日志必须标明它不是 beauty；
   - 如果真机误判明显，临时将它关闭或只在明确 debug flag 下启用。
5. 如果当前需求仍要求三份保存，恢复 native `uris` 输出：
   - combined 使用合成图；
   - front 使用真实前置帧经过美颜；
   - back 使用真实后置 raw 帧；
   - 三者路径分别写入事件 `uris`。
6. 同步修改 `native/LocalPods/DualCamera` 和 `ios/LocalPods/DualCamera` 对应文件；注意 `ios/` 被 `.gitignore` 忽略，但本机 Xcode 当前编译依赖它。
7. 更新 `.ai/project.md`。

## 验证方式
- 静态检查：
  - `rg "beautifiedFrontImage|beautifiedImage|BeautyRoute|realtimeOutputAdjustedImage|sendPhotoSaved|sendRecordingFinished" native/LocalPods/DualCamera ios/LocalPods/DualCamera`
  - `diff -q native/LocalPods/DualCamera/DualCameraView+Composition.m ios/LocalPods/DualCamera/DualCameraView+Composition.m`
  - `diff -q native/LocalPods/DualCamera/DualCameraView+Capture.m ios/LocalPods/DualCamera/DualCameraView+Capture.m`
  - `diff -q native/LocalPods/DualCamera/DualCameraView+Recording.m ios/LocalPods/DualCamera/DualCameraView+Recording.m`
- 编译：
  - `npx tsc --noEmit`
  - `node -c plugin/withDualCamera.js`
  - `cd ios && pod install`
  - `xcodebuild -workspace ios/KIRO.xcworkspace -scheme KIRO -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 真机验证：
  - 设置美颜参数到明显值。
  - 拍照保存 combined/front/back：
    - combined 中只有前置区域有美颜；
    - front 独立图有美颜；
    - back 独立图无美颜。
  - 录制保存 combined/front/back：
    - combined 中只有前置区域有美颜；
    - front 独立视频有美颜；
    - back 独立视频无美颜。
  - Xcode 日志必须出现 `output=back cameraSource=back beauty=never`。

## 回滚方案
- 如果隔离后前置保存美颜丢失：
  - 保留 `cameraSource` 日志；
  - 临时只在 `output=front` 和 `combined.frontSlot` 启用 Core Image fallback；
  - 禁用 GPUPixel 保存调用，避免 adapter 误路由。
- 如果三份保存恢复引入不稳定：
  - 保留 combined 保存；
  - 暂停 front/back 独立 writer；
  - 不回退相机身份隔离和日志。

## 目标编辑文件清单
- `my-app/native/LocalPods/DualCamera/DualCameraView_Internal.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Composition.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m`
- `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.h`
- `my-app/native/LocalPods/DualCamera/DualCameraEventEmitter.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView_Internal.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Capture.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraView+Recording.m`
- `my-app/ios/LocalPods/DualCamera/DualCameraEventEmitter.h`
- `my-app/ios/LocalPods/DualCamera/DualCameraEventEmitter.m`
- `my-app/src/hooks/useDualCameraSession.ts`
- `.ai/project.md`
