#import "DualCameraView+Recording.h"
#import "DualCameraView_Internal.h"

static CGColorSpaceRef DualCameraCreateRealtimeRenderColorSpace(void) {
  return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
}

static NSString *DualCameraRecordingFourCCString(OSType code) {
  char chars[5] = {
    (char)((code >> 24) & 0xff),
    (char)((code >> 16) & 0xff),
    (char)((code >> 8) & 0xff),
    (char)(code & 0xff),
    0
  };
  return [NSString stringWithFormat:@"%s/%u", chars, (unsigned int)code];
}

static id DualCameraRecordingBufferAttachment(CVBufferRef buffer, CFStringRef key) {
  if (!buffer || !key) return nil;
  return (__bridge id)CVBufferGetAttachment(buffer, key, NULL);
}

static const CGFloat DualCameraHDRDebugOutputExposureEV = 0.0;

@implementation DualCameraView (Recording)

#pragma mark - State machine

- (NSNumber *)realtimeVideoBitRateForOutputSize:(CGSize)outputSize {
  CGFloat pixels = MAX(1.0, outputSize.width * outputSize.height);
  CGFloat fullPortraitPixels = 1440.0 * 2560.0;
  NSInteger bitRate = (NSInteger)llround(45000000.0 * (pixels / fullPortraitPixels));
  bitRate = MAX(24000000, MIN(55000000, bitRate));
  return @(bitRate);
}

- (NSDictionary *)realtimeVideoSettingsForOutputSize:(CGSize)outputSize {
  return @{
    AVVideoCodecKey: AVVideoCodecTypeHEVC,
    AVVideoWidthKey: @(outputSize.width),
    AVVideoHeightKey: @(outputSize.height),
    AVVideoColorPropertiesKey: @{
      AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
      AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
      AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    },
    AVVideoCompressionPropertiesKey: @{
      AVVideoAverageBitRateKey: [self realtimeVideoBitRateForOutputSize:outputSize],
      AVVideoExpectedSourceFrameRateKey: @(30),
      AVVideoMaxKeyFrameIntervalKey: @(30)
    }
  };
}

