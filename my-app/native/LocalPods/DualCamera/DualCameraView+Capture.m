#import "DualCameraView+Capture.h"
#import "DualCameraView_Internal.h"

static NSString *DualCameraCaptureFourCCString(OSType code) {
  char chars[5] = {
    (char)((code >> 24) & 0xff),
    (char)((code >> 16) & 0xff),
    (char)((code >> 8) & 0xff),
    (char)(code & 0xff),
    0
  };
  return [NSString stringWithFormat:@"%s/%u", chars, (unsigned int)code];
}

static id DualCameraBufferAttachment(CVBufferRef buffer, CFStringRef key) {
  if (!buffer || !key) return nil;
  return (__bridge id)CVBufferGetAttachment(buffer, key, NULL);
}

@implementation DualCameraView (Capture)

- (CGSize)limitedBeautyPreviewSizeForRawFrame:(CIImage *)rawFrame preferredSize:(CGSize)preferredSize {
  CGSize rawSize = rawFrame.extent.size;
  if (rawSize.width <= 1 || rawSize.height <= 1) return CGSizeZero;

  CGFloat width = preferredSize.width > 1 ? preferredSize.width : rawSize.width;
  CGFloat height = preferredSize.height > 1 ? preferredSize.height : rawSize.height;
  CGFloat maxEdge = MAX(width, height);
  CGFloat limit = 720.0;
  if (maxEdge > limit) {
    CGFloat scale = limit / maxEdge;
    width *= scale;
    height *= scale;
  }
  width = MAX(2.0, floor(width));
  height = MAX(2.0, floor(height));
  return CGSizeMake(width, height);
}

- (void)finishFrontBeautyProcessingPass {
  BOOL needsAnother = NO;
  @synchronized(self) {
    needsAnother = self.beautyProcessingNeedsAnotherFrame;
    self.beautyProcessingInFlight = NO;
    self.beautyProcessingNeedsAnotherFrame = NO;
  }
  if (needsAnother) {
    [self scheduleFrontBeautyProcessingIfNeeded];
  }
}

