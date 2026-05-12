#import "DualCameraView+Session.h"
#import "DualCameraView_Internal.h"

static NSString *DualCameraFourCCString(OSType code) {
  char chars[5] = {
    (char)((code >> 24) & 0xff),
    (char)((code >> 16) & 0xff),
    (char)((code >> 8) & 0xff),
    (char)(code & 0xff),
    0
  };
  return [NSString stringWithFormat:@"%s/%u", chars, (unsigned int)code];
}

@implementation DualCameraView (Session)

#pragma mark - Lifecycle

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
      dispatch_async(self.realtimeRenderQueue, ^{
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

#pragma mark - Multi-cam configuration

- (void)configureAndStartMultiCamSession {
  // Choose physical back lens based on the requested zoom level at startup.
  // Ultra-wide covers user-facing zooms < 1.0x; wide-angle handles >= 1.0x.
  BOOL startWithUltraWide = (self.backZoomFactor < 1.0);
  AVCaptureDevice *backDevice = startWithUltraWide
    ? [self ultraWideCameraDevice]
    : [self cameraDeviceForPosition:AVCaptureDevicePositionBack];
  // Fall back to wide-angle if ultra-wide is absent on this device.
  if (!backDevice) {
    backDevice = [self cameraDeviceForPosition:AVCaptureDevicePositionBack];
    startWithUltraWide = NO;
  }
  self.backUsingUltraWide = startWithUltraWide;

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
  // Enable high-resolution still capture on iOS<16 so capturePhoto walks the
  // full multi-frame still pipeline (HDR/Smart-HDR + denoise) instead of
  // returning a downsampled video-buffer-grade frame.  iOS 16+ derives
  // maxPhotoDimensions automatically from the active format.
  if (@available(iOS 16.0, *)) {
    // maxPhotoDimensions is read-only on output; nothing to set here.
  } else {
    backPhotoOutput.highResolutionCaptureEnabled = YES;
    frontPhotoOutput.highResolutionCaptureEnabled = YES;
  }

  BOOL ok = YES;
  NSString *failure = nil;
  NSString *failureCode = nil;

  [self.multiCamSession beginConfiguration];

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

  // VideoDataOutput — front camera (WYSIWYG frames for compositing)
  if (ok) {
    self.frontVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSLog(@"[DualCamera][QualityDiag] front available pixel formats=%@",
          [self.frontVideoDataOutput.availableVideoPixelFormatTypes valueForKey:@"description"]);
    self.frontVideoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    NSLog(@"[DualCamera][QualityDiag] front selected pixel format=%@",
          DualCameraFourCCString(kCVPixelFormatType_32BGRA));
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

  // VideoDataOutput — back camera
  if (ok) {
    self.backVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSLog(@"[DualCamera][QualityDiag] back available pixel formats=%@",
          [self.backVideoDataOutput.availableVideoPixelFormatTypes valueForKey:@"description"]);
    self.backVideoDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    NSLog(@"[DualCamera][QualityDiag] back selected pixel format=%@",
          DualCameraFourCCString(kCVPixelFormatType_32BGRA));
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

  // AudioDataOutput
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
  NSLog(@"[DualCamera] Session config complete — realtime front=%@ back=%@ audio=%@ hardwareCost=%.3f systemPressureCost=%.3f",
        self.frontVideoDataOutput ? @"OK" : @"NIL",
        self.backVideoDataOutput ? @"OK" : @"NIL",
        self.audioDataOutput ? @"OK" : @"NIL",
        self.multiCamSession.hardwareCost,
        self.multiCamSession.systemPressureCost);
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

#pragma mark - Single-cam configuration

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

  if ([device lockForConfiguration:&error]) {
    if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
      device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    }
    if (position == AVCaptureDevicePositionBack) {
      device.videoZoomFactor = self.backZoomFactor;
    } else {
      device.videoZoomFactor = self.frontZoomFactor;
    }
    [device unlockForConfiguration];
  }

  AVCapturePhotoOutput *photoOutput = [[AVCapturePhotoOutput alloc] init];
  AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];

  [session beginConfiguration];

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

#pragma mark - Zoom

- (void)dc_setFrontZoom:(CGFloat)factor {
  self.frontZoomFactor = factor;
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
  self.backZoomFactor = factor;
  dispatch_async(self.sessionQueue, ^{
    if (self.usingMultiCam) {
      BOOL needsUltraWide = (factor < 1.0);
      if (needsUltraWide != self.backUsingUltraWide) {
        [self switchBackCameraToUltraWide:needsUltraWide];
      }
    }

    AVCaptureDevice *backDevice = self.usingMultiCam
      ? self.backDeviceInput.device
      : [self cameraDeviceForPosition:AVCaptureDevicePositionBack];
    if (!backDevice) return;

    CGFloat f = [self backDeviceZoomForUserZoom:factor];
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

// Maps a user-facing zoom level to the physical device's videoZoomFactor.
//
// Ultra-wide native FOV = 0.5x relative to wide-angle (approximately 13mm vs 26mm).
// So:  device_zoom = user_zoom / 0.5  = user_zoom * 2.0  (for ultra-wide)
//      device_zoom = user_zoom                            (for wide-angle)
//
// Examples:  user 0.5x → ultra-wide @ 1.0 (native FOV, no digital zoom)
//            user 0.7x → ultra-wide @ 1.4
//            user 1.0x → wide-angle @ 1.0
//            user 2.0x → wide-angle @ 2.0
- (CGFloat)backDeviceZoomForUserZoom:(CGFloat)userZoom {
  return self.backUsingUltraWide ? userZoom * 2.0 : userZoom;
}

// Swaps the multicam back input between ultra-wide and wide-angle without
// rebuilding the entire session.  Must be called on sessionQueue.
//
// Visual smoothing strategy: AVCaptureMultiCamSession does not support virtual
// devices (BuiltInDualWide / BuiltInTriple), so a physical lens swap is the
// only path for 0.5x ↔ 1x.  beginConfiguration / commitConfiguration disrupts
// the preview pipeline for ~100-300ms which the user perceives as a flash.
// We mask that gap by capturing a UIView snapshot of the current back preview
// frame and overlaying it over backPreviewView during the swap, then crossfade
// it out once the new physical camera produces its first frame.
- (void)switchBackCameraToUltraWide:(BOOL)useUltraWide {
  if (!self.usingMultiCam || !self.multiCamSession) return;
  if (self.backUsingUltraWide == useUltraWide) return;

  AVCaptureDevice *newDevice = useUltraWide
    ? [self ultraWideCameraDevice]
    : [self cameraDeviceForPosition:AVCaptureDevicePositionBack];
  if (!newDevice) {
    NSLog(@"[DualCamera] switchBackCamera: target lens not available — skipping");
    return;
  }

  NSError *error = nil;
  if (![self configureDeviceForMultiCam:newDevice error:&error]) {
    NSLog(@"[DualCamera] switchBackCamera: format config failed: %@", error);
    return;
  }

  AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&error];
  if (!newInput) {
    NSLog(@"[DualCamera] switchBackCamera: input creation failed: %@", error);
    return;
  }

  // Place a freeze-frame cover over backPreviewView before reconfiguring the
  // session so the user does not see a black flash mid-swap.
  __block UIView *coverView = nil;
  dispatch_sync(dispatch_get_main_queue(), ^{
    UIView *snap = [self.backPreviewView snapshotViewAfterScreenUpdates:NO];
    if (!snap) return;
    snap.frame = self.backPreviewView.bounds;
    snap.userInteractionEnabled = NO;
    [self.backPreviewView addSubview:snap];
    coverView = snap;
  });

  [self.multiCamSession beginConfiguration];

  if (self.backDeviceInput) {
    [self.multiCamSession removeInput:self.backDeviceInput];
  }

  if (![self.multiCamSession canAddInput:newInput]) {
    [self.multiCamSession commitConfiguration];
    [self removePreviewCover:coverView];
    NSLog(@"[DualCamera] switchBackCamera: session rejected new input");
    return;
  }
  [self.multiCamSession addInputWithNoConnections:newInput];

  AVCaptureInputPort *newVideoPort = [self videoPortForInput:newInput];
  if (!newVideoPort) {
    [self.multiCamSession commitConfiguration];
    [self removePreviewCover:coverView];
    NSLog(@"[DualCamera] switchBackCamera: no video port on new input");
    return;
  }

  // Reconnect back preview layer.
  if (self.backPreviewLayer) {
    AVCaptureConnection *c = [[AVCaptureConnection alloc]
      initWithInputPort:newVideoPort videoPreviewLayer:self.backPreviewLayer];
    if ([self.multiCamSession canAddConnection:c]) {
      [self.multiCamSession addConnection:c];
      if (c.isVideoOrientationSupported) {
        c.videoOrientation = [self currentCaptureVideoOrientation];
      }
      if (self.backPreviewMirrored && c.isVideoMirroringSupported) {
        c.automaticallyAdjustsVideoMirroring = NO;
        c.videoMirrored = YES;
      }
    }
  }

  // Reconnect back photo output.
  if (self.backPhotoOutput) {
    AVCaptureConnection *c = [[AVCaptureConnection alloc]
      initWithInputPorts:@[newVideoPort] output:self.backPhotoOutput];
    if ([self.multiCamSession canAddConnection:c]) {
      [self.multiCamSession addConnection:c];
      if (c.isVideoOrientationSupported) {
        c.videoOrientation = [self currentCaptureVideoOrientation];
      }
    }
  }

  // Reconnect back video data output.
  if (self.backVideoDataOutput) {
    AVCaptureConnection *c = [[AVCaptureConnection alloc]
      initWithInputPorts:@[newVideoPort] output:self.backVideoDataOutput];
    [self applyOrientation:[self currentCaptureVideoOrientation]
                  mirrored:self.backOutputMirrored
              toConnection:c];
    if ([self.multiCamSession canAddConnection:c]) {
      [self.multiCamSession addConnection:c];
    }
  }

  [self.multiCamSession commitConfiguration];

  self.backDeviceInput = newInput;
  self.backUsingUltraWide = useUltraWide;
  NSLog(@"[DualCamera] switchBackCamera: now using %@", useUltraWide ? @"ultra-wide" : @"wide-angle");

  // Crossfade the freeze-frame out.  The 120ms delay gives the new physical
  // lens enough time to deliver its first preview frame after commit; the
  // 200ms fade hides any remaining hardware ramp (AE/AWB convergence).
  if (coverView) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [UIView animateWithDuration:0.20
                            delay:0.12
                          options:UIViewAnimationOptionCurveEaseOut
                       animations:^{
        coverView.alpha = 0.0;
      } completion:^(BOOL finished) {
        [coverView removeFromSuperview];
      }];
    });
  }
}

- (void)removePreviewCover:(UIView *)coverView {
  if (!coverView) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    [coverView removeFromSuperview];
  });
}

