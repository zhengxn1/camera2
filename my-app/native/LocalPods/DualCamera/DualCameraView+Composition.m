#import "DualCameraView+Composition.h"
#import "DualCameraView_Internal.h"

@implementation DualCameraView (Composition)

#pragma mark - Canvas helpers

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

- (CIImage *)clearCanvasSize:(CGSize)size {
  CIFilter *colorGen = [CIFilter filterWithName:@"CIConstantColorGenerator"];
  [colorGen setValue:[CIColor colorWithRed:0 green:0 blue:0 alpha:0] forKey:kCIInputColorKey];
  return [colorGen.outputImage imageByCroppingToRect:CGRectMake(0, 0, size.width, size.height)];
}

- (CIImage *)scaledCIImage:(CIImage *)image toSize:(CGSize)size {
  return [self scaledCIImage:image toSize:size highQuality:NO];
}

- (CIImage *)scaledCIImage:(CIImage *)image toSize:(CGSize)size highQuality:(BOOL)highQuality {
  CGFloat scaleX = size.width / image.extent.size.width;
  CGFloat scaleY = size.height / image.extent.size.height;

  CIImage *result = nil;
  if (highQuality) {
    // Lanczos preserves edge sharpness when downscaling photo-sized buffers.
    // Approximated as: uniform scale Y, then aspect ratio adjustment in X.
    CIFilter *lanczos = [CIFilter filterWithName:@"CILanczosScaleTransform"];
    [lanczos setValue:image forKey:kCIInputImageKey];
    [lanczos setValue:@(scaleY) forKey:kCIInputScaleKey];
    [lanczos setValue:@(scaleY != 0 ? scaleX / scaleY : 1.0) forKey:kCIInputAspectRatioKey];
    result = lanczos.outputImage;
  }

  if (!result) {
    CIFilter *transformFilter = [CIFilter filterWithName:@"CIAffineTransform"];
    [transformFilter setValue:image forKey:kCIInputImageKey];
    [transformFilter setValue:[NSValue valueWithCGAffineTransform:CGAffineTransformMakeScale(scaleX, scaleY)] forKey:kCIInputTransformKey];
    result = transformFilter.outputImage;
  }
  if (!result) return image;
  CGFloat offsetX = -result.extent.origin.x;
  CGFloat offsetY = -result.extent.origin.y;
  if (offsetX != 0 || offsetY != 0) {
    result = [result imageByApplyingTransform:CGAffineTransformMakeTranslation(offsetX, offsetY)];
  }
  return result;
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

- (CIImage *)beautifiedFrontImage:(CIImage *)image {
  return [self beautifiedFrontImage:image source:@"unknown"];
}

- (CIImage *)beautifiedFrontImage:(CIImage *)image source:(NSString *)source {
  return [self beautifiedImage:image cameraSource:@"front" usage:source ?: @"unknown"];
}

- (CIImage *)beautifiedImage:(CIImage *)image
                cameraSource:(NSString *)cameraSource
                       usage:(NSString *)usage {
  if (!image) return image;

  BOOL isFrontCamera = [cameraSource isEqualToString:@"front"];
  BOOL isRealtimeRecording = [usage isEqualToString:@"recording"] ||
    [usage isEqualToString:@"recording_preview"];
  CGFloat smooth = MAX(0, MIN(100, self.frontBeautySmooth)) / 100.0;
  CGFloat brighten = MAX(0, MIN(100, self.frontBeautyBrighten)) / 100.0;
  CGFloat whiten = MAX(0, MIN(100, self.frontBeautyWhiten)) / 100.0;

  static NSMutableSet<NSString *> *loggedSources = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    loggedSources = [NSMutableSet set];
  });
  NSString *logKey = [NSString stringWithFormat:@"%@:%@", usage ?: @"unknown", cameraSource ?: @"unknown"];
  void (^logBeautyProcess)(NSString *, NSString *, CIImage *) = ^(NSString *pipeline, NSString *reason, CIImage *outputImage) {
    @synchronized(loggedSources) {
      if (![loggedSources containsObject:logKey]) {
        [loggedSources addObject:logKey];
        NSLog(@"[BeautyProcess] usage=%@ cameraSource=%@ pipeline=%@ reason=%@ smooth=%.1f brighten=%.1f whiten=%.1f input=%.0fx%.0f output=%.0fx%.0f",
              usage ?: @"unknown", cameraSource ?: @"unknown", pipeline ?: @"raw", reason ?: @"unknown",
              self.frontBeautySmooth, self.frontBeautyBrighten, self.frontBeautyWhiten,
              image.extent.size.width, image.extent.size.height,
              outputImage.extent.size.width, outputImage.extent.size.height);
      }
    }
  };

  if (!isFrontCamera) {
    logBeautyProcess(@"raw", @"camera_source_not_front", image);
    return image;
  }
  if (!self.frontBeautyEnabled) {
    logBeautyProcess(@"raw", @"disabled", image);
    return image;
  }
  if (smooth <= 0 && brighten <= 0 && whiten <= 0) {
    logBeautyProcess(@"raw", @"zero_params", image);
    return image;
  }

  NSString *pipeline = @"gpupixel";
  NSString *reason = [usage isEqualToString:@"recording_preview"]
    ? @"recording_preview_cached_gpupixel"
    : ([usage isEqualToString:@"recording"] ? @"recording_cached_gpupixel" : @"ok");
  CIImage *result = image;
  CIImage *gpupixelImage = [self.gpupixelBeautyAdapter processFrontImage:image];
  if (gpupixelImage) {
    result = gpupixelImage;
  } else {
    pipeline = @"coreimage";
    reason = @"gpupixel_unavailable";
    static BOOL didLogGPUPixelFallback = NO;
    if (!didLogGPUPixelFallback) {
      didLogGPUPixelFallback = YES;
      NSLog(@"[DualCamera][GPUPixel] using Core Image beauty fallback");
    }
  }

  BOOL useRealtimeFallbackTuning = [pipeline isEqualToString:@"coreimage"] && isRealtimeRecording;

  if ([pipeline isEqualToString:@"coreimage"] && smooth > 0) {
    CIFilter *noise = [CIFilter filterWithName:@"CINoiseReduction"];
    [noise setValue:result forKey:kCIInputImageKey];
    CGFloat noiseLevel = useRealtimeFallbackTuning ? (0.012 + smooth * 0.05) : (0.006 + smooth * 0.032);
    CGFloat sharpness = useRealtimeFallbackTuning ? (0.28 + (1.0 - smooth) * 0.22) : (0.36 + (1.0 - smooth) * 0.28);
    [noise setValue:@(noiseLevel) forKey:@"inputNoiseLevel"];
    [noise setValue:@(sharpness) forKey:@"inputSharpness"];
    result = noise.outputImage ?: result;

    if (useRealtimeFallbackTuning) {
      CGRect extent = result.extent;
      CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
      [blur setValue:result forKey:kCIInputImageKey];
      [blur setValue:@(0.8 + smooth * 2.0) forKey:kCIInputRadiusKey];
      CIImage *blurred = [blur.outputImage imageByCroppingToRect:extent];
      if (blurred) {
        CIFilter *alpha = [CIFilter filterWithName:@"CIColorMatrix"];
        [alpha setValue:blurred forKey:kCIInputImageKey];
        [alpha setValue:[CIVector vectorWithX:1 Y:0 Z:0 W:0] forKey:@"inputRVector"];
        [alpha setValue:[CIVector vectorWithX:0 Y:1 Z:0 W:0] forKey:@"inputGVector"];
        [alpha setValue:[CIVector vectorWithX:0 Y:0 Z:1 W:0] forKey:@"inputBVector"];
        [alpha setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:(0.10 + smooth * 0.24)] forKey:@"inputAVector"];
        CIImage *softLayer = alpha.outputImage;
        if (softLayer) {
          result = [[softLayer imageByCroppingToRect:extent] imageByCompositingOverImage:result];
        }
      }
    }
  }

  if (brighten > 0 || whiten > 0) {
    CIFilter *color = [CIFilter filterWithName:@"CIColorControls"];
    [color setValue:result forKey:kCIInputImageKey];
    CGFloat brightness = useRealtimeFallbackTuning
      ? (brighten * 0.13 + whiten * 0.07)
      : (brighten * 0.10 + whiten * 0.10);
    CGFloat saturation = useRealtimeFallbackTuning
      ? (1.0 + brighten * 0.02 - whiten * 0.025)
      : (1.0 + brighten * 0.018 - whiten * 0.04);
    CGFloat contrast = useRealtimeFallbackTuning
      ? (1.0 + brighten * 0.018 + whiten * 0.012)
      : (1.0 + brighten * 0.02 + whiten * 0.025);
    [color setValue:@(brightness) forKey:kCIInputBrightnessKey];
    [color setValue:@(saturation) forKey:kCIInputSaturationKey];
    [color setValue:@(contrast) forKey:kCIInputContrastKey];
    result = color.outputImage ?: result;

    if (whiten > 0) {
      CIFilter *exposure = [CIFilter filterWithName:@"CIExposureAdjust"];
      [exposure setValue:result forKey:kCIInputImageKey];
      [exposure setValue:@(whiten * 0.16) forKey:kCIInputEVKey];
      result = exposure.outputImage ?: result;
    }

    if (useRealtimeFallbackTuning && whiten > 0) {
      CIFilter *gamma = [CIFilter filterWithName:@"CIGammaAdjust"];
      [gamma setValue:result forKey:kCIInputImageKey];
      [gamma setValue:@(MAX(0.82, 1.0 - whiten * 0.14)) forKey:@"inputPower"];
      result = gamma.outputImage ?: result;
    }
  }

  logBeautyProcess(pipeline, reason, result);

  return result;
}