- (void)scheduleFrontBeautyProcessingIfNeeded {
  if (!self.frontBeautyEnabled || !self.beautyProcessingQueue) return;

  CIImage *rawFrame = nil;
  CGSize targetSize = CGSizeZero;
  NSInteger previewGeneration = -1;
  NSString *previewLayout = nil;
  BOOL previewMirrored = NO;
  BOOL shouldProcessFullFrame = NO;
  @synchronized(self) {
    if (self.beautyProcessingInFlight) {
      self.beautyProcessingNeedsAnotherFrame = YES;
      return;
    }
    rawFrame = self.latestRawFrontFrame;
    targetSize = self.beautyPreviewTargetSize;
    previewGeneration = self.beautyLayoutGeneration;
    previewLayout = [self.currentLayout copy] ?: @"back";
    previewMirrored = self.frontPreviewMirrored;
    shouldProcessFullFrame = self.isDualRecordingActive;
    if (!rawFrame) return;
    self.beautyProcessingInFlight = YES;
    self.beautyProcessingNeedsAnotherFrame = NO;
  }

  dispatch_async(self.beautyProcessingQueue, ^{
    @autoreleasepool {
      CGSize previewSize = [self limitedBeautyPreviewSizeForRawFrame:rawFrame preferredSize:targetSize];
      CIImage *previewFrame = nil;
      if (previewSize.width > 1 && previewSize.height > 1) {
        CGRect previewRect = CGRectMake(0, 0, previewSize.width, previewSize.height);
        CIImage *preparedPreview = [self preparedCameraImage:rawFrame
                                                  targetRect:previewRect
                                                  canvasSize:previewSize
                                                    mirrored:previewMirrored
                                                 highQuality:NO];
        previewFrame = [self beautifiedFrontImage:preparedPreview ?: rawFrame] ?: preparedPreview;
      }

      CIImage *fullFrame = shouldProcessFullFrame ? ([self beautifiedFrontImage:rawFrame] ?: rawFrame) : nil;
      BOOL canPublishPreviewFrame = NO;
      NSString *dropReason = nil;
      @synchronized(self) {
        BOOL generationMatches = self.beautyLayoutGeneration == previewGeneration;
        NSString *currentLayout = self.currentLayout ?: @"back";
        NSString *capturedLayout = previewLayout ?: @"back";
        BOOL layoutMatches = [currentLayout isEqualToString:capturedLayout];
        BOOL targetMatches = fabs(self.beautyPreviewTargetSize.width - targetSize.width) <= 2.0 &&
                             fabs(self.beautyPreviewTargetSize.height - targetSize.height) <= 2.0;
        BOOL mirrorMatches = self.frontPreviewMirrored == previewMirrored;
        canPublishPreviewFrame = previewFrame && generationMatches && layoutMatches && targetMatches && mirrorMatches;
        if (previewFrame) {
          if (canPublishPreviewFrame) {
            self.latestBeautyPreviewFrame = previewFrame;
            self.latestBeautyPreviewGeneration = previewGeneration;
            self.latestBeautyPreviewLayoutMode = previewLayout;
            self.latestBeautyPreviewTargetSize = targetSize;
            self.latestBeautyPreviewMirrored = previewMirrored;
          } else if (!generationMatches) {
            dropReason = @"staleGeneration";
          } else if (!layoutMatches) {
            dropReason = @"layoutMismatch";
          } else if (!targetMatches) {
            dropReason = @"targetMismatch";
          } else if (!mirrorMatches) {
            dropReason = @"mirrorMismatch";
          } else {
            dropReason = @"emptyFrame";
          }
        }
        if (fullFrame) {
          self.latestFrontFrame = fullFrame;
        } else if (!self.latestFrontFrame) {
          self.latestFrontFrame = rawFrame;
        }
      }
      if (dropReason) {
        NSLog(@"[BeautyProbe][PreviewVersion] dropReason=%@ capturedGen=%ld currentGen=%ld capturedLayout=%@ currentLayout=%@ capturedTarget=%@ currentTarget=%@",
              dropReason,
              (long)previewGeneration,
              (long)self.beautyLayoutGeneration,
              previewLayout ?: @"nil",
              self.currentLayout ?: @"nil",
              NSStringFromCGSize(targetSize),
              NSStringFromCGSize(self.beautyPreviewTargetSize));
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        [self updateBeautyPreviewVisibility];
        [self renderBeautyPreviewIfNeeded];
      });
      [self finishFrontBeautyProcessingPass];
    }
  });
}

#pragma mark - Entry points

