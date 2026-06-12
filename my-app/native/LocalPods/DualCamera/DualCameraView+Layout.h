#import "DualCameraView.h"

@class DualCameraLayoutState;

/**
 * DualCameraView+Layout
 *
 * Canvas geometry, preview-view frame calculation, layout state snapshots,
 * preview layer management, and layout-related helpers.
 */
@interface DualCameraView (Layout)

// ---------------------------------------------------------------------------
// Canvas
// ---------------------------------------------------------------------------

/// Returns the CGRect inside self.bounds that satisfies the current saveAspectRatio.
- (CGRect)canvasBoundsForAspectRatio;

// ---------------------------------------------------------------------------
// Layout state snapshot
// ---------------------------------------------------------------------------

- (DualCameraLayoutState *)currentLayoutStateForCanvasSize:(CGSize)canvasSize
                                                outputSize:(CGSize)outputSize;

- (DualCameraLayoutState *)layoutStateSnapshotForCanvasSize:(CGSize)canvasSize
                                                 outputSize:(CGSize)outputSize
                                                orientation:(NSInteger)orientation;

// ---------------------------------------------------------------------------
// Rect calculation
// ---------------------------------------------------------------------------

/// Returns {back: NSValue(CGRect), front: NSValue(CGRect)} for a given layout state.
- (NSDictionary<NSString *, NSValue *> *)rectsForLayoutState:(DualCameraLayoutState *)state
                                                  canvasSize:(CGSize)canvasSize;

// ---------------------------------------------------------------------------
// View update
// ---------------------------------------------------------------------------

/// Apply current layout to preview subviews (frame, visibility, corner radius).
- (void)updateLayout;

// ---------------------------------------------------------------------------
// Preview view / layer management
// ---------------------------------------------------------------------------

- (void)createPlaceholderViews;
- (void)removePreviewLayers;
- (void)clearPreviewLayersOnMainQueue;
- (void)bringFrontBeautyPreviewToFront;

// ---------------------------------------------------------------------------
// Convenience helpers
// ---------------------------------------------------------------------------

/// YES for any layout that requires both cameras simultaneously.
- (BOOL)isDualLayout:(NSString *)layout;

/// The "primary" camera for single-cam mode (back for all layouts except "front").
- (AVCaptureDevicePosition)primaryCameraPosition;

/// Returns the preview UIView associated with the given camera position.
- (UIView *)targetPreviewViewForPosition:(AVCaptureDevicePosition)position;

@end
