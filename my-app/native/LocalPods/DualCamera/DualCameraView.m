#import "DualCameraView.h"
#import "DualCameraEventEmitter.h"
#import "DualCameraSessionManager.h"
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>

@interface DualCameraLayoutState : NSObject
@property (nonatomic, copy) NSString *layoutMode;
@property (nonatomic, assign) CGFloat dualLayoutRatio;
@property (nonatomic, assign) CGFloat pipSize;
@property (nonatomic, assign) CGFloat pipPositionX;
@property (nonatomic, assign) CGFloat pipPositionY;
@property (nonatomic, assign) BOOL sxBackOnTop;
@property (nonatomic, assign) BOOL pipMainIsBack;
@property (nonatomic, assign) CGSize canvasSize;
@property (nonatomic, assign) CGSize outputSize;
@property (nonatomic, assign) BOOL frontMirrored;
@property (nonatomic, assign) BOOL backMirrored;
@property (nonatomic, assign) BOOL isLandscape;
@property (nonatomic, assign) BOOL primaryOnLeadingEdge;
@end

@implementation DualCameraLayoutState
@end

typedef NS_ENUM(NSInteger, DualCameraDeviceOrientation) {
  DualCameraDeviceOrientationPortrait,
  DualCameraDeviceOrientationPortraitUpsideDown,
  DualCameraDeviceOrientationLandscapeLeft,
  DualCameraDeviceOrientationLandscapeRight
};

typedef NS_ENUM(NSInteger, DualCameraRealtimeRecordingState) {
  DualCameraRealtimeRecordingStateIdle,
  DualCameraRealtimeRecordingStatePrepared,
  DualCameraRealtimeRecordingStateWriting,
  DualCameraRealtimeRecordingStateFinishing,
  DualCameraRealtimeRecordingStateFailed
};

@interface DualCameraView () <AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) AVCaptureMultiCamSession *multiCamSession;
@property (nonatomic, strong) AVCaptureSession *singleSession;
@property (nonatomic, strong) AVCaptureDeviceInput *frontDeviceInput;
@property (nonatomic, strong) AVCaptureDeviceInput *backDeviceInput;
@property (nonatomic, strong) AVCaptureDeviceInput *singleDeviceInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *frontPreviewLayer;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *backPreviewLayer;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *singlePreviewLayer;
@property (nonatomic, strong) AVCapturePhotoOutput *frontPhotoOutput;
@property (nonatomic, strong) AVCapturePhotoOutput *backPhotoOutput;
@property (nonatomic, strong) AVCapturePhotoOutput *singlePhotoOutput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *singleMovieOutput;
@property (nonatomic, assign) BOOL singleRecordingStartPending;
@property (nonatomic, assign) BOOL singleRecordingStopRequested;
@property (nonatomic, strong) UIView *frontPreviewView;
@property (nonatomic, strong) UIView *backPreviewView;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, assign) AVCaptureDevicePosition singleCameraPosition;
@property (nonatomic, assign) BOOL usingMultiCam;
@property (nonatomic, assign) BOOL isConfigured;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, copy) NSString *currentLayout;

// VideoDataOutput for WYSIWYG photo capture
@property (nonatomic, strong) AVCaptureVideoDataOutput *frontVideoDataOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *backVideoDataOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) CIImage *latestFrontFrame;
@property (nonatomic, strong) CIImage *latestBackFrame;
@property (nonatomic, strong) CIContext *ciContext;

// Dual compositing state
@property (nonatomic, strong) NSMutableDictionary *pendingDualPhotos;
@property (nonatomic, assign) BOOL pendingDualPhotosFront;
@property (nonatomic, assign) BOOL pendingDualPhotosBack;
@property (nonatomic, assign) BOOL isDualRecordingActive;
@property (nonatomic, strong) AVAssetExportSession *videoExportSession;
@property (nonatomic, strong) dispatch_queue_t compositingQueue;
@property (nonatomic, strong) AVAssetWriter *realtimeAssetWriter;
@property (nonatomic, strong) AVAssetWriterInput *realtimeVideoInput;
@property (nonatomic, strong) AVAssetWriterInput *realtimeAudioInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *realtimePixelBufferAdaptor;
@property (nonatomic, copy) NSString *realtimeRecordingPath;
@property (nonatomic, copy) NSString *realtimeRecordingAspectRatio;
@property (nonatomic, assign) CGSize realtimeOutputSize;
@property (nonatomic, assign) DualCameraRealtimeRecordingState realtimeRecordingState;
@property (nonatomic, assign) BOOL realtimeWriterStarted;
@property (nonatomic, assign) BOOL realtimeFinishRequested;
@property (nonatomic, assign) BOOL realtimeFinishWhenFirstFrameWritten;
@property (nonatomic, assign) BOOL realtimeRecordingStartedEventEmitted;
@property (nonatomic, assign) NSInteger realtimeDroppedFrameCount;
@property (nonatomic, assign) NSInteger realtimeWrittenVideoFrameCount;
@property (nonatomic, assign) NSInteger realtimeDroppedAudioSampleCount;
@property (nonatomic, strong) DualCameraLayoutState *recordingLayoutState;
@property (nonatomic, assign) CMTime lastRealtimeVideoPTS;
@property (nonatomic, assign) BOOL hasLastRealtimeVideoPTS;

// canvasSizeAtRecording — only declared here (not in .h), used internally
@property (nonatomic, assign) CGSize canvasSizeAtRecording;

// sxBackOnTop and pipMainIsBack are declared in DualCameraView.h

// PiP gesture recognizers
@property (nonatomic, strong) UIPanGestureRecognizer *pipPanGesture;
@property (nonatomic, strong) UIPinchGestureRecognizer *pipPinchGesture;
@property (nonatomic, assign) CGFloat lastPipSize;
@property (nonatomic, assign) DualCameraDeviceOrientation deviceOrientation;
@property (nonatomic, assign) BOOL frontPreviewMirrored;
@property (nonatomic, assign) BOOL frontOutputMirrored;
@property (nonatomic, assign) BOOL backPreviewMirrored;
@property (nonatomic, assign) BOOL backOutputMirrored;

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
  _ciContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
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
  _backZoomFactor = 1.0;
  _canvasSizeAtRecording = CGSizeZero;
  _sxBackOnTop = YES;    // SX: default back on top
  _pipMainIsBack = YES;  // PiP: default back is main (full-screen)
  _deviceOrientation = DualCameraDeviceOrientationPortrait;
  _frontPreviewMirrored = YES;
  _frontOutputMirrored = NO;
  _backPreviewMirrored = NO;
  _backOutputMirrored = NO;
  [self createPlaceholderViews];
  [self setupPipGestures];
  [self startDeviceOrientationMonitoring];
  [[DualCameraSessionManager shared] registerView:self];
}

#pragma mark - Orientation

- (void)startDeviceOrientationMonitoring {
  [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(deviceOrientationDidChange:)
                                               name:UIDeviceOrientationDidChangeNotification
                                             object:nil];
  [self updateDeviceOrientation:[UIDevice currentDevice].orientation];
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
  [self updateDeviceOrientation:[UIDevice currentDevice].orientation];
}

- (void)updateDeviceOrientation:(UIDeviceOrientation)orientation {
  DualCameraDeviceOrientation next = self.deviceOrientation;
  switch (orientation) {
    case UIDeviceOrientationPortrait:
      next = DualCameraDeviceOrientationPortrait;
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      next = DualCameraDeviceOrientationPortraitUpsideDown;
      break;
    case UIDeviceOrientationLandscapeLeft:
      next = DualCameraDeviceOrientationLandscapeLeft;
      break;
    case UIDeviceOrientationLandscapeRight:
      next = DualCameraDeviceOrientationLandscapeRight;
      break;
    default:
      return;
  }

  if (next == self.deviceOrientation) return;
  if (self.isDualRecordingActive || self.realtimeAssetWriter) return;
  self.deviceOrientation = next;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
    [self applyCurrentVideoOrientationAndMirroring];
  });
}

- (AVCaptureVideoOrientation)currentCaptureVideoOrientation {
  switch (self.deviceOrientation) {
    case DualCameraDeviceOrientationPortraitUpsideDown:
      return AVCaptureVideoOrientationPortraitUpsideDown;
    case DualCameraDeviceOrientationLandscapeLeft:
      return AVCaptureVideoOrientationLandscapeRight;
    case DualCameraDeviceOrientationLandscapeRight:
      return AVCaptureVideoOrientationLandscapeLeft;
    case DualCameraDeviceOrientationPortrait:
    default:
      return AVCaptureVideoOrientationPortrait;
  }
}

- (BOOL)isCurrentDeviceLandscape {
  return self.deviceOrientation == DualCameraDeviceOrientationLandscapeLeft ||
         self.deviceOrientation == DualCameraDeviceOrientationLandscapeRight;
}

- (BOOL)isDeviceOrientationLandscape:(DualCameraDeviceOrientation)orientation {
  return orientation == DualCameraDeviceOrientationLandscapeLeft ||
         orientation == DualCameraDeviceOrientationLandscapeRight;
}

- (BOOL)primaryOnLeadingEdgeForDeviceOrientation:(DualCameraDeviceOrientation)orientation {
  return orientation != DualCameraDeviceOrientationLandscapeRight;
}

- (void)applyOrientation:(AVCaptureVideoOrientation)orientation
             mirrored:(BOOL)mirrored
         toConnection:(AVCaptureConnection *)connection {
  if (!connection) return;
  if (connection.isVideoOrientationSupported) {
    connection.videoOrientation = orientation;
  }
  if (connection.isVideoMirroringSupported) {
    connection.automaticallyAdjustsVideoMirroring = NO;
    connection.videoMirrored = mirrored;
  }
}

- (void)applyOrientation:(AVCaptureVideoOrientation)orientation
             mirrored:(BOOL)mirrored
            toOutput:(AVCaptureOutput *)output {
  for (AVCaptureConnection *connection in output.connections) {
    [self applyOrientation:orientation mirrored:mirrored toConnection:connection];
  }
}

- (void)applyCurrentVideoOrientationAndMirroring {
  AVCaptureVideoOrientation orientation = [self currentCaptureVideoOrientation];

  [self applyOrientation:orientation
                mirrored:self.backPreviewMirrored
            toConnection:self.backPreviewLayer.connection];
  [self applyOrientation:orientation
                mirrored:self.frontPreviewMirrored
            toConnection:self.frontPreviewLayer.connection];

  BOOL singlePreviewMirrored = self.singleCameraPosition == AVCaptureDevicePositionFront
    ? self.frontPreviewMirrored
    : self.backPreviewMirrored;
  [self applyOrientation:orientation
                mirrored:singlePreviewMirrored
            toConnection:self.singlePreviewLayer.connection];

  [self applyOrientation:orientation mirrored:self.backOutputMirrored toOutput:self.backPhotoOutput];
  [self applyOrientation:orientation mirrored:self.frontOutputMirrored toOutput:self.frontPhotoOutput];
  [self applyOrientation:orientation mirrored:self.backOutputMirrored toOutput:self.backVideoDataOutput];
  [self applyOrientation:orientation mirrored:self.frontOutputMirrored toOutput:self.frontVideoDataOutput];

  BOOL singleOutputMirrored = self.singleCameraPosition == AVCaptureDevicePositionFront
    ? self.frontOutputMirrored
    : self.backOutputMirrored;
  [self applyOrientation:orientation mirrored:singleOutputMirrored toOutput:self.singlePhotoOutput];
  [self applyOrientation:orientation mirrored:singleOutputMirrored toOutput:self.singleMovieOutput];
}