#pragma mark - Device / format helpers

- (AVCaptureDevice *)cameraDeviceForPosition:(AVCaptureDevicePosition)position {
  AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
    discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
    mediaType:AVMediaTypeVideo
    position:position];
  return discovery.devices.firstObject;
}

- (AVCaptureDevice *)ultraWideCameraDevice {
  AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
    discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInUltraWideCamera]
    mediaType:AVMediaTypeVideo
    position:AVCaptureDevicePositionBack];
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
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    NSDictionary *extensions = (__bridge NSDictionary *)CMFormatDescriptionGetExtensions(format.formatDescription);
    NSLog(@"[DualCamera] Selected multicam format position=%ld dimensions=%dx%d",
          (long)device.position, dimensions.width, dimensions.height);
    NSLog(@"[DualCamera][QualityDiag] activeFormat position=%ld mediaSubType=%@ extensions=%@",
          (long)device.position,
          DualCameraFourCCString(CMFormatDescriptionGetMediaSubType(format.formatDescription)),
          extensions ?: @{});
  }
  device.activeVideoMinFrameDuration = CMTimeMake(1, 30);
  device.activeVideoMaxFrameDuration = CMTimeMake(1, 30);

  CGFloat userZoom = (device.position == AVCaptureDevicePositionBack) ? self.backZoomFactor : self.frontZoomFactor;
  CGFloat zoomFactor = (device.position == AVCaptureDevicePositionBack)
    ? [self backDeviceZoomForUserZoom:userZoom]
    : userZoom;
  CGFloat clampedZoom = zoomFactor;
  if (clampedZoom < device.minAvailableVideoZoomFactor) {
    clampedZoom = device.minAvailableVideoZoomFactor;
  } else if (clampedZoom > device.maxAvailableVideoZoomFactor) {
    clampedZoom = device.maxAvailableVideoZoomFactor;
  }
  device.videoZoomFactor = clampedZoom;

  if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
    device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
  }
  [device unlockForConfiguration];
  return YES;
}

