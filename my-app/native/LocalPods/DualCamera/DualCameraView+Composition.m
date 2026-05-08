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
  CGFloat scaleX = size.width / image.extent.size.width;
  CGFloat scaleY = size.height / image.extent.size.height;
  CIFilter *transformFilter = [CIFilter filterWithName:@"CIAffineTransform"];
  [transformFilter setValue:image forKey:kCIInputImageKey];
  [transformFilter setValue:[NSValue valueWithCGAffineTransform:CGAffineTransformMakeScale(scaleX, scaleY)] forKey:kCIInputTransformKey];
  CIImage *result = transformFilter.outputImage;
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

/// Convert a UIKit rect (Y=0 at top) to CIImage rect (Y=0 at bottom) for a given canvas height.
- (CGRect)ciRectFromUIKitRect:(CGRect)rect canvasHeight:(CGFloat)h {
  return CGRectMake(rect.origin.x, h - rect.origin.y - rect.size.height, rect.size.width, rect.size.height);
}

- (CIImage *)compositedImageForLayoutState:(DualCameraLayoutState *)state
                                     front:(CIImage *)front
                                      back:(CIImage *)back {
  CGSize canvasSize = state.outputSize;
  NSDictionary<NSString *, NSValue *> *rects = [self rectsForLayoutState:state canvasSize:canvasSize];

  // rectsForLayoutState returns UIKit coordinates (Y=0 at top).
  // CIImage uses Y=0 at bottom, so flip each rect before compositing.
  CGFloat H = canvasSize.height;
  CGRect backRect  = [self ciRectFromUIKitRect:[rects[@"back"]  CGRectValue] canvasHeight:H];
  CGRect frontRect = [self ciRectFromUIKitRect:[rects[@"front"] CGRectValue] canvasHeight:H];
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
                                                  options:@{}
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

- (CGSize)realtimeRecordingOutputSizeForAspectRatio:(NSString *)aspectRatio landscape:(BOOL)landscape {
  return [self outputSizeForAspectRatio:aspectRatio referenceWidth:1080.0 landscape:landscape];
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
