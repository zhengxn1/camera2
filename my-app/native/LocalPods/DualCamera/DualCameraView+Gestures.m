#import "DualCameraView+Gestures.h"
#import "DualCameraView_Internal.h"

@implementation DualCameraView (Gestures)

- (UIView *)pipPreviewView {
  return self.pipMainIsBack ? self.frontPreviewView : self.backPreviewView;
}

- (void)setupPipGestures {
  UIView *pipView = [self pipPreviewView];

  if (self.pipPanGesture) {
    // Re-attach to whichever view is currently the PIP.
    if (self.pipPanGesture.view != pipView) {
      [self.pipPanGesture.view removeGestureRecognizer:self.pipPanGesture];
      [self.pipPinchGesture.view removeGestureRecognizer:self.pipPinchGesture];
      [pipView addGestureRecognizer:self.pipPanGesture];
      [pipView addGestureRecognizer:self.pipPinchGesture];
    }
    self.pipPanGesture.enabled = YES;
    self.pipPinchGesture.enabled = YES;
    pipView.userInteractionEnabled = YES;
    return;
  }

  self.pipPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePipPan:)];
  self.pipPanGesture.delegate = self;
  [pipView addGestureRecognizer:self.pipPanGesture];
  pipView.userInteractionEnabled = YES;

  self.pipPinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePipPinch:)];
  self.pipPinchGesture.delegate = self;
  [pipView addGestureRecognizer:self.pipPinchGesture];
}

- (void)handlePipPan:(UIPanGestureRecognizer *)pan {
  UIView *pipView = [self pipPreviewView];
  CGPoint translation = [pan translationInView:self];
  CGPoint center = pipView.center;
  center.x += translation.x;
  center.y += translation.y;

  CGFloat halfW = pipView.bounds.size.width / 2;
  CGFloat halfH = pipView.bounds.size.height / 2;
  center.x = MAX(halfW, MIN(self.bounds.size.width - halfW, center.x));
  center.y = MAX(halfH, MIN(self.bounds.size.height - halfH, center.y));

  pipView.center = center;
  [pan setTranslation:CGPointZero inView:self];

  self.pipPositionX = center.x / self.bounds.size.width;
  self.pipPositionY = center.y / self.bounds.size.height;

  if (pan.state == UIGestureRecognizerStateEnded) {
    [[DualCameraEventEmitter shared] sendPipPositionChanged:self.pipPositionX y:self.pipPositionY];
  }
}

- (void)handlePipPinch:(UIPinchGestureRecognizer *)pinch {
  if (pinch.state == UIGestureRecognizerStateBegan) {
    self.lastPipSize = self.pipSize;
  }
  CGFloat newSize = self.lastPipSize * pinch.scale;
  self.pipSize = MAX(0.05, MIN(0.5, newSize));

  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });

  if (pinch.state == UIGestureRecognizerStateEnded) {
    [[DualCameraEventEmitter shared] sendPipSizeChanged:self.pipSize];
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