- (AVCaptureDeviceFormat *)bestMultiCamFormatForDevice:(AVCaptureDevice *)device {
  AVCaptureDeviceFormat *bestFormat = nil;
  int32_t bestArea = 0;
  NSInteger bestTier = -1;

  for (AVCaptureDeviceFormat *format in device.formats) {
    if (![format isMultiCamSupported] || ![self formatSupportsThirtyFps:format]) {
      continue;
    }

    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    int32_t area = dimensions.width * dimensions.height;
    int32_t longEdge = MAX(dimensions.width, dimensions.height);
    int32_t shortEdge = MIN(dimensions.width, dimensions.height);
    NSInteger tier = 0;
    if (longEdge <= 1920 && shortEdge <= 1440) {
      tier = 2;
    } else if (longEdge <= 2560 && shortEdge <= 1440) {
      tier = 1;
    }

    if (!bestFormat ||
        tier > bestTier ||
        (tier == bestTier && area > bestArea)) {
      bestFormat = format;
      bestArea = area;
      bestTier = tier;
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

#pragma mark - Session notifications

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
  NSNumber *reasonNumber = notification.userInfo[AVCaptureSessionInterruptionReasonKey];
  AVCaptureSessionInterruptionReason reason = (AVCaptureSessionInterruptionReason)reasonNumber.integerValue;

  // Background / multitasking interruptions are normal OS behaviour — mark as not
  // running so resumeIfNeeded can restart the session when the app returns, but do
  // NOT surface an error to the user.
  if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground ||
      reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps) {
    NSLog(@"[DualCamera] Session interrupted (reason=%ld), will resume on foreground.", (long)reason);
    self.isRunning = NO;
    return;
  }

  NSString *message = reasonNumber
    ? [NSString stringWithFormat:@"Camera session was interrupted. reason=%@", reasonNumber]
    : @"Camera session was interrupted.";
  [self emitSessionError:message code:@"session_interrupted"];
}

- (void)sessionInterruptionEnded:(NSNotification *)notification {
  // isRunning was cleared in sessionWasInterrupted for background-type interruptions,
  // so resumeIfNeeded will call startRunning and bring the session back.
  [self startOnSessionQueue];
}

#pragma mark - Event emission

- (void)emitSessionError:(NSString *)error code:(NSString *)code {
  [[DualCameraEventEmitter shared] sendSessionError:error code:code];
}

@end
