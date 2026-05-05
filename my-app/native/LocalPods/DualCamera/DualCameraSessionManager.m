#import "DualCameraSessionManager.h"
#import "DualCameraView.h"
#import "DualCameraEventEmitter.h"

@implementation DualCameraSessionManager {
  DualCameraView *_registeredView;
}

+ (instancetype)shared {
  static DualCameraSessionManager *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[DualCameraSessionManager alloc] init];
  });
  return instance;
}

- (void)registerView:(DualCameraView *)view {
  NSLog(@"[DualCamera] SessionManager registerView called, view=%@", view);
  _registeredView = view;
}

- (void)startSession {
  NSLog(@"[DualCamera] SessionManager startSession called, registeredView=%@", _registeredView);
  if (!_registeredView) {
    NSLog(@"[DualCamera] ERROR: No registered view! dualcam native module not connected to JS.");
    return;
  }
  [_registeredView dc_startSession];
}
- (void)stopSession     { [_registeredView dc_stopSession]; }
- (void)takePhoto       { [_registeredView dc_takePhoto]; }
- (void)startRecording  { [_registeredView dc_startRecording]; }
- (void)stopRecording   { [_registeredView dc_stopRecording]; }
- (void)flipCamera      { [_registeredView dc_flipCamera]; }
- (void)setZoom:(NSString *)camera factor:(CGFloat)factor {
  if ([camera isEqualToString:@"front"]) {
    [_registeredView dc_setFrontZoom:factor];
  } else {
    [_registeredView dc_setBackZoom:factor];
  }
}

@end