#pragma mark - Properties

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

- (void)setPipMainIsBack:(BOOL)pipMainIsBack {
  _pipMainIsBack = pipMainIsBack;
  // Enable/disable PiP gestures based on which view is the small window
  // pipMainIsBack=YES: _frontPreviewView is the small window (enable gestures)
  // pipMainIsBack=NO:  _frontPreviewView is the main view (disable gestures)
  self.pipPanGesture.enabled = pipMainIsBack;
  self.pipPinchGesture.enabled = pipMainIsBack;
}

- (void)setupPipGestures {
  // Guard: if views were recreated after initial setup, re-attach gestures
  if (_pipPanGesture) {
    // Views were recreated (createPlaceholderViews called again)
    // Re-add gesture recognizers to the new _frontPreviewView
    if (_pipPanGesture.view != _frontPreviewView) {
      [_pipPanGesture.view removeGestureRecognizer:_pipPanGesture];
      [_pipPinchGesture.view removeGestureRecognizer:_pipPinchGesture];
      [_frontPreviewView addGestureRecognizer:_pipPanGesture];
      [_frontPreviewView addGestureRecognizer:_pipPinchGesture];
    }
    return;
  }

  // UIPanGestureRecognizer — PiP drag
  _pipPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePipPan:)];
  _pipPanGesture.delegate = self;
  _pipPanGesture.enabled = _pipMainIsBack; // only enabled when _frontPreviewView is the small window
  [_frontPreviewView addGestureRecognizer:_pipPanGesture];
  _frontPreviewView.userInteractionEnabled = YES;

  // UIPinchGestureRecognizer — PiP pinch to resize
  _pipPinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePipPinch:)];
  _pipPinchGesture.delegate = self;
  _pipPinchGesture.enabled = _pipMainIsBack;
  [_frontPreviewView addGestureRecognizer:_pipPinchGesture];
}

- (void)handlePipPan:(UIPanGestureRecognizer *)pan {
  CGPoint translation = [pan translationInView:self];
  CGPoint center = _frontPreviewView.center;
  center.x += translation.x;
  center.y += translation.y;

  // Clamp: small window center cannot exit canvas bounds
  CGFloat halfW = _frontPreviewView.bounds.size.width / 2;
  CGFloat halfH = _frontPreviewView.bounds.size.height / 2;
  center.x = MAX(halfW, MIN(self.bounds.size.width - halfW, center.x));
  center.y = MAX(halfH, MIN(self.bounds.size.height - halfH, center.y));

  _frontPreviewView.center = center;
  [pan setTranslation:CGPointZero inView:self];

  // Update normalized coordinates for save
  _pipPositionX = center.x / self.bounds.size.width;
  _pipPositionY = center.y / self.bounds.size.height;

  if (pan.state == UIGestureRecognizerStateEnded) {
    [[DualCameraEventEmitter shared] sendPipPositionChanged:_pipPositionX y:_pipPositionY];
  }
}

- (void)handlePipPinch:(UIPinchGestureRecognizer *)pinch {
  if (pinch.state == UIGestureRecognizerStateBegan) {
    _lastPipSize = _pipSize;
  }
  CGFloat newSize = _lastPipSize * pinch.scale;
  _pipSize = MAX(0.05, MIN(0.5, newSize));

  // Update view frame
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });

  if (pinch.state == UIGestureRecognizerStateEnded) {
    [[DualCameraEventEmitter shared] sendPipSizeChanged:_pipSize];
  }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  // Allow pan and pinch to work simultaneously
  if ((gestureRecognizer == self.pipPanGesture && otherGestureRecognizer == self.pipPinchGesture) ||
      (gestureRecognizer == self.pipPinchGesture && otherGestureRecognizer == self.pipPanGesture)) {
    return YES;
  }
  return NO;
}

- (void)createPlaceholderViews {
  [_frontPreviewView removeFromSuperview];
  [_backPreviewView removeFromSuperview];

  UIView *bv = [[UIView alloc] init];
  bv.backgroundColor = [UIColor blackColor];
  bv.clipsToBounds = YES;
  bv.frame = self.bounds;
  [self addSubview:bv];
  _backPreviewView = bv;

  UIView *fv = [[UIView alloc] init];
  fv.backgroundColor = [UIColor blackColor];
  fv.clipsToBounds = YES;
  fv.frame = self.bounds;
  [self addSubview:fv];
  _frontPreviewView = fv;

  // Re-setup PiP gestures whenever views are recreated
  [self setupPipGestures];

  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });
}

#pragma mark - Layout

- (CGRect)canvasBoundsForAspectRatio {
  CGFloat screenW = self.bounds.size.width;
  CGFloat screenH = self.bounds.size.height;
  CGFloat canvasW, canvasH;

  if ([self.saveAspectRatio isEqualToString:@"9:16"]) {
    canvasW = screenW;
    canvasH = canvasW * 16.0 / 9.0;
    if (canvasH > screenH) {
      canvasH = screenH;
      canvasW = canvasH * 9.0 / 16.0;
    }
  } else if ([self.saveAspectRatio isEqualToString:@"3:4"]) {
    canvasW = screenW;
    canvasH = canvasW * 4.0 / 3.0;
    if (canvasH > screenH) {
      canvasH = screenH;
      canvasW = canvasH * 3.0 / 4.0;
    }
  } else if ([self.saveAspectRatio isEqualToString:@"1:1"]) {
    CGFloat minDim = MIN(screenW, screenH);
    canvasW = canvasH = minDim;
  } else {
    return self.bounds;
  }

  CGFloat ox = (screenW - canvasW) / 2.0;
  CGFloat oy = (screenH - canvasH) / 2.0;
  return CGRectMake(ox, oy, canvasW, canvasH);
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self updateLayout];
}

- (DualCameraLayoutState *)currentLayoutStateForCanvasSize:(CGSize)canvasSize outputSize:(CGSize)outputSize {
  return [self layoutStateSnapshotForCanvasSize:canvasSize
                                     outputSize:outputSize
                                    orientation:self.deviceOrientation];
}

- (DualCameraLayoutState *)layoutStateSnapshotForCanvasSize:(CGSize)canvasSize
                                                 outputSize:(CGSize)outputSize
                                                orientation:(DualCameraDeviceOrientation)orientation {
  DualCameraLayoutState *state = [[DualCameraLayoutState alloc] init];
  state.layoutMode = self.currentLayout ?: @"back";
  state.dualLayoutRatio = self.dualLayoutRatio > 0 ? self.dualLayoutRatio : 0.5;
  state.pipSize = self.pipSize > 0 ? self.pipSize : 0.28;
  state.pipPositionX = self.pipPositionX;
  state.pipPositionY = self.pipPositionY;
  state.sxBackOnTop = self.sxBackOnTop;
  state.pipMainIsBack = self.pipMainIsBack;
  state.canvasSize = canvasSize;
  state.outputSize = outputSize;
  state.frontMirrored = self.frontOutputMirrored;
  state.backMirrored = self.backOutputMirrored;
  state.isLandscape = [self isDeviceOrientationLandscape:orientation];
  state.primaryOnLeadingEdge = [self primaryOnLeadingEdgeForDeviceOrientation:orientation];
  return state;
}

- (NSDictionary<NSString *, NSValue *> *)rectsForLayoutState:(DualCameraLayoutState *)state canvasSize:(CGSize)canvasSize {
  CGFloat w = canvasSize.width;
  CGFloat h = canvasSize.height;
  CGFloat ratio = MAX(0.1, MIN(0.9, state.dualLayoutRatio > 0 ? state.dualLayoutRatio : 0.5));
  NSString *layout = state.layoutMode ?: @"back";

  CGRect backRect = CGRectZero;
  CGRect frontRect = CGRectZero;

  if ([layout isEqualToString:@"back"]) {
    backRect = CGRectMake(0, 0, w, h);
  } else if ([layout isEqualToString:@"front"]) {
    frontRect = CGRectMake(0, 0, w, h);
  } else if ([layout isEqualToString:@"lr"]) {
    CGFloat primaryW = w * ratio;
    CGFloat secondaryW = w * (1 - ratio);
    if (state.sxBackOnTop) {
      backRect = CGRectMake(0, 0, primaryW, h);
      frontRect = CGRectMake(primaryW, 0, secondaryW, h);
    } else {
      frontRect = CGRectMake(0, 0, primaryW, h);
      backRect = CGRectMake(primaryW, 0, secondaryW, h);
    }
  } else if ([layout isEqualToString:@"sx"]) {
    if (state.isLandscape) {
      CGFloat primaryW = w * ratio;
      CGFloat secondaryW = w * (1 - ratio);
      CGRect leadingRect = CGRectMake(0, 0, primaryW, h);
      CGRect trailingRect = CGRectMake(primaryW, 0, secondaryW, h);
      CGRect primaryRect = state.primaryOnLeadingEdge ? leadingRect : trailingRect;
      CGRect secondaryRect = state.primaryOnLeadingEdge ? trailingRect : leadingRect;
      if (state.sxBackOnTop) {
        backRect = primaryRect;
        frontRect = secondaryRect;
      } else {
        frontRect = primaryRect;
        backRect = secondaryRect;
      }
    } else {
      CGFloat primaryH = h * ratio;
      CGFloat secondaryH = h * (1 - ratio);
      if (state.sxBackOnTop) {
        backRect = CGRectMake(0, 0, w, primaryH);
        frontRect = CGRectMake(0, primaryH, w, secondaryH);
      } else {
        frontRect = CGRectMake(0, 0, w, primaryH);
        backRect = CGRectMake(0, primaryH, w, secondaryH);
      }
    }
  } else if ([layout isEqualToString:@"pip_square"] || [layout isEqualToString:@"pip_circle"]) {
    CGFloat s = w * MAX(0.05, MIN(0.5, state.pipSize));
    CGFloat cx = w * MAX(0, MIN(1, state.pipPositionX));
    CGFloat cy = h * MAX(0, MIN(1, state.pipPositionY));
    cx = MAX(s / 2, MIN(w - s / 2, cx));
    cy = MAX(s / 2, MIN(h - s / 2, cy));
    CGRect pipRect = CGRectMake(cx - s / 2, cy - s / 2, s, s);
    CGRect fullRect = CGRectMake(0, 0, w, h);
    if (state.pipMainIsBack) {
      backRect = fullRect;
      frontRect = pipRect;
    } else {
      frontRect = fullRect;
      backRect = pipRect;
    }
  } else {
    backRect = CGRectMake(0, 0, w, h);
  }

  return @{
    @"back": [NSValue valueWithCGRect:backRect],
    @"front": [NSValue valueWithCGRect:frontRect]
  };
}

