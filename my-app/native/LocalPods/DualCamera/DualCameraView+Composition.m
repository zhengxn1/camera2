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
  CGSize canvasSize = state.outputSize;
  NSDictionary<NSString *, NSValue *> *rects = [self rectsForLayoutState:state canvasSize:canvasSize];

  // rectsForLayoutState returns UIKit coordinates (Y=0 at top).
  // CIImage uses Y=0 at bottom, so flip each rect before compositing.
  CGFloat H = canvasSize.height;
  CGRect backRect  = [self ciRectFromUIKitRect:[rects[@"back"]  CGRectValue] canvasHeight:H];
  CGRect frontRect = [self ciRectFromUIKitRect:[rects[@"front"] CGRectValue] canvasHeight:H];
  NSString *layout = state.layoutMode ?: @"back";
  BOOL hasFrontFrame = front != nil;

  if ([layout isEqualToString:@"back"] && !back) {
    back = front;
  }
  if ([layout isEqualToString:@"front"] && !front) {
    front = back;
  }
  if ([self isDualLayout:layout] && !front && !back) return nil;
  if (hasFrontFrame) {
    front = [self beautifiedFrontImage:front];
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

#pragma mark - Beauty

- (CGFloat)clampedBeautyAmount:(CGFloat)value {
  return MAX(0.0, MIN(1.0, value / 100.0));
}

- (CIImage *)solidBeautyMaskForExtent:(CGRect)extent {
  CIFilter *colorGen = [CIFilter filterWithName:@"CIConstantColorGenerator"];
  [colorGen setValue:[CIColor colorWithRed:1 green:1 blue:1 alpha:1] forKey:kCIInputColorKey];
  return [colorGen.outputImage imageByCroppingToRect:extent];
}

- (CIImage *)radialMaskWithCenter:(CGPoint)center
                          radius0:(CGFloat)radius0
                          radius1:(CGFloat)radius1
                           extent:(CGRect)extent
                            white:(BOOL)white {
  CIFilter *radial = [CIFilter filterWithName:@"CIRadialGradient"];
  [radial setValue:[CIVector vectorWithX:center.x Y:center.y] forKey:kCIInputCenterKey];
  [radial setValue:@(MAX(0.0, radius0)) forKey:@"inputRadius0"];
  [radial setValue:@(MAX(radius0 + 1.0, radius1)) forKey:@"inputRadius1"];
  CIColor *inside = white ? [CIColor colorWithRed:1 green:1 blue:1 alpha:1] : [CIColor colorWithRed:0 green:0 blue:0 alpha:1];
  CIColor *outside = white ? [CIColor colorWithRed:0 green:0 blue:0 alpha:0] : [CIColor colorWithRed:0 green:0 blue:0 alpha:0];
  [radial setValue:inside forKey:@"inputColor0"];
  [radial setValue:outside forKey:@"inputColor1"];
  return [radial.outputImage imageByCroppingToRect:extent];
}

- (VNFaceObservation *)largestFaceObservationFromResults:(NSArray<VNFaceObservation *> *)faces {
  VNFaceObservation *largest = nil;
  CGFloat largestArea = 0.0;
  for (VNFaceObservation *face in faces) {
    CGFloat area = face.boundingBox.size.width * face.boundingBox.size.height;
    if (area > largestArea) {
      largest = face;
      largestArea = area;
    }
  }
  return largest;
}

- (VNFaceObservation *)frontBeautyFaceObservationForImage:(CIImage *)image {
  if (!image) return nil;

  CGRect extent = image.extent;
  CGSize imageSize = extent.size;
  BOOL cachedSizeMatches = CGSizeEqualToSize(self.frontBeautyMaskImageSize, imageSize);
  self.frontBeautyFrameCounter += 1;
  BOOL shouldRefresh = !self.frontBeautyFaceObservation || !cachedSizeMatches || (self.frontBeautyFrameCounter % 18 == 0);
  BOOL didRefresh = NO;

  if (shouldRefresh) {
    didRefresh = YES;
    VNDetectFaceLandmarksRequest *request = [[VNDetectFaceLandmarksRequest alloc] init];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCIImage:image options:@{}];
    NSError *visionError = nil;
    if ([handler performRequests:@[request] error:&visionError]) {
      VNFaceObservation *face = [self largestFaceObservationFromResults:request.results];
      if (face && face.boundingBox.size.width > 0.12 && face.boundingBox.size.height > 0.12 && face.landmarks) {
        self.frontBeautyFaceObservation = face;
        self.frontBeautyFramesSinceFace = 0;
        self.frontBeautyMask = nil;
      } else {
        self.frontBeautyFramesSinceFace += 1;
        if (self.frontBeautyFramesSinceFace > 10) {
          self.frontBeautyFaceObservation = nil;
          self.frontBeautyMask = nil;
        }
      }
    } else {
      self.frontBeautyFramesSinceFace += 1;
      self.frontBeautyMask = nil;
      NSLog(@"[DualCamera] VNDetectFaceLandmarksRequest failed: %@", visionError.localizedDescription);
    }
  }

  return (cachedSizeMatches || didRefresh) ? self.frontBeautyFaceObservation : nil;
}

