#import <CoreImage/CoreImage.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GPUPixelBeautyAdapter : NSObject

@property (nonatomic, assign, readonly) BOOL available;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) CGFloat smooth;
@property (nonatomic, assign) CGFloat whiten;

- (instancetype)initWithCIContext:(CIContext *)ciContext NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (nullable CIImage *)processFrontImage:(CIImage *)image;

@end

NS_ASSUME_NONNULL_END
