#import "GPUPixelBeautyAdapter.h"
#import <CoreGraphics/CoreGraphics.h>

#if __has_include(<gpupixel/gpupixel.h>)
#import <gpupixel/gpupixel.h>
#define DUAL_CAMERA_HAS_GPUPIXEL 1
#elif __has_include("gpupixel.h")
#import "gpupixel.h"
#define DUAL_CAMERA_HAS_GPUPIXEL 1
#else
#define DUAL_CAMERA_HAS_GPUPIXEL 0
#endif

#if DUAL_CAMERA_HAS_GPUPIXEL
#include <memory>
#endif

@interface GPUPixelBeautyAdapter ()
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, assign, readwrite) BOOL available;
@property (nonatomic, assign) BOOL didLogAvailability;
@property (nonatomic, assign) BOOL didLogUnavailable;
@property (nonatomic, assign) BOOL didLogNoEffectParams;
@property (nonatomic, assign) BOOL didLogInvalidInput;
@property (nonatomic, assign) BOOL didLogSetupFailure;
@property (nonatomic, assign) BOOL didLogOutputFailure;
@end

@implementation GPUPixelBeautyAdapter {
#if DUAL_CAMERA_HAS_GPUPIXEL
  std::shared_ptr<gpupixel::SourceRawData> _source;
  std::shared_ptr<gpupixel::BeautyFaceFilter> _beautyFilter;
  std::shared_ptr<gpupixel::SinkRawData> _sink;
#endif
}

- (instancetype)initWithCIContext:(CIContext *)ciContext {
  self = [super init];
  if (self) {
    _ciContext = ciContext;
    _available = DUAL_CAMERA_HAS_GPUPIXEL ? YES : NO;
    _enabled = NO;
    _smooth = 0;
    _whiten = 0;
    NSLog(@"[DualCamera][GPUPixel] adapter init compiled=%d available=%d", DUAL_CAMERA_HAS_GPUPIXEL, _available);
  }
  return self;
}

- (BOOL)setupPipeline {
#if DUAL_CAMERA_HAS_GPUPIXEL
  _source = gpupixel::SourceRawData::Create();
  _beautyFilter = gpupixel::BeautyFaceFilter::Create();
  _sink = gpupixel::SinkRawData::Create();
  if (!_source || !_beautyFilter || !_sink) {
    if (!self.didLogSetupFailure) {
      self.didLogSetupFailure = YES;
      NSLog(@"[DualCamera][GPUPixel] setup failed source=%d beauty=%d sink=%d",
            _source != nullptr, _beautyFilter != nullptr, _sink != nullptr);
    }
    return NO;
  }
  _source->AddSink(_beautyFilter);
  _beautyFilter->AddSink(_sink);
  NSLog(@"[DualCamera][GPUPixel] raw beauty pipeline setup complete");
  return YES;
#else
  if (!self.didLogSetupFailure) {
    self.didLogSetupFailure = YES;
    NSLog(@"[DualCamera][GPUPixel] setup skipped because gpupixel headers/framework were not visible at compile time");
  }
  return NO;
#endif
}

- (void)setEnabled:(BOOL)enabled {
  _enabled = enabled;
  NSLog(@"[DualCamera][GPUPixel] enabled=%d available=%d smooth=%.1f whiten=%.1f",
        enabled, self.available, self.smooth, self.whiten);
}

- (void)setSmooth:(CGFloat)value {
  _smooth = MAX(0, MIN(100, value));
  if (self.enabled) {
    NSLog(@"[DualCamera][GPUPixel] smooth=%.1f", _smooth);
  }
}

- (void)setWhiten:(CGFloat)value {
  _whiten = MAX(0, MIN(100, value));
  if (self.enabled) {
    NSLog(@"[DualCamera][GPUPixel] whiten=%.1f", _whiten);
  }
}

