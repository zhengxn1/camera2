#import "DualCameraView+Capture.h"
#import "DualCameraView_Internal.h"

@implementation DualCameraView (Capture)

#pragma mark - Entry points

- (void)internalTakePhoto {
  __block CGSize canvasSizeForPhoto;
  dispatch_sync(dispatch_get_main_queue(), ^{
    canvasSizeForPhoto = self.bounds.size;
  });

  dispatch_async(self.sessionQueue, ^{
    @autoreleasepool {
      if (!self.isConfigured) return;

      if (self.usingMultiCam && [self isDualLayout:self.currentLayout]) {
        [self triggerMulticamDualPhotoCaptureWithCanvasSize:canvasSizeForPhoto];
      } else {
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

#pragma mark - Multicam dual-photo capture

// Triggers both front and back AVCapturePhotoOutputs in parallel.  Each
// callback lands in captureOutput:didFinishProcessingPhoto: which routes to
// handleDualPhotoOutput:photo:error:.  When both photos arrive, composite +
// save runs on a background queue.
- (void)triggerMulticamDualPhotoCaptureWithCanvasSize:(CGSize)canvasSize {
  if (self.pendingPhotoCaptureInFlight) {
    NSLog(@"[DualCamera] triggerMulticamDualPhotoCapture — capture already in flight, ignoring");
    return;
  }
  if (!self.frontPhotoOutput || !self.backPhotoOutput) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitError:@"Photo outputs not configured"];
    });
    return;
  }

  CGFloat refW = MIN(canvasSize.width, canvasSize.height) * 3.0;
  DualCameraDeviceOrientation photoOrientation = self.deviceOrientation;
  CGSize saveCanvas = [self outputSizeForAspectRatio:self.saveAspectRatio ?: @"9:16"
                                       referenceWidth:refW
                                            landscape:[self isDeviceOrientationLandscape:photoOrientation]];
  DualCameraLayoutState *photoState = [self layoutStateSnapshotForCanvasSize:canvasSize
                                                                  outputSize:saveCanvas
                                                                 orientation:photoOrientation];

  self.pendingPhotoFrontImage = nil;
  self.pendingPhotoBackImage = nil;
  self.pendingPhotoFrontReceived = NO;
  self.pendingPhotoBackReceived = NO;
  self.pendingPhotoFrontOrientation = kCGImagePropertyOrientationUp;
  self.pendingPhotoBackOrientation = kCGImagePropertyOrientationUp;
  self.pendingPhotoCanvasSize = saveCanvas;
  self.pendingPhotoLayoutState = photoState;
  self.pendingPhotoCaptureInFlight = YES;

  AVCapturePhotoSettings *backSettings = [AVCapturePhotoSettings photoSettings];
  backSettings.flashMode = AVCaptureFlashModeOff;
  [self applyHighQualityPhotoSettings:backSettings forOutput:self.backPhotoOutput];

  AVCapturePhotoSettings *frontSettings = [AVCapturePhotoSettings photoSettings];
  frontSettings.flashMode = AVCaptureFlashModeOff;
  [self applyHighQualityPhotoSettings:frontSettings forOutput:self.frontPhotoOutput];

  NSLog(@"[DualCamera] triggerMulticamDualPhotoCapture — orientation=%ld saveCanvas=%@",
        (long)photoOrientation, NSStringFromCGSize(saveCanvas));

  @try {
    [self.backPhotoOutput capturePhotoWithSettings:backSettings delegate:self];
    [self.frontPhotoOutput capturePhotoWithSettings:frontSettings delegate:self];
  } @catch (NSException *exception) {
    self.pendingPhotoCaptureInFlight = NO;
    NSLog(@"[DualCamera] dual-photo capture exception: %@", exception);
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitError:[NSString stringWithFormat:@"Photo capture failed: %@", exception.reason ?: @"Unknown error"]];
    });
  }
}

