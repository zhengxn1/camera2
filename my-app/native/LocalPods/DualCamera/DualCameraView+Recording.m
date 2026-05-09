#import "DualCameraView+Recording.h"
#import "DualCameraView_Internal.h"

static NSString *DCRealtimeWriterStatusString(AVAssetWriterStatus status) {
  switch (status) {
    case AVAssetWriterStatusUnknown: return @"unknown";
    case AVAssetWriterStatusWriting: return @"writing";
    case AVAssetWriterStatusCompleted: return @"completed";
    case AVAssetWriterStatusFailed: return @"failed";
    case AVAssetWriterStatusCancelled: return @"cancelled";
  }
  return @"unknown";
}

@implementation DualCameraView (Recording)

#pragma mark - State machine

- (NSDictionary *)realtimeVideoSettingsForOutputSize:(CGSize)outputSize {
  return @{
    AVVideoCodecKey: AVVideoCodecTypeH264,
    AVVideoWidthKey: @(outputSize.width),
    AVVideoHeightKey: @(outputSize.height),
    AVVideoColorPropertiesKey: @{
      AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
      AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
      AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    },
    AVVideoCompressionPropertiesKey: @{
      AVVideoAverageBitRateKey: @(12000000),
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
  NSInteger traceID = self.realtimeRecordingTraceID;
  NSTimeInterval requestTime = self.realtimeRecordingRequestTime;
  NSTimeInterval prepareCallTime = CFAbsoluteTimeGetCurrent();
  if (CGSizeEqualToSize(canvasSize, CGSizeZero)) {
    NSLog(@"[DualCamera][RecordTrace #%ld] warmup skipped: zero canvas", (long)traceID);
    return;
  }
  if (!self.usingMultiCam || !self.isConfigured) {
    NSLog(@"[DualCamera][RecordTrace #%ld] warmup skipped: usingMultiCam=%d configured=%d",
          (long)traceID, self.usingMultiCam, self.isConfigured);
    return;
  }

  NSString *aspectRatio = self.saveAspectRatio ?: @"9:16";
  DualCameraDeviceOrientation orientation = self.deviceOrientation;
  CGSize outputSize = [self realtimeRecordingOutputSizeForAspectRatio:aspectRatio
                                                             landscape:[self isDeviceOrientationLandscape:orientation]];
  CIImage *frontFrame = nil;
  CIImage *backFrame = nil;
  @synchronized(self) {
    frontFrame = self.latestFrontFrame;
    backFrame = self.latestBackFrame;
  }
  @synchronized(self) {
    BOOL canReuseWarmup = [self canUseWarmedRealtimePipelineForAspectRatio:aspectRatio canvasSize:canvasSize outputSize:outputSize];
    if (canReuseWarmup || self.realtimePipelineWarmupInProgress) {
      NSLog(@"[DualCamera][RecordTrace #%ld] warmup skipped: reusable=%d inProgress=%d aspect=%@ canvas=%@ output=%@ sinceRequest=%.3fs",
            (long)traceID, canReuseWarmup, self.realtimePipelineWarmupInProgress, aspectRatio,
            NSStringFromCGSize(canvasSize), NSStringFromCGSize(outputSize),
            requestTime > 0 ? prepareCallTime - requestTime : -1);
      return;
    }
    self.realtimePipelineWarmupInProgress = YES;
  }
  NSLog(@"[DualCamera][RecordTrace #%ld] warmup queued aspect=%@ orientation=%ld canvas=%@ output=%@ hasFront=%d hasBack=%d sinceRequest=%.3fs",
        (long)traceID, aspectRatio, (long)orientation, NSStringFromCGSize(canvasSize),
        NSStringFromCGSize(outputSize), frontFrame != nil, backFrame != nil,
        requestTime > 0 ? prepareCallTime - requestTime : -1);

  dispatch_async(self.realtimeRenderQueue, ^{
    NSTimeInterval warmupStartTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"[DualCamera][RecordTrace #%ld] warmup begin on render queue queueDelay=%.3fs",
          (long)traceID, warmupStartTime - prepareCallTime);
    NSDictionary *videoSettings = [self realtimeVideoSettingsForOutputSize:outputSize];
    NSDictionary *pixelAttrs = [self realtimePixelBufferAttributesForOutputSize:outputSize];
    NSDictionary *audioSettings = [self realtimeAudioSettings];
    DualCameraLayoutState *warmupState = [self layoutStateSnapshotForCanvasSize:canvasSize
                                                                     outputSize:outputSize
                                                                    orientation:orientation];
    warmupState.frontMirrored = self.frontPreviewMirrored;
    warmupState.backMirrored = self.backPreviewMirrored;
    CIImage *warmupImage = nil;
    if (frontFrame && backFrame) {
      NSTimeInterval composeStart = CFAbsoluteTimeGetCurrent();
      warmupImage = [self compositedImageForLayoutState:warmupState
                                                  front:frontFrame
                                                   back:backFrame];
      NSLog(@"[DualCamera][RecordTrace #%ld] warmup compose done source=latestFrames duration=%.3fs image=%d",
            (long)traceID, CFAbsoluteTimeGetCurrent() - composeStart, warmupImage != nil);
    }
    if (!warmupImage) {
      warmupImage = [self blackCanvasSize:outputSize];
      NSLog(@"[DualCamera][RecordTrace #%ld] warmup using black fallback image=%d",
            (long)traceID, warmupImage != nil);
    }

    CVPixelBufferRef scratchBuffer = NULL;
    NSTimeInterval scratchStart = CFAbsoluteTimeGetCurrent();
    CVReturn createStatus = CVPixelBufferCreate(kCFAllocatorDefault,
                                                (size_t)outputSize.width,
                                                (size_t)outputSize.height,
                                                kCVPixelFormatType_32BGRA,
                                                (__bridge CFDictionaryRef)pixelAttrs,
                                                &scratchBuffer);
    if (createStatus == kCVReturnSuccess && scratchBuffer) {
      CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      [self.ciContext render:warmupImage
             toCVPixelBuffer:scratchBuffer
                      bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
                  colorSpace:colorSpace];
      if (colorSpace) {
        CGColorSpaceRelease(colorSpace);
      }
      CVPixelBufferRelease(scratchBuffer);
    }
    NSLog(@"[DualCamera][RecordTrace #%ld] warmup scratch render status=%d duration=%.3fs",
          (long)traceID, createStatus, CFAbsoluteTimeGetCurrent() - scratchStart);

    NSString *warmupPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dual_realtime_warmup.mp4"];
    NSURL *warmupURL = [NSURL fileURLWithPath:warmupPath];
    [[NSFileManager defaultManager] removeItemAtURL:warmupURL error:nil];
    NSError *writerError = nil;
    NSTimeInterval writerCreateStart = CFAbsoluteTimeGetCurrent();
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:warmupURL fileType:AVFileTypeMPEG4 error:&writerError];
    NSLog(@"[DualCamera][RecordTrace #%ld] warmup writer created writer=%d status=%@ error=%@ duration=%.3fs",
          (long)traceID, writer != nil, writer ? DCRealtimeWriterStatusString(writer.status) : @"nil",
          writerError, CFAbsoluteTimeGetCurrent() - writerCreateStart);
    AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    videoInput.expectsMediaDataInRealTime = YES;
    __block BOOL writerWarmupSucceeded = NO;
    if (writer && [writer canAddInput:videoInput]) {
      [writer addInput:videoInput];
      AVAssetWriterInputPixelBufferAdaptor *adaptor =
        [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoInput
                                                                         sourcePixelBufferAttributes:pixelAttrs];
      CVPixelBufferPoolRef pool = adaptor.pixelBufferPool;
      if (pool) {
        CVPixelBufferRef poolBuffer = NULL;
        NSTimeInterval poolStart = CFAbsoluteTimeGetCurrent();
        if (CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &poolBuffer) == kCVReturnSuccess && poolBuffer) {
          NSLog(@"[DualCamera][RecordTrace #%ld] warmup pool buffer created duration=%.3fs",
                (long)traceID, CFAbsoluteTimeGetCurrent() - poolStart);
          NSTimeInterval poolRenderStart = CFAbsoluteTimeGetCurrent();
          CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
          [self.ciContext render:warmupImage
                 toCVPixelBuffer:poolBuffer
                          bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
                      colorSpace:colorSpace];
          if (colorSpace) {
            CGColorSpaceRelease(colorSpace);
          }
          NSLog(@"[DualCamera][RecordTrace #%ld] warmup pool render done duration=%.3fs",
                (long)traceID, CFAbsoluteTimeGetCurrent() - poolRenderStart);

          NSTimeInterval startWritingStart = CFAbsoluteTimeGetCurrent();
          if ([writer startWriting]) {
            NSLog(@"[DualCamera][RecordTrace #%ld] warmup startWriting ok duration=%.3fs status=%@",
                  (long)traceID, CFAbsoluteTimeGetCurrent() - startWritingStart,
                  DCRealtimeWriterStatusString(writer.status));
            [writer startSessionAtSourceTime:kCMTimeZero];
            NSTimeInterval appendStart = CFAbsoluteTimeGetCurrent();
            if (videoInput.isReadyForMoreMediaData &&
                [adaptor appendPixelBuffer:poolBuffer withPresentationTime:kCMTimeZero]) {
              NSLog(@"[DualCamera][RecordTrace #%ld] warmup append ok duration=%.3fs status=%@",
                    (long)traceID, CFAbsoluteTimeGetCurrent() - appendStart,
                    DCRealtimeWriterStatusString(writer.status));
              [videoInput markAsFinished];
              dispatch_semaphore_t finishSemaphore = dispatch_semaphore_create(0);
              NSTimeInterval finishStart = CFAbsoluteTimeGetCurrent();
              [writer finishWritingWithCompletionHandler:^{
                writerWarmupSucceeded = (writer.status == AVAssetWriterStatusCompleted);
                NSLog(@"[DualCamera][RecordTrace #%ld] warmup finish callback success=%d status=%@ error=%@ duration=%.3fs",
                      (long)traceID, writerWarmupSucceeded, DCRealtimeWriterStatusString(writer.status),
                      writer.error, CFAbsoluteTimeGetCurrent() - finishStart);
                dispatch_semaphore_signal(finishSemaphore);
              }];
              dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC));
              if (dispatch_semaphore_wait(finishSemaphore, timeout) != 0) {
                [writer cancelWriting];
                writerWarmupSucceeded = NO;
                NSLog(@"[DualCamera][RecordTrace #%ld] warmup finish timeout status=%@ error=%@",
                      (long)traceID, DCRealtimeWriterStatusString(writer.status), writer.error);
              }
              if (!writerWarmupSucceeded) {
                writerError = writer.error;
              }
            } else {
              writerError = writer.error;
              NSLog(@"[DualCamera][RecordTrace #%ld] warmup append failed ready=%d status=%@ error=%@",
                    (long)traceID, videoInput.isReadyForMoreMediaData,
                    DCRealtimeWriterStatusString(writer.status), writerError);
              [writer cancelWriting];
            }
          } else {
            writerError = writer.error;
            NSLog(@"[DualCamera][RecordTrace #%ld] warmup startWriting failed status=%@ error=%@ duration=%.3fs",
                  (long)traceID, DCRealtimeWriterStatusString(writer.status), writerError,
                  CFAbsoluteTimeGetCurrent() - startWritingStart);
          }
          CVPixelBufferRelease(poolBuffer);
        } else {
          NSLog(@"[DualCamera][RecordTrace #%ld] warmup pool buffer failed duration=%.3fs",
                (long)traceID, CFAbsoluteTimeGetCurrent() - poolStart);
        }
      } else {
        NSLog(@"[DualCamera][RecordTrace #%ld] warmup missing pixelBufferPool", (long)traceID);
      }
    } else {
      NSLog(@"[DualCamera][RecordTrace #%ld] warmup cannot add input writer=%d error=%@",
            (long)traceID, writer != nil, writerError);
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
    NSLog(@"[DualCamera][RecordTrace #%ld] warmup end success=%d aspect=%@ canvas=%@ output=%@ scratch=%d writerWarm=%d writerErr=%@ total=%.3fs",
          (long)traceID, warmupSucceeded, aspectRatio, NSStringFromCGSize(canvasSize),
          NSStringFromCGSize(outputSize), createStatus, writerWarmupSucceeded, writerError,
          CFAbsoluteTimeGetCurrent() - warmupStartTime);
  });
}