- (nullable CIImage *)processFrontImage:(CIImage *)image {
  if (!image || !self.enabled) {
    return nil;
  }
  if (!self.available) {
    if (!self.didLogUnavailable) {
      self.didLogUnavailable = YES;
      NSLog(@"[DualCamera][GPUPixel] unavailable; Core Image fallback will be used");
    }
    return nil;
  }
  if (self.smooth <= 0 && self.whiten <= 0) {
    if (!self.didLogNoEffectParams) {
      self.didLogNoEffectParams = YES;
      NSLog(@"[DualCamera][GPUPixel] skipped because all beauty params are zero");
    }
    return nil;
  }

#if DUAL_CAMERA_HAS_GPUPIXEL
  if (!_source || !_beautyFilter || !_sink) {
    if (![self setupPipeline]) {
      self.available = NO;
      return nil;
    }
  }

  CGRect extent = image.extent;
  NSInteger width = (NSInteger)llround(CGRectGetWidth(extent));
  NSInteger height = (NSInteger)llround(CGRectGetHeight(extent));
  if (width <= 0 || height <= 0 || !self.ciContext) {
    if (!self.didLogInvalidInput) {
      self.didLogInvalidInput = YES;
      NSLog(@"[DualCamera][GPUPixel] invalid input width=%ld height=%ld ciContext=%d",
            (long)width, (long)height, self.ciContext != nil);
    }
    return nil;
  }

  size_t bytesPerPixel = 4;
  size_t rowBytes = (size_t)width * bytesPerPixel;
  size_t byteCount = rowBytes * (size_t)height;
  NSMutableData *rgbaData = [NSMutableData dataWithLength:byteCount];
  if (!rgbaData.mutableBytes) {
    return nil;
  }

  CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  [self.ciContext render:image
                toBitmap:rgbaData.mutableBytes
                rowBytes:rowBytes
                  bounds:extent
                  format:kCIFormatRGBA8
              colorSpace:colorSpace];

  float blurAlpha = (float)(self.smooth / 100.0);
  float white = (float)MIN(1.0, (self.whiten / 100.0) * 1.35);
  float sharpen = (float)MAX(0.08, 0.22 - blurAlpha * 0.08);
  _beautyFilter->SetBlurAlpha(blurAlpha);
  _beautyFilter->SetWhite(white);
  _beautyFilter->SetSharpen(sharpen);
  _source->ProcessData((const uint8_t *)rgbaData.bytes, width, height, rowBytes, gpupixel::GPUPIXEL_FRAME_TYPE_RGBA);

  const uint8_t *outputBuffer = _sink->GetRgbaBuffer();
  int outputWidth = _sink->GetWidth();
  int outputHeight = _sink->GetHeight();
  if (!outputBuffer || outputWidth <= 0 || outputHeight <= 0) {
    if (!self.didLogOutputFailure) {
      self.didLogOutputFailure = YES;
      NSLog(@"[DualCamera][GPUPixel] output unavailable buffer=%d width=%d height=%d",
            outputBuffer != nullptr, outputWidth, outputHeight);
    }
    if (colorSpace) CGColorSpaceRelease(colorSpace);
    return nil;
  }

  NSData *outputData = [NSData dataWithBytes:outputBuffer
                                      length:(NSUInteger)outputWidth * (NSUInteger)outputHeight * bytesPerPixel];
  CIImage *outputImage = [CIImage imageWithBitmapData:outputData
                                         bytesPerRow:(size_t)outputWidth * bytesPerPixel
                                                size:CGSizeMake(outputWidth, outputHeight)
                                              format:kCIFormatRGBA8
                                          colorSpace:colorSpace];
  if (colorSpace) CGColorSpaceRelease(colorSpace);

  if (!self.didLogAvailability) {
    self.didLogAvailability = YES;
    NSLog(@"[DualCamera][GPUPixel] raw beauty pipeline active size=%dx%d blur=%.3f white=%.3f whiten=%.1f sharpen=%.3f",
          outputWidth, outputHeight, blurAlpha, white, self.whiten, sharpen);
  }
  return outputImage;
#else
  return nil;
#endif
}

@end
