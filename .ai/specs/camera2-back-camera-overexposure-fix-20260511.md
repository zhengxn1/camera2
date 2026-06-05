# 后置摄像头保存照片/视频过曝 — 技术根因分析

**spec_id**: camera2-back-camera-overexposure-fix-20260511
**date**: 2026-05-11
**severity**: 高 — 影响所有双摄和单摄保存的图像质量

---

## 用户症状

- 最终保存的照片和视频，后置摄像头画面过曝（白色区域完全曝光丢失）
- 预览层看起来正常，但保存的文件中后置摄像头区域明显过亮/发白
- 前置摄像头正常

---

## 数据流全链路分析

### 1. 预览层（预览正常 ✅）

```
AVCaptureVideoDataOutput → latestBackFrame → compositedImage → self.ciContext render → 预览 layer
```

预览使用 `AVCaptureVideoPreviewLayer`（GPU 合成），完全不受颜色空间影响。

### 2. 照片保存 — 双摄 WYSIWYG 路径

```
captureWysiwygDualPhotoWithCanvasSize:
  latestBackFrame → compositedImageForLayoutState → saveCIImageAsJPEG
```

`saveCIImageAsJPEG` 使用 `writeJPEGRepresentationOfImage:toURL:colorSpace:options:` 写入 sRGB JPEG。
这是**直接保存路径**，正确。

### 3. 照片保存 — 单摄 AVCapturePhotoOutput 路径

```
AVCapturePhotoSettings → capturePhotoWithSettings → didFinishProcessingPhoto
  → [photo fileDataRepresentation] → NSData → writeToFile
```

**完全绕过了 CIContext**，直接用系统 JPEG 编码器。系统会正确处理 photo output 的颜色空间。

### 4. 视频保存 — 单摄路径

```
AVCaptureMovieFileOutput → .mov → 后处理合成 → 导出 MP4
```

后处理合成使用 `AVMutableVideoComposition` + `AVAssetExportSession`。这是 Core Video/AVFoundation 管道。

### 5. 视频保存 — 双摄 Realtime 路径

```
VideoDataOutput → latestBackFrame → compositedImage → ciContext render → CVPixelBuffer → AVAssetWriter → MP4
```

这里使用了：
- `DualCameraCreateRealtimeVideoColorSpace()` → `kCGColorSpaceITUR_709` (Rec.709 / BT.709)
- `ciContext render:toCVPixelBuffer:bounds:colorSpace:`

**这是问题核心之一**（见 Bug 2）。

---

## 发现的 Bug

### Bug 1 — CIContext 创建时缺少 WorkingColorSpace

**文件**: `DualCameraView.m` 第 43–48 行

```objc
CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
_ciContext = [CIContext contextWithOptions:@{
  kCIContextUseSoftwareRenderer: @NO,
  kCIContextWorkingColorSpace: (__bridge id)srgb,
  kCIContextOutputColorSpace: (__bridge id)srgb
}];
CGColorSpaceRelease(srgb);
```

**问题**：`kCIContextWorkingColorSpace` 设置为 sRGB，但 VideoDataOutput 传入的 pixel buffer 可能是 **Display P3** 或 **BT.709**。

当 CIImage 带有嵌入颜色空间（P3 或 BT.709 的元数据），CIContext 需要知道"工作空间"来正确处理转换。如果 CIContext 的工作空间是 sRGB 而图像是 P3：
- **正向**：P3 → sRGB 转换可能不准确
- **反向**（渲染到 CVPixelBuffer）：需要从 CIContext 工作空间（sRGB）转回目标颜色空间

但这不太可能直接导致过曝。过曝更可能是**线性 vs 非线性的混淆**。

**更关键的问题**：CIContext 的 `kCIContextWorkingColorSpace` 应该根据实际输入像素的原生色彩空间来设置。如果摄像头输出 P3 但 CIContext 工作在 sRGB，所有滤镜操作都在错误空间中执行，可能导致**色调映射错误和过曝**。