- (BOOL)startRealtimeRecordingWithCanvasSize:(CGSize)canvasSize {
  NSInteger traceID = self.realtimeRecordingTraceID;
  NSTimeInterval startCallTime = CFAbsoluteTimeGetCurrent();
  if (self.realtimeRecordingState != DualCameraRealtimeRecordingStateIdle || self.realtimeAssetWriter) {
    NSLog(@"[DualCamera][RecordTrace #%ld] start skipped state=%ld hasWriter=%d sinceRequest=%.3fs",
          (long)traceID, (long)self.realtimeRecordingState, self.realtimeAssetWriter != nil,
          self.realtimeRecordingRequestTime > 0 ? startCallTime - self.realtimeRecordingRequestTime : -1);
    return NO;
  }

  NSString *path = [self documentsPathWithPrefix:@"dual_realtime_"];
  NSURL *url = [NSURL fileURLWithPath:path];
  [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

  NSError *error = nil;
  NSTimeInterval writerCreateStart = CFAbsoluteTimeGetCurrent();
  AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&error];
  if (!writer || error) {
    NSLog(@"[DualCamera][RecordTrace #%ld] start failed creating writer error=%@ duration=%.3fs",
          (long)traceID, error, CFAbsoluteTimeGetCurrent() - writerCreateStart);
    [self emitRecordingError:error.localizedDescription ?: @"Failed to create realtime video writer."];
    return NO;
  }
  NSLog(@"[DualCamera][RecordTrace #%ld] start writer created status=%@ duration=%.3fs",
        (long)traceID, DCRealtimeWriterStatusString(writer.status), CFAbsoluteTimeGetCurrent() - writerCreateStart);

  NSString *aspectRatio = self.saveAspectRatio ?: @"9:16";
  DualCameraDeviceOrientation recordingOrientation = self.deviceOrientation;
  CGSize outputSize = [self realtimeRecordingOutputSizeForAspectRatio:aspectRatio
                                                             landscape:[self isDeviceOrientationLandscape:recordingOrientation]];
  BOOL useWarmSettings = [self canUseWarmedRealtimePipelineForAspectRatio:aspectRatio
                                                               canvasSize:canvasSize
                                                               outputSize:outputSize];
  NSLog(@"[DualCamera][RecordTrace #%ld] start configuring aspect=%@ orientation=%ld canvas=%@ output=%@ useWarm=%d warmed=%d warmInProgress=%d sinceRequest=%.3fs",
        (long)traceID, aspectRatio, (long)recordingOrientation, NSStringFromCGSize(canvasSize),
        NSStringFromCGSize(outputSize), useWarmSettings, self.realtimePipelineWarmed,
        self.realtimePipelineWarmupInProgress,
        self.realtimeRecordingRequestTime > 0 ? startCallTime - self.realtimeRecordingRequestTime : -1);
  DualCameraLayoutState *recordingState = [self layoutStateSnapshotForCanvasSize:canvasSize
                                                                       outputSize:outputSize
                                                                      orientation:recordingOrientation];
  // WYSIWYG: realtime dual recording is composited from VideoDataOutput frames
  // and should match the visible preview.  The front preview is mirrored by
  // default, while frontOutputMirrored intentionally remains off for single
  // camera photo/movie export semantics.
  recordingState.frontMirrored = self.frontPreviewMirrored;
  recordingState.backMirrored = self.backPreviewMirrored;
  NSDictionary *videoSettings = useWarmSettings
    ? self.warmedRealtimeVideoSettings
    : [self realtimeVideoSettingsForOutputSize:outputSize];
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
    NSLog(@"[DualCamera][RecordTrace #%ld] start rejected video input status=%@ error=%@",
          (long)traceID, DCRealtimeWriterStatusString(writer.status), writer.error);
    [self emitRecordingError:@"Realtime video writer rejected the video input."];
    return NO;
  }
  [writer addInput:videoInput];

  if ([writer canAddInput:audioInput]) {
    [writer addInput:audioInput];
  } else {
    NSLog(@"[DualCamera][RecordTrace #%ld] start rejected audio input; recording video only status=%@ error=%@",
          (long)traceID, DCRealtimeWriterStatusString(writer.status), writer.error);
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
  self.realtimeRecordingPreparedTime = CFAbsoluteTimeGetCurrent();
  self.realtimeWriterStartedTime = 0;
  self.canvasSizeAtRecording = canvasSize;
  self.isDualRecordingActive = YES;

  NSDictionary<NSString *, NSValue *> *recordingRects = [self rectsForLayoutState:recordingState canvasSize:outputSize];
  NSLog(@"[DualCamera][RecordTrace #%ld] prepared path=%@ layout=%@ aspect=%@ output=%.0fx%.0f canvas=%.0fx%.0f landscape=%d hardwareCost=%.3f systemPressureCost=%.3f backRect=%@ frontRect=%@ duration=%.3fs sinceRequest=%.3fs",
        (long)traceID, path, recordingState.layoutMode, aspectRatio, outputSize.width, outputSize.height,
        canvasSize.width, canvasSize.height, recordingState.isLandscape,
        self.multiCamSession.hardwareCost, self.multiCamSession.systemPressureCost,
        NSStringFromCGRect([recordingRects[@"back"] CGRectValue]),
        NSStringFromCGRect([recordingRects[@"front"] CGRectValue]),
        self.realtimeRecordingPreparedTime - startCallTime,
        self.realtimeRecordingRequestTime > 0 ? self.realtimeRecordingPreparedTime - self.realtimeRecordingRequestTime : -1);
  NSLog(@"[DualCamera][RecordTrace #%ld] warm settings used=%d", (long)traceID, useWarmSettings);
  return YES;
}