- (void)updateLayout {
  CGRect canvas = [self canvasBoundsForAspectRatio];
  CGFloat ox = canvas.origin.x;
  CGFloat oy = canvas.origin.y;
  DualCameraLayoutState *state = [self currentLayoutStateForCanvasSize:canvas.size outputSize:canvas.size];
  NSDictionary<NSString *, NSValue *> *rects = [self rectsForLayoutState:state canvasSize:canvas.size];
  CGRect backRect = [rects[@"back"] CGRectValue];
  CGRect frontRect = [rects[@"front"] CGRectValue];
  CGRect backFrame = CGRectOffset(backRect, ox, oy);
  CGRect frontFrame = CGRectOffset(frontRect, ox, oy);

  _frontPreviewView.layer.masksToBounds = YES;
  _backPreviewView.layer.masksToBounds = YES;
  _frontPreviewView.layer.cornerRadius = 0;
  _backPreviewView.layer.cornerRadius = 0;

  if ([_currentLayout isEqualToString:@"back"]) {
    _frontPreviewView.hidden = YES;
    _backPreviewView.hidden = NO;
    _backPreviewView.frame = backFrame;

  } else if ([_currentLayout isEqualToString:@"front"]) {
    _backPreviewView.hidden = YES;
    _frontPreviewView.hidden = NO;
    _frontPreviewView.frame = frontFrame;

  } else if ([_currentLayout isEqualToString:@"lr"]) {
    _backPreviewView.hidden = NO;
    _frontPreviewView.hidden = NO;
    _backPreviewView.frame = backFrame;
    _frontPreviewView.frame = frontFrame;

  } else if ([_currentLayout isEqualToString:@"sx"]) {
    _backPreviewView.hidden = NO;
    _frontPreviewView.hidden = NO;
    _backPreviewView.frame = backFrame;
    _frontPreviewView.frame = frontFrame;

  } else if ([_currentLayout isEqualToString:@"pip_square"] || [_currentLayout isEqualToString:@"pip_circle"]) {
    _backPreviewView.hidden = NO;
    _frontPreviewView.hidden = NO;
    _backPreviewView.frame = backFrame;
    _frontPreviewView.frame = frontFrame;

    // Calculate pipRect for corner radius
    CGFloat pipW = canvas.size.width;
    CGFloat pipS = pipW * MAX(0.05, MIN(0.5, self.pipSize));
    CGFloat pipCX = pipW * MAX(0, MIN(1, self.pipPositionX));
    CGFloat pipCY = canvas.size.height * MAX(0, MIN(1, self.pipPositionY));
    pipCX = MAX(pipS / 2, MIN(pipW - pipS / 2, pipCX));
    pipCY = MAX(pipS / 2, MIN(canvas.size.height - pipS / 2, pipCY));
    CGRect pipRect = CGRectMake(pipCX - pipS / 2, pipCY - pipS / 2, pipS, pipS);

    if ([_currentLayout isEqualToString:@"pip_circle"]) {
      CGFloat radius = pipRect.size.width / 2;
      if (self.pipMainIsBack) {
        _frontPreviewView.layer.cornerRadius = radius;
      } else {
        _backPreviewView.layer.cornerRadius = radius;
      }
    } else {
      _frontPreviewView.layer.cornerRadius = 8;
      _backPreviewView.layer.cornerRadius = 8;
    }

  } else {
    _frontPreviewView.hidden = YES;
    _backPreviewView.hidden = NO;
    _backPreviewView.frame = canvas;
  }

  // Update preview layer frames to match view frames (nil-safe: layers may not exist yet on first layout)
  if (_frontPreviewLayer) _frontPreviewLayer.frame = _frontPreviewView.bounds;
  if (_backPreviewLayer) _backPreviewLayer.frame = _backPreviewView.bounds;
  if (_singlePreviewLayer) _singlePreviewLayer.frame = [self targetPreviewViewForPosition:self.singleCameraPosition].bounds;
}

- (void)setSaveAspectRatio:(NSString *)saveAspectRatio {
  if (![_saveAspectRatio isEqualToString:saveAspectRatio]) {
    _saveAspectRatio = [saveAspectRatio copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateLayout];
    });
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

#pragma mark - Session Lifecycle

- (void)internalStartSession {
  NSLog(@"[DualCamera] internalStartSession called, layout=%@", self.currentLayout);
  AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  NSLog(@"[DualCamera] Camera auth status: %ld", (long)status);
  if (status == AVAuthorizationStatusNotDetermined) {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
      if (granted) {
        [self startOnSessionQueue];
      } else {
        [self emitSessionError:@"Camera permission was not granted." code:@"camera_permission_denied"];
      }
    }];
  } else if (status == AVAuthorizationStatusAuthorized) {
    [self startOnSessionQueue];
  } else {
    [self emitSessionError:@"Camera permission is denied or restricted." code:@"camera_permission_denied"];
  }
}

- (void)startOnSessionQueue {
  dispatch_async(self.sessionQueue, ^{
    if (self.isConfigured) {
      [self resumeIfNeeded];
      return;
    }

    if ([AVCaptureMultiCamSession isMultiCamSupported]) {
      [self configureAndStartMultiCamSession];
    } else {
      [self configureAndStartSingleCameraFallback];
    }
  });
}

