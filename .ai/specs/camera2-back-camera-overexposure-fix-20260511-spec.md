# 后置摄像头过曝 — 技术契约与架构设计书

**spec_id**: camera2-back-camera-overexposure-fix-20260511
**date**: 2026-05-11
**severity**: 高 — 影响所有双摄和单摄保存的图像质量
**type**: 系统级颜色空间契约修复

---

## 一、问题背景与已知上下文

### 1.1 用户症状

- 预览层正常，但保存的照片/视频中**后置摄像头画面严重过曝**（白色区域完全曝光丢失）
- 前置摄像头正常
- 仅影响通过 `latestBackFrame` 路径保存的内容（双摄 WYSIWYG 照片、双摄 Realtime 录制）

### 1.2 已有知识（KB 快速定位）

| KB 条目 | 状态 | 关联 |
|---|---|---|
| `camera2-back-camera-overexposure-fix-20260511` | [ANALYZED] | 根因已定位 — CIContext WorkingColorSpace = sRGB 与 VideoDataOutput Display P3 不匹配 |
| `⚠️ CILanczosScaleTransform 的 aspectRatio 参数会破坏图像宽高比` | [FIXED] | 相关 — 不影响过曝 |

---

## 二、根因分析（已确认）

### 2.1 完整数据流

```
摄像头硬件 (Display P3 / BT.709)
  → AVCaptureVideoDataOutput pixel buffer (P3)
    → CIImage + kCIImageColorSpace=P3 (latestBackFrame)
      → CIContext (WorkingColorSpace = sRGB) ← 颜色空间不匹配！
        → compositedImageForLayoutState
          → 两条保存路径:

路径 A (双摄拍照 WYSIWYG):
  compositedImage → saveCIImageAsJPEG
    → CIContext writeJPEGRepresentationOfImage: colorSpace=sRGB
    → JPEG 文件 (过曝)

路径 B (双摄 Realtime 录制):
  compositedImage → CIContext render:toCVPixelBuffer: colorSpace=BT.709
    → AVAssetWriter → MP4 (过曝)
```

### 2.2 根因链

```
摄像头输出 Display P3
  CIImage 正确携带 P3 元数据
    CIContext WorkingColorSpace = sRGB ← 问题1：处理时假设 sRGB
      ↓
    所有滤镜操作 (imageByCompositingOverImage, scaledCIImage)
      在错误的颜色空间执行
        ↓
      色调映射错误，线性值被错误解释
        ↓
      高光区域饱和，白蒙蒙
```

### 2.3 颜色空间契约分析

| 操作 | 当前值 | 问题 |
|---|---|---|
| `CIImage` 创建（captureOutput） | `kCIImageColorSpace = P3/BufferCS` | ✅ 正确携带 |
| `CIContext WorkingColorSpace` | `kCGColorSpaceSRGB` | ❌ 应为 P3 |
| `CIContext OutputColorSpace` | `kCGColorSpaceSRGB` | ⚠️ 仅输出端正确 |
| `writeJPEG colorSpace` | `kCGColorSpaceSRGB` | ✅ JPEG 输出应为 sRGB |
| `render:toCVPixelBuffer: colorSpace` | `kCGColorSpaceITUR_709` | ⚠️ 与 Working 不一致 |
| `AVAssetWriter videoSettings` | BT.709 primaries | ✅ 视频标准色域 |

### 2.4 为什么前置摄像头不过曝

前置摄像头分辨率通常低于后置（1080p vs 4K/12MP），后置 12MP 摄像头的色彩处理管线更复杂，色域更宽（P3 覆盖率更高），颜色空间不匹配对其影响更大。

---

## 三、技术契约设计

### 3.1 CIContext 颜色空间契约

**原则**：CIContext 的 WorkingColorSpace 必须覆盖所有可能的输入颜色空间。

**修复方案**：将 `kCIContextWorkingColorSpace` 从 `kCGColorSpaceSRGB` 改为 `kCGColorSpaceDisplayP3`。

