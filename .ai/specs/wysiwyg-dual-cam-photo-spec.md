# WYSIWYG 双摄拍照：VideoDataOutput 实时帧捕获方案

**spec_id**: wysiwyg-dual-cam-photo-20260427
**goal**: 双摄拍照所见即所得（WYSIWYG），支持用户自定义保存比例和各自画面大小
**status**: to-implement

---

## 一、根因：为什么 photo output 方案无法做到 WYSIWYG

### 问题 1：不同分辨率导致 crop 不对称

`AVCapturePhotoOutput` 输出的是摄像头硬件原生分辨率（前置 ~1080×1420，后置 ~1920×1440），与屏幕比例（~390×844）完全不同。用原生分辨率合成时：

```
前置 1080×1420 → 按 canvas 缩放后宽度=390 → 高度=844
后置 1920×1440 → 按 canvas 缩放后宽度=390 → 高度=316
```

两者在 canvas 上的高度不一致，无法精确对齐。

### 问题 2：photo output 固定分辨率与用户调整的比例不匹配

用户调整 PiP 大小/LR 分割比时，`AVCapturePhotoOutput` 无法实时响应，只能用 canvas 的当前 bounds 计算 crop，但 crop 区域来自 1080×1420 和 1920×1440 的不同原生图，crop 位置和预览所见必然有偏差。

### 问题 3：两次拍摄有微小时间差

`capturePhotoWithSettings:delegate:` 两次调用的时间差导致 front/back 不是同一时刻的画面，快速运动时会有重影。

---

## 二、WYSIWYG 架构：VideoDataOutput + 最新帧捕获

### 核心思路

用 `AVCaptureVideoDataOutput` 实时接收每个摄像头的原始帧（与预览完全同步），存入最新帧 buffer。快门按下时，直接从 buffer 取帧合成——合成的就是屏幕上此刻显示的内容。

```
用户屏幕显示的是什么 → 合成出来的就是什么
```

### 架构图

```
AVCaptureMultiCamSession
   │
   ├── frontInput
   │       └── frontVideoDataOutput ──→ (sessionQueue) ──→ _latestFrontBuffer
   │
   ├── backInput
   │       └── backVideoDataOutput ──→ (sessionQueue) ──→ _latestBackBuffer
   │
   ├── frontPhotoOutput ──→ (不使用，废弃)
   └── backPhotoOutput ──→ (不使用，废弃)

快门按下:
  1. 从 _latestFrontBuffer 取前置帧
  2. 从 _latestBackBuffer 取后置帧
  3. 按 canvas 当前 bounds + 用户指定比例 合成
  4. 导出 JPEG → 保存
```

### VideoDataOutput 技术细节

**是否支持两个 VideoDataOutput？**

`AVCaptureMultiCamSession` 的限制：每个 session 最多一个 `AVCaptureVideoDataOutput`。

但本项目架构中，两个摄像头分别来自 `frontInput` 和 `backInput`（两个不同的 `AVCaptureInputPort`）。关键问题：**同一个 port 只能连接到一个 video 数据输出**。

当前 session 配置：
```
frontInput → frontPhotoOutput  (只用到 photo output)
          → frontVideoDataOutput  (空闲，可连接)
backInput  → backPhotoOutput   (只用到 photo output)
          → backVideoDataOutput  (空闲，可连接)
```

由于 frontInput 和 backInput 是**两个独立的 input**，它们的 port 不冲突。因此：
- frontInput 的 video port → frontVideoDataOutput ✅
- backInput 的 video port → backVideoDataOutput ✅

两个 `AVCaptureVideoDataOutput` 互不冲突，可以在同一个 `AVCaptureMultiCamSession` 中使用。

---

## 三、保存比例与画面大小设计

### 保存比例

用户可选三种比例：`9:16`、`3:4`、`1:1`

```objc
// DualCameraView.h 新增属性
@property (nonatomic, copy) NSString *saveAspectRatio;  // @"9:16" | @"3:4" | @"1:1"
```

### 保存时的画面大小（各自占比）

用户可调整 front/back 在屏幕中的相对大小（对应 LR 分割比、SX 上下比、PiP 大小）。

这些值已经在运行时存在于 `self.dualLayoutRatio`、`self.pipSize` 等属性中，**快门按下时直接使用当前值**。

### 保存尺寸计算

对于选定的 aspect ratio，计算最终输出的 canvas size：

```
aspectRatio = "9:16" → width : height = 9 : 16
aspectRatio = "3:4"  → width : height = 3 : 4
aspectRatio = "1:1"  → width : height = 1 : 1

输出 canvas：取屏幕宽度为基准，按比例计算高度（或反过来）
例如屏幕 390×844，选择 9:16:
  canvasW = 390
  canvasH = 390 * 16 / 9 = 693
```