- (void)configureAndStartMultiCamSession {
  AVCaptureDevice *backDevice = [self cameraDeviceForPosition:AVCaptureDevicePositionBack];
  AVCaptureDevice *frontDevice = [self cameraDeviceForPosition:AVCaptureDevicePositionFront];
  if (!backDevice || !frontDevice) {
    [self emitSessionError:@"Could not find both front and back cameras." code:@"camera_not_found"];
    return;
  }

  NSError *error = nil;
  if (![self configureDeviceForMultiCam:backDevice error:&error]) {
    [self emitSessionError:[NSString stringWithFormat:@"Back camera configuration failed: %@", error.localizedDescription] code:@"back_format_failed"];
    return;
  }
  if (![self configureDeviceForMultiCam:frontDevice error:&error]) {
    [self emitSessionError:[NSString stringWithFormat:@"Front camera configuration failed: %@", error.localizedDescription] code:@"front_format_failed"];
    return;
  }

  self.multiCamSession = [[AVCaptureMultiCamSession alloc] init];
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self removePreviewLayers];

    AVCaptureVideoPreviewLayer *bl = [[AVCaptureVideoPreviewLayer alloc] initWithSessionWithNoConnection:self.multiCamSession];
    bl.videoGravity = AVLayerVideoGravityResizeAspectFill;
    bl.frame = self.backPreviewView.bounds;
    [self.backPreviewView.layer addSublayer:bl];
    self.backPreviewLayer = bl;

    AVCaptureVideoPreviewLayer *fl = [[AVCaptureVideoPreviewLayer alloc] initWithSessionWithNoConnection:self.multiCamSession];
    fl.videoGravity = AVLayerVideoGravityResizeAspectFill;
    fl.frame = self.frontPreviewView.bounds;
    [self.frontPreviewView.layer addSublayer:fl];
    self.frontPreviewLayer = fl;

    [self updateLayout];
  });

  AVCaptureDeviceInput *backInput = [AVCaptureDeviceInput deviceInputWithDevice:backDevice error:&error];
  if (!backInput) {
    [self clearPreviewLayersOnMainQueue];
    [self emitSessionError:[NSString stringWithFormat:@"Back camera input failed: %@", error.localizedDescription] code:@"back_input_failed"];
    return;
  }

  AVCaptureDeviceInput *frontInput = [AVCaptureDeviceInput deviceInputWithDevice:frontDevice error:&error];
  if (!frontInput) {
    [self clearPreviewLayersOnMainQueue];
    [self emitSessionError:[NSString stringWithFormat:@"Front camera input failed: %@", error.localizedDescription] code:@"front_input_failed"];
    return;
  }

  AVCapturePhotoOutput *backPhotoOutput = [[AVCapturePhotoOutput alloc] init];
  AVCapturePhotoOutput *frontPhotoOutput = [[AVCapturePhotoOutput alloc] init];

  BOOL ok = YES;
  NSString *failure = nil;
  NSString *failureCode = nil;

  [self.multiCamSession beginConfiguration];

  // Audio input (microphone)
  AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
  if (audioDevice) {
    NSError *audioErr = nil;
    self.audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&audioErr];
    if (self.audioInput && [self.multiCamSession canAddInput:self.audioInput]) {
      [self.multiCamSession addInputWithNoConnections:self.audioInput];
    } else {
      NSLog(@"[DualCamera] Audio input not available: %@", audioErr.localizedDescription);
      self.audioInput = nil;
    }
  }

  if ([self.multiCamSession canAddInput:backInput]) {
    [self.multiCamSession addInputWithNoConnections:backInput];
  } else {
    ok = NO;
    failure = @"Cannot add back camera input to multi-cam session.";
    failureCode = @"back_input_rejected";
  }

  if (ok && [self.multiCamSession canAddInput:frontInput]) {
    [self.multiCamSession addInputWithNoConnections:frontInput];
  } else if (ok) {
    ok = NO;
    failure = @"Cannot add front camera input to multi-cam session.";
    failureCode = @"front_input_rejected";
  }

  AVCaptureInputPort *backVideoPort = ok ? [self videoPortForInput:backInput] : nil;
  AVCaptureInputPort *frontVideoPort = ok ? [self videoPortForInput:frontInput] : nil;
  if (ok && (!backVideoPort || !frontVideoPort)) {
    ok = NO;
    failure = @"Could not find front/back video input ports.";
    failureCode = @"video_port_missing";
  }

  if (ok) {
    ok = [self addPreviewLayer:self.backPreviewLayer
                      forPort:backVideoPort
                    toSession:self.multiCamSession
                  mirrorVideo:self.backPreviewMirrored
                      failure:&failure
                  failureCode:&failureCode];
  }

  if (ok) {
    ok = [self addPreviewLayer:self.frontPreviewLayer
                      forPort:frontVideoPort
                    toSession:self.multiCamSession
                  mirrorVideo:self.frontPreviewMirrored
                      failure:&failure
                  failureCode:&failureCode];
  }

  if (ok) {
    ok = [self addOutput:backPhotoOutput
                 forPort:backVideoPort
               toSession:self.multiCamSession
                 failure:&failure
             failureCode:&failureCode];
  }

  if (ok) {
    ok = [self addOutput:frontPhotoOutput
                 forPort:frontVideoPort
               toSession:self.multiCamSession
                 failure:&failure
             failureCode:&failureCode];
  }

  // VideoDataOutput for WYSIWYG photo capture (front camera)
  // Use addOutputWithNoConnections: + manual connection for AVCaptureMultiCamSession
  if (ok) {
    self.frontVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.frontVideoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    self.frontVideoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    [self.frontVideoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    if ([self.multiCamSession canAddOutput:self.frontVideoDataOutput]) {
      [self.multiCamSession addOutputWithNoConnections:self.frontVideoDataOutput];
      if (frontVideoPort) {
        AVCaptureConnection *conn = [[AVCaptureConnection alloc] initWithInputPorts:@[frontVideoPort] output:self.frontVideoDataOutput];
        [self applyOrientation:[self currentCaptureVideoOrientation] mirrored:self.frontOutputMirrored toConnection:conn];
        if ([self.multiCamSession canAddConnection:conn]) {
          [self.multiCamSession addConnection:conn];
          NSLog(@"[DualCamera] frontVideoDataOutput connected to frontVideoPort (no mirror — WYSIWYG)");
        } else {
          NSLog(@"[DualCamera] frontVideoDataOutput connection failed");
        }
      } else {
        NSLog(@"[DualCamera] frontVideoDataOutput: frontVideoPort is nil");
      }
    } else {
      NSLog(@"[DualCamera] Cannot add frontVideoDataOutput to session");
    }
  }

  // VideoDataOutput for WYSIWYG photo capture (back camera)
  // Use same pattern as frontVideoDataOutput
  if (ok) {
    self.backVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.backVideoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    self.backVideoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    [self.backVideoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    if ([self.multiCamSession canAddOutput:self.backVideoDataOutput]) {
      [self.multiCamSession addOutputWithNoConnections:self.backVideoDataOutput];
      if (backVideoPort) {
        AVCaptureConnection *conn = [[AVCaptureConnection alloc] initWithInputPorts:@[backVideoPort] output:self.backVideoDataOutput];
        [self applyOrientation:[self currentCaptureVideoOrientation] mirrored:self.backOutputMirrored toConnection:conn];
        if ([self.multiCamSession canAddConnection:conn]) {
          [self.multiCamSession addConnection:conn];
          NSLog(@"[DualCamera] backVideoDataOutput connected to backVideoPort");
        } else {
          NSLog(@"[DualCamera] backVideoDataOutput connection failed — port may be in use");
        }
      }
    } else {
      NSLog(@"[DualCamera] Cannot add backVideoDataOutput to session");
    }
  }

  if (ok && self.audioInput) {
    self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    if ([self.multiCamSession canAddOutput:self.audioDataOutput]) {
      [self.multiCamSession addOutputWithNoConnections:self.audioDataOutput];
      AVCaptureInputPort *audioPort = nil;
      for (AVCaptureInputPort *port in self.audioInput.ports) {
        if ([port.mediaType isEqualToString:AVMediaTypeAudio]) {
          audioPort = port;
          break;
        }
      }
      if (audioPort) {
        AVCaptureConnection *audioConn = [[AVCaptureConnection alloc] initWithInputPorts:@[audioPort] output:self.audioDataOutput];
        if ([self.multiCamSession canAddConnection:audioConn]) {
          [self.multiCamSession addConnection:audioConn];
          NSLog(@"[DualCamera] audioDataOutput connected to microphone");
        } else {
          NSLog(@"[DualCamera] audioDataOutput connection failed");
        }
      }
    } else {
      NSLog(@"[DualCamera] Cannot add audioDataOutput to session");
      self.audioDataOutput = nil;
    }
  }

  [self.multiCamSession commitConfiguration];

  if (!ok) {
    [self clearPreviewLayersOnMainQueue];
    [self emitSessionError:failure ?: @"Multi-cam session configuration failed." code:failureCode ?: @"multicam_configuration_failed"];
    return;
  }

  if (self.multiCamSession.hardwareCost > 1.0) {
    [self clearPreviewLayersOnMainQueue];
    [self emitSessionError:@"This front/back camera configuration exceeds the device hardware budget." code:@"hardware_cost_exceeded"];
    return;
  }

  self.singleSession = nil;
  self.frontDeviceInput = frontInput;
  self.backDeviceInput = backInput;
  self.frontPhotoOutput = frontPhotoOutput;
  self.backPhotoOutput = backPhotoOutput;
  NSLog(@"[DualCamera] Session config complete — realtime front=%@ back=%@ audio=%@",
        self.frontVideoDataOutput ? @"OK" : @"NIL",
        self.backVideoDataOutput ? @"OK" : @"NIL",
        self.audioDataOutput ? @"OK" : @"NIL");
  self.usingMultiCam = YES;
  self.isConfigured = YES;
  [self registerSessionNotifications:self.multiCamSession];
  [self applyCurrentVideoOrientationAndMirroring];

  [self.multiCamSession startRunning];
  self.isRunning = self.multiCamSession.isRunning;
  if (!self.isRunning) {
    [self emitSessionError:@"Multi-cam session did not start running." code:@"multicam_start_failed"];
  }
}

- (void)configureAndStartSingleCameraFallback {
  if ([self isDualLayout:self.currentLayout]) {
    [self emitSessionError:@"This device does not support simultaneous front and back camera preview." code:@"multicam_unsupported"];
  }
  [self configureSingleSessionForPosition:[self primaryCameraPosition] startRunning:YES];
}

- (void)configureSingleSessionForPosition:(AVCaptureDevicePosition)position startRunning:(BOOL)startRunning {
  [self unregisterSessionNotifications];
  [self.singleSession stopRunning];

  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  session.sessionPreset = AVCaptureSessionPresetHigh;

  AVCaptureDevice *device = [self cameraDeviceForPosition:position];
  if (!device) {
    [self emitSessionError:@"Could not find the requested camera." code:@"camera_not_found"];
    return;
  }

  NSError *error = nil;
  AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
  if (!input) {
    [self emitSessionError:[NSString stringWithFormat:@"Camera input failed: %@", error.localizedDescription] code:@"single_input_failed"];
    return;
  }

  // Configure device before creating input — apply exposure + zoom
  if ([device lockForConfiguration:&error]) {
    if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
      device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    }
    if (position == AVCaptureDevicePositionBack) {
      device.videoZoomFactor = _backZoomFactor;
    } else {
      device.videoZoomFactor = _frontZoomFactor;
    }
    [device unlockForConfiguration];
  }

  AVCapturePhotoOutput *photoOutput = [[AVCapturePhotoOutput alloc] init];
  AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];

  [session beginConfiguration];

  // Audio input (microphone)
  AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
  if (audioDevice) {
    NSError *audioErr = nil;
    self.audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&audioErr];
    if (self.audioInput && [session canAddInput:self.audioInput]) {
      [session addInputWithNoConnections:self.audioInput];
    } else {
      NSLog(@"[DualCamera] Audio input not available: %@", audioErr.localizedDescription);
      self.audioInput = nil;
    }
  }

  BOOL addedInput = NO;
  if ([session canAddInput:input]) {
    [session addInput:input];
    addedInput = YES;
  }
  if ([session canAddOutput:photoOutput]) {
    [session addOutput:photoOutput];
  } else {
    photoOutput = nil;
  }
  if ([session canAddOutput:movieOutput]) {
    [session addOutput:movieOutput];
  } else {
    movieOutput = nil;
  }

  // Audio → singleMovieOutput (must be inside begin/commitConfiguration block)
  if (self.audioInput && movieOutput) {
    [self addAudioConnectionToMovieOutput:self.audioInput output:movieOutput session:session];
  }

  [session commitConfiguration];

  if (!addedInput) {
    [self emitSessionError:@"Cannot add camera input to fallback session." code:@"single_input_rejected"];
    return;
  }

  UIView *targetView = [self targetPreviewViewForPosition:position];
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self removePreviewLayers];
    AVCaptureVideoPreviewLayer *layer = [AVCaptureVideoPreviewLayer layerWithSession:session];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    layer.frame = targetView.bounds;
    [targetView.layer addSublayer:layer];
    self.singlePreviewLayer = layer;
    [self updateLayout];
    [self applyCurrentVideoOrientationAndMirroring];
  });

  self.singleSession = session;
  self.multiCamSession = nil;
  self.singleDeviceInput = input;
  self.singlePhotoOutput = photoOutput;
  self.singleMovieOutput = movieOutput;
  self.singleCameraPosition = position;
  self.usingMultiCam = NO;
  self.isConfigured = YES;
  [self registerSessionNotifications:session];
  [self applyCurrentVideoOrientationAndMirroring];

  if (startRunning) {
    [session startRunning];
    self.isRunning = session.isRunning;
    if (!self.isRunning) {
      [self emitSessionError:@"Single camera fallback session did not start running." code:@"single_start_failed"];
    }
  }
}

- (void)reconfigureSingleSessionForCurrentLayout {
  AVCaptureDevicePosition nextPosition = [self primaryCameraPosition];
  if (nextPosition == self.singleCameraPosition && self.singleSession) {
    return;
  }
  BOOL shouldRun = self.isRunning;
  [self configureSingleSessionForPosition:nextPosition startRunning:shouldRun];
}

- (void)resumeIfNeeded {
  if (!self.isConfigured || self.isRunning) return;

  AVCaptureSession *session = self.usingMultiCam ? self.multiCamSession : self.singleSession;
  [session startRunning];
  self.isRunning = session.isRunning;
}

- (void)internalStopSession {
  dispatch_async(self.sessionQueue, ^{
    if (!self.isConfigured || !self.isRunning) return;

    if (self.isDualRecordingActive || self.realtimeAssetWriter) {
      dispatch_async(self.videoDataOutputQueue, ^{
        [self finishRealtimeRecording];
      });
    }
    if (self.singleMovieOutput.isRecording) {
      [self.singleMovieOutput stopRecording];
    }

    [self.multiCamSession stopRunning];
    [self.singleSession stopRunning];
    self.isRunning = NO;
  });
}

#pragma mark - Session Configuration Helpers

- (AVCaptureDevice *)cameraDeviceForPosition:(AVCaptureDevicePosition)position {
  AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
    discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
    mediaType:AVMediaTypeVideo
    position:position];
  return discovery.devices.firstObject;
}

- (BOOL)configureDeviceForMultiCam:(AVCaptureDevice *)device error:(NSError **)error {
  AVCaptureDeviceFormat *format = [self bestMultiCamFormatForDevice:device];
  if (!format && ![device.activeFormat isMultiCamSupported]) {
    if (error) {
      *error = [NSError errorWithDomain:@"DualCamera"
                                   code:1001
                               userInfo:@{NSLocalizedDescriptionKey: @"No multi-cam supported format is available."}];
    }
    return NO;
  }

  if (![device lockForConfiguration:error]) {
    return NO;
  }

  if (format) {
    device.activeFormat = format;
  }
  device.activeVideoMinFrameDuration = CMTimeMake(1, 30);
  device.activeVideoMaxFrameDuration = CMTimeMake(1, 30);

  // Apply the CORRECT zoom factor for THIS camera (not _backZoomFactor for all)
  CGFloat zoomFactor = (device.position == AVCaptureDevicePositionBack) ? _backZoomFactor : _frontZoomFactor;
  CGFloat clampedZoom = zoomFactor;
  if (clampedZoom < device.minAvailableVideoZoomFactor) {
    clampedZoom = device.minAvailableVideoZoomFactor;
  } else if (clampedZoom > device.maxAvailableVideoZoomFactor) {
    clampedZoom = device.maxAvailableVideoZoomFactor;
  }
  device.videoZoomFactor = clampedZoom;

  // 自动曝光：防止严重过曝/欠曝，保持画面亮度正常
  if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
    device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
  }
  [device unlockForConfiguration];
  return YES;
}

- (void)dc_setFrontZoom:(CGFloat)factor {
  _frontZoomFactor = factor;
  dispatch_async(self.sessionQueue, ^{
    AVCaptureDevice *frontDevice = [self cameraDeviceForPosition:AVCaptureDevicePositionFront];
    if (!frontDevice) return;
    CGFloat f = factor;
    if (f < frontDevice.minAvailableVideoZoomFactor) {
      f = frontDevice.minAvailableVideoZoomFactor;
    } else if (f > frontDevice.maxAvailableVideoZoomFactor) {
      f = frontDevice.maxAvailableVideoZoomFactor;
    }
    NSError *err = nil;
    if ([frontDevice lockForConfiguration:&err]) {
      frontDevice.videoZoomFactor = f;
      [frontDevice unlockForConfiguration];
    }
  });
}

