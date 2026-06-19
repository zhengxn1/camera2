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

static CGColorSpaceRef DualCameraCreateCaptureInputColorSpace(CVImageBufferRef pixelBuffer) {
  CGColorSpaceRef bufferCS = pixelBuffer ? CVImageBufferGetColorSpace(pixelBuffer) : NULL;
  if (bufferCS) {
    CFRetain(bufferCS);
    return bufferCS;
  }
  return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
}

static CGImagePropertyOrientation DualCameraCGImageOrientationFromPhotoData(NSData *data) {
  if (!data) return kCGImagePropertyOrientationUp;

  CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
  if (!source) return kCGImagePropertyOrientationUp;

  CGImagePropertyOrientation orientation = kCGImagePropertyOrientationUp;
  NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
  NSNumber *orientationNumber = properties[(NSString *)kCGImagePropertyOrientation];
  if (orientationNumber) {
    orientation = (CGImagePropertyOrientation)orientationNumber.unsignedIntValue;
  }
  CFRelease(source);
  return orientation;
}

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

      BOOL isDualPhotoLayout = self.usingMultiCam && [self isDualLayout:self.currentLayout];
      BOOL useWysiwygFrames = self.usingMultiCam &&
        (!isDualPhotoLayout &&
         ([self.currentLayout isEqualToString:@"front"] && self.frontBeautyEnabled));
      NSLog(@"[BeautyCapture] photo layout=%@ usingMultiCam=%d useWysiwygFrames=%d beautyEnabled=%d smooth=%.1f brighten=%.1f whiten=%.1f",
            self.currentLayout ?: @"unknown",
            self.usingMultiCam,
            useWysiwygFrames,
            self.frontBeautyEnabled,
            self.frontBeautySmooth,
            self.frontBeautyBrighten,
            self.frontBeautyWhiten);
      if (isDualPhotoLayout) {
        [self startHighQualityDualPhotoCaptureWithCanvasSize:canvasSizeForPhoto];
      } else if (useWysiwygFrames) {
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

#pragma mark - Realtime beauty preview

- (BOOL)shouldRenderFrontBeautyPreview {
  if (!self.frontBeautyEnabled) return NO;
  if ([self.currentLayout isEqualToString:@"back"]) return NO;
  return self.frontBeautySmooth > 0 ||
         self.frontBeautyBrighten > 0 ||
         self.frontBeautyWhiten > 0;
}

- (CIImage *)previewImageFromFrontImage:(CIImage *)image {
  if (!image) return nil;

  BOOL recordingPreview = self.isDualRecordingActive ||
    self.realtimeRecordingState == DualCameraRealtimeRecordingStatePrepared ||
    self.realtimeRecordingState == DualCameraRealtimeRecordingStateWriting ||
    self.realtimeRecordingState == DualCameraRealtimeRecordingStateFinishing;
  CIImage *result = [self beautifiedFrontImage:image source:recordingPreview ? @"recording_preview" : @"preview"];
  @synchronized(self) {
    self.latestFrontBeautifiedFrame = result;
    self.latestFrontBeautifiedFrameSequence = self.latestFrontFrameSequence;
    self.latestFrontBeautifiedFramePTS = self.latestFrontFramePTS;
  }
  CGFloat width = CGRectGetWidth(result.extent);
  if (self.frontPreviewMirrored && width > 0) {
    CGAffineTransform mirror = CGAffineTransformMakeTranslation(width, 0);
    mirror = CGAffineTransformScale(mirror, -1, 1);
    result = [result imageByApplyingTransform:mirror];
  }

  if (result.extent.origin.x != 0 || result.extent.origin.y != 0) {
    result = [result imageByApplyingTransform:CGAffineTransformMakeTranslation(-result.extent.origin.x,
                                                                               -result.extent.origin.y)];
  }
  return result;
}

- (void)renderFrontBeautyPreviewFrame:(CIImage *)frontFrame {
  if (!frontFrame || ![self shouldRenderFrontBeautyPreview]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      self.frontBeautyPreviewRenderInFlight = NO;
      self.latestFrontBeautyPreviewImage = nil;
      self.latestFrontBeautyPreviewImageExtent = CGRectZero;
      @synchronized(self) {
        self.latestFrontBeautifiedFrame = nil;
        self.latestFrontBeautifiedFrameSequence = 0;
        self.latestFrontBeautifiedFramePTS = kCMTimeInvalid;
      }
      self.frontBeautyPreviewMetalView.hidden = YES;
      self.frontBeautyPreviewImageView.hidden = YES;
      self.frontBeautyPreviewImageView.image = nil;
    });
    return;
  }

  CFTimeInterval now = CFAbsoluteTimeGetCurrent();
  BOOL recordingPreview = self.isDualRecordingActive ||
    self.realtimeRecordingState == DualCameraRealtimeRecordingStatePrepared ||
    self.realtimeRecordingState == DualCameraRealtimeRecordingStateWriting ||
    self.realtimeRecordingState == DualCameraRealtimeRecordingStateFinishing;
  CFTimeInterval minInterval = recordingPreview ? (1.0 / 30.0) : (1.0 / 15.0);
  if (self.frontBeautyPreviewRenderInFlight ||
      now - self.lastFrontBeautyPreviewUpdateTime < minInterval) {
    return;
  }
  self.frontBeautyPreviewRenderInFlight = YES;
  self.lastFrontBeautyPreviewUpdateTime = now;

  dispatch_async(self.frontBeautyProcessingQueue, ^{
    @autoreleasepool {
      CIImage *renderImage = nil;
      UIImage *previewImage = nil;
      if ([self shouldRenderFrontBeautyPreview]) {
        renderImage = [self previewImageFromFrontImage:frontFrame];
        CGRect renderRect = renderImage.extent;
        if (!self.frontBeautyPreviewMetalView && renderImage && !CGRectIsEmpty(renderRect)) {
          CGImageRef cgImage = [self.ciContext createCGImage:renderImage fromRect:renderRect];
          if (cgImage) {
            previewImage = [UIImage imageWithCGImage:cgImage
                                               scale:[UIScreen mainScreen].scale
                                         orientation:UIImageOrientationUp];
            CGImageRelease(cgImage);
          }
        }
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        self.frontBeautyPreviewRenderInFlight = NO;
        if (renderImage && [self shouldRenderFrontBeautyPreview]) {
          self.latestFrontBeautyPreviewImage = renderImage;
          self.latestFrontBeautyPreviewImageExtent = renderImage.extent;
          if (self.frontBeautyPreviewMetalView) {
            self.frontBeautyPreviewMetalView.frame = self.frontPreviewView.bounds;
            self.frontBeautyPreviewMetalView.hidden = NO;
            self.frontBeautyPreviewImageView.hidden = YES;
            self.frontBeautyPreviewImageView.image = nil;
            [self bringFrontBeautyPreviewToFront];
            [self.frontBeautyPreviewMetalView setNeedsDisplay];
          } else if (previewImage) {
            self.frontBeautyPreviewImageView.frame = self.frontPreviewView.bounds;
            self.frontBeautyPreviewImageView.image = previewImage;
            self.frontBeautyPreviewImageView.hidden = NO;
            [self bringFrontBeautyPreviewToFront];
          }
        } else {
          self.latestFrontBeautyPreviewImage = nil;
          self.latestFrontBeautyPreviewImageExtent = CGRectZero;
          self.frontBeautyPreviewMetalView.hidden = YES;
          self.frontBeautyPreviewImageView.hidden = YES;
          self.frontBeautyPreviewImageView.image = nil;
        }
      });
    }
  });
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (void)drawInMTKView:(MTKView *)view {
  if (view != self.frontBeautyPreviewMetalView || view.hidden) return;
  CIImage *image = self.latestFrontBeautyPreviewImage;
  id<CAMetalDrawable> drawable = view.currentDrawable;
  if (!image || !drawable || !self.metalCommandQueue) return;

  CGSize drawableSize = view.drawableSize;
  if (drawableSize.width <= 0 || drawableSize.height <= 0) return;

  CIImage *source = image;
  if (source.extent.origin.x != 0 || source.extent.origin.y != 0) {
    source = [source imageByApplyingTransform:CGAffineTransformMakeTranslation(-source.extent.origin.x,
                                                                               -source.extent.origin.y)];
  }
  CGFloat sourceW = source.extent.size.width;
  CGFloat sourceH = source.extent.size.height;
  if (sourceW <= 0 || sourceH <= 0) return;

  CGFloat scale = MAX(drawableSize.width / sourceW, drawableSize.height / sourceH);
  CIImage *scaled = [source imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
  CGFloat cropX = MAX(0, (scaled.extent.size.width - drawableSize.width) / 2.0);
  CGFloat cropY = MAX(0, (scaled.extent.size.height - drawableSize.height) / 2.0);
  CIImage *cropped = [scaled imageByCroppingToRect:CGRectMake(cropX,
                                                              cropY,
                                                              drawableSize.width,
                                                              drawableSize.height)];
  CIImage *placed = [cropped imageByApplyingTransform:CGAffineTransformMakeTranslation(-cropX, -cropY)];
  CGRect bounds = CGRectMake(0, 0, drawableSize.width, drawableSize.height);

  id<MTLCommandBuffer> commandBuffer = [self.metalCommandQueue commandBuffer];
  if (!commandBuffer) return;
  CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  [self.ciContext render:placed
            toMTLTexture:drawable.texture
           commandBuffer:commandBuffer
                  bounds:bounds
              colorSpace:colorSpace];
  if (colorSpace) CGColorSpaceRelease(colorSpace);
  [commandBuffer presentDrawable:drawable];
  [commandBuffer commit];
}

#pragma mark - Multicam WYSIWYG photo capture

// Fallback path: saves the same composited camera frames used by realtime recording.
// High-quality dual stills should use AVCapturePhotoOutput first.
- (void)captureWysiwygDualPhotoWithCanvasSize:(CGSize)canvasSize {
  CIImage *frontFrame = nil;
  CIImage *backFrame = nil;
  NSInteger frontSeq = 0;
  NSInteger backSeq = 0;
  @synchronized(self) {
    frontFrame = self.latestFrontFrame;
    backFrame = self.latestBackFrame;
    frontSeq = self.latestFrontFrameSequence;
    backSeq = self.latestBackFrameSequence;
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
      NSLog(@"[PhotoQuality] fallback source=videoFrame reason=photoOutput_unavailable_or_failed layout=%@ frontSeq=%ld backSeq=%ld",
            self.currentLayout ?: @"unknown", (long)frontSeq, (long)backSeq);
      NSLog(@"[BeautyRoute] source=photo output=combined frontCamera=%@ backCamera=%@ frontSeq=%ld backSeq=%ld",
            frontFrame ? @"front" : @"none",
            backFrame ? @"back" : @"none",
            (long)frontSeq,
            (long)backSeq);
      CIImage *composited = [self compositedImageForLayoutState:photoState
                                                          front:frontFrame
                                                           back:backFrame
                                                    highQuality:YES
                                                         source:@"photo"];
      NSString *path = [self saveCIImageAsJPEG:composited];
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

- (AVCapturePhotoSettings *)safePhotoSettingsForOutput:(AVCapturePhotoOutput *)output {
  AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
  settings.flashMode = AVCaptureFlashModeOff;
  [self applyHighQualityPhotoSettings:settings forOutput:output];
  return settings;
}

- (void)startHighQualityDualPhotoCaptureWithCanvasSize:(CGSize)canvasSize {
  if (!self.frontPhotoOutput || !self.backPhotoOutput) {
    NSLog(@"[PhotoQuality] fallback source=videoFrame reason=missing_photo_output layout=%@",
          self.currentLayout ?: @"unknown");
    [self captureWysiwygDualPhotoWithCanvasSize:canvasSize];
    return;
  }

  if (self.highQualityDualPhotoCaptureInProgress) {
    NSLog(@"[PhotoQuality] fallback source=videoFrame reason=photo_capture_busy layout=%@",
          self.currentLayout ?: @"unknown");
    [self captureWysiwygDualPhotoWithCanvasSize:canvasSize];
    return;
  }

  DualCameraDeviceOrientation photoOrientation = self.deviceOrientation;
  CGSize saveCanvas = [self outputSizeForAspectRatio:self.saveAspectRatio ?: @"9:16"
                                      referenceWidth:1440.0
                                           landscape:[self isDeviceOrientationLandscape:photoOrientation]];
  DualCameraLayoutState *photoState = [self layoutStateSnapshotForCanvasSize:canvasSize
                                                                  outputSize:saveCanvas
                                                                 orientation:photoOrientation];
  photoState.frontMirrored = self.frontPreviewMirrored;
  photoState.backMirrored = self.backPreviewMirrored;

  self.highQualityDualPhotoCaptureInProgress = YES;
  self.highQualityDualPhotoCaptureID += 1;
  self.pendingHighQualityFrontPhotoData = nil;
  self.pendingHighQualityBackPhotoData = nil;
  self.pendingHighQualityFrontPhotoFinished = NO;
  self.pendingHighQualityBackPhotoFinished = NO;
  self.pendingHighQualityDualPhotoState = photoState;
  self.pendingHighQualityDualPhotoLayout = self.currentLayout ?: @"unknown";
  self.pendingHighQualityDualPhotoCanvasSize = canvasSize;
  NSInteger captureID = self.highQualityDualPhotoCaptureID;

  @try {
    NSLog(@"[PhotoQuality] start source=photoOutput layout=%@ captureID=%ld",
          self.pendingHighQualityDualPhotoLayout ?: @"unknown", (long)captureID);
    [self.frontPhotoOutput capturePhotoWithSettings:[self safePhotoSettingsForOutput:self.frontPhotoOutput] delegate:self];
    [self.backPhotoOutput capturePhotoWithSettings:[self safePhotoSettingsForOutput:self.backPhotoOutput] delegate:self];
  } @catch (NSException *exception) {
    NSLog(@"[PhotoQuality] fallback source=videoFrame reason=photo_output_exception exception=%@",
          exception.reason ?: @"unknown");
    [self resetHighQualityDualPhotoCaptureState];
    [self captureWysiwygDualPhotoWithCanvasSize:canvasSize];
    return;
  }

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), self.sessionQueue, ^{
    if (!self.highQualityDualPhotoCaptureInProgress || self.highQualityDualPhotoCaptureID != captureID) {
      return;
    }
    NSLog(@"[PhotoQuality] fallback source=videoFrame reason=photo_output_timeout frontDone=%d backDone=%d layout=%@",
          self.pendingHighQualityFrontPhotoFinished,
          self.pendingHighQualityBackPhotoFinished,
          self.pendingHighQualityDualPhotoLayout ?: @"unknown");
    CGSize fallbackCanvas = self.pendingHighQualityDualPhotoCanvasSize;
    [self resetHighQualityDualPhotoCaptureState];
    [self captureWysiwygDualPhotoWithCanvasSize:fallbackCanvas];
  });
}

- (void)resetHighQualityDualPhotoCaptureState {
  self.highQualityDualPhotoCaptureInProgress = NO;
  self.pendingHighQualityFrontPhotoData = nil;
  self.pendingHighQualityBackPhotoData = nil;
  self.pendingHighQualityFrontPhotoFinished = NO;
  self.pendingHighQualityBackPhotoFinished = NO;
  self.pendingHighQualityDualPhotoState = nil;
  self.pendingHighQualityDualPhotoLayout = nil;
  self.pendingHighQualityDualPhotoCanvasSize = CGSizeZero;
}

- (CIImage *)ciImageFromPhotoData:(NSData *)data cameraSource:(NSString *)cameraSource {
  if (!data) return nil;

  CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  NSDictionary *options = srgb ? @{(id)kCIImageColorSpace: (__bridge id)srgb} : nil;
  CIImage *image = [CIImage imageWithData:data options:options];
  if (srgb) CGColorSpaceRelease(srgb);
  if (!image) return nil;

  CGImagePropertyOrientation orientation = DualCameraCGImageOrientationFromPhotoData(data);
  image = [image imageByApplyingCGOrientation:orientation];
  if (image.extent.origin.x != 0 || image.extent.origin.y != 0) {
    image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-image.extent.origin.x,
                                                                             -image.extent.origin.y)];
  }
  NSLog(@"[PhotoQuality] output=%@ source=photoOutput size=%.0fx%.0f orientation=%u",
        cameraSource ?: @"unknown",
        image.extent.size.width,
        image.extent.size.height,
        orientation);
  return image;
}