- (NSDictionary *)realtimePixelBufferAttributesForOutputSize:(CGSize)outputSize {
  return @{
    (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferWidthKey: @(outputSize.width),
    (id)kCVPixelBufferHeightKey: @(outputSize.height),
    (id)kCVImageBufferColorPrimariesKey: (id)kCVImageBufferColorPrimaries_ITU_R_709_2,
    (id)kCVImageBufferTransferFunctionKey: (id)kCVImageBufferTransferFunction_ITU_R_709_2,
    (id)kCVImageBufferYCbCrMatrixKey: (id)kCVImageBufferYCbCrMatrix_ITU_R_709_2,
    (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
  };
}

- (NSDictionary *)realtimeAudioSettings {
  return @{
    AVFormatIDKey: @(kAudioFormatMPEG4AAC),
    AVSampleRateKey: @(44100),
    AVNumberOfChannelsKey: @(1),
    AVEncoderBitRateKey: @(128000)
  };
}

- (CIImage *)realtimeOutputAdjustedImage:(CIImage *)image {
  if (!image || DualCameraHDRDebugOutputExposureEV == 0) return image;
  static BOOL didLogOutputAdjustment = NO;
  if (!didLogOutputAdjustment) {
    didLogOutputAdjustment = YES;
    NSLog(@"[BeautyRoute] source=recording output=combined postCompositeAdjustment=exposure beauty=not_applied ev=%.2f",
          DualCameraHDRDebugOutputExposureEV);
  }

  CIFilter *exposure = [CIFilter filterWithName:@"CIExposureAdjust"];
  [exposure setValue:image forKey:kCIInputImageKey];
  [exposure setValue:@(DualCameraHDRDebugOutputExposureEV) forKey:kCIInputEVKey];
  return exposure.outputImage ?: image;
}

- (BOOL)canUseWarmedRealtimePipelineForAspectRatio:(NSString *)aspectRatio
                                        canvasSize:(CGSize)canvasSize
                                        outputSize:(CGSize)outputSize {
  return self.realtimePipelineWarmed &&
         [self.warmedRealtimeAspectRatio isEqualToString:aspectRatio] &&
         CGSizeEqualToSize(self.warmedRealtimeCanvasSize, canvasSize) &&
         CGSizeEqualToSize(self.warmedRealtimeOutputSize, outputSize) &&
         self.warmedRealtimeVideoSettings &&
         self.warmedRealtimePixelBufferAttributes &&
         self.warmedRealtimeAudioSettings;
}

- (void)prepareRealtimeRecordingPipelineForCanvasSize:(CGSize)canvasSize {
  if (CGSizeEqualToSize(canvasSize, CGSizeZero)) return;
  if (!self.usingMultiCam || !self.isConfigured) return;

  NSString *aspectRatio = self.saveAspectRatio ?: @"9:16";
  DualCameraDeviceOrientation orientation = self.deviceOrientation;
  CGSize outputSize = [self realtimeRecordingOutputSizeForAspectRatio:aspectRatio
                                                             landscape:[self isDeviceOrientationLandscape:orientation]];
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
  @synchronized(self) {
    BOOL canReuseWarmup = [self canUseWarmedRealtimePipelineForAspectRatio:aspectRatio canvasSize:canvasSize outputSize:outputSize];
    if (canReuseWarmup || self.realtimePipelineWarmupInProgress) {
      return;
    }
    self.realtimePipelineWarmupInProgress = YES;
  }

  dispatch_async(self.realtimeRenderQueue, ^{
    NSDictionary *videoSettings = [self realtimeVideoSettingsForOutputSize:outputSize];
    NSDictionary *pixelAttrs = [self realtimePixelBufferAttributesForOutputSize:outputSize];
    NSDictionary *audioSettings = [self realtimeAudioSettings];
    DualCameraLayoutState *warmupState = [self layoutStateSnapshotForCanvasSize:canvasSize
                                                                     outputSize:outputSize
                                                                    orientation:orientation];
    if ([self isDualLayout:self.currentLayout]) {
      warmupState.frontMirrored = self.frontPreviewMirrored;
      warmupState.backMirrored = self.backPreviewMirrored;
    } else {
      warmupState.frontMirrored = self.frontOutputMirrored;
      warmupState.backMirrored = self.backOutputMirrored;
    }
    CIImage *warmupImage = nil;
    if (frontFrame && backFrame) {
      NSLog(@"[BeautyRoute] source=warmup output=combined frontCamera=front backCamera=back frontSeq=%ld backSeq=%ld",
            (long)frontSeq,
            (long)backSeq);
      warmupImage = [self compositedImageForLayoutState:warmupState
                                                  front:frontFrame
                                                   back:backFrame
                                            highQuality:NO
                                                 source:@"warmup"];
    }
    if (!warmupImage) {
      warmupImage = [self blackCanvasSize:outputSize];
    }

    CVPixelBufferRef scratchBuffer = NULL;
    CVReturn createStatus = CVPixelBufferCreate(kCFAllocatorDefault,
                                                (size_t)outputSize.width,
                                                (size_t)outputSize.height,
                                                kCVPixelFormatType_32BGRA,
                                                (__bridge CFDictionaryRef)pixelAttrs,
                                                &scratchBuffer);
    if (createStatus == kCVReturnSuccess && scratchBuffer) {
      CGColorSpaceRef colorSpace = DualCameraCreateRealtimeRenderColorSpace();
      [self.ciContext render:warmupImage
             toCVPixelBuffer:scratchBuffer
                      bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
                  colorSpace:colorSpace];
      if (colorSpace) {
        CGColorSpaceRelease(colorSpace);
      }
      CVPixelBufferRelease(scratchBuffer);
    }

    NSString *warmupPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dual_realtime_warmup.mp4"];
    NSURL *warmupURL = [NSURL fileURLWithPath:warmupPath];
    [[NSFileManager defaultManager] removeItemAtURL:warmupURL error:nil];
    NSError *writerError = nil;
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:warmupURL fileType:AVFileTypeMPEG4 error:&writerError];
    AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    videoInput.expectsMediaDataInRealTime = YES;
    __block BOOL writerWarmupSucceeded = NO;
    if (writer && [writer canAddInput:videoInput]) {
      [writer addInput:videoInput];
      AVAssetWriterInputPixelBufferAdaptor *adaptor =
        [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoInput
                                                                         sourcePixelBufferAttributes:pixelAttrs];
      CVPixelBufferRef warmupBuffer = NULL;
      CVReturn bufferStatus = CVPixelBufferCreate(kCFAllocatorDefault,
                                                  (size_t)outputSize.width,
                                                  (size_t)outputSize.height,
                                                  kCVPixelFormatType_32BGRA,
                                                  (__bridge CFDictionaryRef)pixelAttrs,
                                                  &warmupBuffer);
      if (bufferStatus == kCVReturnSuccess && warmupBuffer) {
        CGColorSpaceRef colorSpace = DualCameraCreateRealtimeRenderColorSpace();
        [self.ciContext render:warmupImage
               toCVPixelBuffer:warmupBuffer
                        bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
                    colorSpace:colorSpace];
        if (colorSpace) {
          CGColorSpaceRelease(colorSpace);
        }

        if ([writer startWriting]) {
          [writer startSessionAtSourceTime:kCMTimeZero];
          if (videoInput.isReadyForMoreMediaData &&
              [adaptor appendPixelBuffer:warmupBuffer withPresentationTime:kCMTimeZero]) {
            [videoInput markAsFinished];
            dispatch_semaphore_t finishSemaphore = dispatch_semaphore_create(0);
            [writer finishWritingWithCompletionHandler:^{
              writerWarmupSucceeded = (writer.status == AVAssetWriterStatusCompleted);
              dispatch_semaphore_signal(finishSemaphore);
            }];
            dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC));
            if (dispatch_semaphore_wait(finishSemaphore, timeout) != 0) {
              [writer cancelWriting];
              writerWarmupSucceeded = NO;
            }
            if (!writerWarmupSucceeded) {
              writerError = writer.error;
            }
          } else {
            writerError = writer.error;
            [writer cancelWriting];
          }
        } else {
          writerError = writer.error;
        }
        CVPixelBufferRelease(warmupBuffer);
      }
    }
    [[NSFileManager defaultManager] removeItemAtURL:warmupURL error:nil];

    BOOL warmupSucceeded = (createStatus == kCVReturnSuccess && !writerError && writerWarmupSucceeded);
    @synchronized(self) {
      if (warmupSucceeded) {
        self.warmedRealtimeVideoSettings = videoSettings;
        self.warmedRealtimePixelBufferAttributes = pixelAttrs;
        self.warmedRealtimeAudioSettings = audioSettings;
        self.warmedRealtimeAspectRatio = aspectRatio;
        self.warmedRealtimeCanvasSize = canvasSize;
        self.warmedRealtimeOutputSize = outputSize;
        self.realtimePipelineWarmed = YES;
      } else {
        self.realtimePipelineWarmed = NO;
      }
      self.realtimePipelineWarmupInProgress = NO;
    }
  });
}