- (void)internalTakePhoto {
  __block CGSize canvasSizeForPhoto;
  dispatch_sync(dispatch_get_main_queue(), ^{
    canvasSizeForPhoto = self.bounds.size;
  });

  dispatch_async(self.sessionQueue, ^{
    @autoreleasepool {
      if (!self.isConfigured) return;

      BOOL useWysiwygFrames = self.usingMultiCam &&
        ([self isDualLayout:self.currentLayout] ||
         ([self.currentLayout isEqualToString:@"front"] && self.frontBeautyEnabled));
      if (useWysiwygFrames) {
        [self captureWysiwygDualPhotoWithCanvasSize:canvasSizeForPhoto];
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
          [self applyHighQualityPhotoSettings:settings forOutput:output];
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

#pragma mark - Multicam WYSIWYG photo capture

// Saves the same composited camera frames used by realtime recording. This keeps
// stills aligned with preview/recording and avoids MultiCam PhotoOutput races.
- (void)captureWysiwygDualPhotoWithCanvasSize:(CGSize)canvasSize {
	  CIImage *frontFrame = nil;
	  CIImage *rawFrontFrame = nil;
	  CIImage *backFrame = nil;
	  @synchronized(self) {
	    rawFrontFrame = self.latestRawFrontFrame;
	    frontFrame = self.latestFrontFrame;
	    backFrame = self.latestBackFrame;
	  }
	  if (self.frontBeautyEnabled && rawFrontFrame) {
	    frontFrame = [self beautifiedFrontImage:rawFrontFrame] ?: rawFrontFrame;
	  }

  BOOL isDual = [self isDualLayout:self.currentLayout];
  BOOL needsFront = isDual || [self.currentLayout isEqualToString:@"front"];
  BOOL needsBack = isDual || [self.currentLayout isEqualToString:@"back"];

  if ((needsFront && !frontFrame) || (needsBack && !backFrame)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitError:@"Camera not ready, please try again"];
    });
    return;
  }

  DualCameraDeviceOrientation photoOrientation = self.deviceOrientation;
  CGSize saveCanvas = [self photoOutputSizeForAspectRatio:self.saveAspectRatio ?: @"9:16"
                                                    front:frontFrame
                                                     back:backFrame
                                                landscape:[self isDeviceOrientationLandscape:photoOrientation]];
  DualCameraLayoutState *photoState = [self layoutStateSnapshotForCanvasSize:canvasSize
                                                                  outputSize:saveCanvas
                                                                 orientation:photoOrientation];
  if ([self isDualLayout:self.currentLayout]) {
    // Dual stills are composited from VideoDataOutput frames, so mirror them
    // like the visible preview.
    photoState.frontMirrored = self.frontPreviewMirrored;
    photoState.backMirrored = self.backPreviewMirrored;
  } else {
    photoState.frontMirrored = self.frontOutputMirrored;
    photoState.backMirrored = self.backOutputMirrored;
  }

  dispatch_async(self.realtimeRenderQueue, ^{
    @autoreleasepool {
      CIImage *composited = [self compositedImageForLayoutState:photoState
                                                          front:frontFrame
                                                           back:backFrame
                                                    highQuality:YES];
      NSString *path = [self saveCIImageAsJPEG:composited prefix:@"dual_composited_"];
      BOOL saveSeparatePhotos = [self.videoSaveMode isEqualToString:@"all3"] &&
                                self.usingMultiCam &&
                                [self isDualLayout:self.currentLayout];
      NSString *frontPath = nil;
      NSString *backPath = nil;
      if (saveSeparatePhotos) {
        frontPath = [self saveSeparateCameraPhotoImage:frontFrame
                                              mirrored:self.frontPreviewMirrored
                                                prefix:@"dual_front_"];
        backPath = [self saveSeparateCameraPhotoImage:backFrame
                                             mirrored:self.backOutputMirrored
                                               prefix:@"dual_back_"];
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        if (path && (!saveSeparatePhotos || (frontPath && backPath))) {
          NSString *combinedURI = [NSString stringWithFormat:@"file://%@", path];
          if (saveSeparatePhotos) {
            NSMutableDictionary *uris = [@{@"combined": combinedURI} mutableCopy];
            uris[@"front"] = [NSString stringWithFormat:@"file://%@", frontPath];
            uris[@"back"] = [NSString stringWithFormat:@"file://%@", backPath];
            [self emitPhotoSaved:combinedURI uris:uris];
          } else {
            [self emitPhotoSaved:combinedURI];
          }
        } else {
          [self emitError:@"Failed to save photo"];
        }
      });
    }
  });
}

- (NSString *)saveSeparateCameraPhotoImage:(CIImage *)image
                                  mirrored:(BOOL)mirrored
                                    prefix:(NSString *)prefix {
  if (!image) return nil;

  CGFloat width = floor(image.extent.size.width);
  CGFloat height = floor(image.extent.size.height);
  if (width <= 0 || height <= 0) return nil;

  CGSize outputSize = CGSizeMake(width, height);
  CGRect fullRect = CGRectMake(0, 0, outputSize.width, outputSize.height);
  CIImage *prepared = [self preparedCameraImage:image
                                    targetRect:fullRect
                                    canvasSize:outputSize
                                      mirrored:mirrored
                                   highQuality:YES];
  return [self saveCIImageAsJPEG:prepared prefix:prefix];
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
	    __block BOOL hasBothFrames = NO;
	    @synchronized(self) {
	      hasBothFrames = (self.latestFrontFrame || self.latestRawFrontFrame) && self.latestBackFrame;
	    }
      if (!hasBothFrames) {
        self.pendingStartRecordingAfterWarmup = YES;
        self.pendingStartRecordingCanvasSize = canvasSizeForRecording;
        NSLog(@"[DualCamera] Deferring first recording start until both camera frames are ready.");
        return;
      }
      [self prepareRealtimeRecordingPipelineForCanvasSize:canvasSizeForRecording];
      dispatch_async(self.realtimeRenderQueue, ^{
        dispatch_async(self.sessionQueue, ^{
          [self startRealtimeRecordingWithCanvasSize:canvasSizeForRecording];
        });
      });
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
      dispatch_async(self.realtimeRenderQueue, ^{
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

	  static BOOL didLogFrontSample = NO;
	  static BOOL didLogBackSample = NO;
	  static NSInteger beautyProbeFrontSampleCount = 0;
	  static CFTimeInterval beautyProbeLastFrontSampleAt = 0;
	  static CFTimeInterval beautyProbeLastFrontLogAt = 0;
	  BOOL shouldLogSample = (isFrontOutput && !didLogFrontSample) || (isBackOutput && !didLogBackSample);
  if (shouldLogSample) {
    if (isFrontOutput) didLogFrontSample = YES;
    if (isBackOutput) didLogBackSample = YES;

    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    NSDictionary *formatExtensions = formatDescription
      ? (__bridge NSDictionary *)CMFormatDescriptionGetExtensions(formatDescription)
      : nil;
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    id colorPrimaries = DualCameraBufferAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey);
    id transferFunction = DualCameraBufferAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey);
    id ycbcrMatrix = DualCameraBufferAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey);
    id cgColorSpace = DualCameraBufferAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey);
    NSLog(@"[DualCamera][QualityDiag] %@ sample pixelFormat=%@ size=%zux%zu bufferCS=%@ primaries=%@ transfer=%@ matrix=%@ formatExtensions=%@",
          isFrontOutput ? @"front" : @"back",
          DualCameraCaptureFourCCString(pixelFormat),
          width,
          height,
          cgColorSpace ?: @"nil",
          colorPrimaries ?: @"nil",
          transferFunction ?: @"nil",
          ycbcrMatrix ?: @"nil",
          formatExtensions ?: @{});
  }

	  // Store the same front frame that preview, photo, and realtime recording use.
	  // Mirroring is still applied at composition time so the preview and saved
	  // media share one camera-frame source.
	  if (isFrontOutput) {
	    beautyProbeFrontSampleCount += 1;
	    CFTimeInterval frontSampleNow = CACurrentMediaTime();
	    CFTimeInterval frontSampleGapMs = beautyProbeLastFrontSampleAt > 0
	      ? (frontSampleNow - beautyProbeLastFrontSampleAt) * 1000.0
	      : 0.0;
	    beautyProbeLastFrontSampleAt = frontSampleNow;
	    BOOL shouldLogFrontProbe = beautyProbeFrontSampleCount == 1 ||
	                               beautyProbeFrontSampleCount % 60 == 0 ||
	                               frontSampleGapMs > 120.0 ||
	                               frontSampleNow - beautyProbeLastFrontLogAt > 2.0;
	    if (shouldLogFrontProbe) {
	      beautyProbeLastFrontLogAt = frontSampleNow;
	      NSLog(@"[BeautyProbe][Sample] front count=%ld gapMs=%.2f enabled=%d layout=%@ usingMultiCam=%d latestFront=%d extent=%@ scheduled=%d",
	            (long)beautyProbeFrontSampleCount,
	            frontSampleGapMs,
	            self.frontBeautyEnabled,
	            self.currentLayout ?: @"nil",
	            self.usingMultiCam,
	            self.latestFrontFrame != nil,
	            NSStringFromCGRect(ciImage.extent),
	            self.beautyPreviewFrameScheduled);
	    }
	    if (frontSampleGapMs > 120.0) {
	      NSLog(@"[BeautyProbe][FrameGap] front gapMs=%.2f count=%ld layout=%@ enabled=%d usingMultiCam=%d",
	            frontSampleGapMs,
	            (long)beautyProbeFrontSampleCount,
	            self.currentLayout ?: @"nil",
	            self.frontBeautyEnabled,
	            self.usingMultiCam);
	    }
	    @synchronized(self) {
	      self.latestRawFrontFrame = ciImage;
	      if (!self.frontBeautyEnabled) {
	        self.latestFrontFrame = ciImage;
	        self.latestBeautyPreviewFrame = nil;
	        self.latestBeautyPreviewGeneration = -1;
	        self.latestBeautyPreviewLayoutMode = nil;
	        self.latestBeautyPreviewTargetSize = CGSizeZero;
	      }
	    }
	    [self scheduleFrontBeautyProcessingIfNeeded];
  } else {
    @synchronized(self) {
      self.latestBackFrame = ciImage;
    }
  }

  if (isFrontOutput) {
    if (!self.beautyPreviewFrameScheduled) {
      self.beautyPreviewFrameScheduled = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        self.beautyPreviewFrameScheduled = NO;
        [self updateBeautyPreviewVisibility];
        [self renderBeautyPreviewIfNeeded];
      });
    }
  }

  if (self.usingMultiCam && !self.isDualRecordingActive &&
      self.realtimeRecordingState == DualCameraRealtimeRecordingStateIdle &&
      !self.realtimePipelineWarmed && !self.realtimePipelineWarmupInProgress) {
	    __block BOOL hasBothFrames = NO;
	    @synchronized(self) {
	      hasBothFrames = (self.latestFrontFrame || self.latestRawFrontFrame) && self.latestBackFrame;
	    }
    if (hasBothFrames) {
      dispatch_async(dispatch_get_main_queue(), ^{
        CGSize canvasSize = self.bounds.size;
        [self prepareRealtimeRecordingPipelineForCanvasSize:canvasSize];
      });
    }
  }

  if (self.pendingStartRecordingAfterWarmup && !self.isDualRecordingActive && isBackOutput) {
    __block BOOL hasBothFrames = NO;
    @synchronized(self) {
      hasBothFrames = self.latestFrontFrame && self.latestBackFrame;
    }
    if (hasBothFrames) {
      CGSize canvasSize = self.pendingStartRecordingCanvasSize;
      self.pendingStartRecordingAfterWarmup = NO;
      self.pendingStartRecordingCanvasSize = CGSizeZero;
      [self prepareRealtimeRecordingPipelineForCanvasSize:canvasSize];
      dispatch_async(self.realtimeRenderQueue, ^{
        dispatch_async(self.sessionQueue, ^{
          [self startRealtimeRecordingWithCanvasSize:canvasSize];
        });
      });
    }
  }

  if (self.isDualRecordingActive && isBackOutput) {
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    dispatch_async(self.realtimeRenderQueue, ^{
      [self appendRealtimeVideoFrameAtTime:pts source:@"back_clock"];
    });
  }
}

#pragma mark - Event emission

- (void)emitPhotoSaved:(NSString *)uri {
  [[DualCameraEventEmitter shared] sendPhotoSaved:uri];
}

- (void)emitPhotoSaved:(NSString *)uri uris:(NSDictionary *)uris {
  [[DualCameraEventEmitter shared] sendPhotoSaved:uri uris:uris];
}

- (void)emitError:(NSString *)error {
  [[DualCameraEventEmitter shared] sendPhotoError:error];
}

@end