- (CGPoint)pointForLandmarkPoint:(CGPoint)point
                            face:(VNFaceObservation *)face
                          extent:(CGRect)extent {
  return CGPointMake(extent.origin.x + (face.boundingBox.origin.x + point.x * face.boundingBox.size.width) * extent.size.width,
                     extent.origin.y + (face.boundingBox.origin.y + point.y * face.boundingBox.size.height) * extent.size.height);
}

- (CGPoint)averagePointForLandmark:(VNFaceLandmarkRegion2D *)landmark
                              face:(VNFaceObservation *)face
                            extent:(CGRect)extent {
  if (!landmark || landmark.pointCount == 0) return CGPointZero;

  CGFloat sx = 0.0;
  CGFloat sy = 0.0;
  for (NSUInteger i = 0; i < landmark.pointCount; i++) {
    CGPoint p = landmark.normalizedPoints[i];
    CGPoint imagePoint = [self pointForLandmarkPoint:p face:face extent:extent];
    sx += imagePoint.x;
    sy += imagePoint.y;
  }
  return CGPointMake(sx / landmark.pointCount, sy / landmark.pointCount);
}

- (CIImage *)blackFeatureMaskForLandmark:(VNFaceLandmarkRegion2D *)landmark
                                    face:(VNFaceObservation *)face
                                  extent:(CGRect)extent
                             radiusScale:(CGFloat)radiusScale {
  if (!landmark || landmark.pointCount == 0) return nil;

  CGPoint center = [self averagePointForLandmark:landmark face:face extent:extent];
  CGFloat maxDistance = 0.0;
  for (NSUInteger i = 0; i < landmark.pointCount; i++) {
    CGPoint p = [self pointForLandmarkPoint:landmark.normalizedPoints[i] face:face extent:extent];
    CGFloat dx = p.x - center.x;
    CGFloat dy = p.y - center.y;
    maxDistance = MAX(maxDistance, sqrt(dx * dx + dy * dy));
  }
  CGFloat radius = MAX(10.0, maxDistance * radiusScale);
  return [self radialMaskWithCenter:center radius0:radius * 0.72 radius1:radius extent:extent white:NO];
}