Display P3 色域与 P3 一致，覆盖 iPhone 摄像头输出的完整色域（sRGB 的子集）。所有 CIImage 操作在 Display P3 空间进行，与摄像头原生输出匹配。输出到 JPEG 时，CIContext 自动从 Display P3 转换到 sRGB（CIImage writeJPEG 带 colorSpace=sRGB 参数）。

### 3.2 Realtime 录制渲染契约

**原则**：`ciContext render: toCVPixelBuffer: colorSpace:` 不再硬编码 BT.709，让 CIContext 使用自身 OutputColorSpace。

**修复方案**：render 调用时不指定 colorSpace 参数，让 CIContext 根据自身 `kCIContextOutputColorSpace` 自动处理。CVPixelBuffer 的颜色空间通过 `CVBufferSetAttachment` 设置（与 `kCIContextOutputColorSpace` 一致）。

### 3.3 JPEG 输出契约（不变）

`sRGB` 是 JPEG/Web 的标准色域，输出端使用 sRGB 正确。

---

## 四、Schema 与接口变更

### 4.1 DualCameraView.m — commonInit

**文件**: `my-app/ios/LocalPods/DualCamera/DualCameraView.m`

```objc
// 修改前
CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
_ciContext = [CIContext contextWithOptions:@{
  kCIContextUseSoftwareRenderer: @NO,
  kCIContextWorkingColorSpace: (__bridge id)srgb,
  kCIContextOutputColorSpace: (__bridge id)srgb
}];
CGColorSpaceRelease(srgb);

// 修改后
CGColorSpaceRef displayP3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
_ciContext = [CIContext contextWithOptions:@{
  kCIContextUseSoftwareRenderer: @NO,
  kCIContextWorkingColorSpace: (__bridge id)displayP3,
  kCIContextOutputColorSpace: (__bridge id)displayP3
}];
CGColorSpaceRelease(displayP3);
```

### 4.2 DualCameraView+Recording.m — appendRealtimeVideoFrameAtTime

**文件**: `my-app/ios/LocalPods/DualCamera/DualCameraView+Recording.m`

**修改点 1**: `appendRealtimeVideoFrameAtTime:` 中 render 调用（大约第 401–407 行）

```objc
// 修改前
CGColorSpaceRef colorSpace = DualCameraCreateRealtimeVideoColorSpace();
if (colorSpace) {
  CVBufferSetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, colorSpace, kCVAttachmentMode_ShouldPropagate);
  CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
  CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
  CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
}
[self.ciContext render:composited
       toCVPixelBuffer:pixelBuffer
                bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
            colorSpace:colorSpace];
if (colorSpace) CGColorSpaceRelease(colorSpace);

// 修改后
// Use CIContext's OutputColorSpace (Display P3) for rendering.
// Pixel buffer color space set to match OutputColorSpace.
CGColorSpaceRef outputCS = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
if (outputCS) {
  CVBufferSetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, outputCS, kCVAttachmentMode_ShouldPropagate);
  CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_EBU_3213_E, kCVAttachmentMode_ShouldPropagate);
  CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_SMPTE_240M_1995, kCVAttachmentMode_ShouldPropagate);
  CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
}
[self.ciContext render:composited
       toCVPixelBuffer:pixelBuffer
                bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)];
if (outputCS) CGColorSpaceRelease(outputCS);
```

**修改点 2**: `prepareRealtimeRecordingPipelineForCanvasSize:` 中 render 调用（warmup 第 118–125 行和第 150–157 行）

同样将 `DualCameraCreateRealtimeVideoColorSpace()` 替换为 `kCGColorSpaceDisplayP3`，并移除 render 调用的 `colorSpace:` 参数。

**修改点 3**: `DualCameraCreateRealtimeVideoColorSpace()` 函数

**修改前**：
```objc
static CGColorSpaceRef DualCameraCreateRealtimeVideoColorSpace(void) {
  CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
  if (!colorSpace) {
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  }
  return colorSpace;
}
```

**修改后**：
```objc
// Returns the CIContext's OutputColorSpace for consistent render pipeline.
// Used for setting pixel buffer attachments to match what CIContext produces.
static CGColorSpaceRef DualCameraRealtimeOutputColorSpace(void) {
  return CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
}
```

