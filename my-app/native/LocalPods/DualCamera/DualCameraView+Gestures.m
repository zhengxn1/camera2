#import "DualCameraView+Gestures.h"
#import "DualCameraView_Internal.h"

@implementation DualCameraView (Gestures)

- (void)setupPipGestures {
  if (self.pipPanGesture) {
    if (self.pipPanGesture.view != self.frontPreviewView) {
      [self.pipPanGesture.view removeGestureRecognizer:self.pipPanGesture];
      [self.pipPinchGesture.view removeGestureRecognizer:self.pipPinchGesture];
      [self.frontPreviewView addGestureRecognizer:self.pipPanGesture];
      [self.frontPreviewView addGestureRecognizer:self.pipPinchGesture];
    }
    return;
  }

  self.pipPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePipPan:)];
  self.pipPanGesture.delegate = self;
  self.pipPanGesture.enabled = self.pipMainIsBack;
  [self.frontPreviewView addGestureRecognizer:self.pipPanGesture];
  self.frontPreviewView.userInteractionEnabled = YES;

  self.pipPinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePipPinch:)];
  self.pipPinchGesture.delegate = self;
  self.pipPinchGesture.enabled = self.pipMainIsBack;
  [self.frontPreviewView addGestureRecognizer:self.pipPinchGesture];
}

- (void)handlePipPan:(UIPanGestureRecognizer *)pan {
  CGPoint translation = [pan translationInView:self];
  CGPoint center = self.frontPreviewView.center;
  center.x += translation.x;
  center.y += translation.y;

  CGFloat halfW = self.frontPreviewView.bounds.size.width / 2;
  CGFloat halfH = self.frontPreviewView.bounds.size.height / 2;
  center.x = MAX(halfW, MIN(self.bounds.size.width - halfW, center.x));
  center.y = MAX(halfH, MIN(self.bounds.size.height - halfH, center.y));

  self.frontPreviewView.center = center;
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