- (CIImage *)faceBeautyMaskForImage:(CIImage *)image {
  if (!image) return nil;

  CGRect extent = image.extent;
  CGSize imageSize = extent.size;
  BOOL cachedSizeMatches = CGSizeEqualToSize(self.frontBeautyMaskImageSize, imageSize);
  if (self.frontBeautyMask && cachedSizeMatches) return self.frontBeautyMask;

  VNFaceObservation *face = [self frontBeautyFaceObservationForImage:image];
  if (!face) {
    self.frontBeautyMaskImageSize = imageSize;
    self.frontBeautyMask = [self solidBeautyMaskForExtent:extent];
    return self.frontBeautyMask;
  }

  CGRect box = face.boundingBox;
  CGRect faceRect = CGRectMake(extent.origin.x + box.origin.x * imageSize.width,
                               extent.origin.y + box.origin.y * imageSize.height,
                               box.size.width * imageSize.width,
                               box.size.height * imageSize.height);
  faceRect = CGRectInset(faceRect, -faceRect.size.width * 0.16, -faceRect.size.height * 0.08);
  CGPoint center = CGPointMake(CGRectGetMidX(faceRect), CGRectGetMidY(faceRect));
  CGFloat radius = MAX(faceRect.size.width, faceRect.size.height) * 0.66;
  CIImage *mask = [self radialMaskWithCenter:center radius0:radius * 0.56 radius1:radius extent:extent white:YES];

  NSArray<CIImage *> *protectedFeatures = @[
    [self blackFeatureMaskForLandmark:face.landmarks.leftEye face:face extent:extent radiusScale:2.0] ?: [self clearCanvasSize:extent.size],
    [self blackFeatureMaskForLandmark:face.landmarks.rightEye face:face extent:extent radiusScale:2.0] ?: [self clearCanvasSize:extent.size],
    [self blackFeatureMaskForLandmark:face.landmarks.leftEyebrow face:face extent:extent radiusScale:1.7] ?: [self clearCanvasSize:extent.size],
    [self blackFeatureMaskForLandmark:face.landmarks.rightEyebrow face:face extent:extent radiusScale:1.7] ?: [self clearCanvasSize:extent.size],
    [self blackFeatureMaskForLandmark:face.landmarks.outerLips face:face extent:extent radiusScale:1.8] ?: [self clearCanvasSize:extent.size]
  ];
  for (CIImage *featureMask in protectedFeatures) {
    mask = [featureMask imageByCompositingOverImage:mask];
  }

  self.frontBeautyMask = [mask imageByCroppingToRect:extent];
  self.frontBeautyMaskFaceBounds = faceRect;
  self.frontBeautyMaskImageSize = imageSize;
  return self.frontBeautyMask;
}

- (CIImage *)blendBeautyImage:(CIImage *)beauty
                 overOriginal:(CIImage *)original
                         mask:(CIImage *)mask {
  if (!beauty || !original) return original ?: beauty;
  if (!mask) return beauty;

  CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
  [blend setValue:beauty forKey:kCIInputImageKey];
  [blend setValue:original forKey:kCIInputBackgroundImageKey];
  [blend setValue:mask forKey:@"inputMaskImage"];
  return blend.outputImage ?: beauty;
}

- (CIImage *)applySmoothBeautyToImage:(CIImage *)image
                                  mask:(CIImage *)mask
                                amount:(CGFloat)amount {
  if (!image || amount <= 0.01) return image;

  CGRect extent = image.extent;
  CIFilter *noiseReduction = [CIFilter filterWithName:@"CINoiseReduction"];
  [noiseReduction setValue:image forKey:kCIInputImageKey];
  [noiseReduction setValue:@(0.05 + amount * 0.22) forKey:@"inputNoiseLevel"];
  [noiseReduction setValue:@(0.22 + amount * 0.38) forKey:@"inputSharpness"];
  CIImage *denoised = noiseReduction.outputImage ?: image;

  CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
  [blur setValue:denoised forKey:kCIInputImageKey];
  [blur setValue:@(0.8 + amount * 4.4) forKey:kCIInputRadiusKey];
  CIImage *soft = [blur.outputImage imageByCroppingToRect:extent] ?: denoised;

  CIFilter *softBlend = [CIFilter filterWithName:@"CIDissolveTransition"];
  [softBlend setValue:soft forKey:kCIInputImageKey];
  [softBlend setValue:image forKey:kCIInputTargetImageKey];
  [softBlend setValue:@(amount * 0.48) forKey:kCIInputTimeKey];
  CIImage *smoothed = softBlend.outputImage ?: soft;

  CIFilter *details = [CIFilter filterWithName:@"CIUnsharpMask"];
  [details setValue:image forKey:kCIInputImageKey];
  [details setValue:@(0.7) forKey:kCIInputRadiusKey];
  [details setValue:@(0.18 + amount * 0.16) forKey:kCIInputIntensityKey];
  CIImage *detailImage = details.outputImage ?: image;

  CIFilter *detailBlend = [CIFilter filterWithName:@"CIDissolveTransition"];
  [detailBlend setValue:detailImage forKey:kCIInputImageKey];
  [detailBlend setValue:smoothed forKey:kCIInputTargetImageKey];
  [detailBlend setValue:@(0.18) forKey:kCIInputTimeKey];
  CIImage *withDetails = detailBlend.outputImage ?: smoothed;
  return [self blendBeautyImage:withDetails overOriginal:image mask:mask];
}

