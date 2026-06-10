#import "GPUPixelBeautyAdapter.h"
#import <CoreGraphics/CoreGraphics.h>

#if __has_include(<gpupixel/gpupixel.h>)
#import <gpupixel/gpupixel.h>
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
    _brighten = 0;
    _tone = 0;
  }
  return self;
}

- (BOOL)setupPipeline {
#if DUAL_CAMERA_HAS_GPUPIXEL
  _source = gpupixel::SourceRawData::Create();
  _beautyFilter = gpupixel::BeautyFaceFilter::Create();
  _sink = gpupixel::SinkRawData::Create();
  if (!_source || !_beautyFilter || !_sink) {
    return NO;
  }
  _source->AddSink(_beautyFilter);
  _beautyFilter->AddSink(_sink);
  return YES;
#else
  return NO;
#endif
}

- (void)setSmooth:(CGFloat)value {
  _smooth = MAX(0, MIN(100, value));
}

- (void)setBrighten:(CGFloat)value {
  _brighten = MAX(0, MIN(100, value));
}

- (void)setTone:(CGFloat)value {
  _tone = MAX(0, MIN(100, value));
}

- (nullable CIImage *)processFrontImage:(CIImage *)image {
  if (!image || !self.enabled || !self.available ||
      (self.smooth <= 0 && self.brighten <= 0 && self.tone <= 0)) {
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

  _beautyFilter->SetBlurAlpha((float)(self.smooth / 100.0));
  _beautyFilter->SetWhite((float)(MAX(self.brighten, self.tone) / 100.0));
  _source->ProcessData((const uint8_t *)rgbaData.bytes, width, height, rowBytes, gpupixel::GPUPIXEL_FRAME_TYPE_RGBA);

  const uint8_t *outputBuffer = _sink->GetRgbaBuffer();
  int outputWidth = _sink->GetWidth();
  int outputHeight = _sink->GetHeight();
  if (!outputBuffer || outputWidth <= 0 || outputHeight <= 0) {
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
    NSLog(@"[DualCamera][GPUPixel] raw beauty pipeline active size=%dx%d", outputWidth, outputHeight);
  }
  return outputImage;
#else
  return nil;
#endif
}

@end
