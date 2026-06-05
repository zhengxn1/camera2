#import "DualCameraView+Gestures.h"
#import "DualCameraView_Internal.h"
#import "DualCameraView+Layout.h"

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
  CGRect canvas = [self canvasBoundsForAspectRatio];
  if (canvas.size.width <= 0 || canvas.size.height <= 0) return;
  if (self.frontBeautyEnabled &&
      (pan.state == UIGestureRecognizerStateBegan ||
       pan.state == UIGestureRecognizerStateChanged)) {
    [self invalidateBeautyPreviewForLayoutChange:@"pipPan"];
  }
  CGPoint translation = [pan translationInView:self];
  CGPoint center = pipView.center;
  center.x += translation.x;
  center.y += translation.y;

  CGFloat halfW = pipView.bounds.size.width / 2;
  CGFloat halfH = pipView.bounds.size.height / 2;
  CGFloat minX = canvas.origin.x + halfW;
  CGFloat maxX = CGRectGetMaxX(canvas) - halfW;
  CGFloat minY = canvas.origin.y + halfH;
  CGFloat maxY = CGRectGetMaxY(canvas) - halfH;
  center.x = MAX(minX, MIN(maxX, center.x));
  center.y = MAX(minY, MIN(maxY, center.y));

  pipView.center = center;
  [pan setTranslation:CGPointZero inView:self];

  self.pipPositionX = (center.x - canvas.origin.x) / canvas.size.width;
  self.pipPositionY = (center.y - canvas.origin.y) / canvas.size.height;

  if (pan.state == UIGestureRecognizerStateEnded) {
    [[DualCameraEventEmitter shared] sendPipPositionChanged:self.pipPositionX y:self.pipPositionY];
  }
}

- (void)handlePipPinch:(UIPinchGestureRecognizer *)pinch {
  if (pinch.state == UIGestureRecognizerStateBegan) {
    self.lastPipSize = self.pipSize;
  }
  if (self.frontBeautyEnabled &&
      (pinch.state == UIGestureRecognizerStateBegan ||
       pinch.state == UIGestureRecognizerStateChanged)) {
    [self invalidateBeautyPreviewForLayoutChange:@"pipPinch"];
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
