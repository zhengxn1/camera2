#import <React/RCTEventEmitter.h>

@interface DualCameraEventEmitter : RCTEventEmitter <RCTBridgeModule>

+ (instancetype)shared;

- (void)sendPhotoSaved:(NSString *)uri;
- (void)sendPhotoSaved:(NSString *)uri uris:(NSDictionary *)uris;
- (void)sendPhotoError:(NSString *)error;
- (void)sendRecordingStarted;
- (void)sendRecordingFinished:(NSString *)uri;
- (void)sendRecordingFinished:(NSString *)uri uris:(NSDictionary *)uris;
- (void)sendRecordingError:(NSString *)error;
- (void)sendRecordingError:(NSString *)error details:(NSDictionary *)details;
- (void)sendSessionError:(NSString *)error code:(NSString *)code;
- (void)sendAudioLevel:(float)average peak:(float)peak;
- (void)sendPipPositionChanged:(CGFloat)x y:(CGFloat)y;
- (void)sendPipSizeChanged:(CGFloat)size;

@end
