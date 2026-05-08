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
// Device / format helpers (used by configure methods)
// ---------------------------------------------------------------------------
- (AVCaptureDevice *)cameraDeviceForPosition:(AVCaptureDevicePosition)position;
- (BOOL)configureDeviceForMultiCam:(AVCaptureDevice *)device error:(NSError **)error;
- (AVCaptureDeviceFormat *)bestMultiCamFormatForDevice:(AVCaptureDevice *)device;
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
