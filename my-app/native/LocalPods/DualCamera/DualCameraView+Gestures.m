#import "DualCameraView+Gestures.h"
#import "DualCameraView_Internal.h"

@implementation DualCameraView (Gestures)

- (void)setPipMainIsBack:(BOOL)pipMainIsBack {
  _pipMainIsBack = pipMainIsBack;
  // pipMainIsBack=YES: _frontPreviewView is the small window (enable gestures)
  // pipMainIsBack=NO:  _frontPreviewView is the main view (disable gestures)
  self.pipPanGesture.enabled = pipMainIsBack;
  self.pipPinchGesture.enabled = pipMainIsBack;
}

- (void)setupPipGestures {
  if (_pipPanGesture) {
    if (_pipPanGesture.view != _frontPreviewView) {
      [_pipPanGesture.view removeGestureRecognizer:_pipPanGesture];
      [_pipPinchGesture.view removeGestureRecognizer:_pipPinchGesture];
      [_frontPreviewView addGestureRecognizer:_pipPanGesture];
      [_frontPreviewView addGestureRecognizer:_pipPinchGesture];
    }
    return;
  }

  _pipPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePipPan:)];
  _pipPanGesture.delegate = self;
  _pipPanGesture.enabled = _pipMainIsBack;
  [_frontPreviewView addGestureRecognizer:_pipPanGesture];
  _frontPreviewView.userInteractionEnabled = YES;

  _pipPinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePipPinch:)];
  _pipPinchGesture.delegate = self;
  _pipPinchGesture.enabled = _pipMainIsBack;
  [_frontPreviewView addGestureRecognizer:_pipPinchGesture];
}

- (void)handlePipPan:(UIPanGestureRecognizer *)pan {
  CGPoint translation = [pan translationInView:self];
  CGPoint center = _frontPreviewView.center;
  center.x += translation.x;
  center.y += translation.y;

  CGFloat halfW = _frontPreviewView.bounds.size.width / 2;
  CGFloat halfH = _frontPreviewView.bounds.size.height / 2;
  center.x = MAX(halfW, MIN(self.bounds.size.width - halfW, center.x));
  center.y = MAX(halfH, MIN(self.bounds.size.height - halfH, center.y));

  _frontPreviewView.center = center;
  [pan setTranslation:CGPointZero inView:self];

  _pipPositionX = center.x / self.bounds.size.width;
  _pipPositionY = center.y / self.bounds.size.height;

  if (pan.state == UIGestureRecognizerStateEnded) {
    [[DualCameraEventEmitter shared] sendPipPositionChanged:_pipPositionX y:_pipPositionY];
  }
}

- (void)handlePipPinch:(UIPinchGestureRecognizer *)pinch {
  if (pinch.state == UIGestureRecognizerStateBegan) {
    _lastPipSize = _pipSize;
  }
  CGFloat newSize = _lastPipSize * pinch.scale;
  _pipSize = MAX(0.05, MIN(0.5, newSize));

  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });

  if (pinch.state == UIGestureRecognizerStateEnded) {
    [[DualCameraEventEmitter shared] sendPipSizeChanged:_pipSize];
  }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
  if ((gestureRecognizer == self.pipPanGesture && otherGestureRecognizer == self.pipPinchGesture) ||
      (gestureRecognizer == self.pipPinchGesture && otherGestureRecognizer == self.pipPanGesture)) {
    return YES;
  }
  return NO;
}

@end