- (void)dc_setBackZoom:(CGFloat)factor {
  _backZoomFactor = factor;
  dispatch_async(self.sessionQueue, ^{
    AVCaptureDevice *backDevice = [self cameraDeviceForPosition:AVCaptureDevicePositionBack];
    if (!backDevice) return;
    CGFloat f = factor;
    if (f < backDevice.minAvailableVideoZoomFactor) {
      f = backDevice.minAvailableVideoZoomFactor;
    } else if (f > backDevice.maxAvailableVideoZoomFactor) {
      f = backDevice.maxAvailableVideoZoomFactor;
    }
    NSError *err = nil;
    if ([backDevice lockForConfiguration:&err]) {
      backDevice.videoZoomFactor = f;
      [backDevice unlockForConfiguration];
    }
  });
}

- (AVCaptureDeviceFormat *)bestMultiCamFormatForDevice:(AVCaptureDevice *)device {
  AVCaptureDeviceFormat *bestFormat = nil;
  int32_t bestArea = 0;

  for (AVCaptureDeviceFormat *format in device.formats) {
    if (![format isMultiCamSupported] || ![self formatSupportsThirtyFps:format]) {
      continue;
    }

    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    int32_t area = dimensions.width * dimensions.height;
    BOOL fitsModerateBudget = dimensions.width <= 1920 && dimensions.height <= 1440;
    BOOL currentBestFitsBudget = NO;
    if (bestFormat) {
      CMVideoDimensions bestDimensions = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription);
      currentBestFitsBudget = bestDimensions.width <= 1920 && bestDimensions.height <= 1440;
    }

    if (!bestFormat ||
        (fitsModerateBudget && !currentBestFitsBudget) ||
        (fitsModerateBudget == currentBestFitsBudget && area > bestArea)) {
      bestFormat = format;
      bestArea = area;
    }
  }

  return bestFormat;
}

- (BOOL)formatSupportsThirtyFps:(AVCaptureDeviceFormat *)format {
  for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
    if (range.minFrameRate <= 30.0 && range.maxFrameRate >= 30.0) {
      return YES;
    }
  }
  return NO;
}

- (AVCaptureInputPort *)videoPortForInput:(AVCaptureDeviceInput *)input {
  for (AVCaptureInputPort *port in input.ports) {
    if ([port.mediaType isEqualToString:AVMediaTypeVideo]) {
      return port;
    }
  }
  return nil;
}

- (BOOL)addPreviewLayer:(AVCaptureVideoPreviewLayer *)layer
                forPort:(AVCaptureInputPort *)port
              toSession:(AVCaptureSession *)session
            mirrorVideo:(BOOL)mirrorVideo
                failure:(NSString **)failure
            failureCode:(NSString **)failureCode {
  AVCaptureConnection *connection = [[AVCaptureConnection alloc] initWithInputPort:port videoPreviewLayer:layer];
  if (![session canAddConnection:connection]) {
    if (failure) *failure = @"Cannot connect camera input to preview layer.";
    if (failureCode) *failureCode = @"preview_connection_failed";
    return NO;
  }

  [session addConnection:connection];
  if (connection.isVideoOrientationSupported) {
    connection.videoOrientation = [self currentCaptureVideoOrientation];
  }
  if (mirrorVideo && connection.isVideoMirroringSupported) {
    connection.automaticallyAdjustsVideoMirroring = NO;
    connection.videoMirrored = YES;
  }
  return YES;
}

- (BOOL)addOutput:(AVCaptureOutput *)output
          forPort:(AVCaptureInputPort *)port
        toSession:(AVCaptureSession *)session
          failure:(NSString **)failure
      failureCode:(NSString **)failureCode {
  if (![session canAddOutput:output]) {
    if (failure) *failure = @"Cannot add camera output to session.";
    if (failureCode) *failureCode = @"output_rejected";
    return NO;
  }

  [session addOutputWithNoConnections:output];
  AVCaptureConnection *connection = [[AVCaptureConnection alloc] initWithInputPorts:@[port] output:output];
  if (![session canAddConnection:connection]) {
    if (failure) *failure = @"Cannot connect camera input to output.";
    if (failureCode) *failureCode = @"output_connection_failed";
    return NO;
  }

  [session addConnection:connection];
  if (connection.isVideoOrientationSupported) {
    connection.videoOrientation = [self currentCaptureVideoOrientation];
  }
  return YES;
}

- (void)addAudioConnectionToMovieOutput:(AVCaptureDeviceInput *)audioInput
                                 output:(AVCaptureMovieFileOutput *)movieOutput
                                session:(AVCaptureSession *)session {
  if (!movieOutput || !audioInput) return;

  for (AVCaptureInputPort *port in audioInput.ports) {
    if ([port.mediaType isEqualToString:AVMediaTypeAudio]) {
      AVCaptureConnection *audioConn = [[AVCaptureConnection alloc] initWithInputPorts:@[port] output:movieOutput];
      if ([session canAddConnection:audioConn]) {
        [session addConnection:audioConn];
      }
      break;
    }
  }
}

#pragma mark - Capture Helpers

- (BOOL)isUsingMultiCamDualLayout {
  return self.usingMultiCam && [self isDualLayout:self.currentLayout];
}

- (NSString *)tempPathWithPrefix:(NSString *)prefix {
  return [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat:@"%@%ld.mov", prefix, (long)[[NSDate date] timeIntervalSince1970]]];
}

- (NSString *)saveCIImageAsJPEG:(CIImage *)ciImage {
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat:@"dual_composited_%ld.jpg", (long)[[NSDate date] timeIntervalSince1970]]];

  CIContext *ctx = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];

  // Ensure image is at origin (0,0) before saving to avoid partial crop
  CIImage *toSave = ciImage;
  if (ciImage.extent.origin.x != 0 || ciImage.extent.origin.y != 0) {
    CGFloat ox = -ciImage.extent.origin.x;
    CGFloat oy = -ciImage.extent.origin.y;
    toSave = [ciImage imageByApplyingTransform:CGAffineTransformMakeTranslation(ox, oy)];
  }

  CGImageRef cgImg = [ctx createCGImage:toSave fromRect:toSave.extent];
  if (!cgImg) return nil;

  UIImage *uiImage = [UIImage imageWithCGImage:cgImg];
  CGImageRelease(cgImg);

  NSData *jpgData = UIImageJPEGRepresentation(uiImage, 0.9);
  if (!jpgData) return nil;

  [jpgData writeToFile:path atomically:YES];
  return path;
}

- (CIImage *)blackCanvasSize:(CGSize)size {
  CIFilter *colorGen = [CIFilter filterWithName:@"CIConstantColorGenerator"];
  [colorGen setValue:[CIColor colorWithRed:0 green:0 blue:0 alpha:1] forKey:kCIInputColorKey];
  CIImage *canvas = [colorGen.outputImage imageByCroppingToRect:CGRectMake(0, 0, size.width, size.height)];
  CGFloat ox = -canvas.extent.origin.x;
  CGFloat oy = -canvas.extent.origin.y;
  if (ox != 0 || oy != 0) {
    canvas = [canvas imageByApplyingTransform:CGAffineTransformMakeTranslation(ox, oy)];
  }
  return canvas;
}

- (CIImage *)scaledCIImage:(CIImage *)image toSize:(CGSize)size {
  CGFloat scaleX = size.width / image.extent.size.width;
  CGFloat scaleY = size.height / image.extent.size.height;
  // Use CIAffineTransform to preserve correct aspect ratio
  CIFilter *transformFilter = [CIFilter filterWithName:@"CIAffineTransform"];
  [transformFilter setValue:image forKey:kCIInputImageKey];
  [transformFilter setValue:[NSValue valueWithCGAffineTransform:CGAffineTransformMakeScale(scaleX, scaleY)] forKey:kCIInputTransformKey];
  CIImage *result = transformFilter.outputImage;
  if (!result) return image;
  // CIAffineTransform moves the extent origin; translate back to (0,0)
  CGFloat offsetX = -result.extent.origin.x;
  CGFloat offsetY = -result.extent.origin.y;
  if (offsetX != 0 || offsetY != 0) {
    result = [result imageByApplyingTransform:CGAffineTransformMakeTranslation(offsetX, offsetY)];
  }
  return result;
}

- (NSString *)documentsPathWithPrefix:(NSString *)prefix {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  return [paths.firstObject stringByAppendingPathComponent:
    [NSString stringWithFormat:@"%@%ld.mp4", prefix, (long)[[NSDate date] timeIntervalSince1970]]];
}

- (CGSize)outputSizeForAspectRatio:(NSString *)aspectRatio
                     referenceWidth:(CGFloat)referenceWidth
                          landscape:(BOOL)landscape {
  CGFloat width = referenceWidth > 0 ? referenceWidth : 1080.0;
  CGSize portraitSize;
  if ([aspectRatio isEqualToString:@"3:4"]) {
    portraitSize = CGSizeMake(width, round(width * 4.0 / 3.0));
  } else if ([aspectRatio isEqualToString:@"1:1"]) {
    portraitSize = CGSizeMake(width, width);
  } else {
    portraitSize = CGSizeMake(width, round(width * 16.0 / 9.0));
  }
  if (landscape && portraitSize.height != portraitSize.width) {
    return CGSizeMake(portraitSize.height, portraitSize.width);
  }
  return portraitSize;
}

- (CGSize)realtimeRecordingOutputSizeForAspectRatio:(NSString *)aspectRatio landscape:(BOOL)landscape {
  return [self outputSizeForAspectRatio:aspectRatio referenceWidth:1080.0 landscape:landscape];
}

- (void)resetRealtimeRecordingContext {
  self.realtimeAssetWriter = nil;
  self.realtimeVideoInput = nil;
  self.realtimeAudioInput = nil;
  self.realtimePixelBufferAdaptor = nil;
  self.realtimeRecordingPath = nil;
  self.realtimeRecordingAspectRatio = nil;
  self.realtimeOutputSize = CGSizeZero;
  self.recordingLayoutState = nil;
  self.realtimeWriterStarted = NO;
  self.realtimeFinishRequested = NO;
  self.realtimeFinishWhenFirstFrameWritten = NO;
  self.realtimeRecordingStartedEventEmitted = NO;
  self.realtimeDroppedFrameCount = 0;
  self.realtimeWrittenVideoFrameCount = 0;
  self.realtimeDroppedAudioSampleCount = 0;
  self.lastRealtimeVideoPTS = kCMTimeInvalid;
  self.hasLastRealtimeVideoPTS = NO;
  self.realtimeRecordingState = DualCameraRealtimeRecordingStateIdle;
  self.isDualRecordingActive = NO;
  [self updateDeviceOrientation:[UIDevice currentDevice].orientation];
}

- (NSNumber *)numberForCMTimeSeconds:(CMTime)time {
  if (!CMTIME_IS_VALID(time)) return nil;
  Float64 seconds = CMTimeGetSeconds(time);
  if (!isfinite(seconds)) return nil;
  return @(seconds);
}