- (CIImage *)applyWhitenBeautyToImage:(CIImage *)image
                                  mask:(CIImage *)mask
                                amount:(CGFloat)amount {
  if (!image || amount <= 0.01) return image;

  CGRect extent = image.extent;
  CIFilter *shadow = [CIFilter filterWithName:@"CIHighlightShadowAdjust"];
  [shadow setValue:image forKey:kCIInputImageKey];
  [shadow setValue:@(0.94 - amount * 0.20) forKey:@"inputHighlightAmount"];
  [shadow setValue:@(0.08 + amount * 0.48) forKey:@"inputShadowAmount"];
  CIImage *lifted = shadow.outputImage ?: image;

  CIFilter *color = [CIFilter filterWithName:@"CIColorControls"];
  [color setValue:lifted forKey:kCIInputImageKey];
  [color setValue:@(1.0 + amount * 0.035) forKey:kCIInputSaturationKey];
  [color setValue:@(amount * 0.12) forKey:kCIInputBrightnessKey];
  [color setValue:@(1.0 - amount * 0.035) forKey:kCIInputContrastKey];
  CIImage *bright = color.outputImage ?: lifted;

  CIFilter *protect = [CIFilter filterWithName:@"CIHighlightShadowAdjust"];
  [protect setValue:bright forKey:kCIInputImageKey];
  [protect setValue:@(0.86) forKey:@"inputHighlightAmount"];
  [protect setValue:@(0.0) forKey:@"inputShadowAmount"];
  CIImage *protectedHighlights = protect.outputImage ?: bright;
  return [[self blendBeautyImage:protectedHighlights overOriginal:image mask:mask] imageByCroppingToRect:extent];
}

- (CIImage *)applyEvenBeautyToImage:(CIImage *)image
                                mask:(CIImage *)mask
                              amount:(CGFloat)amount {
  if (!image || amount <= 0.01) return image;

  CGRect extent = image.extent;
  CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
  [blur setValue:image forKey:kCIInputImageKey];
  [blur setValue:@(8.0 + amount * 18.0) forKey:kCIInputRadiusKey];
  CIImage *lowFrequency = [blur.outputImage imageByCroppingToRect:extent] ?: image;

  CIFilter *lowColor = [CIFilter filterWithName:@"CIColorControls"];
  [lowColor setValue:lowFrequency forKey:kCIInputImageKey];
  [lowColor setValue:@(0.95) forKey:kCIInputSaturationKey];
  [lowColor setValue:@(amount * 0.025) forKey:kCIInputBrightnessKey];
  [lowColor setValue:@(0.98) forKey:kCIInputContrastKey];
  CIImage *toneLayer = lowColor.outputImage ?: lowFrequency;

  CIFilter *toneBlend = [CIFilter filterWithName:@"CIDissolveTransition"];
  [toneBlend setValue:toneLayer forKey:kCIInputImageKey];
  [toneBlend setValue:image forKey:kCIInputTargetImageKey];
  [toneBlend setValue:@(amount * 0.36) forKey:kCIInputTimeKey];
  CIImage *evened = toneBlend.outputImage ?: toneLayer;

  CIFilter *structure = [CIFilter filterWithName:@"CIUnsharpMask"];
  [structure setValue:evened forKey:kCIInputImageKey];
  [structure setValue:@(1.2) forKey:kCIInputRadiusKey];
  [structure setValue:@(0.12) forKey:kCIInputIntensityKey];
  CIImage *structured = structure.outputImage ?: evened;
  return [self blendBeautyImage:structured overOriginal:image mask:mask];
}

- (CIImage *)applyBumpToImage:(CIImage *)image
                        center:(CGPoint)center
                        radius:(CGFloat)radius
                         scale:(CGFloat)scale {
  if (!image || radius <= 1.0 || fabs(scale) <= 0.001) return image;

  CIFilter *bump = [CIFilter filterWithName:@"CIBumpDistortion"];
  [bump setValue:image forKey:kCIInputImageKey];
  [bump setValue:[CIVector vectorWithX:center.x Y:center.y] forKey:kCIInputCenterKey];
  [bump setValue:@(radius) forKey:kCIInputRadiusKey];
  [bump setValue:@(scale) forKey:kCIInputScaleKey];
  return [bump.outputImage imageByCroppingToRect:image.extent] ?: image;
}

