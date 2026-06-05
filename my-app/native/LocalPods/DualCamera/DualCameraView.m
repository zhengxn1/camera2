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
	  _beautyProcessingQueue = dispatch_queue_create("com.zhengning.dualcamera.beauty-processing", DISPATCH_QUEUE_SERIAL);
  _metalDevice = MTLCreateSystemDefaultDevice();
  _metalCommandQueue = [_metalDevice newCommandQueue];
  CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  NSDictionary *ciOptions = @{
    kCIContextUseSoftwareRenderer: @NO,
    kCIContextWorkingColorSpace: (__bridge id)srgb,
    kCIContextOutputColorSpace: (__bridge id)srgb
  };
  if (_metalDevice) {
    _ciContext = [CIContext contextWithMTLDevice:_metalDevice options:ciOptions];
  } else {
    _ciContext = [CIContext contextWithOptions:ciOptions];
  }
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
  _videoSaveMode = @"combined";
  _frontBeautyEnabled = YES;
  _frontBeautySmooth = 60.0;
  _frontBeautyWhiten = 45.0;
  _frontBeautyEven = 50.0;
  _frontBeautyPlump = 55.0;
  _layoutUpdateScheduled = NO;
  _beautyLayoutChanging = NO;
  _lastBeautyLayoutChangeTime = 0;
	  _lastBeautyPreviewRenderTime = 0;
	  _beautyPreviewSkippedRenderCount = 0;
	  _beautyPreviewTargetSize = CGSizeZero;
	  _beautyLayoutGeneration = 0;
	  _latestBeautyPreviewGeneration = -1;
	  _latestBeautyPreviewTargetSize = CGSizeZero;
	  _latestBeautyPreviewMirrored = _frontPreviewMirrored;
	  _beautyProcessingInFlight = NO;
	  _beautyProcessingNeedsAnotherFrame = NO;
  _realtimeRecordingState = DualCameraRealtimeRecordingStateIdle;
  _realtimeOutputSize = CGSizeZero;
  _frontRealtimeOutputSize = CGSizeZero;
  _backRealtimeOutputSize = CGSizeZero;
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
	  _latestBeautyPreviewMirrored = _frontPreviewMirrored;
	  NSLog(@"[BeautyProbe][ViewInit] enabled=%d smooth=%.1f whiten=%.1f even=%.1f plump=%.1f metal=%d commandQueue=%d",
	        _frontBeautyEnabled,
	        _frontBeautySmooth,
	        _frontBeautyWhiten,
	        _frontBeautyEven,
	        _frontBeautyPlump,
	        _metalDevice != nil,
	        _metalCommandQueue != nil);
	  [self createPlaceholderViews];
  [self setupPipGestures];
  [self startDeviceOrientationMonitoring];
  [[DualCameraSessionManager shared] registerView:self];
}

#pragma mark - Properties (layout setters)

- (void)invalidateBeautyPreviewForLayoutChange:(NSString *)reason {
  @synchronized(self) {
    self.beautyLayoutGeneration += 1;
    self.latestBeautyPreviewGeneration = -1;
    self.latestBeautyPreviewLayoutMode = nil;
    self.latestBeautyPreviewTargetSize = CGSizeZero;
    self.latestBeautyPreviewFrame = nil;
    self.beautyLayoutChanging = YES;
    self.lastBeautyLayoutChangeTime = CACurrentMediaTime();
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.beautyPreviewView) {
      self.beautyPreviewView.hidden = YES;
    }
    if (self.frontPreviewLayer && !self.frontPreviewView.hidden) {
      self.frontPreviewLayer.hidden = NO;
    }
  });

  NSLog(@"[BeautyProbe][PreviewVersion] invalidated reason=%@ currentGen=%ld layout=%@ target=%@",
        reason ?: @"unknown",
        (long)self.beautyLayoutGeneration,
        self.currentLayout ?: @"nil",
        NSStringFromCGSize(self.beautyPreviewTargetSize));
}

- (void)scheduleLayoutUpdateMarkingBeautyLayoutChange:(BOOL)markBeautyLayoutChange {
  if (markBeautyLayoutChange && self.frontBeautyEnabled) {
    [self invalidateBeautyPreviewForLayoutChange:@"layoutProp"];
  }

  if (self.layoutUpdateScheduled) return;
  self.layoutUpdateScheduled = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.layoutUpdateScheduled = NO;
    [self updateLayout];
  });
}

- (void)setLayoutMode:(NSString *)layoutMode {
	  NSString *nextLayout = layoutMode ?: @"back";
	  _layoutMode = nextLayout;
	  _currentLayout = nextLayout;
	  NSLog(@"[BeautyProbe][Prop] layoutMode=%@ enabled=%d usingMultiCam=%d configured=%d running=%d",
	        nextLayout,
	        self.frontBeautyEnabled,
	        self.usingMultiCam,
	        self.isConfigured,
	        self.isRunning);

  [self scheduleLayoutUpdateMarkingBeautyLayoutChange:YES];

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
  [self scheduleLayoutUpdateMarkingBeautyLayoutChange:YES];
}