- (void)handleDualPhotoOutput:(AVCaptureOutput *)output
                         photo:(AVCapturePhoto *)photo
                         error:(NSError *)error {
  BOOL isFront = (output == self.frontPhotoOutput);
  BOOL isBack = (output == self.backPhotoOutput);
  if (!isFront && !isBack) return;

  if (error) {
    self.pendingPhotoCaptureInFlight = NO;
    [self resetPendingDualPhotoState];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitError:error.localizedDescription ?: @"Dual photo capture failed"];
    });
    return;
  }

  CIImage *image = [self ciImageFromCapturedPhoto:photo];
  if (!image) {
    self.pendingPhotoCaptureInFlight = NO;
    [self resetPendingDualPhotoState];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitError:@"Failed to decode captured photo"];
    });
    return;
  }

  AVCaptureDevicePosition position = isFront ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
  CGImagePropertyOrientation exifOrientation = [self exifOrientationFromCapturedPhoto:photo
                                                                              position:position];

  if (isFront) {
    self.pendingPhotoFrontImage = image;
    self.pendingPhotoFrontOrientation = exifOrientation;
    self.pendingPhotoFrontReceived = YES;
  } else {
    self.pendingPhotoBackImage = image;
    self.pendingPhotoBackOrientation = exifOrientation;
    self.pendingPhotoBackReceived = YES;
  }

  NSLog(@"[DualCamera] handleDualPhotoOutput — %@ received (size=%@ exif=%u). frontReady=%d backReady=%d",
        isFront ? @"front" : @"back",
        NSStringFromCGSize(image.extent.size), (unsigned)exifOrientation,
        self.pendingPhotoFrontReceived, self.pendingPhotoBackReceived);

  if (self.pendingPhotoFrontReceived && self.pendingPhotoBackReceived) {
    [self compositeAndSavePendingDualPhoto];
  }
}

- (CIImage *)ciImageFromCapturedPhoto:(AVCapturePhoto *)photo {
  CVPixelBufferRef pixelBuffer = photo.pixelBuffer;
  if (pixelBuffer) {
    CGColorSpaceRef cs = CVImageBufferGetColorSpace(pixelBuffer);
    if (cs) {
      return [CIImage imageWithCVPixelBuffer:pixelBuffer
                                     options:@{(id)kCIImageColorSpace: (__bridge id)cs}];
    }
    return [CIImage imageWithCVPixelBuffer:pixelBuffer];
  }
  // Fallback: decode JPEG/HEIC representation.
  NSData *data = [photo fileDataRepresentation];
  if (!data) return nil;
  return [CIImage imageWithData:data];
}

- (CGImagePropertyOrientation)exifOrientationFromCapturedPhoto:(AVCapturePhoto *)photo
                                                       position:(AVCaptureDevicePosition)position {
  // AVCapturePhoto.metadata mirrors the CGImage TIFF dictionary; the top-level
  // kCGImagePropertyOrientation is the authoritative orientation that should
  // be applied to make the image upright.  When the AVCaptureConnection had
  // videoOrientation set, this is usually kCGImagePropertyOrientationUp (the
  // photo is already pre-rotated); otherwise it carries the sensor-native
  // EXIF tag and tells us exactly how to rotate.
  NSNumber *orientationNumber = photo.metadata[(NSString *)kCGImagePropertyOrientation];
  if (orientationNumber) {
    return (CGImagePropertyOrientation)orientationNumber.unsignedIntValue;
  }
  return [self exifOrientationForCameraPosition:position
                              deviceOrientation:self.deviceOrientation];
}

- (void)compositeAndSavePendingDualPhoto {
  CIImage *frontRaw = self.pendingPhotoFrontImage;
  CIImage *backRaw = self.pendingPhotoBackImage;
  CGImagePropertyOrientation frontExif = self.pendingPhotoFrontOrientation;
  CGImagePropertyOrientation backExif = self.pendingPhotoBackOrientation;
  CGSize saveCanvas = self.pendingPhotoCanvasSize;
  DualCameraLayoutState *photoState = self.pendingPhotoLayoutState;

  [self resetPendingDualPhotoState];

  if (!frontRaw || !backRaw || !photoState) {
    self.pendingPhotoCaptureInFlight = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitError:@"Dual photo capture state lost"];
    });
    return;
  }

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    @autoreleasepool {
      CIImage *frontUpright = [self imageByApplyingExifOrientation:frontExif toImage:frontRaw];
      CIImage *backUpright = [self imageByApplyingExifOrientation:backExif toImage:backRaw];

      // The mirroring flags inside the layout state reflect *output* mirroring
      // for video data outputs.  AVCapturePhotoOutput doesn't pre-mirror, so
      // for the photo path we treat both cameras as non-mirrored except where
      // the user explicitly opts into a mirrored selfie via frontOutputMirrored.
      photoState.frontMirrored = self.frontOutputMirrored;
      photoState.backMirrored = self.backOutputMirrored;

      CIImage *composited = [self compositedImageForLayoutState:photoState
                                                          front:frontUpright
                                                           back:backUpright
                                                    highQuality:YES];
      NSLog(@"[DualCamera] compositeAndSavePendingDualPhoto — composited=%@ (expect %.0fx%.0f)",
            NSStringFromCGRect(composited.extent), saveCanvas.width, saveCanvas.height);

      NSString *path = [self saveCIImageAsJPEG:composited];
      self.pendingPhotoCaptureInFlight = NO;
      dispatch_async(dispatch_get_main_queue(), ^{
        if (path) {
          [self emitPhotoSaved:[NSString stringWithFormat:@"file://%@", path]];
        } else {
          [self emitError:@"Failed to save photo"];
        }
      });
    }
  });
}

