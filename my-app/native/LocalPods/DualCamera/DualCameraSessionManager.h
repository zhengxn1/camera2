#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DualCameraView;

@interface DualCameraSessionManager : NSObject

+ (instancetype)shared;

- (void)registerView:(DualCameraView *)view;
- (void)startSession;
- (void)stopSession;
- (void)takePhoto;
- (void)startRecording;
- (void)stopRecording;
- (void)flipCamera;
- (void)setZoom:(NSString *)camera factor:(CGFloat)factor;

@end

NS_ASSUME_NONNULL_END