- (BOOL)startRealtimeRecordingWithCanvasSize:(CGSize)canvasSize {
  if (self.realtimeRecordingState != DualCameraRealtimeRecordingStateIdle || self.realtimeAssetWriter) {
    return NO;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    self.frontBeautyPreviewRenderInFlight = NO;
    self.frontBeautyPreviewImageView.hidden = YES;
    self.frontBeautyPreviewImageView.image = nil;
  });

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
  BOOL useWarmSettings = [self canUseWarmedRealtimePipelineForAspectRatio:aspectRatio
                                                               canvasSize:canvasSize
                                                               outputSize:outputSize];
  DualCameraLayoutState *recordingState = [self layoutStateSnapshotForCanvasSize:canvasSize
                                                                       outputSize:outputSize
                                                                      orientation:recordingOrientation];
  if ([self isDualLayout:self.currentLayout]) {
    // Realtime dual recording is composited from VideoDataOutput frames and
    // should match the visible preview.
    recordingState.frontMirrored = self.frontPreviewMirrored;
    recordingState.backMirrored = self.backPreviewMirrored;
  } else {
    recordingState.frontMirrored = self.frontOutputMirrored;
    recordingState.backMirrored = self.backOutputMirrored;
  }
  NSDictionary *videoSettings = useWarmSettings
    ? self.warmedRealtimeVideoSettings
    : [self realtimeVideoSettingsForOutputSize:outputSize];
  NSDictionary *frontRecommendedSettings = self.frontVideoDataOutput
    ? [self.frontVideoDataOutput recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeMPEG4]
    : nil;
  NSDictionary *backRecommendedSettings = self.backVideoDataOutput
    ? [self.backVideoDataOutput recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeMPEG4]
    : nil;
  NSLog(@"[DualCamera][QualityDiag] writer current videoSettings=%@", videoSettings ?: @{});
  NSLog(@"[DualCamera][QualityDiag] writer recommended front=%@", frontRecommendedSettings ?: @{});
  NSLog(@"[DualCamera][QualityDiag] writer recommended back=%@", backRecommendedSettings ?: @{});
  AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
  videoInput.expectsMediaDataInRealTime = YES;
  videoInput.transform = CGAffineTransformIdentity;

  NSDictionary *pixelAttrs = useWarmSettings
    ? self.warmedRealtimePixelBufferAttributes
    : [self realtimePixelBufferAttributesForOutputSize:outputSize];
  AVAssetWriterInputPixelBufferAdaptor *adaptor =
    [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoInput
                                                                     sourcePixelBufferAttributes:pixelAttrs];

  NSDictionary *audioSettings = useWarmSettings
    ? self.warmedRealtimeAudioSettings
    : [self realtimeAudioSettings];
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
  NSLog(@"[DualCamera] Realtime recording warm settings used=%d", useWarmSettings);
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

