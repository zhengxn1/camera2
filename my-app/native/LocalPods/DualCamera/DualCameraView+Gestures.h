#import "DualCameraView.h"

/**
 * DualCameraView+Gestures
 *
 * PiP window pan (drag) and pinch (resize) gesture recognizers,
 * including UIGestureRecognizerDelegate conformance.
 */
@interface DualCameraView (Gestures)

/// Create (or re-attach) the pan and pinch gesture recognizers on _frontPreviewView.
- (void)setupPipGestures;

@end