- (void)finishHighQualityDualPhotoCaptureIfReady {
  if (!self.highQualityDualPhotoCaptureInProgress) return;
  if (!self.pendingHighQualityFrontPhotoFinished || !self.pendingHighQualityBackPhotoFinished) return;

  NSData *frontData = self.pendingHighQualityFrontPhotoData;
  NSData *backData = self.pendingHighQualityBackPhotoData;
  DualCameraLayoutState *photoState = self.pendingHighQualityDualPhotoState;
  NSString *layout = self.pendingHighQualityDualPhotoLayout ?: @"unknown";
  CGSize fallbackCanvas = self.pendingHighQualityDualPhotoCanvasSize;
  [self resetHighQualityDualPhotoCaptureState];

  if (!frontData || !backData || !photoState) {
    NSLog(@"[PhotoQuality] fallback source=videoFrame reason=missing_photo_data_after_finish layout=%@",
          layout);
    [self captureWysiwygDualPhotoWithCanvasSize:fallbackCanvas];
    return;
  }

  dispatch_async(self.realtimeRenderQueue, ^{
    @autoreleasepool {
      CIImage *frontPhoto = [self ciImageFromPhotoData:frontData cameraSource:@"front"];
      CIImage *backPhoto = [self ciImageFromPhotoData:backData cameraSource:@"back"];
      if (!frontPhoto || !backPhoto) {
        NSLog(@"[PhotoQuality] fallback source=videoFrame reason=photo_data_decode_failed layout=%@",
              layout);
        dispatch_async(self.sessionQueue, ^{
          [self captureWysiwygDualPhotoWithCanvasSize:fallbackCanvas];
        });
        return;
      }

      NSLog(@"[PhotoQuality] output=combined source=photoOutput layout=%@ canvas=%.0fx%.0f",
            layout, photoState.outputSize.width, photoState.outputSize.height);
      NSLog(@"[BeautyRoute] source=photo output=back cameraSource=back beauty=never");
      CIImage *composited = [self compositedImageForLayoutState:photoState
                                                          front:frontPhoto
                                                           back:backPhoto
                                                    highQuality:YES
                                                         source:@"photo"];
      NSString *path = [self saveCIImageAsJPEG:composited];
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

  // MultiCam may cap a camera output below Quality. Clamp to each output's
  // actual maximum so capturePhoto does not throw and fall back to video frames.
  if (@available(iOS 13.0, *)) {
    AVCapturePhotoQualityPrioritization requested = AVCapturePhotoQualityPrioritizationQuality;
    AVCapturePhotoQualityPrioritization maxSupported = output.maxPhotoQualityPrioritization;
    settings.photoQualityPrioritization = MIN(requested, maxSupported);
    NSLog(@"[PhotoQuality] settings requested=%ld max=%ld selected=%ld",
          (long)requested,
          (long)maxSupported,
          (long)settings.photoQualityPrioritization);
  }

  // iOS 16+: use the output's max dimensions.
  if (@available(iOS 16.0, *)) {
    if (settings.maxPhotoDimensions.width == 0 && settings.maxPhotoDimensions.height == 0) {
      settings.maxPhotoDimensions = output.maxPhotoDimensions;
    }
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
      NSLog(@"[BeautyCapture] video layout=%@ usingMultiCam=%d realtime=1 beautyEnabled=%d smooth=%.1f brighten=%.1f whiten=%.1f",
            self.currentLayout ?: @"unknown",
            self.usingMultiCam,
            self.frontBeautyEnabled,
            self.frontBeautySmooth,
            self.frontBeautyBrighten,
            self.frontBeautyWhiten);
      if (!self.frontVideoDataOutput || !self.backVideoDataOutput) {
        [self emitRecordingError:@"Realtime recording unavailable — video data outputs are not configured."];
        return;
      }
      __block BOOL hasBothFrames = NO;
      @synchronized(self) {
        hasBothFrames = self.latestFrontFrame && self.latestBackFrame;
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
      NSLog(@"[BeautyCapture] video layout=%@ usingMultiCam=0 realtime=0 beautyEnabled=%d smooth=%.1f brighten=%.1f whiten=%.1f",
            self.currentLayout ?: @"unknown",
            self.frontBeautyEnabled,
            self.frontBeautySmooth,
            self.frontBeautyBrighten,
            self.frontBeautyWhiten);
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
    if (self.highQualityDualPhotoCaptureInProgress &&
        (output == self.frontPhotoOutput || output == self.backPhotoOutput)) {
      BOOL isFrontPhoto = output == self.frontPhotoOutput;
      if (error) {
        NSLog(@"[PhotoQuality] fallback source=videoFrame reason=%@_photo_error error=%@",
              isFrontPhoto ? @"front" : @"back",
              error.localizedDescription ?: @"unknown");
        CGSize fallbackCanvas = self.pendingHighQualityDualPhotoCanvasSize;
        [self resetHighQualityDualPhotoCaptureState];
        dispatch_async(self.sessionQueue, ^{
          [self captureWysiwygDualPhotoWithCanvasSize:fallbackCanvas];
        });
        return;
      }

      NSData *data = [photo fileDataRepresentation];
      if (!data) {
        NSLog(@"[PhotoQuality] fallback source=videoFrame reason=%@_photo_data_nil",
              isFrontPhoto ? @"front" : @"back");
        CGSize fallbackCanvas = self.pendingHighQualityDualPhotoCanvasSize;
        [self resetHighQualityDualPhotoCaptureState];
        dispatch_async(self.sessionQueue, ^{
          [self captureWysiwygDualPhotoWithCanvasSize:fallbackCanvas];
        });
        return;
      }

      if (isFrontPhoto) {
        self.pendingHighQualityFrontPhotoData = data;
        self.pendingHighQualityFrontPhotoFinished = YES;
      } else {
        self.pendingHighQualityBackPhotoData = data;
        self.pendingHighQualityBackPhotoFinished = YES;
      }
      [self finishHighQualityDualPhotoCaptureIfReady];
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

  // Preserve the pixel buffer's embedded colour space. Some BGRA camera buffers
  // do not expose kCVImageBufferCGColorSpaceKey even though their format
  // extensions are SDR/709; use sRGB as the Core Image input fallback so the
  // saved compositing path matches the Metal preview path.
  CGColorSpaceRef inputCS = DualCameraCreateCaptureInputColorSpace(pixelBuffer);
  NSDictionary *ciOptions = inputCS ? @{(id)kCIImageColorSpace: (__bridge id)inputCS} : nil;
  CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer options:ciOptions];
  if (inputCS) CGColorSpaceRelease(inputCS);
  if (!ciImage) return;

  BOOL isFrontOutput = (output == self.frontVideoDataOutput);
  BOOL isBackOutput = (output == self.backVideoDataOutput);
  if (!isFrontOutput && !isBackOutput) return;

  static BOOL didLogFrontSample = NO;
  static BOOL didLogBackSample = NO;
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

  // Store raw frames (WYSIWYG: save what preview shows — mirroring applied at compositing time)
  if (isFrontOutput) {
    @synchronized(self) {
      self.latestFrontFrame = ciImage;
      self.latestFrontFrameSequence += 1;
      self.latestFrontFramePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    }
    static BOOL didLogFrontRoute = NO;
    if (!didLogFrontRoute) {
      didLogFrontRoute = YES;
      NSLog(@"[BeautyRoute] capture cameraSource=front output=latestFrontFrame beauty=eligible");
    }
    [self renderFrontBeautyPreviewFrame:ciImage];
  } else {
    @synchronized(self) {
      self.latestBackFrame = ciImage;
      self.latestBackFrameSequence += 1;
      self.latestBackFramePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    }
    static BOOL didLogBackRoute = NO;
    if (!didLogBackRoute) {
      didLogBackRoute = YES;
      NSLog(@"[BeautyRoute] capture cameraSource=back output=latestBackFrame beauty=never");
    }
  }

  if (self.usingMultiCam && !self.isDualRecordingActive &&
      self.realtimeRecordingState == DualCameraRealtimeRecordingStateIdle &&
      !self.realtimePipelineWarmed && !self.realtimePipelineWarmupInProgress) {
    __block BOOL hasBothFrames = NO;
    @synchronized(self) {
      hasBothFrames = self.latestFrontFrame && self.latestBackFrame;
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