- (NSDictionary *)recordingErrorDetailsForError:(NSError *)error
                                        context:(NSString *)context
                                    rejectedPTS:(CMTime)rejectedPTS {
  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  if (context) details[@"context"] = context;
  details[@"realtimeState"] = @(self.realtimeRecordingState);
  details[@"writerStatus"] = self.realtimeAssetWriter ? @(self.realtimeAssetWriter.status) : @(-1);
  details[@"writtenVideoFrames"] = @(self.realtimeWrittenVideoFrameCount);
  details[@"droppedVideoFrames"] = @(self.realtimeDroppedFrameCount);
  details[@"droppedAudioSamples"] = @(self.realtimeDroppedAudioSampleCount);
  details[@"hardwareCost"] = self.multiCamSession ? @(self.multiCamSession.hardwareCost) : @(0);
  details[@"systemPressureCost"] = self.multiCamSession ? @(self.multiCamSession.systemPressureCost) : @(0);
  NSNumber *lastPTS = [self numberForCMTimeSeconds:self.lastRealtimeVideoPTS];
  if (lastPTS) details[@"lastVideoPTS"] = lastPTS;
  NSNumber *incomingPTS = [self numberForCMTimeSeconds:rejectedPTS];
  if (incomingPTS) details[@"incomingVideoPTS"] = incomingPTS;

  if (error) {
    details[@"domain"] = error.domain ?: @"";
    details[@"code"] = @(error.code);
    if (error.localizedFailureReason) details[@"failureReason"] = error.localizedFailureReason;
    if (error.localizedRecoverySuggestion) details[@"recoverySuggestion"] = error.localizedRecoverySuggestion;
    if (error.userInfo.count > 0) details[@"userInfo"] = error.userInfo.description;
  }
  return details;
}

- (void)emitRecordingError:(NSString *)message
                   details:(NSDictionary *)details {
  NSLog(@"[DualCamera] Recording error: %@ details=%@", message ?: @"Recording error", details ?: @{});
  [[DualCameraEventEmitter shared] sendRecordingError:message details:details];
}

- (void)emitRecordingErrorForError:(NSError *)error
                            prefix:(NSString *)prefix
                           context:(NSString *)context
                       rejectedPTS:(CMTime)rejectedPTS {
  NSString *message = error.localizedDescription ?: prefix ?: @"Recording error";
  NSDictionary *details = [self recordingErrorDetailsForError:error context:context rejectedPTS:rejectedPTS];
  [self emitRecordingError:message details:details];
}

- (void)failRealtimeRecording:(NSString *)message {
  if (self.realtimeRecordingState == DualCameraRealtimeRecordingStateIdle) return;
  NSDictionary *details = [self recordingErrorDetailsForError:self.realtimeAssetWriter.error
                                                     context:@"realtime_fail"
                                                 rejectedPTS:kCMTimeInvalid];
  self.realtimeRecordingState = DualCameraRealtimeRecordingStateFailed;
  self.isDualRecordingActive = NO;
  [self.realtimeAssetWriter cancelWriting];
  [self resetRealtimeRecordingContext];
  [self emitRecordingError:message ?: @"Realtime recording failed." details:details];
}

