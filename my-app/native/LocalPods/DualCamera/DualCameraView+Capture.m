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
        // Single-cam: use AVCapturePhotoOutput for full resolution
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