- (void)applyHighQualityPhotoSettings:(AVCapturePhotoSettings *)settings
                             forOutput:(AVCapturePhotoOutput *)output {
  if (!settings || !output) return;

  // iOS 16+: prioritize quality over speed and use the output's max dimensions.
  if (@available(iOS 16.0, *)) {
    settings.photoQualityPrioritization = AVCapturePhotoQualityPrioritizationQuality;
    if (settings.maxPhotoDimensions.width == 0 && settings.maxPhotoDimensions.height == 0) {
      settings.maxPhotoDimensions = output.maxPhotoDimensions;
    }
  } else if (@available(iOS 13.0, *)) {
    settings.photoQualityPrioritization = AVCapturePhotoQualityPrioritizationQuality;
  }

  // iOS < 16 high-resolution flag (deprecated in 16+, ignored without warning).
  if (@available(iOS 16.0, *)) {
    // no-op: maxPhotoDimensions covers it
  } else {
    if (output.isHighResolutionCaptureEnabled) {
      settings.highResolutionPhotoEnabled = YES;
    }
  }
}

- (void)resetPendingDualPhotoState {
  self.pendingPhotoFrontImage = nil;
  self.pendingPhotoBackImage = nil;
  self.pendingPhotoFrontReceived = NO;
  self.pendingPhotoBackReceived = NO;
  self.pendingPhotoLayoutState = nil;
  self.pendingPhotoCanvasSize = CGSizeZero;
}

- (void)internalStartRecording {
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

#pragma mark - Output selectors

- (BOOL)isUsingMultiCamDualLayout {
  return self.usingMultiCam && [self isDualLayout:self.currentLayout];
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

#pragma mark - AVCapturePhotoCaptureDelegate

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
                       error:(NSError *)error {
  @try {
    // Multicam dual-photo path: route to the dual capture handler.  This runs
    // when triggerMulticamDualPhotoCaptureWithCanvasSize: kicked off a parallel
    // front+back capture; both photos are buffered and composited on arrival.
    if (self.pendingPhotoCaptureInFlight &&
        (output == self.frontPhotoOutput || output == self.backPhotoOutput)) {
      [self handleDualPhotoOutput:output photo:photo error:error];
      return;
    }

    if (error) {
      [self emitError:error.localizedDescription];
      return;
    }

    NSData *data = [photo fileDataRepresentation];
    if (!data) {
      [self emitError:@"Failed to get photo data"];
      return;
    }

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

  [self emitRecordingFinished:fileURL.absoluteString];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate / AVCaptureAudioDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
  if (output == self.audioDataOutput) {
    [self appendRealtimeAudioSampleBuffer:sampleBuffer];
    return;
  }

  CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (!pixelBuffer) return;

  // Preserve the pixel buffer's embedded colour space so Core Image does not
  // misinterpret gamma-encoded sRGB/P3 data as linear light (which causes
  // overexposed / washed-out output when compositing and saving).
  CGColorSpaceRef bufferCS = CVImageBufferGetColorSpace(pixelBuffer);
  CIImage *ciImage;
  if (bufferCS) {
    ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer
                                      options:@{(id)kCIImageColorSpace: (__bridge id)bufferCS}];
  } else {
    ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
  }
  if (!ciImage) return;

  BOOL isFrontOutput = (output == self.frontVideoDataOutput);
  BOOL isBackOutput = (output == self.backVideoDataOutput);
  if (!isFrontOutput && !isBackOutput) return;

  // Store raw frames (WYSIWYG: save what preview shows — mirroring applied at compositing time)
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

#pragma mark - Event emission

- (void)emitPhotoSaved:(NSString *)uri {
  [[DualCameraEventEmitter shared] sendPhotoSaved:uri];
}

- (void)emitError:(NSString *)error {
  [[DualCameraEventEmitter shared] sendPhotoError:error];
}

@end