- (BOOL)startRealtimeRecordingWithCanvasSize:(CGSize)canvasSize {
  if (self.realtimeRecordingState != DualCameraRealtimeRecordingStateIdle || self.realtimeAssetWriter) return NO;

  NSString *path = [self documentsPathWithPrefix:@"dual_realtime_"];
  NSURL *url = [NSURL fileURLWithPath:path];
  [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

  NSError *error = nil;
  AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&error];
  if (!writer || error) {
    [self emitRecordingError:error.localizedDescription ?: @"Failed to create realtime video writer."];
    return NO;
  }

  NSString *aspectRatio = self.saveAspectRatio ?: @"9:16";
  DualCameraDeviceOrientation recordingOrientation = self.deviceOrientation;
  CGSize outputSize = [self realtimeRecordingOutputSizeForAspectRatio:aspectRatio
                                                             landscape:[self isDeviceOrientationLandscape:recordingOrientation]];
  DualCameraLayoutState *recordingState = [self layoutStateSnapshotForCanvasSize:canvasSize
                                                                       outputSize:outputSize
                                                                      orientation:recordingOrientation];
  NSDictionary *videoSettings = @{
    AVVideoCodecKey: AVVideoCodecTypeH264,
    AVVideoWidthKey: @(outputSize.width),
    AVVideoHeightKey: @(outputSize.height),
    AVVideoCompressionPropertiesKey: @{
      AVVideoAverageBitRateKey: @(8000000),
      AVVideoExpectedSourceFrameRateKey: @(30),
      AVVideoMaxKeyFrameIntervalKey: @(30)
    }
  };
  AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
  videoInput.expectsMediaDataInRealTime = YES;
  videoInput.transform = CGAffineTransformIdentity;

  NSDictionary *pixelAttrs = @{
    (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferWidthKey: @(outputSize.width),
    (id)kCVPixelBufferHeightKey: @(outputSize.height),
    (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
  };
  AVAssetWriterInputPixelBufferAdaptor *adaptor =
    [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoInput
                                                                     sourcePixelBufferAttributes:pixelAttrs];

  NSDictionary *audioSettings = @{
    AVFormatIDKey: @(kAudioFormatMPEG4AAC),
    AVSampleRateKey: @(44100),
    AVNumberOfChannelsKey: @(1),
    AVEncoderBitRateKey: @(128000)
  };
  AVAssetWriterInput *audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
  audioInput.expectsMediaDataInRealTime = YES;

  if (![writer canAddInput:videoInput]) {
    [self emitRecordingError:@"Realtime video writer rejected the video input."];
    return NO;
  }
  [writer addInput:videoInput];

  if ([writer canAddInput:audioInput]) {
    [writer addInput:audioInput];
  } else {
    NSLog(@"[DualCamera] Realtime writer rejected audio input; recording video only");
    audioInput = nil;
  }

  self.realtimeAssetWriter = writer;
  self.realtimeVideoInput = videoInput;
  self.realtimeAudioInput = audioInput;
  self.realtimePixelBufferAdaptor = adaptor;
  self.realtimeRecordingPath = path;
  self.realtimeRecordingAspectRatio = aspectRatio;
  self.realtimeOutputSize = outputSize;
  self.recordingLayoutState = recordingState;
  self.realtimeRecordingState = DualCameraRealtimeRecordingStatePrepared;
  self.realtimeWriterStarted = NO;
  self.realtimeFinishRequested = NO;
  self.realtimeFinishWhenFirstFrameWritten = NO;
  self.realtimeRecordingStartedEventEmitted = NO;
  self.realtimeDroppedFrameCount = 0;
  self.realtimeWrittenVideoFrameCount = 0;
  self.realtimeDroppedAudioSampleCount = 0;
  self.lastRealtimeVideoPTS = kCMTimeInvalid;
  self.hasLastRealtimeVideoPTS = NO;
  self.canvasSizeAtRecording = canvasSize;
  self.isDualRecordingActive = YES;

  NSDictionary<NSString *, NSValue *> *recordingRects = [self rectsForLayoutState:recordingState canvasSize:outputSize];
  NSLog(@"[DualCamera] Realtime recording prepared path=%@ layout=%@ aspect=%@ output=%.0fx%.0f canvas=%.0fx%.0f landscape=%d hardwareCost=%.3f systemPressureCost=%.3f backRect=%@ frontRect=%@",
        path, recordingState.layoutMode, aspectRatio, outputSize.width, outputSize.height,
        canvasSize.width, canvasSize.height, recordingState.isLandscape,
        self.multiCamSession.hardwareCost, self.multiCamSession.systemPressureCost,
        NSStringFromCGRect([recordingRects[@"back"] CGRectValue]),
        NSStringFromCGRect([recordingRects[@"front"] CGRectValue]));
  return YES;
}

- (BOOL)ensureRealtimeWriterStartedAtTime:(CMTime)time {
  if (self.realtimeWriterStarted) return YES;
  if (!self.realtimeAssetWriter) return NO;
  if (CMTIME_IS_INVALID(time)) return NO;

  if (![self.realtimeAssetWriter startWriting]) {
    [self failRealtimeRecording:self.realtimeAssetWriter.error.localizedDescription ?: @"Realtime writer failed to start."];
    return NO;
  }
  [self.realtimeAssetWriter startSessionAtSourceTime:time];
  self.realtimeWriterStarted = YES;
  return YES;
}

- (CIImage *)clearCanvasSize:(CGSize)size {
  CIFilter *colorGen = [CIFilter filterWithName:@"CIConstantColorGenerator"];
  [colorGen setValue:[CIColor colorWithRed:0 green:0 blue:0 alpha:0] forKey:kCIInputColorKey];
  return [colorGen.outputImage imageByCroppingToRect:CGRectMake(0, 0, size.width, size.height)];
}

- (CIImage *)circleAlphaMaskForRect:(CGRect)rect canvasSize:(CGSize)canvasSize {
  CIFilter *radialGradient = [CIFilter filterWithName:@"CIRadialGradient"];
  CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
  CGFloat radius = MIN(rect.size.width, rect.size.height) / 2.0;
  [radialGradient setValue:[CIVector vectorWithX:center.x Y:center.y] forKey:kCIInputCenterKey];
  [radialGradient setValue:@(radius * 0.98) forKey:@"inputRadius0"];
  [radialGradient setValue:@(radius) forKey:@"inputRadius1"];
  [radialGradient setValue:[CIColor colorWithRed:1 green:1 blue:1 alpha:1] forKey:@"inputColor0"];
  [radialGradient setValue:[CIColor colorWithRed:1 green:1 blue:1 alpha:0] forKey:@"inputColor1"];
  return [radialGradient.outputImage imageByCroppingToRect:CGRectMake(0, 0, canvasSize.width, canvasSize.height)];
}

- (CIImage *)preparedCameraImage:(CIImage *)image
                      targetRect:(CGRect)targetRect
                      canvasSize:(CGSize)canvasSize
                        mirrored:(BOOL)mirrored {
  if (!image || CGRectIsEmpty(targetRect)) return nil;

  CIImage *source = image;
  if (source.extent.origin.x != 0 || source.extent.origin.y != 0) {
    source = [source imageByApplyingTransform:CGAffineTransformMakeTranslation(-source.extent.origin.x, -source.extent.origin.y)];
  }

  CGFloat sourceW = source.extent.size.width;
  CGFloat sourceH = source.extent.size.height;
  if (sourceW <= 0 || sourceH <= 0) return nil;

  if (mirrored) {
    CGAffineTransform mirror = CGAffineTransformMakeTranslation(sourceW, 0);
    mirror = CGAffineTransformScale(mirror, -1, 1);
    source = [source imageByApplyingTransform:mirror];
    if (source.extent.origin.x != 0 || source.extent.origin.y != 0) {
      source = [source imageByApplyingTransform:CGAffineTransformMakeTranslation(-source.extent.origin.x, -source.extent.origin.y)];
    }
  }

  CGFloat scale = MAX(targetRect.size.width / sourceW, targetRect.size.height / sourceH);
  CIImage *scaled = [self scaledCIImage:source toSize:CGSizeMake(sourceW * scale, sourceH * scale)];
  CGFloat cropX = MAX(0, (scaled.extent.size.width - targetRect.size.width) / 2.0);
  CGFloat cropY = MAX(0, (scaled.extent.size.height - targetRect.size.height) / 2.0);
  CIImage *cropped = [scaled imageByCroppingToRect:CGRectMake(cropX, cropY, targetRect.size.width, targetRect.size.height)];
  CIImage *placed = [cropped imageByApplyingTransform:CGAffineTransformMakeTranslation(targetRect.origin.x - cropX, targetRect.origin.y - cropY)];
  return [placed imageByCroppingToRect:CGRectMake(0, 0, canvasSize.width, canvasSize.height)];
}

- (CIImage *)compositedImageForLayoutState:(DualCameraLayoutState *)state
                                     front:(CIImage *)front
                                      back:(CIImage *)back {
  CGSize canvasSize = state.outputSize;
  NSDictionary<NSString *, NSValue *> *rects = [self rectsForLayoutState:state canvasSize:canvasSize];
  CGRect backRect = [rects[@"back"] CGRectValue];
  CGRect frontRect = [rects[@"front"] CGRectValue];
  NSString *layout = state.layoutMode ?: @"back";

  if ([layout isEqualToString:@"back"] && !back) {
    back = front;
  }
  if ([layout isEqualToString:@"front"] && !front) {
    front = back;
  }
  if ([self isDualLayout:layout] && !front && !back) return nil;

  CIImage *result = [self blackCanvasSize:canvasSize];
  CIImage *backImage = [self preparedCameraImage:back targetRect:backRect canvasSize:canvasSize mirrored:state.backMirrored];
  CIImage *frontImage = [self preparedCameraImage:front targetRect:frontRect canvasSize:canvasSize mirrored:state.frontMirrored];

  BOOL isPip = [layout isEqualToString:@"pip_square"] || [layout isEqualToString:@"pip_circle"];
  BOOL isCircle = [layout isEqualToString:@"pip_circle"];

  if (!isPip) {
    if (backImage) result = [backImage imageByCompositingOverImage:result];
    if (frontImage) result = [frontImage imageByCompositingOverImage:result];
    return [result imageByCroppingToRect:CGRectMake(0, 0, canvasSize.width, canvasSize.height)];
  }

  BOOL frontIsPip = state.pipMainIsBack;
  if (state.pipMainIsBack) {
    if (backImage) result = [backImage imageByCompositingOverImage:result];
  } else {
    if (frontImage) result = [frontImage imageByCompositingOverImage:result];
  }

  CIImage *pipImage = frontIsPip ? frontImage : backImage;
  CGRect pipRect = frontIsPip ? frontRect : backRect;
  if (pipImage && isCircle) {
    CIImage *mask = [self circleAlphaMaskForRect:pipRect canvasSize:canvasSize];
    CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithAlphaMask"];
    [blend setValue:pipImage forKey:kCIInputImageKey];
    [blend setValue:[self clearCanvasSize:canvasSize] forKey:kCIInputBackgroundImageKey];
    [blend setValue:mask forKey:kCIInputMaskImageKey];
    pipImage = blend.outputImage ?: pipImage;
  }
  if (pipImage) result = [pipImage imageByCompositingOverImage:result];
  return [result imageByCroppingToRect:CGRectMake(0, 0, canvasSize.width, canvasSize.height)];
}

- (void)appendRealtimeVideoFrameAtTime:(CMTime)time source:(NSString *)source {
  if (!self.isDualRecordingActive || self.realtimeFinishRequested) return;
  if (self.realtimeRecordingState != DualCameraRealtimeRecordingStatePrepared &&
      self.realtimeRecordingState != DualCameraRealtimeRecordingStateWriting) {
    return;
  }
  if (self.realtimeAssetWriter.status == AVAssetWriterStatusFailed) {
    [self failRealtimeRecording:self.realtimeAssetWriter.error.localizedDescription ?: @"Realtime writer failed."];
    return;
  }
  if (!CMTIME_IS_VALID(time)) {
    self.realtimeDroppedFrameCount += 1;
    return;
  }
  if (self.hasLastRealtimeVideoPTS && CMTIME_COMPARE_INLINE(time, <=, self.lastRealtimeVideoPTS)) {
    self.realtimeDroppedFrameCount += 1;
    NSLog(@"[DualCamera] Dropping non-monotonic realtime frame source=%@ incoming=%.6f last=%.6f",
          source ?: @"unknown", CMTimeGetSeconds(time), CMTimeGetSeconds(self.lastRealtimeVideoPTS));
    return;
  }

  CIImage *frontFrame = nil;
  CIImage *backFrame = nil;
  @synchronized(self) {
    frontFrame = self.latestFrontFrame;
    backFrame = self.latestBackFrame;
  }

  CGSize outputSize = CGSizeEqualToSize(self.realtimeOutputSize, CGSizeZero)
    ? [self realtimeRecordingOutputSizeForAspectRatio:self.realtimeRecordingAspectRatio ?: self.saveAspectRatio
                                           landscape:[self isCurrentDeviceLandscape]]
    : self.realtimeOutputSize;
  DualCameraLayoutState *state = self.recordingLayoutState;
  if (!state) {
    state = [self currentLayoutStateForCanvasSize:self.canvasSizeAtRecording outputSize:outputSize];
  }
  CIImage *composited = [self compositedImageForLayoutState:state front:frontFrame back:backFrame];
  if (!composited) return;

  if (![self ensureRealtimeWriterStartedAtTime:time]) return;
  if (!self.realtimeVideoInput.isReadyForMoreMediaData) {
    self.realtimeDroppedFrameCount += 1;
    return;
  }

  CVPixelBufferRef pixelBuffer = NULL;
  CVPixelBufferPoolRef pool = self.realtimePixelBufferAdaptor.pixelBufferPool;
  if (!pool || CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pixelBuffer) != kCVReturnSuccess || !pixelBuffer) {
    self.realtimeDroppedFrameCount += 1;
    return;
  }

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  [self.ciContext render:composited
         toCVPixelBuffer:pixelBuffer
                  bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
              colorSpace:colorSpace];
  CGColorSpaceRelease(colorSpace);

  if (![self.realtimePixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time]) {
    self.realtimeDroppedFrameCount += 1;
    [self failRealtimeRecording:self.realtimeAssetWriter.error.localizedDescription ?: @"Failed to append realtime video frame."];
  } else {
    self.lastRealtimeVideoPTS = time;
    self.hasLastRealtimeVideoPTS = YES;
    self.realtimeWrittenVideoFrameCount += 1;
    self.realtimeRecordingState = DualCameraRealtimeRecordingStateWriting;
    if (!self.realtimeRecordingStartedEventEmitted) {
      self.realtimeRecordingStartedEventEmitted = YES;
      [self emitRecordingStarted];
    }
    if (self.realtimeFinishWhenFirstFrameWritten && self.realtimeWrittenVideoFrameCount > 0) {
      self.realtimeFinishWhenFirstFrameWritten = NO;
      dispatch_async(self.videoDataOutputQueue, ^{
        [self finishRealtimeRecording];
      });
    }
  }
  CVPixelBufferRelease(pixelBuffer);
}

- (void)appendRealtimeAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer {
  if (!self.isDualRecordingActive || self.realtimeFinishRequested || !self.realtimeAudioInput) return;
  if (self.realtimeRecordingState != DualCameraRealtimeRecordingStateWriting) return;
  if (self.realtimeAssetWriter.status == AVAssetWriterStatusFailed) {
    [self failRealtimeRecording:self.realtimeAssetWriter.error.localizedDescription ?: @"Realtime writer failed."];
    return;
  }
  if (self.realtimeAudioInput.isReadyForMoreMediaData) {
    if (![self.realtimeAudioInput appendSampleBuffer:sampleBuffer]) {
      self.realtimeDroppedAudioSampleCount += 1;
      if (self.realtimeAssetWriter.status == AVAssetWriterStatusFailed) {
        [self failRealtimeRecording:self.realtimeAssetWriter.error.localizedDescription ?: @"Failed to append realtime audio sample."];
      }
    }
  }
}

- (void)finishRealtimeRecording {
  if (self.realtimeRecordingState == DualCameraRealtimeRecordingStateIdle ||
      self.realtimeRecordingState == DualCameraRealtimeRecordingStateFinishing) {
    return;
  }

  AVAssetWriter *writer = self.realtimeAssetWriter;
  AVAssetWriterInput *videoInput = self.realtimeVideoInput;
  AVAssetWriterInput *audioInput = self.realtimeAudioInput;
  NSString *path = self.realtimeRecordingPath;
  NSInteger dropped = self.realtimeDroppedFrameCount;
  NSInteger audioDropped = self.realtimeDroppedAudioSampleCount;
  NSInteger written = self.realtimeWrittenVideoFrameCount;

  if (!writer || !path) {
    NSDictionary *details = [self recordingErrorDetailsForError:nil context:@"finish_missing_writer" rejectedPTS:kCMTimeInvalid];
    [self resetRealtimeRecordingContext];
    [self emitRecordingError:@"Realtime recording was not initialized." details:details];
    return;
  }

  if (self.realtimeRecordingState == DualCameraRealtimeRecordingStateFailed ||
      writer.status == AVAssetWriterStatusFailed) {
    NSString *message = writer.error.localizedDescription ?: @"Realtime recording failed.";
    NSDictionary *details = [self recordingErrorDetailsForError:writer.error context:@"finish_failed_status" rejectedPTS:kCMTimeInvalid];
    [writer cancelWriting];
    [self resetRealtimeRecordingContext];
    [self emitRecordingError:message details:details];
    return;
  }

  if (self.realtimeRecordingState == DualCameraRealtimeRecordingStatePrepared ||
      writer.status == AVAssetWriterStatusUnknown ||
      written <= 0) {
    self.realtimeFinishWhenFirstFrameWritten = YES;
    return;
  }

  self.realtimeFinishRequested = YES;
  self.isDualRecordingActive = NO;

  self.realtimeRecordingState = DualCameraRealtimeRecordingStateFinishing;
  [videoInput markAsFinished];
  if (audioInput) [audioInput markAsFinished];
  [writer finishWritingWithCompletionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      if (writer.status == AVAssetWriterStatusCompleted) {
        NSLog(@"[DualCamera] Realtime recording finished path=%@ written=%ld dropped=%ld audioDropped=%ld",
              path, (long)written, (long)dropped, (long)audioDropped);
        [self resetRealtimeRecordingContext];
        [self emitRecordingFinished:[NSString stringWithFormat:@"file://%@", path]];
      } else {
        NSString *message = writer.error.localizedDescription ?: @"Realtime recording failed.";
        NSDictionary *details = [self recordingErrorDetailsForError:writer.error context:@"finish_completion_failed" rejectedPTS:kCMTimeInvalid];
        [self resetRealtimeRecordingContext];
        [self emitRecordingError:message details:details];
      }
    });
  }];
}

