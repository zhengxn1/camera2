#import "DualCameraView.h"
#import <AVFoundation/AVFoundation.h>

/**
 * DualCameraView+Capture
 *
 * Photo and video recording entry points, output selectors, and all
 * AVFoundation delegate callbacks (photo, file output, sample buffer).
 */
@interface DualCameraView (Capture)

// ---------------------------------------------------------------------------
// Entry points (called from DualCameraView.m bridge methods)
// ---------------------------------------------------------------------------
- (void)internalTakePhoto;
- (void)internalStartRecording;
- (void)internalStopRecording;

// ---------------------------------------------------------------------------
// Output selectors
// ---------------------------------------------------------------------------
- (BOOL)isUsingMultiCamDualLayout;
- (AVCapturePhotoOutput *)photoOutputForCurrentLayout;
- (AVCaptureMovieFileOutput *)movieOutputForCurrentLayout;
- (AVCaptureMovieFileOutput *)activeRecordingOutput;

// ---------------------------------------------------------------------------
// Event emission
// ---------------------------------------------------------------------------
- (void)emitPhotoSaved:(NSString *)uri;
- (void)emitPhotoSaved:(NSString *)uri uris:(NSDictionary *)uris;
- (void)emitError:(NSString *)error;

@end