- (BOOL)ensureRealtimeWriterStartedAtTime:(CMTime)time {
  if (self.realtimeWriterStarted) return YES;
  if (!self.realtimeAssetWriter) return NO;
  if (CMTIME_IS_INVALID(time)) return NO;

  NSInteger traceID = self.realtimeRecordingTraceID;
  NSTimeInterval startWritingStart = CFAbsoluteTimeGetCurrent();
  NSLog(@"[DualCamera][RecordTrace #%ld] writer startWriting begin pts=%.6f sincePrepared=%.3fs sinceRequest=%.3fs",
        (long)traceID, CMTimeGetSeconds(time),
        self.realtimeRecordingPreparedTime > 0 ? startWritingStart - self.realtimeRecordingPreparedTime : -1,
        self.realtimeRecordingRequestTime > 0 ? startWritingStart - self.realtimeRecordingRequestTime : -1);
  if (![self.realtimeAssetWriter startWriting]) {
    NSLog(@"[DualCamera][RecordTrace #%ld] writer startWriting failed status=%@ error=%@ duration=%.3fs",
          (long)traceID, DCRealtimeWriterStatusString(self.realtimeAssetWriter.status),
          self.realtimeAssetWriter.error, CFAbsoluteTimeGetCurrent() - startWritingStart);
    [self failRealtimeRecording:self.realtimeAssetWriter.error.localizedDescription ?: @"Realtime writer failed to start."];
    return NO;
  }
  [self.realtimeAssetWriter startSessionAtSourceTime:time];
  self.realtimeWriterStarted = YES;
  self.realtimeWriterStartedTime = CFAbsoluteTimeGetCurrent();
  NSLog(@"[DualCamera][RecordTrace #%ld] writer started status=%@ duration=%.3fs",
        (long)traceID, DCRealtimeWriterStatusString(self.realtimeAssetWriter.status),
        self.realtimeWriterStartedTime - startWritingStart);
  return YES;
}

