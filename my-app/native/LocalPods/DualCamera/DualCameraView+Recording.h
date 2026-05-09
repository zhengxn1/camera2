#import "DualCameraView.h"
#import <AVFoundation/AVFoundation.h>

/**
 * DualCameraView+Recording
 *
 * Real-time dual-camera recording via AVAssetWriter:
 * prepare → write video/audio frames → finish/fail.
 * Also owns the error-emission helpers for recording events.
 */
@interface DualCameraView (Recording)

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

/// Prepare the AVAssetWriter for a new recording. Returns NO on failure (error emitted internally).
- (BOOL)startRealtimeRecordingWithCanvasSize:(CGSize)canvasSize;

/// Start the underlying AVAssetWriter at the given sample timestamp (idempotent).
- (BOOL)ensureRealtimeWriterStartedAtTime:(CMTime)time;

/// Append one composited video frame. Called on realtimeRenderQueue.
- (void)appendRealtimeVideoFrameAtTime:(CMTime)time source:(NSString *)source;

/// Append one audio sample buffer. Called on videoDataOutputQueue.
- (void)appendRealtimeAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;

/// Finalise the recording and emit recordingFinished / recordingError.
- (void)finishRealtimeRecording;

/// Immediately cancel and emit a recording error.
- (void)failRealtimeRecording:(NSString *)message;

/// Reset all realtime-recording ivars back to their idle defaults.
- (void)resetRealtimeRecordingContext;

// ---------------------------------------------------------------------------
// Event emission
// ---------------------------------------------------------------------------
- (void)emitRecordingFinished:(NSString *)uri;
- (void)emitRecordingStarted;
- (void)emitRecordingError:(NSString *)error;
- (void)emitRecordingError:(NSString *)error details:(NSDictionary *)details;
- (void)emitRecordingErrorForError:(NSError *)error
                            prefix:(NSString *)prefix
                           context:(NSString *)context
                       rejectedPTS:(CMTime)rejectedPTS;

@end