- (CIImage *)preparedCameraImage:(CIImage *)image
                      targetRect:(CGRect)targetRect
                      canvasSize:(CGSize)canvasSize
                        mirrored:(BOOL)mirrored {
  return [self preparedCameraImage:image
                        targetRect:targetRect
                        canvasSize:canvasSize
                          mirrored:mirrored
                       highQuality:NO];
}

- (CIImage *)preparedCameraImage:(CIImage *)image
                      targetRect:(CGRect)targetRect
                      canvasSize:(CGSize)canvasSize
                        mirrored:(BOOL)mirrored
                     highQuality:(BOOL)highQuality {
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
  CIImage *scaled = [self scaledCIImage:source
                                 toSize:CGSizeMake(sourceW * scale, sourceH * scale)
                            highQuality:highQuality];
  CGFloat cropX = MAX(0, (scaled.extent.size.width - targetRect.size.width) / 2.0);
  CGFloat cropY = MAX(0, (scaled.extent.size.height - targetRect.size.height) / 2.0);
  CIImage *cropped = [scaled imageByCroppingToRect:CGRectMake(cropX, cropY, targetRect.size.width, targetRect.size.height)];
  CIImage *placed = [cropped imageByApplyingTransform:CGAffineTransformMakeTranslation(targetRect.origin.x - cropX, targetRect.origin.y - cropY)];
  return [placed imageByCroppingToRect:CGRectMake(0, 0, canvasSize.width, canvasSize.height)];
}