> **注意**：`DualCameraCreateRealtimeVideoColorSpace()` 改名后，原有调用点改为使用新函数或直接使用 `kCGColorSpaceDisplayP3`。warmup 中不需要创建函数调用，直接使用 `kCGColorSpaceDisplayP3` 即可。

### 4.4 CILanczosScaleTransform aspectRatio 补充验证

**文件**: `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.m` 第 38–42 行

当前代码：
```objc
[lanczos setValue:@(scaleY) forKey:kCIInputScaleKey];
[lanczos setValue:@(scaleY != 0 ? scaleX / scaleY : 1.0) forKey:kCIInputAspectRatioKey];
```

KB 已知：`kCIInputAspectRatioKey` 默认 1.0 会破坏宽高比。但当前传入的是 `scaleX/scaleY`，这个值本身是为了补偿 scaleY 的宽高比。**不需要修改此处**，因为此处的 aspectRatio 恰好是用来修正 scaleY 不等于 scaleX 时引入的形变的，不是触发 bug 的"默认值 1.0"场景。

---

## 五、全栈影响面分析

### 5.1 受影响路径

| 路径 | 触发条件 | 修复效果 |
|---|---|---|
| 双摄 WYSIWYG 拍照 | 双摄布局（LR/SX/PiP）点击拍照 | ✅ 修复过曝 |
| 双摄 Realtime 录制 | 双摄布局录制视频 | ✅ 修复过曝 |
| 单摄拍照 | 单摄布局点击拍照 | ❌ 不受影响（绕过 CIContext） |
| 单摄录制 | 单摄布局录制视频 | ❌ 不受影响（使用 AVCaptureMovieFileOutput） |
| 预览层 | 所有模式 | ❌ 不受影响（AVCaptureVideoPreviewLayer GPU 合成） |

### 5.2 文件修改清单

| 文件（绝对路径） | 改动类型 | 改动内容 |
|---|---|---|
| `my-app/ios/LocalPods/DualCamera/DualCameraView.m` | 修改 | CIContext WorkingColorSpace: sRGB → Display P3 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Recording.m` | 修改 | render colorSpace 参数移除 + attachment 改为 Display P3 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Composition.m` | 无改动 | — |
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | 同步修改 | 同 ios 版本 |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m` | 同步修改 | 同 ios 版本 |

### 5.3 同步策略

`native/` 是开发源，`ios/` 是编译目标（两者当前是独立文件，非 symlink）。修复必须同时修改两个目录，确保下次 `pod install` 不会覆盖。

---

## 六、验证方法

### 6.1 颜色空间诊断日志

在 `captureOutput:didOutputSampleBuffer:` 中已有 `bufferCS` 获取代码。验证 `native/` 版本是否已包含诊断日志（KB spec 提到应打印颜色空间）。

### 6.2 修复后验证步骤

1. **双摄拍照**：在白墙/天空等高光场景下拍照，检查保存的 JPEG 中后置摄像头区域是否正常曝光，无白蒙蒙现象
2. **双摄录制**：在相同场景下录制视频，检查 MP4 中后置摄像头画面
3. **单摄回归**：确认单摄拍照和录制不受影响
4. **色彩回归**：确认颜色饱和度正常（修复后不应比原来"更淡"或"更浓"）

### 6.3 颜色科学验证

Display P3 是 sRGB 的超集（相同 gamma 2.2，相同白点 D65），将 CIContext 工作空间从 sRGB 改为 Display P3：
- 对于 sRGB 内容（前置摄像头）：行为完全一致
- 对于 Display P3 内容（后置摄像头）：正确处理，消除过曝
- JPEG 输出到 sRGB：CIContext 自动色域映射，无视觉变化

---

## 七、状态

- **spec_id**: camera2-back-camera-overexposure-fix-20260511
- **发现日期**: 2026-05-11
- **状态**: [SPEC_COMPLETE] — 技术蓝图完成，等待 task-coder 执行
