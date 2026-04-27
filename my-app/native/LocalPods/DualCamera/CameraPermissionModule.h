#import <React/RCTBridgeModule.h>

@interface CameraPermissionModule : NSObject <RCTBridgeModule>
- (void)requestAudioPermission:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject;
@end