- (void)appendRealtimeVideoFrameAtTime:(CMTime)time source:(NSString *)source {
  if (!self.isDualRecordingActive || self.realtimeFinishRequested) return;
  if (self.realtimeRecordingState != DualCameraRealtimeRecordingStatePrepared &&
      self.realtimeRecordingState != DualCameraRealtimeRecordingStateWriting) {
    return;
  }
  NSInteger traceID = self.realtimeRecordingTraceID;
  BOOL shouldTraceFrame = self.realtimeWrittenVideoFrameCount < 3;
  NSTimeInterval frameStart = CFAbsoluteTimeGetCurrent();
  if (shouldTraceFrame) {
    NSLog(@"[DualCamera][RecordTrace #%ld] frame begin index=%ld source=%@ pts=%.6f state=%ld writerStarted=%d sincePrepared=%.3fs",
          (long)traceID, (long)self.realtimeWrittenVideoFrameCount + 1, source ?: @"unknown",
          CMTimeGetSeconds(time), (long)self.realtimeRecordingState, self.realtimeWriterStarted,
          self.realtimeRecordingPreparedTime > 0 ? frameStart - self.realtimeRecordingPreparedTime : -1);
  }
  if (self.realtimeAssetWriter.status == AVAssetWriterStatusFailed) {
    NSLog(@"[DualCamera][RecordTrace #%ld] frame abort writer failed error=%@",
          (long)traceID, self.realtimeAssetWriter.error);
    [self failRealtimeRecording:self.realtimeAssetWriter.error.localizedDescription ?: @"Realtime writer failed."];
    return;
  }
  if (!CMTIME_IS_VALID(time)) {
    self.realtimeDroppedFrameCount += 1;
    NSLog(@"[DualCamera][RecordTrace #%ld] frame dropped invalid pts dropped=%ld",
          (long)traceID, (long)self.realtimeDroppedFrameCount);
    return;
  }
  if (self.hasLastRealtimeVideoPTS && CMTIME_COMPARE_INLINE(time, <=, self.lastRealtimeVideoPTS)) {
    self.realtimeDroppedFrameCount += 1;
    NSLog(@"[DualCamera][RecordTrace #%ld] frame dropped non-monotonic source=%@ incoming=%.6f last=%.6f dropped=%ld",
          (long)traceID, source ?: @"unknown", CMTimeGetSeconds(time),
          CMTimeGetSeconds(self.lastRealtimeVideoPTS), (long)self.realtimeDroppedFrameCount);
    return;
  }

  CIImage *frontFrame = nil;
  CIImage *backFrame = nil;
  @synchronized(self) {
    frontFrame = self.latestFrontFrame;
    backFrame = self.latestBackFrame;
  }
  if (shouldTraceFrame) {
    NSLog(@"[DualCamera][RecordTrace #%ld] frame source frames front=%d back=%d",
          (long)traceID, frontFrame != nil, backFrame != nil);
  }

  CGSize outputSize = CGSizeEqualToSize(self.realtimeOutputSize, CGSizeZero)
    ? [self realtimeRecordingOutputSizeForAspectRatio:self.realtimeRecordingAspectRatio ?: self.saveAspectRatio
                                           landscape:[self isCurrentDeviceLandscape]]
    : self.realtimeOutputSize;
  DualCameraLayoutState *state = self.recordingLayoutState;
  if (!state) {
    state = [self currentLayoutStateForCanvasSize:self.canvasSizeAtRecording outputSize:outputSize];
  }
  NSTimeInterval composeStart = CFAbsoluteTimeGetCurrent();
  CIImage *composited = [self compositedImageForLayoutState:state front:frontFrame back:backFrame];
  if (shouldTraceFrame) {
    NSLog(@"[DualCamera][RecordTrace #%ld] frame compose image=%d duration=%.3fs",
          (long)traceID, composited != nil, CFAbsoluteTimeGetCurrent() - composeStart);
  }
  if (!composited) {
    self.realtimeDroppedFrameCount += 1;
    NSLog(@"[DualCamera][RecordTrace #%ld] frame dropped: composition returned nil dropped=%ld",
          (long)traceID, (long)self.realtimeDroppedFrameCount);
    return;
  }

  if (![self ensureRealtimeWriterStartedAtTime:time]) return;
  if (!self.realtimeVideoInput.isReadyForMoreMediaData) {
    self.realtimeDroppedFrameCount += 1;
    NSLog(@"[DualCamera][RecordTrace #%ld] frame dropped: input not ready status=%@ dropped=%ld",
          (long)traceID, DCRealtimeWriterStatusString(self.realtimeAssetWriter.status),
          (long)self.realtimeDroppedFrameCount);
    return;
  }

  CVPixelBufferRef pixelBuffer = NULL;
  CVPixelBufferPoolRef pool = self.realtimePixelBufferAdaptor.pixelBufferPool;
  if (!pool || CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pixelBuffer) != kCVReturnSuccess || !pixelBuffer) {
    self.realtimeDroppedFrameCount += 1;
    NSLog(@"[DualCamera][RecordTrace #%ld] frame dropped: pixel buffer unavailable pool=%d dropped=%ld",
          (long)traceID, pool != NULL, (long)self.realtimeDroppedFrameCount);
    return;
  }

  NSTimeInterval renderStart = CFAbsoluteTimeGetCurrent();
  CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  if (colorSpace) {
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, colorSpace, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
  }
  [self.ciContext render:composited
         toCVPixelBuffer:pixelBuffer
                  bounds:CGRectMake(0, 0, outputSize.width, outputSize.height)
              colorSpace:colorSpace];
  if (colorSpace) {
    CGColorSpaceRelease(colorSpace);
  }
  if (shouldTraceFrame) {
    NSLog(@"[DualCamera][RecordTrace #%ld] frame render duration=%.3fs",
          (long)traceID, CFAbsoluteTimeGetCurrent() - renderStart);
  }

  NSTimeInterval appendStart = CFAbsoluteTimeGetCurrent();
  if (![self.realtimePixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time]) {
    self.realtimeDroppedFrameCount += 1;
    NSLog(@"[DualCamera][RecordTrace #%ld] frame append failed status=%@ error=%@ duration=%.3fs dropped=%ld",
          (long)traceID, DCRealtimeWriterStatusString(self.realtimeAssetWriter.status),
          self.realtimeAssetWriter.error, CFAbsoluteTimeGetCurrent() - appendStart,
          (long)self.realtimeDroppedFrameCount);
    [self failRealtimeRecording:self.realtimeAssetWriter.error.localizedDescription ?: @"Failed to append realtime video frame."];
  } else {
    self.lastRealtimeVideoPTS = time;
    self.hasLastRealtimeVideoPTS = YES;
    self.realtimeWrittenVideoFrameCount += 1;
    self.realtimeRecordingState = DualCameraRealtimeRecordingStateWriting;
    if (shouldTraceFrame) {
      NSLog(@"[DualCamera][RecordTrace #%ld] frame appended index=%ld append=%.3fs total=%.3fs sinceWriterStart=%.3fs",
            (long)traceID, (long)self.realtimeWrittenVideoFrameCount,
            CFAbsoluteTimeGetCurrent() - appendStart,
            CFAbsoluteTimeGetCurrent() - frameStart,
            self.realtimeWriterStartedTime > 0 ? CFAbsoluteTimeGetCurrent() - self.realtimeWriterStartedTime : -1);
    }
    if (!self.realtimeRecordingStartedEventEmitted) {
      self.realtimeRecordingStartedEventEmitted = YES;
      NSLog(@"[DualCamera][RecordTrace #%ld] emit recording started written=%ld sinceRequest=%.3fs",
            (long)traceID, (long)self.realtimeWrittenVideoFrameCount,
            self.realtimeRecordingRequestTime > 0 ? CFAbsoluteTimeGetCurrent() - self.realtimeRecordingRequestTime : -1);
      [self emitRecordingStarted];
    }
    if (self.realtimeFinishWhenFirstFrameWritten && self.realtimeWrittenVideoFrameCount > 0) {
      self.realtimeFinishWhenFirstFrameWritten = NO;
      dispatch_async(self.realtimeRenderQueue, ^{
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
  NSInteger traceID = self.realtimeRecordingTraceID;
  NSLog(@"[DualCamera][RecordTrace #%ld] finish requested state=%ld writerStatus=%@ active=%d written=%ld dropped=%ld audioDropped=%ld",
        (long)traceID, (long)self.realtimeRecordingState,
        self.realtimeAssetWriter ? DCRealtimeWriterStatusString(self.realtimeAssetWriter.status) : @"nil",
        self.isDualRecordingActive, (long)self.realtimeWrittenVideoFrameCount,
        (long)self.realtimeDroppedFrameCount, (long)self.realtimeDroppedAudioSampleCount);
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
    NSLog(@"[DualCamera][RecordTrace #%ld] finish deferred until first frame state=%ld writerStatus=%@ written=%ld",
          (long)traceID, (long)self.realtimeRecordingState,
          DCRealtimeWriterStatusString(writer.status), (long)written);
    return;
  }

  self.realtimeFinishRequested = YES;
  self.isDualRecordingActive = NO;

  self.realtimeRecordingState = DualCameraRealtimeRecordingStateFinishing;
  [videoInput markAsFinished];
  if (audioInput) [audioInput markAsFinished];
  NSTimeInterval finishStart = CFAbsoluteTimeGetCurrent();
  [writer finishWritingWithCompletionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      if (writer.status == AVAssetWriterStatusCompleted) {
        NSLog(@"[DualCamera][RecordTrace #%ld] finish completed path=%@ written=%ld dropped=%ld audioDropped=%ld duration=%.3fs totalSinceRequest=%.3fs",
              (long)traceID, path, (long)written, (long)dropped, (long)audioDropped,
              CFAbsoluteTimeGetCurrent() - finishStart,
              self.realtimeRecordingRequestTime > 0 ? CFAbsoluteTimeGetCurrent() - self.realtimeRecordingRequestTime : -1);
        [self resetRealtimeRecordingContext];
        [self emitRecordingFinished:[NSString stringWithFormat:@"file://%@", path]];
      } else {
        NSString *message = writer.error.localizedDescription ?: @"Realtime recording failed.";
        NSLog(@"[DualCamera][RecordTrace #%ld] finish failed status=%@ error=%@ duration=%.3fs",
              (long)traceID, DCRealtimeWriterStatusString(writer.status), writer.error,
              CFAbsoluteTimeGetCurrent() - finishStart);
        NSDictionary *details = [self recordingErrorDetailsForError:writer.error context:@"finish_completion_failed" rejectedPTS:kCMTimeInvalid];
        [self resetRealtimeRecordingContext];
        [self emitRecordingError:message details:details];
      }
    });
  }];
}

- (void)failRealtimeRecording:(NSString *)message {
  if (self.realtimeRecordingState == DualCameraRealtimeRecordingStateIdle) return;
  NSLog(@"[DualCamera][RecordTrace #%ld] fail message=%@ state=%ld writerStatus=%@ error=%@",
        (long)self.realtimeRecordingTraceID, message ?: @"nil", (long)self.realtimeRecordingState,
        self.realtimeAssetWriter ? DCRealtimeWriterStatusString(self.realtimeAssetWriter.status) : @"nil",
        self.realtimeAssetWriter.error);
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
  self.realtimeRecordingRequestTime = 0;
  self.realtimeRecordingPreparedTime = 0;
  self.realtimeWriterStartedTime = 0;
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
