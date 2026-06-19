#import "DualCameraEventEmitter.h"

static DualCameraEventEmitter *sharedEmitter = nil;

@implementation DualCameraEventEmitter {
  BOOL _hasListeners;
}

RCT_EXPORT_MODULE()

- (instancetype)init {
  NSLog(@"[DualCamera] DualCameraEventEmitter init called");
  self = [super init];
  if (self) {
    sharedEmitter = self;
  }
  return self;
}

+ (instancetype)shared {
  return sharedEmitter;
}

- (NSArray<NSString *> *)supportedEvents {
  return @[@"onPhotoSaved", @"onPhotoError", @"onRecordingStarted", @"onRecordingFinished", @"onRecordingError", @"onSessionError", @"onAudioLevel", @"onPipPositionChanged", @"onPipSizeChanged"];
}

- (void)startObserving { _hasListeners = YES; }
- (void)stopObserving  { _hasListeners = NO; }

+ (BOOL)requiresMainQueueSetup { return YES; }

- (void)sendPhotoSaved:(NSString *)uri {
  [self sendPhotoSaved:uri uris:nil];
}

- (void)sendPhotoSaved:(NSString *)uri uris:(NSDictionary *)uris {
  NSMutableDictionary *body = [@{@"uri": uri ?: @""} mutableCopy];
  if (uris) {
    body[@"uris"] = uris;
  }
  [self sendEventIfNeeded:@"onPhotoSaved" body:body];
}

- (void)sendPhotoError:(NSString *)error {
  [self sendEventIfNeeded:@"onPhotoError" body:@{@"error": error ?: @"Photo error"}];
}

- (void)sendRecordingStarted {
  [self sendEventIfNeeded:@"onRecordingStarted" body:@{}];
}

- (void)sendRecordingFinished:(NSString *)uri {
  [self sendRecordingFinished:uri uris:nil];
}

- (void)sendRecordingFinished:(NSString *)uri uris:(NSDictionary *)uris {
  NSMutableDictionary *body = [@{@"uri": uri ?: @""} mutableCopy];
  if (uris) {
    body[@"uris"] = uris;
  }
  [self sendEventIfNeeded:@"onRecordingFinished" body:body];
}

- (void)sendRecordingError:(NSString *)error {
  [self sendEventIfNeeded:@"onRecordingError" body:@{@"error": error ?: @"Recording error"}];
}

- (void)sendRecordingError:(NSString *)error details:(NSDictionary *)details {
  NSMutableDictionary *body = [@{@"error": error ?: @"Recording error"} mutableCopy];
  if (details) {
    [body addEntriesFromDictionary:details];
  }
  [self sendEventIfNeeded:@"onRecordingError" body:body];
}

- (void)sendSessionError:(NSString *)error code:(NSString *)code {
  [self sendEventIfNeeded:@"onSessionError" body:@{@"error": error ?: @"Camera session error", @"code": code ?: @"session_error"}];
}

- (void)sendAudioLevel:(float)average peak:(float)peak {
  [self sendEventIfNeeded:@"onAudioLevel" body:@{@"average": @(average), @"peak": @(peak)}];
}

- (void)sendPipPositionChanged:(CGFloat)x y:(CGFloat)y {
  [self sendEventIfNeeded:@"onPipPositionChanged" body:@{@"x": @(x), @"y": @(y)}];
}

- (void)sendPipSizeChanged:(CGFloat)size {
  [self sendEventIfNeeded:@"onPipSizeChanged" body:@{@"size": @(size)}];
}

- (void)sendEventIfNeeded:(NSString *)name body:(NSDictionary *)body {
  if (!_hasListeners) return;

  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_hasListeners) {
      [self sendEventWithName:name body:body];
    }
  });
}

@end