- (AVMutableVideoCompositionLayerInstruction *)layerForTrack:(AVMutableCompositionTrack *)track {
  if (!track) return nil;
  return [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
}

#pragma mark - Capture

- (void)internalTakePhoto {
  // Capture screen size on main thread BEFORE dispatching to background
  __block CGSize canvasSizeForPhoto;
  dispatch_sync(dispatch_get_main_queue(), ^{
    canvasSizeForPhoto = self.bounds.size;
  });

  dispatch_async(self.sessionQueue, ^{
    @autoreleasepool {
      if (!self.isConfigured) return;

      if (self.usingMultiCam && [self isDualLayout:self.currentLayout]) {
        // WYSIWYG: grab latest frames from VideoDataOutput and composite
        CIImage *frontFrame;
        CIImage *backFrame;
        @synchronized(self) {
          frontFrame = self.latestFrontFrame;
          backFrame = self.latestBackFrame;
        }

        NSLog(@"[DualCamera] internalTakePhoto WYSIWYG — frontFrame=%@ backFrame=%@ layout=%@",
              frontFrame ? @"OK" : @"NIL",
              backFrame ? @"OK" : @"NIL",
              self.currentLayout);

        if (!frontFrame || !backFrame) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [self emitError:@"Camera not ready, please try again"];
          });
          return;
        }

        CGFloat refW = MIN(canvasSizeForPhoto.width, canvasSizeForPhoto.height) * 3.0;
        DualCameraDeviceOrientation photoOrientation = self.deviceOrientation;
        CGSize saveCanvas = [self outputSizeForAspectRatio:self.saveAspectRatio ?: @"9:16"
                                             referenceWidth:refW
                                                  landscape:[self isDeviceOrientationLandscape:photoOrientation]];
        DualCameraLayoutState *photoState = [self layoutStateSnapshotForCanvasSize:canvasSizeForPhoto
                                                                        outputSize:saveCanvas
                                                                       orientation:photoOrientation];

        NSLog(@"[DualCamera] internalTakePhoto — front size=%@ back size=%@ canvasSizeForPhoto=%@ saveCanvas=%@",
              NSStringFromCGSize(frontFrame.extent.size),
              NSStringFromCGSize(backFrame.extent.size),
              NSStringFromCGSize(canvasSizeForPhoto),
              NSStringFromCGSize(saveCanvas));

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          @autoreleasepool {
            CIImage *composited = [self compositedImageForLayoutState:photoState front:frontFrame back:backFrame];
            NSLog(@"[DualCamera] internalTakePhoto — composited extent=%@ (expect W=%.0f H=%.0f)",
                  NSStringFromCGRect(composited.extent), saveCanvas.width, saveCanvas.height);
            NSString *path = [self saveCIImageAsJPEG:composited];
            NSLog(@"[DualCamera] internalTakePhoto — saved path=%@", path);
            dispatch_async(dispatch_get_main_queue(), ^{
              if (path) {
                [self emitPhotoSaved:[NSString stringWithFormat:@"file://%@", path]];
              } else {
                [self emitError:@"Failed to save photo"];
              }
            });
          }
        });
      } else {
        // Single-cam: use photo output for full-resolution
        AVCapturePhotoOutput *output = [self photoOutputForCurrentLayout];
        if (!output) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [self emitError:@"Photo output not available"];
          });
          return;
        }
        @try {
          AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
          settings.flashMode = AVCaptureFlashModeOff;
          [output capturePhotoWithSettings:settings delegate:self];
        } @catch (NSException *exception) {
          NSLog(@"[DualCamera] internalTakePhoto exception: %@", exception);
          dispatch_async(dispatch_get_main_queue(), ^{
            [self emitError:[NSString stringWithFormat:@"Photo capture failed: %@", exception.reason ?: @"Unknown error"]];
          });
        }
      }
    }
  });
}

- (void)internalStartRecording {
  // Capture bounds on main thread BEFORE dispatching to background queue
  // (UIView.bounds must not be accessed from background threads)
  __block CGSize canvasSizeForRecording;
  dispatch_sync(dispatch_get_main_queue(), ^{
    canvasSizeForRecording = self.bounds.size;
  });

  dispatch_async(self.sessionQueue, ^{
    if (!self.isConfigured) return;

    if (self.usingMultiCam) {
      if (!self.frontVideoDataOutput || !self.backVideoDataOutput) {
        [self emitRecordingError:@"Realtime recording unavailable — video data outputs are not configured."];
        return;
      }
      [self startRealtimeRecordingWithCanvasSize:canvasSizeForRecording];
    } else {
      // Single-cam
      self.canvasSizeAtRecording = canvasSizeForRecording;
      AVCaptureMovieFileOutput *output = [self movieOutputForCurrentLayout];
      if (!output) {
        [self emitRecordingError:@"Video recording is currently available only for the active single camera or the back camera stream in dual mode."];
        return;
      }
      if (output.isRecording || self.singleRecordingStartPending) return;

      NSString *path = [self tempPathWithPrefix:@"dual_"];
      self.singleRecordingStartPending = YES;
      self.singleRecordingStopRequested = NO;
      [output startRecordingToOutputFileURL:[NSURL fileURLWithPath:path] recordingDelegate:self];
    }
  });
}

- (void)internalStopRecording {
  dispatch_async(self.sessionQueue, ^{
    if (!self.isConfigured) return;

    if (self.usingMultiCam) {
      dispatch_async(self.videoDataOutputQueue, ^{
        [self finishRealtimeRecording];
      });
    } else {
      // Single-cam
      AVCaptureMovieFileOutput *output = [self activeRecordingOutput];
      if (output.isRecording) {
        [output stopRecording];
      } else if (self.singleRecordingStartPending) {
        self.singleRecordingStopRequested = YES;
      }
    }
  });
}

- (AVCapturePhotoOutput *)photoOutputForCurrentLayout {
  if (self.usingMultiCam) {
    return [self primaryCameraPosition] == AVCaptureDevicePositionFront ? self.frontPhotoOutput : self.backPhotoOutput;
  }
  return self.singlePhotoOutput;
}

- (AVCaptureMovieFileOutput *)movieOutputForCurrentLayout {
  if (self.usingMultiCam) {
    return nil;
  }
  return self.singleMovieOutput;
}

- (AVCaptureMovieFileOutput *)activeRecordingOutput {
  if (self.singleMovieOutput.isRecording) return self.singleMovieOutput;
  return nil;
}

#pragma mark - Layout Helpers

- (BOOL)isDualLayout:(NSString *)layout {
  return ![layout isEqualToString:@"back"] && ![layout isEqualToString:@"front"];
}

- (AVCaptureDevicePosition)primaryCameraPosition {
  return [self.currentLayout isEqualToString:@"front"] ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
}

- (UIView *)targetPreviewViewForPosition:(AVCaptureDevicePosition)position {
  return position == AVCaptureDevicePositionFront ? self.frontPreviewView : self.backPreviewView;
}

- (void)removePreviewLayers {
  [self.frontPreviewLayer removeFromSuperlayer];
  [self.backPreviewLayer removeFromSuperlayer];
  [self.singlePreviewLayer removeFromSuperlayer];
  self.frontPreviewLayer = nil;
  self.backPreviewLayer = nil;
  self.singlePreviewLayer = nil;
}

- (void)clearPreviewLayersOnMainQueue {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self removePreviewLayers];
  });
}

#pragma mark - Notifications

- (void)registerSessionNotifications:(AVCaptureSession *)session {
  [self unregisterSessionNotifications];
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:session];
  [center addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:session];
  [center addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:session];
}

- (void)unregisterSessionNotifications {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionRuntimeErrorNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionWasInterruptedNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionInterruptionEndedNotification object:nil];
}

- (void)sessionRuntimeError:(NSNotification *)notification {
  NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
  [self emitSessionError:error.localizedDescription ?: @"Camera session runtime error." code:@"session_runtime_error"];
}

- (void)sessionWasInterrupted:(NSNotification *)notification {
  NSNumber *reason = notification.userInfo[AVCaptureSessionInterruptionReasonKey];
  NSString *message = reason ? [NSString stringWithFormat:@"Camera session was interrupted. reason=%@", reason] : @"Camera session was interrupted.";
  [self emitSessionError:message code:@"session_interrupted"];
}

- (void)sessionInterruptionEnded:(NSNotification *)notification {
  [self startOnSessionQueue];
}

#pragma mark - Event Emission

- (void)emitPhotoSaved:(NSString *)uri {
  [[DualCameraEventEmitter shared] sendPhotoSaved:uri];
}

- (void)emitError:(NSString *)error {
  [[DualCameraEventEmitter shared] sendPhotoError:error];
}

- (void)emitRecordingFinished:(NSString *)uri {
  [[DualCameraEventEmitter shared] sendRecordingFinished:uri];
}

- (void)emitRecordingStarted {
  [[DualCameraEventEmitter shared] sendRecordingStarted];
}

- (void)emitRecordingError:(NSString *)error {
  [[DualCameraEventEmitter shared] sendRecordingError:error];
}

- (void)emitSessionError:(NSString *)error code:(NSString *)code {
  [[DualCameraEventEmitter shared] sendSessionError:error code:code];
}

#pragma mark - AVCapturePhotoCaptureDelegate

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
                       error:(NSError *)error {
  @try {
    if (error) {
      [self emitError:error.localizedDescription];
      return;
    }

    NSData *data = [photo fileDataRepresentation];
    if (!data) {
      [self emitError:@"Failed to get photo data"];
      return;
    }

    // Single-cam: save directly from photo data
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      @autoreleasepool {
        @try {
          NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
          NSString *filename = [NSString stringWithFormat:@"photo_%@.jpg", @((NSInteger)[[NSDate date] timeIntervalSince1970])];
          NSString *path = [documentsPath stringByAppendingPathComponent:filename];
          NSError *writeError = nil;
          [data writeToFile:path options:NSDataWritingAtomic error:&writeError];
          dispatch_async(dispatch_get_main_queue(), ^{
            if (writeError) {
              [self emitError:writeError.localizedDescription];
            } else {
              [self emitPhotoSaved:[NSString stringWithFormat:@"file://%@", path]];
            }
          });
        } @catch (NSException *exception) {
          NSLog(@"[DualCamera] captureOutput photo inner exception: %@", exception);
          dispatch_async(dispatch_get_main_queue(), ^{
            [self emitError:[NSString stringWithFormat:@"Photo save failed: %@", exception.reason ?: @"Unknown error"]];
          });
        }
      }
    });
  } @catch (NSException *exception) {
    NSLog(@"[DualCamera] captureOutput delegate outer exception: %@", exception);
    [self emitError:[NSString stringWithFormat:@"Photo capture delegate failed: %@", exception.reason ?: @"Unknown error"]];
  }
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)output
    didStartRecordingToOutputFileAtURL:(NSURL *)fileURL
                       fromConnections:(NSArray<AVCaptureConnection *> *)connections {
  self.singleRecordingStartPending = NO;
  [self emitRecordingStarted];
  if (self.singleRecordingStopRequested && output.isRecording) {
    [output stopRecording];
  }
}

- (void)captureOutput:(AVCaptureFileOutput *)output
    didFinishRecordingToOutputFileAtURL:(NSURL *)fileURL
                        fromConnections:(NSArray<AVCaptureConnection *> *)connections
                                  error:(NSError *)error {
  self.singleRecordingStartPending = NO;
  self.singleRecordingStopRequested = NO;
  if (error) {
    NSNumber *recordedSuccessfully = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey];
    if (![recordedSuccessfully boolValue]) {
      [self emitRecordingErrorForError:error
                                prefix:@"Movie file recording failed."
                               context:@"single_movie_finish"
                           rejectedPTS:kCMTimeInvalid];
      return;
    }
    NSLog(@"[DualCamera] Movie file output finished with recoverable error: %@", error);
  }

  // Single-cam fallback mode: emit directly. Multi-cam recording uses AVAssetWriter.
  [self emitRecordingFinished:fileURL.absoluteString];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
  if (output == self.audioDataOutput) {
    [self appendRealtimeAudioSampleBuffer:sampleBuffer];
    return;
  }

  CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (!pixelBuffer) return;

  CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
  if (!ciImage) return;

  BOOL isFrontOutput = (output == self.frontVideoDataOutput);
  BOOL isBackOutput = (output == self.backVideoDataOutput);
  if (!isFrontOutput && !isBackOutput) return;

  // Store raw frames (no mirror applied — WYSIWYG: save what preview shows)
  if (isFrontOutput) {
    @synchronized(self) {
      self.latestFrontFrame = ciImage;
    }
  } else {
    @synchronized(self) {
      self.latestBackFrame = ciImage;
    }
  }

  if (self.isDualRecordingActive && isBackOutput) {
    [self appendRealtimeVideoFrameAtTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer) source:@"back_clock"];
  }
}

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