- (CIImage *)applyPinchToImage:(CIImage *)image
                         center:(CGPoint)center
                         radius:(CGFloat)radius
                          scale:(CGFloat)scale {
  if (!image || radius <= 1.0 || fabs(scale) <= 0.001) return image;

  CIFilter *pinch = [CIFilter filterWithName:@"CIPinchDistortion"];
  [pinch setValue:image forKey:kCIInputImageKey];
  [pinch setValue:[CIVector vectorWithX:center.x Y:center.y] forKey:kCIInputCenterKey];
  [pinch setValue:@(radius) forKey:kCIInputRadiusKey];
  [pinch setValue:@(scale) forKey:kCIInputScaleKey];
  return [pinch.outputImage imageByCroppingToRect:image.extent] ?: image;
}

- (CIImage *)applyPlumpBeautyToImage:(CIImage *)image
                                 face:(VNFaceObservation *)face
                               amount:(CGFloat)amount {
  if (!image || !face || amount <= 0.01 || !face.landmarks) return image;
  if (!face.landmarks.leftEye || !face.landmarks.rightEye || !face.landmarks.nose) return image;

  CGRect extent = image.extent;
  CGPoint leftEye = [self averagePointForLandmark:face.landmarks.leftEye face:face extent:extent];
  CGPoint rightEye = [self averagePointForLandmark:face.landmarks.rightEye face:face extent:extent];
  CGPoint nose = [self averagePointForLandmark:face.landmarks.nose face:face extent:extent];
  if (CGPointEqualToPoint(leftEye, CGPointZero) || CGPointEqualToPoint(rightEye, CGPointZero) || CGPointEqualToPoint(nose, CGPointZero)) {
    return image;
  }

  CGFloat eyeDistance = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y);
  if (eyeDistance < 24.0) return image;
  CGFloat faceW = face.boundingBox.size.width * extent.size.width;
  CGFloat faceH = face.boundingBox.size.height * extent.size.height;
  if (faceW / MAX(faceH, 1.0) < 0.55 || faceW / MAX(faceH, 1.0) > 1.18) return image;

  CGFloat a = amount;
  CGFloat cheekRadius = eyeDistance * (0.92 + a * 0.15);
  CGFloat templeRadius = eyeDistance * 0.68;
  CGFloat jawRadius = eyeDistance * 1.05;
  CGPoint faceCenter = CGPointMake((leftEye.x + rightEye.x) / 2.0, nose.y - eyeDistance * 0.12);
  CGPoint leftCheek = CGPointMake(leftEye.x - eyeDistance * 0.15, nose.y - eyeDistance * 0.48);
  CGPoint rightCheek = CGPointMake(rightEye.x + eyeDistance * 0.15, nose.y - eyeDistance * 0.48);
  CGPoint leftTemple = CGPointMake(leftEye.x - eyeDistance * 0.74, leftEye.y + eyeDistance * 0.28);
  CGPoint rightTemple = CGPointMake(rightEye.x + eyeDistance * 0.74, rightEye.y + eyeDistance * 0.28);
  CGPoint leftJaw = CGPointMake(faceCenter.x - faceW * 0.38, nose.y - faceH * 0.34);
  CGPoint rightJaw = CGPointMake(faceCenter.x + faceW * 0.38, nose.y - faceH * 0.34);

  CIImage *result = image;
  result = [self applyBumpToImage:result center:leftCheek radius:cheekRadius scale:a * 0.16];
  result = [self applyBumpToImage:result center:rightCheek radius:cheekRadius scale:a * 0.16];
  result = [self applyBumpToImage:result center:leftTemple radius:templeRadius scale:a * 0.09];
  result = [self applyBumpToImage:result center:rightTemple radius:templeRadius scale:a * 0.09];
  result = [self applyPinchToImage:result center:leftJaw radius:jawRadius scale:0.0 - a * 0.10];
  result = [self applyPinchToImage:result center:rightJaw radius:jawRadius scale:0.0 - a * 0.10];
  return [result imageByCroppingToRect:extent];
}

