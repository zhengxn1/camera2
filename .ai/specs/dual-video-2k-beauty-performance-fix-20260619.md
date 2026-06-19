# 2K 视频录制美颜与卡顿修复技术规格书

## 目标
- 恢复双摄实时录制输出为 2K：9:16 输出 `1440x2560`。
- 保存视频中的前置画面必须有可见美颜效果。
- 后置画面永远不应用美颜。
- 录制期间关闭旧的前置美颜预览叠层，避免预览处理与录制处理抢实时渲染资源。
- 保持 SDR/BT.709，避免 HDR/HLG 导致后置发白、模糊。

## 影响范围
| 文件 | 原因 |
|---|---|
| native/LocalPods/DualCamera/DualCameraView+Composition.m | 调整录制保存美颜管线，增强录制 Core Image 美颜效果并保持后置隔离 |
| native/LocalPods/DualCamera/DualCameraView+Recording.m | 恢复 2K 输出尺寸、提高 HEVC 码率、录制开始时清理旧预览叠层 |
| native/LocalPods/DualCamera/DualCameraView+Capture.m | 录制期间阻止并清理旧 UIImageView 美颜预览叠层 |
| native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h | 预留美颜 adapter 契约，不改 JS |
| native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm | 保持 GPUPixel 预览/照片路径，不用于 2K 录制 raw-data 往返 |
| ios/LocalPods/DualCamera/对应文件 | Xcode 当前实际编译副本，需要与 native 同步 |
| ../.ai/project.md | 记录本次验证结果 |

## 契约设计
- **数据**：录制输出恢复 `1440x2560`；HEVC 码率提升到 2K 可用档；色彩仍为 `ITU_R_709_2`。
- **接口**：JS props、事件 payload 不变。
- **界面**：UI 不变；录制期间不显示旧的前置美颜预览 UIImageView 叠层。

## 实施步骤
1. 将 `realtimeRecordingOutputSizeForAspectRatio` 恢复为 `referenceWidth:1440.0`。
2. 将 `realtimeVideoBitRateForOutputSize` 调整为 2K HEVC 质量档，避免 16 Mbps 导致 2K 细节不足。
3. 录制开始前清空 `frontBeautyPreviewImageView`，并把 `frontBeautyPreviewRenderInFlight` 复位，避免旧预览回调重新显示。
4. `beautifiedImage(... usage:@"recording")` 保留轻量 Core Image 路径，但增强磨皮、提亮、美白效果，确保保存视频肉眼可见美颜。
5. 后置仍通过 `cameraSource:@"back"` 直接返回 raw，不参与任何美颜或后处理。
6. 同步 native LocalPods 到 ios LocalPods。

## 验证方式
- `npx tsc --noEmit`
- `xcodebuild -workspace ios/KIRO.xcworkspace -scheme KIRO -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 真机安装并拉日志，确认：
  - `output=1440x2560`
  - `AVVideoCodecKey = hvc1`
  - `ITU_R_709_2`
  - `BeautyProcess usage=recording cameraSource=front pipeline=coreimage reason=recording_2k_beauty`
  - `BeautyRoute source=recording output=back cameraSource=back beauty=never`
  - 长时间录制无持续 `frameMs > 33ms`，无持续 dropped frame。

## 回滚方案
- 若 2K 保存美颜仍超实时预算，保留 2K 与后置清晰度，降低录制保存美颜强度，不回退 1080p。

## 目标编辑文件清单
- native/LocalPods/DualCamera/DualCameraView+Composition.m
- native/LocalPods/DualCamera/DualCameraView+Recording.m
- native/LocalPods/DualCamera/DualCameraView+Capture.m
- native/LocalPods/DualCamera/GPUPixelBeautyAdapter.h
- native/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm
- ios/LocalPods/DualCamera/DualCameraView+Composition.m
- ios/LocalPods/DualCamera/DualCameraView+Recording.m
- ios/LocalPods/DualCamera/DualCameraView+Capture.m
- ios/LocalPods/DualCamera/GPUPixelBeautyAdapter.h
- ios/LocalPods/DualCamera/GPUPixelBeautyAdapter.mm
- ../.ai/project.md
