#import "DualCameraView_Internal.h"

@implementation DualCameraLayoutState
@end

@implementation DualCameraView

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self commonInit];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    [self commonInit];
  }
  return self;
}

- (void)commonInit {
  NSLog(@"[DualCamera] DualCameraView commonInit called");
  self.backgroundColor = [UIColor blackColor];
  self.clipsToBounds = YES;
  _currentLayout = @"back";
  _layoutMode = @"back";
  _singleCameraPosition = AVCaptureDevicePositionBack;
  _sessionQueue = dispatch_queue_create("com.zhengning.dualcamera.session", DISPATCH_QUEUE_SERIAL);
  _isConfigured = NO;
  _isRunning = NO;
  _usingMultiCam = NO;
  _singleRecordingStartPending = NO;
  _singleRecordingStopRequested = NO;
  _pendingDualPhotos = [NSMutableDictionary dictionary];
  _compositingQueue = dispatch_queue_create("com.zhengning.dualcamera.compositing", DISPATCH_QUEUE_SERIAL);
  _videoDataOutputQueue = dispatch_queue_create("com.zhengning.dualcamera.videodata", DISPATCH_QUEUE_SERIAL);
  _realtimeRenderQueue = dispatch_queue_create("com.zhengning.dualcamera.realtime-render", DISPATCH_QUEUE_SERIAL);
  CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  _ciContext = [CIContext contextWithOptions:@{
    kCIContextUseSoftwareRenderer: @NO,
    kCIContextWorkingColorSpace: (__bridge id)srgb,
    kCIContextOutputColorSpace: (__bridge id)srgb
  }];
  NSLog(@"[DualCamera][QualityDiag] CIContext workingColorSpace=sRGB outputColorSpace=sRGB softwareRenderer=NO");
  CGColorSpaceRelease(srgb);
  // Default values for layout/PiP/zoom properties (declared in .h for React Native)
  _dualLayoutRatio = 0.5;
  _pipSize = 0.28;
  _pipPositionX = 0.85;
  _pipPositionY = 0.80;
  _frontZoomFactor = 1.0;
  _backZoomFactor = 1.0;
  _saveAspectRatio = @"9:16";
  _realtimeRecordingState = DualCameraRealtimeRecordingStateIdle;
  _realtimeOutputSize = CGSizeZero;
  _lastRealtimeVideoPTS = kCMTimeInvalid;
  _hasLastRealtimeVideoPTS = NO;
  _canvasSizeAtRecording = CGSizeZero;
  _sxBackOnTop = YES;    // SX: default back on top
  _pipMainIsBack = YES;  // PiP: default back is main (full-screen)
  _deviceOrientation = DualCameraDeviceOrientationPortrait;
  _frontPreviewMirrored = YES;
  _frontOutputMirrored = NO;
  _backPreviewMirrored = NO;
  _backOutputMirrored = NO;
  _frontBeautyEnabled = NO;
  _frontBeautySmooth = 0;
  _frontBeautyBrighten = 0;
  _frontBeautyWhiten = 0;
  _lastFrontBeautyPreviewUpdateTime = 0;
  _frontBeautyPreviewRenderInFlight = NO;
  _gpupixelBeautyAdapter = [[GPUPixelBeautyAdapter alloc] initWithCIContext:_ciContext];
  [self createPlaceholderViews];
  [self setupPipGestures];
  [self startDeviceOrientationMonitoring];
  [[DualCameraSessionManager shared] registerView:self];
}

#pragma mark - Properties (layout setters)

- (BOOL)hasActiveFrontBeautyValues {
  return self.frontBeautySmooth > 0 ||
         self.frontBeautyBrighten > 0 ||
         self.frontBeautyWhiten > 0;
}

- (void)hideFrontBeautyPreviewIfInactive {
  if (self.frontBeautyEnabled && [self hasActiveFrontBeautyValues]) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.frontBeautyPreviewImageView.hidden = YES;
    self.frontBeautyPreviewImageView.image = nil;
  });
}

- (void)setLayoutMode:(NSString *)layoutMode {
  NSString *nextLayout = layoutMode ?: @"back";
  _layoutMode = nextLayout;
  _currentLayout = nextLayout;

  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });

  dispatch_async(self.sessionQueue, ^{
    if (self.isConfigured && !self.usingMultiCam) {
      if ([self isDualLayout:nextLayout]) {
        [self emitSessionError:@"This device does not support simultaneous front and back camera preview." code:@"multicam_unsupported"];
      } else {
        [self reconfigureSingleSessionForCurrentLayout];
      }
    }
  });
}

- (void)setDualLayoutRatio:(CGFloat)ratio {
  _dualLayoutRatio = MAX(0.1, MIN(0.9, ratio));
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });
}