/// Convert a UIKit rect (Y=0 at top) to CIImage rect (Y=0 at bottom) for a given canvas height.
- (CGRect)ciRectFromUIKitRect:(CGRect)rect canvasHeight:(CGFloat)h {
  return CGRectMake(rect.origin.x, h - rect.origin.y - rect.size.height, rect.size.width, rect.size.height);
}

- (CIImage *)compositedImageForLayoutState:(DualCameraLayoutState *)state
                                     front:(CIImage *)front
                                      back:(CIImage *)back {
  return [self compositedImageForLayoutState:state front:front back:back highQuality:NO];
}

- (CIImage *)compositedImageForLayoutState:(DualCameraLayoutState *)state
                                     front:(CIImage *)front
                                      back:(CIImage *)back
                                highQuality:(BOOL)highQuality {
  return [self compositedImageForLayoutState:state
                                       front:front
                                        back:back
                                  highQuality:highQuality
                                       source:@"compose"];
}

- (CIImage *)compositedImageForLayoutState:(DualCameraLayoutState *)state
                                     front:(CIImage *)front
                                      back:(CIImage *)back
                                highQuality:(BOOL)highQuality
                                     source:(NSString *)source {
  CGSize canvasSize = state.outputSize;
  NSDictionary<NSString *, NSValue *> *rects = [self rectsForLayoutState:state canvasSize:canvasSize];

  // rectsForLayoutState returns UIKit coordinates (Y=0 at top).
  // CIImage uses Y=0 at bottom, so flip each rect before compositing.
  CGFloat H = canvasSize.height;
  CGRect backRect  = [self ciRectFromUIKitRect:[rects[@"back"]  CGRectValue] canvasHeight:H];
  CGRect frontRect = [self ciRectFromUIKitRect:[rects[@"front"] CGRectValue] canvasHeight:H];
  NSString *layout = state.layoutMode ?: @"back";
  BOOL hasFrontFrame = front != nil;
  BOOL hasBackFrame = back != nil;
  BOOL hasActiveBeauty = self.frontBeautyEnabled &&
    (self.frontBeautySmooth > 0 ||
     self.frontBeautyBrighten > 0 ||
     self.frontBeautyWhiten > 0);
  BOOL frontAlreadyBeautified = [source rangeOfString:@"cached_beauty"].location != NSNotFound;

  if (hasActiveBeauty && [layout isEqualToString:@"back"] && !back && front) {
    NSLog(@"[BeautyRoute] source=%@ output=back cameraSource=unknown beauty=never reason=missing_back_frame_blocked",
          source ?: @"compose");
    return nil;
  }
  if (hasActiveBeauty && [layout isEqualToString:@"front"] && !front && back) {
    NSLog(@"[BeautyRoute] source=%@ output=front cameraSource=unknown beauty=skipped reason=missing_front_frame_blocked",
          source ?: @"compose");
    return nil;
  }

  if ([layout isEqualToString:@"back"] && !back) {
    back = front;
  }
  if ([layout isEqualToString:@"front"] && !front) {
    front = back;
  }
  if ([self isDualLayout:layout] && !front && !back) return nil;

  BOOL shouldBeautifyFront = hasFrontFrame &&
    hasActiveBeauty &&
    !frontAlreadyBeautified &&
    ![layout isEqualToString:@"back"];
  static NSMutableSet<NSString *> *loggedComposeSources = nil;
  static dispatch_once_t composeOnceToken;
  dispatch_once(&composeOnceToken, ^{
    loggedComposeSources = [NSMutableSet set];
  });
  NSString *composeLogKey = source ?: @"compose";
  @synchronized(loggedComposeSources) {
    if (![loggedComposeSources containsObject:composeLogKey]) {
      [loggedComposeSources addObject:composeLogKey];
      NSLog(@"[BeautySave] source=%@ layout=%@ front=%d back=%d shouldBeautifyFront=%d enabled=%d smooth=%.1f brighten=%.1f whiten=%.1f",
            composeLogKey, layout, front != nil, back != nil, shouldBeautifyFront, self.frontBeautyEnabled,
            self.frontBeautySmooth, self.frontBeautyBrighten, self.frontBeautyWhiten);
      NSLog(@"[BeautyRoute] source=%@ output=combined layout=%@ frontCamera=%@ backCamera=%@ beautifyFront=%d beautifyBack=0 frontAlreadyBeautified=%d",
            composeLogKey, layout, hasFrontFrame ? @"front" : @"none", hasBackFrame ? @"back" : @"none", shouldBeautifyFront, frontAlreadyBeautified);
      if (hasFrontFrame) {
        NSLog(@"[BeautyRoute] source=%@ output=front cameraSource=front beauty=%@ reason=%@",
              composeLogKey,
              shouldBeautifyFront ? @"applied" : @"skipped",
              shouldBeautifyFront ? @"active" : (hasActiveBeauty ? @"layout_back" : @"inactive"));
      }
      if (hasBackFrame) {
        NSLog(@"[BeautyRoute] source=%@ output=back cameraSource=back beauty=never",
              composeLogKey);
      }
    }
  }
  if (shouldBeautifyFront) {
    front = [self beautifiedImage:front cameraSource:@"front" usage:composeLogKey];
  }

  CIImage *result = [self blackCanvasSize:canvasSize];
  CIImage *backImage = [self preparedCameraImage:back targetRect:backRect canvasSize:canvasSize mirrored:state.backMirrored highQuality:highQuality];
  CIImage *frontImage = [self preparedCameraImage:front targetRect:frontRect canvasSize:canvasSize mirrored:state.frontMirrored highQuality:highQuality];

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

#pragma mark - File / size utilities

- (NSString *)saveCIImageAsJPEG:(CIImage *)ciImage {
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat:@"dual_composited_%ld.jpg", (long)[[NSDate date] timeIntervalSince1970]]];

  CIImage *toSave = ciImage;
  if (ciImage.extent.origin.x != 0 || ciImage.extent.origin.y != 0) {
    CGFloat ox = -ciImage.extent.origin.x;
    CGFloat oy = -ciImage.extent.origin.y;
    toSave = [ciImage imageByApplyingTransform:CGAffineTransformMakeTranslation(ox, oy)];
  }

  // Use CIContext's native JPEG writer — one-step conversion with explicit sRGB
  // output colour space.  Avoids the CIImage→CGImage→UIImage→JPEG chain whose
  // implicit colour-space round-trips cause the washed-out appearance.
  CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  NSURL *fileURL = [NSURL fileURLWithPath:path];
  NSError *writeError = nil;
  BOOL ok = [self.ciContext writeJPEGRepresentationOfImage:toSave
                                                    toURL:fileURL
                                               colorSpace:srgb
                                                  options:@{(id)kCGImageDestinationLossyCompressionQuality: @0.95}
                                                    error:&writeError];
  CGColorSpaceRelease(srgb);

  if (!ok) {
    NSLog(@"[DualCamera] saveCIImageAsJPEG failed: %@", writeError);
    return nil;
  }
  return path;
}

