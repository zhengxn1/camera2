#import "DualCameraSessionManager.h"
#import "DualCameraView.h"
#import "DualCameraEventEmitter.h"

@implementation DualCameraSessionManager {
  DualCameraView *_registeredView;
  BOOL _startRequested;
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
  if (_startRequested && _registeredView) {
    NSLog(@"[DualCamera] Pending start request found; starting newly registered view.");
    [_registeredView dc_startSession];
  }
}

- (void)startSession {
  NSLog(@"[DualCamera] SessionManager startSession called, registeredView=%@", _registeredView);
  _startRequested = YES;
  if (!_registeredView) {
    NSLog(@"[DualCamera] No registered view yet; start request will run after view registration.");
    return;
  }
  [_registeredView dc_startSession];
}
- (void)stopSession     { _startRequested = NO; [_registeredView dc_stopSession]; }
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