- (void)setPipSize:(CGFloat)size {
  _pipSize = MAX(0.05, MIN(0.5, size));
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });
}

- (void)setPipPositionX:(CGFloat)px {
  _pipPositionX = MAX(0, MIN(1, px));
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });
}

- (void)setPipPositionY:(CGFloat)py {
  _pipPositionY = MAX(0, MIN(1, py));
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });
}

- (void)setSaveAspectRatio:(NSString *)saveAspectRatio {
  if (![_saveAspectRatio isEqualToString:saveAspectRatio]) {
    _saveAspectRatio = [saveAspectRatio copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateLayout];
    });
  }
}

- (void)setFrontBeautyEnabled:(BOOL)enabled {
  _frontBeautyEnabled = enabled;
  self.gpupixelBeautyAdapter.enabled = enabled;
  NSLog(@"[BeautyNative] enabled=%d smooth=%.1f brighten=%.1f whiten=%.1f",
        enabled, self.frontBeautySmooth, self.frontBeautyBrighten, self.frontBeautyWhiten);
  [self hideFrontBeautyPreviewIfInactive];
}

- (void)setFrontBeautySmooth:(CGFloat)value {
  _frontBeautySmooth = MAX(0, MIN(100, value));
  self.gpupixelBeautyAdapter.smooth = _frontBeautySmooth;
  NSLog(@"[BeautyNative] smooth=%.1f brighten=%.1f whiten=%.1f enabled=%d",
        self.frontBeautySmooth, self.frontBeautyBrighten, self.frontBeautyWhiten, self.frontBeautyEnabled);
  [self hideFrontBeautyPreviewIfInactive];
}

- (void)setFrontBeautyBrighten:(CGFloat)value {
  _frontBeautyBrighten = MAX(0, MIN(100, value));
  NSLog(@"[BeautyNative] smooth=%.1f brighten=%.1f whiten=%.1f enabled=%d",
        self.frontBeautySmooth, self.frontBeautyBrighten, self.frontBeautyWhiten, self.frontBeautyEnabled);
  [self hideFrontBeautyPreviewIfInactive];
}

- (void)setFrontBeautyWhiten:(CGFloat)value {
  _frontBeautyWhiten = MAX(0, MIN(100, value));
  self.gpupixelBeautyAdapter.whiten = _frontBeautyWhiten;
  NSLog(@"[BeautyNative] smooth=%.1f brighten=%.1f whiten=%.1f enabled=%d",
        self.frontBeautySmooth, self.frontBeautyBrighten, self.frontBeautyWhiten, self.frontBeautyEnabled);
  [self hideFrontBeautyPreviewIfInactive];
}

#pragma mark - Layout

- (void)layoutSubviews {
  [super layoutSubviews];
  [self updateLayout];
}

#pragma mark - ObjC Bridge Methods

- (void)dc_startSession {
  NSLog(@"[DualCamera] dc_startSession called");
  [self internalStartSession];
}
- (void)dc_stopSession  { [self internalStopSession]; }
- (void)dc_takePhoto    { [self internalTakePhoto]; }
- (void)dc_startRecording { [self internalStartRecording]; }
- (void)dc_stopRecording  { [self internalStopRecording]; }

- (void)dc_flipCamera {
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([self isDualLayout:self.currentLayout]) {
      if ([self.currentLayout isEqualToString:@"sx"] || [self.currentLayout isEqualToString:@"lr"]) {
        self.sxBackOnTop = !self.sxBackOnTop;
        NSLog(@"[DualCamera] flipCamera: sxBackOnTop=%d", self.sxBackOnTop);
      } else if ([self.currentLayout isEqualToString:@"pip_square"] || [self.currentLayout isEqualToString:@"pip_circle"]) {
        self.pipMainIsBack = !self.pipMainIsBack;
        NSLog(@"[DualCamera] flipCamera: pipMainIsBack=%d", self.pipMainIsBack);
      }
      [self updateLayout];
    } else {
      // Single-cam: switch front/back
      AVCaptureDevicePosition next = (self.singleCameraPosition == AVCaptureDevicePositionBack)
        ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
      dispatch_async(self.sessionQueue, ^{
        [self configureSingleSessionForPosition:next startRunning:YES];
      });
    }
  });
}

#pragma mark - Dealloc

- (void)dealloc {
  [self unregisterSessionNotifications];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
  [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
  if (_realtimeAssetWriter) {
    [_realtimeAssetWriter cancelWriting];
  }
  // Stop sessions synchronously on current thread to avoid queue deadlock during dealloc
  [_multiCamSession stopRunning];
  [_singleSession stopRunning];
  _isConfigured = NO;
  _videoExportSession = nil;
}

@end
