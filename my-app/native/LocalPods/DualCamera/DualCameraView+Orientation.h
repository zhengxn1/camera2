#import "DualCameraView.h"
#import <AVFoundation/AVFoundation.h>

/**
 * DualCameraView+Orientation
 *
 * Device-orientation monitoring and applying video orientation / mirroring
 * to all active connections and outputs.
 */
@interface DualCameraView (Orientation)

- (void)startDeviceOrientationMonitoring;

/// Process a raw UIDeviceOrientation value and update internal state + layout if changed.
- (void)updateDeviceOrientation:(UIDeviceOrientation)orientation;

/// Returns the AVCaptureVideoOrientation matching the current device orientation.
- (AVCaptureVideoOrientation)currentCaptureVideoOrientation;

/// YES if the current device orientation is landscape.
- (BOOL)isCurrentDeviceLandscape;

/// YES if the given internal orientation value is landscape.
- (BOOL)isDeviceOrientationLandscape:(NSInteger)orientation;

/// YES when the primary (back/larger) panel should appear on the leading edge for the given orientation.
- (BOOL)primaryOnLeadingEdgeForDeviceOrientation:(NSInteger)orientation;

/// Apply orientation+mirroring to a single AVCaptureConnection.
- (void)applyOrientation:(AVCaptureVideoOrientation)orientation
             mirrored:(BOOL)mirrored
         toConnection:(AVCaptureConnection *)connection;

/// Apply orientation+mirroring to all connections of an AVCaptureOutput.
- (void)applyOrientation:(AVCaptureVideoOrientation)orientation
             mirrored:(BOOL)mirrored
            toOutput:(AVCaptureOutput *)output;

/// Reapply the current device orientation and mirroring settings to every
/// preview layer connection, photo output, and video data output.
- (void)applyCurrentVideoOrientationAndMirroring;

@end