- (CIImage *)beautifiedFrontImage:(CIImage *)image {
	  if (!image) return nil;

	  CFTimeInterval beautyStart = CACurrentMediaTime();
	  CFTimeInterval now = beautyStart;
	  static CFTimeInterval beautyProbeLastEntryLogAt = 0;
	  CGFloat smooth = [self clampedBeautyAmount:self.frontBeautySmooth];
	  CGFloat whiten = [self clampedBeautyAmount:self.frontBeautyWhiten];
	  CGFloat even = [self clampedBeautyAmount:self.frontBeautyEven];
	  CGFloat plump = [self clampedBeautyAmount:self.frontBeautyPlump];
	  if (now - beautyProbeLastEntryLogAt > 2.0) {
	    beautyProbeLastEntryLogAt = now;
	    NSLog(@"[BeautyProbe][BeautyEntry] smooth=%.2f whiten=%.2f even=%.2f plump=%.2f layout=%@ changing=%d extent=%@",
	          smooth,
	          whiten,
	          even,
	          plump,
	          self.currentLayout ?: @"nil",
	          self.beautyLayoutChanging,
	          NSStringFromCGRect(image.extent));
	  }
	  if (smooth <= 0.01 && whiten <= 0.01 && even <= 0.01 && plump <= 0.01) return image;

  VNFaceObservation *face = [self frontBeautyFaceObservationForImage:image];
  CIImage *mask = [self faceBeautyMaskForImage:image];
  CIImage *result = image;
  result = [self applySmoothBeautyToImage:result mask:mask amount:smooth];
  result = [self applyWhitenBeautyToImage:result mask:mask amount:whiten];
  result = [self applyEvenBeautyToImage:result mask:mask amount:even];
	  now = CACurrentMediaTime();
	  BOOL layoutChangingAtPlump = self.beautyLayoutChanging;
	  BOOL skipPlumpForLayout = self.beautyLayoutChanging && (now - self.lastBeautyLayoutChangeTime < 0.80);
	  if (skipPlumpForLayout) {
	    plump = 0.0;
	  }
	  if (layoutChangingAtPlump && !skipPlumpForLayout && plump > 0.01) {
	    NSLog(@"[BeautyProbe][PlumpDuringLayout] plump=%.2f layout=%@ elapsed=%.3f extent=%@",
	          plump,
	          self.currentLayout ?: @"nil",
	          now - self.lastBeautyLayoutChangeTime,
	          NSStringFromCGRect(image.extent));
	  }
	  result = [self applyPlumpBeautyToImage:result face:face amount:plump];
	  CFTimeInterval beautyMs = (CACurrentMediaTime() - beautyStart) * 1000.0;
	  if (beautyMs > 33.0) {
	    NSLog(@"[BeautyProbe][SlowRender] beautyMs=%.2f smooth=%.2f whiten=%.2f even=%.2f plump=%.2f face=%d layout=%@",
	          beautyMs,
	          smooth,
	          whiten,
	          even,
	          plump,
	          face != nil,
	          self.currentLayout ?: @"nil");
	  }

	  if (now - self.lastBeautyFaceDiagLogTime > 0.8 || skipPlumpForLayout) {
    self.lastBeautyFaceDiagLogTime = now;
    CGRect faceBox = face ? face.boundingBox : CGRectZero;
    NSLog(@"[BeautyFaceDiag] smooth=%.2f whiten=%.2f even=%.2f plump=%.2f skipPlump=%d face=%d faceBox=%@ extent=%@ beautyMs=%.2f changing=%d",
          smooth,
          whiten,
          even,
          plump,
          skipPlumpForLayout,
	          face != nil,
	          NSStringFromCGRect(faceBox),
	          NSStringFromCGRect(image.extent),
	          beautyMs,
	          self.beautyLayoutChanging);
  }
  return [result imageByCroppingToRect:image.extent];
}

#pragma mark - File / size utilities

- (NSString *)saveCIImageAsJPEG:(CIImage *)ciImage {
  return [self saveCIImageAsJPEG:ciImage prefix:@"dual_composited_"];
}

- (NSString *)saveCIImageAsJPEG:(CIImage *)ciImage prefix:(NSString *)prefix {
  NSString *safePrefix = prefix.length > 0 ? prefix : @"dual_photo_";
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat:@"%@%@.jpg", safePrefix, NSUUID.UUID.UUIDString]];

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