- (NSString *)tempPathWithPrefix:(NSString *)prefix {
  return [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat:@"%@%ld.mov", prefix, (long)[[NSDate date] timeIntervalSince1970]]];
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

- (CGSize)photoOutputSizeForAspectRatio:(NSString *)aspectRatio
                                   front:(CIImage *)front
                                    back:(CIImage *)back
                               landscape:(BOOL)landscape {
  CGFloat targetReferenceWidth = 1440.0;
  CGFloat minSourceLongEdge = CGFLOAT_MAX;
  if (front) {
    minSourceLongEdge = MIN(minSourceLongEdge, MAX(front.extent.size.width, front.extent.size.height));
  }
  if (back) {
    minSourceLongEdge = MIN(minSourceLongEdge, MAX(back.extent.size.width, back.extent.size.height));
  }

  if (minSourceLongEdge != CGFLOAT_MAX && minSourceLongEdge > 0) {
    targetReferenceWidth = MAX(720.0, MIN(targetReferenceWidth, minSourceLongEdge));
  } else {
    targetReferenceWidth = 1080.0;
  }
  return [self outputSizeForAspectRatio:aspectRatio
                         referenceWidth:targetReferenceWidth
                              landscape:landscape];
}

- (CGSize)realtimeRecordingOutputSizeForAspectRatio:(NSString *)aspectRatio landscape:(BOOL)landscape {
  return [self outputSizeForAspectRatio:aspectRatio referenceWidth:1440.0 landscape:landscape];
}

#pragma mark - AVFoundation layer helper

- (AVMutableVideoCompositionLayerInstruction *)layerForTrack:(AVMutableCompositionTrack *)track {
  if (!track) return nil;
  return [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
}

#pragma mark - Recording error-detail builder

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

@end
