#import "DualCameraView.h"
#import <AVFoundation/AVFoundation.h>

/**
 * DualCameraView+Session
 *
 * AVCaptureSession lifecycle (start / stop / configure / reconfigure),
 * camera device helpers, zoom, and session runtime notifications.
 */
@interface DualCameraView (Session)

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------
- (void)internalStartSession;
- (void)internalStopSession;
- (void)startOnSessionQueue;
- (void)resumeIfNeeded;

// ---------------------------------------------------------------------------
// Multi-cam and single-cam configuration
// ---------------------------------------------------------------------------
- (void)configureAndStartMultiCamSession;
- (void)configureAndStartSingleCameraFallback;
- (void)configureSingleSessionForPosition:(AVCaptureDevicePosition)position
                             startRunning:(BOOL)startRunning;
- (void)reconfigureSingleSessionForCurrentLayout;

// ---------------------------------------------------------------------------
// Zoom
// ---------------------------------------------------------------------------
- (void)dc_setFrontZoom:(CGFloat)factor;
- (void)dc_setBackZoom:(CGFloat)factor;

// ---------------------------------------------------------------------------
// Back camera lens switching (multicam only)
// ---------------------------------------------------------------------------

// Switch the multicam back input between ultra-wide and wide-angle.
// Must be called on sessionQueue. No-op in single-cam mode.
- (void)switchBackCameraToUltraWide:(BOOL)useUltraWide;

// Map a user-facing zoom level (0.5x = ultra-wide FOV) to the device
// videoZoomFactor for the physical camera currently in use.
- (CGFloat)backDeviceZoomForUserZoom:(CGFloat)userZoom;

// ---------------------------------------------------------------------------
// Device / format helpers (used by configure methods)
// ---------------------------------------------------------------------------
- (AVCaptureDevice *)cameraDeviceForPosition:(AVCaptureDevicePosition)position;
- (BOOL)configureDeviceForMultiCam:(AVCaptureDevice *)device error:(NSError **)error;
- (AVCaptureDeviceFormat *)bestMultiCamFormatForDevice:(AVCaptureDevice *)device;
- (BOOL)formatIsPreferredSDR:(AVCaptureDeviceFormat *)format;
- (BOOL)formatLooksHDR:(AVCaptureDeviceFormat *)format;
- (BOOL)formatSupportsThirtyFps:(AVCaptureDeviceFormat *)format;
- (AVCaptureInputPort *)videoPortForInput:(AVCaptureDeviceInput *)input;

- (BOOL)addPreviewLayer:(AVCaptureVideoPreviewLayer *)layer
                forPort:(AVCaptureInputPort *)port
              toSession:(AVCaptureSession *)session
            mirrorVideo:(BOOL)mirrorVideo
                failure:(NSString **)failure
            failureCode:(NSString **)failureCode;

- (BOOL)addOutput:(AVCaptureOutput *)output
          forPort:(AVCaptureInputPort *)port
        toSession:(AVCaptureSession *)session
          failure:(NSString **)failure
      failureCode:(NSString **)failureCode;

- (void)addAudioConnectionToMovieOutput:(AVCaptureDeviceInput *)audioInput
                                 output:(AVCaptureMovieFileOutput *)movieOutput
                                session:(AVCaptureSession *)session;

// ---------------------------------------------------------------------------
// Session notifications
// ---------------------------------------------------------------------------
- (void)registerSessionNotifications:(AVCaptureSession *)session;
- (void)unregisterSessionNotifications;

// ---------------------------------------------------------------------------
// Event emission
// ---------------------------------------------------------------------------
- (void)emitSessionError:(NSString *)error code:(NSString *)code;

@end