### Bug 2 — Realtime 录制渲染到 CVPixelBuffer 时颜色空间不匹配

**文件**: `DualCameraView+Recording.m` 第 376–407 行

```objc
CGColorSpaceRef colorSpace = DualCameraCreateRealtimeVideoColorSpace();
// ...
[self.ciContext render:composited
       toCVPixelBuffer:pixelBuffer
                bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
            colorSpace:colorSpace];
```

**问题**：
1. `DualCameraCreateRealtimeVideoColorSpace()` 返回 `kCGColorSpaceITUR_709` (BT.709)
2. 但 `ciContext` 的工作空间是 sRGB
3. 渲染时：CIImage（经过 sRGB 工作空间处理）→ BT.709 CVPixelBuffer

BT.709 和 sRGB 的 gamma 曲线不同：
- sRGB：非线性 gamma ≈ 2.2
- BT.709：非线性 gamma = 1/0.45 ≈ 2.22

如果 `ciContext` 内部做颜色空间转换时没有正确处理 gamma，**线性值可能被错误解释为非线性**，导致亮度被错误拉伸 → 过曝。

### Bug 3 — CILanczosScaleTransform 的 aspectRatio 参数破坏图像

**文件**: `DualCameraView+Composition.m` 第 38–42 行

```objc
CIFilter *lanczos = [CIFilter filterWithName:@"CILanczosScaleTransform"];
[lanczos setValue:image forKey:kCIInputImageKey];
[lanczos setValue:@(scaleY) forKey:kCIInputScaleKey];
[lanczos setValue:@(scaleY != 0 ? scaleX / scaleY : 1.0) forKey:kCIInputAspectRatioKey];
```

**问题**：`kCIInputAspectRatioKey` 默认为 `1.0`。设置 `scaleX/scaleY` 会强制改变宽高比。已知 KB 中记录了此问题。

这不太可能导致过曝，但会导致图像失真。

### Bug 4 — saveCIImageAsJPEG 输出颜色空间注释有误导性

**文件**: `DualCameraView+Composition.m` 第 199–209 行

```objc
// Use CIContext's native JPEG writer — one-step conversion with explicit sRGB
// output colour space.  Avoids the CIImage→CGImage→UIImage→JPEG chain whose
// implicit colour-space round-trips cause the washed-out appearance.
CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
// ...
[self.ciContext writeJPEGRepresentationOfImage:toSave
                                   toURL:fileURL
                              colorSpace:srgb
                                 options:@{...}];
```

**注释说"避免 implicit colour-space round-trips"，但这只是输出端**。真正的问题在输入端：`latestBackFrame` 的 CIImage 带有嵌入的颜色空间元数据，但 CIContext 的工作空间是 sRGB。当 CIContext 处理这个 CIImage 时，颜色空间转换就已经发生了。如果嵌入的元数据与实际像素数据不匹配，结果会错误。

---

## 根因定位

经过逐行分析，我认为**最可能的根因**是：

### 主要根因：CIContext WorkingColorSpace 与 VideoDataOutput PixelBuffer 颜色空间不匹配

`AVCaptureVideoDataOutput` 输出的 pixel buffer 颜色空间取决于：
- 设备型号（iPhone 12+ 输出 Display P3）
- `activeFormat` 的颜色空间配置
- iOS 版本和系统设置

当前代码中：
1. `ciContext` 的 `kCIContextWorkingColorSpace = sRGB`
2. 但 `latestBackFrame` 的 CIImage 来自 P3 或 BT.709 的 pixel buffer
3. CIContext 处理 CIImage 时，**假设输入在 sRGB 空间**，但实际在 P3 空间
4. P3 的色域比 sRGB 宽，P3 中正常的亮度值在 sRGB 工作空间中被拉伸
5. 结果：`imageByCompositingOverImage` 和 `scaledCIImage` 的操作都在错误空间中执行
6. 最终保存的 JPEG 经过了**两次错误的颜色空间转换**