每个半区按比例映射到 canvas 上：
```
LR:  leftW = canvasW * dualLayoutRatio; rightW = canvasW * (1-dualLayoutRatio)
SX:  topH  = canvasH * (1-dualLayoutRatio); bottomH = canvasH * dualLayoutRatio
PiP: pipRect = CGRectMake(canvasW - s - 16, canvasH - s - 160, s, s)
       其中 s = canvasW * pipSize
```

---

## 四、拍摄流程（全新实现）

### 快门按下：`internalTakePhoto`

```
1. dispatch_async(sessionQueue) {
     if (!self.isConfigured) return
     if (self.usingMultiCam && self.isDualLayout) {
       // WYSIWYG: 从最新帧 buffer 取图
       CIImage *frontFrame = self.latestFrontFrame;
       CIImage *backFrame  = self.latestBackFrame;
       if (!frontFrame || !backFrame) {
         [self emitError:@"Camera not ready"]; return;
       }
       // 2. 计算保存 canvas size（按 aspect ratio）
       CGSize saveCanvas = [self canvasSizeForAspectRatio:self.saveAspectRatio];
       // 3. 合成（使用当前布局参数 + saveCanvas）
       dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
         CIImage *composited = [self compositeFront:frontFrame back:backFrame toCanvas:saveCanvas];
         NSString *path = [self saveCIImageAsJPEG:composited];
         dispatch_async(dispatch_get_main_queue(), ^{
           if (path) [self emitPhotoSaved:[NSString stringWithFormat:@"file://%@", path]];
           else [self emitError:@"Failed to save photo"];
         });
       });
     } else {
       // Single cam: 使用 backPhotoOutput
       ...
     }
   }
```

### 帧捕获：`videoDataOutput: outputSampleBuffer:`

```
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)buffer
           fromConnection:(AVCaptureConnection *)conn {
  // 转为 CIImage
  CIImage *ciImage = [self ciImageFromSampleBuffer:buffer];
  if (!ciImage) return;

  if (output == self.frontVideoDataOutput) {
    @synchronized(self) { self.latestFrontFrame = ciImage; }
  } else {
    @synchronized(self) { self.latestBackFrame = ciImage; }
  }
}
```

---

## 五、合成策略（完全重新设计）

### 核心原则

**按最终保存 canvas 比例裁剪，不按屏幕比例**。

```
屏幕: 390×844 (比例 ≈ 9:20)
保存: 9:16 → 390×693

front/back 各自按 390×693 的比例分配空间：
LR:  frontW = 390×dualLayoutRatio,  frontH = 693
     backW  = 390×(1-dualLayoutRatio), backH = 693

SX:  frontH = 693×(1-dualLayoutRatio), frontW = 390
     backH  = 693×dualLayoutRatio,     backW = 390
```

### 合成函数签名

```objc
// 新签名：传入最终 canvas size 和当前布局参数
- (CIImage *)compositeFront:(CIImage *)front
                        back:(CIImage *)back
                   toCanvas:(CGSize)canvasSize;

// 不再使用 self.bounds，而是用传入的 canvasSize
// 当前布局参数从 self.dualLayoutRatio, self.pipSize 等读取
```

### LR 布局

```
canvasW × canvasH (例如 390 × 693)
frontHalfW = canvasW × dualLayoutRatio
backHalfW  = canvasW × (1 - dualLayoutRatio)

front:  scale canvasH/extent.H → crop frontHalfW×canvasH → translate(frontHalfW, 0) → mirror
back:   scale canvasH/extent.H → crop backHalfW×canvasH  → no translate
result: front on right, back on left
composite: front over back (no-black-background rule)
```

### SX 布局

```
canvasW × canvasH (例如 390 × 693)
frontHalfH = canvasH × (1 - dualLayoutRatio)
backHalfH  = canvasH × dualLayoutRatio

front: scale canvasW/extent.W → crop canvasW×frontHalfH → translate(0, 0) → mirror
back:  scale canvasW/extent.W → crop canvasW×backHalfH  → translate(0, frontHalfH)
result: front on top, back on bottom
```

### PiP 布局

```
canvasW × canvasH (例如 390 × 693)
backFill: scale MAX(canvasW/backW, canvasH/backH) → crop canvasW×canvasH → full background
pipSize = canvasW × pipSize
pipRect: CGRectMake(canvasW - pipSize - 16, canvasH - pipSize - 100, pipSize, pipSize)
front: scale MAX(pipSize/frontW, pipSize/frontH) → crop pipSize×pipSize → mirror → translate(pipRect)
result: back as background, front as PiP overlay
```