- (void)setPipSize:(CGFloat)size {
  _pipSize = MAX(0.05, MIN(0.5, size));
  [self scheduleLayoutUpdateMarkingBeautyLayoutChange:YES];
}

- (void)setPipPositionX:(CGFloat)px {
  _pipPositionX = MAX(0, MIN(1, px));
  [self scheduleLayoutUpdateMarkingBeautyLayoutChange:YES];
}

- (void)setPipPositionY:(CGFloat)py {
  _pipPositionY = MAX(0, MIN(1, py));
  [self scheduleLayoutUpdateMarkingBeautyLayoutChange:YES];
}

- (void)setSaveAspectRatio:(NSString *)saveAspectRatio {
  if (![_saveAspectRatio isEqualToString:saveAspectRatio]) {
    _saveAspectRatio = [saveAspectRatio copy];
    [self scheduleLayoutUpdateMarkingBeautyLayoutChange:YES];
  }
}

- (void)setVideoSaveMode:(NSString *)videoSaveMode {
  NSString *nextMode = [videoSaveMode isEqualToString:@"all3"] ? @"all3" : @"combined";
  if (![_videoSaveMode isEqualToString:nextMode]) {
    _videoSaveMode = [nextMode copy];
  }
}

- (void)setFrontBeautySmooth:(CGFloat)frontBeautySmooth {
	  _frontBeautySmooth = MAX(0.0, MIN(100.0, frontBeautySmooth));
	  NSLog(@"[BeautyProbe][Prop] smooth=%.1f", _frontBeautySmooth);
}

- (void)setFrontBeautyWhiten:(CGFloat)frontBeautyWhiten {
	  _frontBeautyWhiten = MAX(0.0, MIN(100.0, frontBeautyWhiten));
	  NSLog(@"[BeautyProbe][Prop] whiten=%.1f", _frontBeautyWhiten);
}

- (void)setFrontBeautyEven:(CGFloat)frontBeautyEven {
	  _frontBeautyEven = MAX(0.0, MIN(100.0, frontBeautyEven));
	  NSLog(@"[BeautyProbe][Prop] even=%.1f", _frontBeautyEven);
}

- (void)setFrontBeautyEnabled:(BOOL)frontBeautyEnabled {
	  _frontBeautyEnabled = frontBeautyEnabled;
	  if (!frontBeautyEnabled) {
	    @synchronized(self) {
	      self.latestBeautyPreviewFrame = nil;
	      self.latestBeautyPreviewGeneration = -1;
	      self.latestBeautyPreviewLayoutMode = nil;
	      self.latestBeautyPreviewTargetSize = CGSizeZero;
	      self.latestFrontFrame = self.latestRawFrontFrame;
	      self.beautyProcessingInFlight = NO;
	      self.beautyProcessingNeedsAnotherFrame = NO;
	    }
	  }
	  NSLog(@"[BeautyProbe][Prop] enabled=%d smooth=%.1f whiten=%.1f even=%.1f plump=%.1f",
	        _frontBeautyEnabled,
	        _frontBeautySmooth,
	        _frontBeautyWhiten,
	        _frontBeautyEven,
	        _frontBeautyPlump);
	  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateBeautyPreviewVisibility];
  });
}

- (void)setFrontBeautyPlump:(CGFloat)frontBeautyPlump {
	  _frontBeautyPlump = MAX(0.0, MIN(100.0, frontBeautyPlump));
	  NSLog(@"[BeautyProbe][Prop] plump=%.1f", _frontBeautyPlump);
}

#pragma mark - Layout

- (void)layoutSubviews {
  [super layoutSubviews];
  CGSize oldTarget = self.beautyPreviewTargetSize;
  [self updateLayout];
  CGSize newTarget = self.beautyPreviewTargetSize;
  if (self.frontBeautyEnabled &&
      (fabs(oldTarget.width - newTarget.width) > 2.0 ||
       fabs(oldTarget.height - newTarget.height) > 2.0)) {
    [self invalidateBeautyPreviewForLayoutChange:@"layoutSubviewsTarget"];
  }
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
      if (self.frontBeautyEnabled) {
        [self invalidateBeautyPreviewForLayoutChange:@"flipCamera"];
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
  if (_frontRealtimeAssetWriter) {
    [_frontRealtimeAssetWriter cancelWriting];
  }
  if (_backRealtimeAssetWriter) {
    [_backRealtimeAssetWriter cancelWriting];
  }
  // Stop sessions synchronously on current thread to avoid queue deadlock during dealloc
  [_multiCamSession stopRunning];
  [_singleSession stopRunning];
  _isConfigured = NO;
  _videoExportSession = nil;
}

@end