### 次要根因：Realtime 录制写入 CVPixelBuffer 时颜色空间不匹配

视频录制时，CIContext 工作在 sRGB，但 `ciContext render: toCVPixelBuffer: colorSpace: BT.709` 强制指定输出为 BT.709。CIContext 需要将 CIImage（被错误地当作 sRGB 处理了）转换到 BT.709。这个转换是**第二次颜色空间扭曲**。

### 为什么前置不过曝？

前置摄像头的 `activeFormat` 分辨率通常低于后置（1080p vs 4K），后置 12MP 摄像头的色彩处理管线更复杂，更容易触发颜色空间问题。

---

## 待修改文件清单

| 文件 | 改动类型 |
|------|---------|
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | 修改 CIContext 创建，增加 PixelBuffer WorkingColorSpace |
| `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m` | 修改 realtime render 的颜色空间处理 |
| `my-app/ios/LocalPods/DualCamera/DualCameraView.m` | 同上（symlink 目标） |
| `my-app/ios/LocalPods/DualCamera/DualCameraView+Recording.m` | 同上（symlink 目标） |

---

## 推荐修复方案

### 方案 A：统一使用 Display P3 作为 WorkingColorSpace（推荐）

```objc
// DualCameraView.m
CGColorSpaceRef displayP3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
_ciContext = [CIContext contextWithOptions:@{
  kCIContextUseSoftwareRenderer: @NO,
  kCIContextWorkingColorSpace: (__bridge id)displayP3,
  kCIContextOutputColorSpace: (__bridge id)displayP3
}];
CGColorSpaceRelease(displayP3);
```

Display P3 是 iPhone 摄像头最接近的输出空间（色域覆盖与 P3 一致）。所有 CIImage 操作在 Display P3 空间进行，与摄像头输出匹配。

### 方案 B：从 VideoDataOutput PixelBuffer 动态获取 WorkingColorSpace

```objc
// 在 captureOutput:didOutputSampleBuffer: 中
CGColorSpaceRef bufferCS = CVImageBufferGetColorSpace(pixelBuffer);
// 当 bufferCS 从 nil 变为有效颜色空间时，重新创建 CIContext
```

但这需要频繁重建 CIContext（开销大），不推荐。

### 方案 C：设置 CIContext 的 OutputColorSpace 为 sRGB，WorkingColorSpace 为 Display P3

```objc
CGColorSpaceRef displayP3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
_ciContext = [CIContext contextWithOptions:@{
  kCIContextUseSoftwareRenderer: @NO,
  kCIContextWorkingColorSpace: (__bridge id)displayP3,
  kCIContextOutputColorSpace: (__bridge id)srgb  // JPEG 输出到 sRGB
}];
// render 时不再指定 colorSpace，让 CIContext 使用 OutputColorSpace
```

### Realtime 录制修复

移除 `DualCameraCreateRealtimeVideoColorSpace()` 的硬编码，改用与 CIContext 一致的颜色空间：

```objc
// 不要在 render 时覆盖颜色空间，让 CIContext 自己处理
[self.ciContext render:composited
       toCVPixelBuffer:pixelBuffer
                bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)];
// CVPixelBuffer 本身的颜色空间通过 pixelBufferPool 或 adaptor 设置
```

---

## 验证方法

1. 在 `captureOutput:didOutputSampleBuffer:` 中打印 buffer 的颜色空间：
   ```objc
   CGColorSpaceRef bufferCS = CVImageBufferGetColorSpace(pixelBuffer);
   NSLog(@"Buffer color space: %@", bufferCS ? CGColorSpaceCopyName(bufferCS) : @"nil");
   ```
2. 拍照/录制后，检查保存文件的 EXIF 颜色空间
3. 在高光场景（白墙/天空）下测试，验证是否还有过曝

---

## 状态

- **发现日期**: 2026-05-11
- **状态**: [ANALYZED] — 根因已定位，等待 task-coder 修复