- (void)appendRealtimeVideoFrameAtTime:(CMTime)time source:(NSString *)source {
  CFTimeInterval frameStart = CFAbsoluteTimeGetCurrent();
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
  CIImage *beautifiedFrontFrame = nil;
  NSInteger frontSeq = 0;
  NSInteger backSeq = 0;
  NSInteger beautifiedFrontSeq = 0;
  @synchronized(self) {
    frontFrame = self.latestFrontFrame;
    backFrame = self.latestBackFrame;
    beautifiedFrontFrame = self.latestFrontBeautifiedFrame;
    frontSeq = self.latestFrontFrameSequence;
    backSeq = self.latestBackFrameSequence;
    beautifiedFrontSeq = self.latestFrontBeautifiedFrameSequence;
  }

  CGSize outputSize = CGSizeEqualToSize(self.realtimeOutputSize, CGSizeZero)
    ? [self realtimeRecordingOutputSizeForAspectRatio:self.realtimeRecordingAspectRatio ?: self.saveAspectRatio
                                           landscape:[self isCurrentDeviceLandscape]]
    : self.realtimeOutputSize;
  DualCameraLayoutState *state = self.recordingLayoutState;
  if (!state) {
    state = [self currentLayoutStateForCanvasSize:self.canvasSizeAtRecording outputSize:outputSize];
  }
  BOOL useCachedBeauty = beautifiedFrontFrame != nil && beautifiedFrontSeq > 0;
  CIImage *frontForComposition = useCachedBeauty ? beautifiedFrontFrame : frontFrame;
  NSString *compositionSource = useCachedBeauty ? @"recording_cached_beauty" : @"recording";
  static BOOL didLogRecordingRoute = NO;
  if (!didLogRecordingRoute) {
    didLogRecordingRoute = YES;
    NSLog(@"[BeautyRoute] source=recording output=combined frontCamera=%@ backCamera=%@ frontSeq=%ld beautifiedFrontSeq=%ld backSeq=%ld usingCachedBeauty=%d postCompositeBeauty=never",
          frontForComposition ? @"front" : @"none",
          backFrame ? @"back" : @"none",
          (long)frontSeq,
          (long)beautifiedFrontSeq,
          (long)backSeq,
          useCachedBeauty);
  }
  CIImage *composited = [self compositedImageForLayoutState:state
                                                      front:frontForComposition
                                                       back:backFrame
                                                highQuality:NO
                                                     source:compositionSource];
  if (!composited) {
    self.realtimeDroppedFrameCount += 1;
    return;
  }
  composited = [self realtimeOutputAdjustedImage:composited];

  if (![self ensureRealtimeWriterStartedAtTime:time]) return;
  if (!self.realtimeVideoInput.isReadyForMoreMediaData) {
    self.realtimeDroppedFrameCount += 1;
    if (self.realtimeDroppedFrameCount <= 5 || self.realtimeDroppedFrameCount % 30 == 0) {
      NSLog(@"[DualCamera][VideoPerf] drop reason=writer_not_ready dropped=%ld written=%ld",
            (long)self.realtimeDroppedFrameCount,
            (long)self.realtimeWrittenVideoFrameCount);
    }
    return;
  }

  CVPixelBufferRef pixelBuffer = NULL;
  CVPixelBufferPoolRef pool = self.realtimePixelBufferAdaptor.pixelBufferPool;
  if (!pool || CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pixelBuffer) != kCVReturnSuccess || !pixelBuffer) {
    self.realtimeDroppedFrameCount += 1;
    return;
  }

  CGColorSpaceRef colorSpace = DualCameraCreateRealtimeRenderColorSpace();
  if (colorSpace) {
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, colorSpace, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
  }
  if (self.realtimeWrittenVideoFrameCount == 0) {
    NSDictionary *compression = self.realtimeVideoInput.outputSettings[AVVideoCompressionPropertiesKey];
    NSNumber *bitrate = compression[AVVideoAverageBitRateKey];
    id colorPrimaries = (__bridge id)CVBufferGetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, NULL);
    id transferFunction = (__bridge id)CVBufferGetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, NULL);
    id ycbcrMatrix = (__bridge id)CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    OSType outputPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    id outputColorSpace = DualCameraRecordingBufferAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey);
    NSLog(@"[DualCamera] Realtime first frame front=%.0fx%.0f back=%.0fx%.0f output=%.0fx%.0f bitrate=%@ colorPrimaries=%@ transfer=%@ matrix=%@",
          frontFrame.extent.size.width,
          frontFrame.extent.size.height,
          backFrame.extent.size.width,
          backFrame.extent.size.height,
          outputSize.width,
          outputSize.height,
          bitrate ?: @"unknown",
          colorPrimaries ?: @"unknown",
          transferFunction ?: @"unknown",
          ycbcrMatrix ?: @"unknown");
    NSLog(@"[DualCamera][QualityDiag] output pixelBuffer pixelFormat=%@ size=%zux%zu renderColorSpace=sRGB colorSpace=%@ primaries=%@ transfer=%@ matrix=%@",
          DualCameraRecordingFourCCString(outputPixelFormat),
          CVPixelBufferGetWidth(pixelBuffer),
          CVPixelBufferGetHeight(pixelBuffer),
          outputColorSpace ?: @"nil",
          colorPrimaries ?: @"nil",
          transferFunction ?: @"nil",
          ycbcrMatrix ?: @"nil");
  }
  [self.ciContext render:composited
         toCVPixelBuffer:pixelBuffer
                  bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
              colorSpace:colorSpace];
  if (colorSpace) {
    CGColorSpaceRelease(colorSpace);
  }

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
      dispatch_async(self.realtimeRenderQueue, ^{
        [self finishRealtimeRecording];
      });
    }
    CFTimeInterval frameMs = (CFAbsoluteTimeGetCurrent() - frameStart) * 1000.0;
    if (frameMs > 33.0 || self.realtimeWrittenVideoFrameCount == 1 || self.realtimeWrittenVideoFrameCount % 60 == 0) {
      NSLog(@"[DualCamera][VideoPerf] frameMs=%.2f written=%ld dropped=%ld source=%@",
            frameMs,
            (long)self.realtimeWrittenVideoFrameCount,
            (long)self.realtimeDroppedFrameCount,
            source ?: @"unknown");
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
  self.pendingStartRecordingAfterWarmup = NO;
  self.pendingStartRecordingCanvasSize = CGSizeZero;
  self.realtimeRecordingState = DualCameraRealtimeRecordingStateIdle;
  self.isDualRecordingActive = NO;
  [self updateDeviceOrientation:[UIDevice currentDevice].orientation];
}

#pragma mark - Event emission

- (void)emitRecordingFinished:(NSString *)uri {
  [[DualCameraEventEmitter shared] sendRecordingFinished:uri];
}

- (void)emitRecordingStarted {
  [[DualCameraEventEmitter shared] sendRecordingStarted];
}

- (void)emitRecordingError:(NSString *)error {
  NSLog(@"[DualCamera] Recording error: %@", error ?: @"Recording error");
  [[DualCameraEventEmitter shared] sendRecordingError:error details:nil];
}

- (void)emitRecordingError:(NSString *)error details:(NSDictionary *)details {
  NSLog(@"[DualCamera] Recording error: %@ details=%@", error ?: @"Recording error", details ?: @{});
  [[DualCameraEventEmitter shared] sendRecordingError:error details:details];
}

- (void)emitRecordingErrorForError:(NSError *)error
                            prefix:(NSString *)prefix
                           context:(NSString *)context
                       rejectedPTS:(CMTime)rejectedPTS {
  NSString *message = error.localizedDescription ?: prefix ?: @"Recording error";
  NSDictionary *details = [self recordingErrorDetailsForError:error context:context rejectedPTS:rejectedPTS];
  [self emitRecordingError:message details:details];
}

@end