---

## 六、Session 配置变更

### 新增属性

```objc
// 在 DualCameraView.m class extension
@property (nonatomic, strong) AVCaptureVideoDataOutput *frontVideoDataOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *backVideoDataOutput;
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) CIImage *latestFrontFrame;
@property (nonatomic, strong) CIImage *latestBackFrame;
```

### Session 配置变更点

**configureAndStartMultiCamSession** 中，在 `beginConfiguration` 后添加：

```objc
// VideoDataOutput for front camera
self.frontVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
self.frontVideoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
[self.frontVideoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];

if ([self.multiCamSession canAddOutput:self.frontVideoDataOutput]) {
  [self.multiCamSession addOutput:self.frontVideoDataOutput];
  AVCaptureConnection *conn = [self.frontVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
  if (conn.isVideoMirroringSupported) conn.videoMirrored = YES;
}

// VideoDataOutput for back camera
self.backVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
self.backVideoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
[self.backVideoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];

if ([self.multiCamSession canAddOutput:self.backVideoDataOutput]) {
  [self.multiCamSession addOutput:self.backVideoDataOutput];
  // back camera: no mirroring
}
```

注意：VideoDataOutput 连接的是 camera 的 video port（与 PhotoOutput/MovieOutput 不同的 port），不会冲突。

---

## 七、文件改动清单

### 修改文件

| 文件 | 改动 |
|------|------|
| `DualCameraView.h` | 新增 `saveAspectRatio` 属性 |
| `DualCameraView.m` | 完全重写拍照流程；新增 VideoDataOutput；新增 WYSIWYG 合成 |
| `DualCameraViewManager.m` | 新增 `saveAspectRatio` RCT property |
| `App.js` | 新增保存比例选择 UI；写入/读取 AsyncStorage 记录比例 |
| `DualCameraEventEmitter` | 新增 `onSaveAspectRatioChanged` 事件（可选） |

### JS 层改动

```jsx
// App.js - 新增状态
const [saveAspectRatio, setSaveAspectRatio] = useState('9:16'); // default

// 启动时从 AsyncStorage 读取
useEffect(() => {
  AsyncStorage.getItem('dualcam_save_aspect').then(r => {
    if (r) setSaveAspectRatio(r);
  });
}, []);

// 切换时保存
const handleAspectChange = async (ratio) => {
  setSaveAspectRatio(ratio);
  await AsyncStorage.setItem('dualcam_save_aspect', ratio);
};

// UI：BottomBar 或浮层中加入比例选择器
<View style={styles.aspectPicker}>
  {['9:16', '3:4', '1:1'].map(r => (
    <Pressable key={r} onPress={() => handleAspectChange(r)}>
      <Text style={[styles.aspectLabel, saveAspectRatio === r && styles.aspectLabelActive]}>
        {r}
      </Text>
    </Pressable>
  ))}
</View>
```

### RCT Property 映射

```objc
// DualCameraViewManager.m
RCT_CUSTOM_VIEW_PROPERTY(saveAspectRatio, NSString, DualCameraView) {
  view.saveAspectRatio = json ? [RCTConvert NSString:json] : @"9:16";
}
```

---

## 八、关键细节

### CIImage 来自 BGRA PixelBuffer

VideoDataOutput 的 `kCVPixelFormatType_32BGRA` 直接转为 `CIImage`：

```objc
- (CIImage *)ciImageFromSampleBuffer:(CMSampleBufferRef)buffer {
  CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(buffer);
  if (!pixelBuffer) return nil;
  CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
  if (!ciImage) return nil;

  // iOS 前置摄像头 video 预览默认镜像，BGRA buffer 也镜像
  // Mirror the image to match front camera preview
  CGFloat w = ciImage.extent.size.width;
  CGAffineTransform transform = CGAffineTransformConcat(
    CGAffineTransformMakeTranslation(w, 0),
    CGAffineTransformMakeScale(-1, 1));
  return [ciImage imageByApplyingTransform:transform];
}
```

### Thread Safety

`_latestFrontFrame` / `_latestBackFrame` 在 `videoDataOutputQueue`（serial queue）写入，在 `sessionQueue` 读取。在 sessionQueue 读取时无需额外同步（串行队列保证），但保险起见用 `@synchronized`。

### PhotoOutput 保留但不用于双摄拍照

保留 `frontPhotoOutput` / `backPhotoOutput` 配置（不影响 session），仅将双摄拍照路径切换到 VideoDataOutput。

### 保存失败容错

如果 `_latestFrontFrame` 或 `_latestBackFrame` 为 nil（摄像头未就绪），发出错误事件 `emitError:@"Camera not ready, please try again"`。
