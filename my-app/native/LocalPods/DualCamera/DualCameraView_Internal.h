/**
 * DualCameraView_Internal.h
 *
 * Private header shared by all DualCameraView category implementation files.
 * MUST NOT be imported from any public .h file.
 */

#import "DualCameraView.h"
#import "DualCameraEventEmitter.h"
#import "DualCameraSessionManager.h"
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <ImageIO/ImageIO.h>
#import <math.h>

// ---------------------------------------------------------------------------
// Internal model: layout snapshot passed between compositing & layout code
// ---------------------------------------------------------------------------

@interface DualCameraLayoutState : NSObject
@property (nonatomic, copy) NSString *layoutMode;
@property (nonatomic, assign) CGFloat dualLayoutRatio;
@property (nonatomic, assign) CGFloat pipSize;
@property (nonatomic, assign) CGFloat pipPositionX;
@property (nonatomic, assign) CGFloat pipPositionY;
@property (nonatomic, assign) BOOL sxBackOnTop;
@property (nonatomic, assign) BOOL pipMainIsBack;
@property (nonatomic, assign) CGSize canvasSize;
@property (nonatomic, assign) CGSize outputSize;
@property (nonatomic, assign) BOOL frontMirrored;
@property (nonatomic, assign) BOOL backMirrored;
@property (nonatomic, assign) BOOL isLandscape;
@property (nonatomic, assign) BOOL primaryOnLeadingEdge;
@end

// ---------------------------------------------------------------------------
// Enums (internal to DualCameraView implementation)
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, DualCameraDeviceOrientation) {
  DualCameraDeviceOrientationPortrait,
  DualCameraDeviceOrientationPortraitUpsideDown,
  DualCameraDeviceOrientationLandscapeLeft,
  DualCameraDeviceOrientationLandscapeRight
};

typedef NS_ENUM(NSInteger, DualCameraRealtimeRecordingState) {
  DualCameraRealtimeRecordingStateIdle,
  DualCameraRealtimeRecordingStatePrepared,
  DualCameraRealtimeRecordingStateWriting,
  DualCameraRealtimeRecordingStateFinishing,
  DualCameraRealtimeRecordingStateFailed
};

// ---------------------------------------------------------------------------
// Private class extension — all internal properties
// ---------------------------------------------------------------------------

@interface DualCameraView () <AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) AVCaptureMultiCamSession *multiCamSession;
@property (nonatomic, strong) AVCaptureSession *singleSession;
@property (nonatomic, strong) AVCaptureDeviceInput *frontDeviceInput;
@property (nonatomic, strong) AVCaptureDeviceInput *backDeviceInput;
@property (nonatomic, strong) AVCaptureDeviceInput *singleDeviceInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *frontPreviewLayer;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *backPreviewLayer;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *singlePreviewLayer;
@property (nonatomic, strong) AVCapturePhotoOutput *frontPhotoOutput;
@property (nonatomic, strong) AVCapturePhotoOutput *backPhotoOutput;
@property (nonatomic, strong) AVCapturePhotoOutput *singlePhotoOutput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *singleMovieOutput;
@property (nonatomic, assign) BOOL singleRecordingStartPending;
@property (nonatomic, assign) BOOL singleRecordingStopRequested;
@property (nonatomic, strong) UIView *frontPreviewView;
@property (nonatomic, strong) UIView *backPreviewView;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, assign) AVCaptureDevicePosition singleCameraPosition;
@property (nonatomic, assign) BOOL usingMultiCam;
@property (nonatomic, assign) BOOL isConfigured;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, copy) NSString *currentLayout;

// VideoDataOutput for WYSIWYG photo capture
@property (nonatomic, strong) AVCaptureVideoDataOutput *frontVideoDataOutput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *backVideoDataOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;
@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) CIImage *latestFrontFrame;
@property (nonatomic, strong) CIImage *latestBackFrame;
@property (nonatomic, strong) CIContext *ciContext;

// Dual compositing state
@property (nonatomic, strong) NSMutableDictionary *pendingDualPhotos;
@property (nonatomic, assign) BOOL pendingDualPhotosFront;
@property (nonatomic, assign) BOOL pendingDualPhotosBack;
@property (nonatomic, assign) BOOL isDualRecordingActive;

// High-resolution dual photo capture state.
// When the user takes a photo in multicam dual layout, both AVCapturePhotoOutputs
// are triggered in parallel; their CIImages and metadata accumulate here until
// both arrive, at which point compositing happens on a background queue.
@property (nonatomic, strong) CIImage *pendingPhotoFrontImage;
@property (nonatomic, strong) CIImage *pendingPhotoBackImage;
@property (nonatomic, assign) CGImagePropertyOrientation pendingPhotoFrontOrientation;
@property (nonatomic, assign) CGImagePropertyOrientation pendingPhotoBackOrientation;
@property (nonatomic, assign) BOOL pendingPhotoFrontReceived;
@property (nonatomic, assign) BOOL pendingPhotoBackReceived;
@property (nonatomic, assign) BOOL pendingPhotoCaptureInFlight;
@property (nonatomic, assign) CGSize pendingPhotoCanvasSize;
@property (nonatomic, strong) DualCameraLayoutState *pendingPhotoLayoutState;
@property (nonatomic, strong) AVAssetExportSession *videoExportSession;
@property (nonatomic, strong) dispatch_queue_t compositingQueue;
@property (nonatomic, strong) AVAssetWriter *realtimeAssetWriter;
@property (nonatomic, strong) AVAssetWriterInput *realtimeVideoInput;
@property (nonatomic, strong) AVAssetWriterInput *realtimeAudioInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *realtimePixelBufferAdaptor;
@property (nonatomic, copy) NSString *realtimeRecordingPath;
@property (nonatomic, copy) NSString *realtimeRecordingAspectRatio;
@property (nonatomic, assign) CGSize realtimeOutputSize;
@property (nonatomic, assign) DualCameraRealtimeRecordingState realtimeRecordingState;
@property (nonatomic, assign) BOOL realtimeWriterStarted;
@property (nonatomic, assign) BOOL realtimeFinishRequested;
@property (nonatomic, assign) BOOL realtimeFinishWhenFirstFrameWritten;
@property (nonatomic, assign) BOOL realtimeRecordingStartedEventEmitted;
@property (nonatomic, assign) NSInteger realtimeDroppedFrameCount;
@property (nonatomic, assign) NSInteger realtimeWrittenVideoFrameCount;
@property (nonatomic, assign) NSInteger realtimeDroppedAudioSampleCount;
@property (nonatomic, strong) DualCameraLayoutState *recordingLayoutState;
@property (nonatomic, assign) CMTime lastRealtimeVideoPTS;
@property (nonatomic, assign) BOOL hasLastRealtimeVideoPTS;

// canvasSizeAtRecording — only declared here (not in .h), used internally
@property (nonatomic, assign) CGSize canvasSizeAtRecording;

// PiP gesture recognizers
@property (nonatomic, strong) UIPanGestureRecognizer *pipPanGesture;
@property (nonatomic, strong) UIPinchGestureRecognizer *pipPinchGesture;
@property (nonatomic, assign) CGFloat lastPipSize;
@property (nonatomic, assign) DualCameraDeviceOrientation deviceOrientation;
@property (nonatomic, assign) BOOL frontPreviewMirrored;
@property (nonatomic, assign) BOOL frontOutputMirrored;
@property (nonatomic, assign) BOOL backPreviewMirrored;
@property (nonatomic, assign) BOOL backOutputMirrored;

// YES when the current multicam back input is the ultra-wide physical camera.
// Wide-angle is used otherwise. Managed by switchBackCameraToUltraWide:.
@property (nonatomic, assign) BOOL backUsingUltraWide;

@end

// ---------------------------------------------------------------------------
// Forward-declare all category method signatures so every category .m can
// call sibling methods without compiler warnings.
// (ObjC dispatches these at runtime; headers are only needed for the compiler.)
// ---------------------------------------------------------------------------
#import "DualCameraView+Orientation.h"
#import "DualCameraView+Layout.h"
#import "DualCameraView+Composition.h"
#import "DualCameraView+Gestures.h"
#import "DualCameraView+Session.h"
#import "DualCameraView+Recording.h"
#import "DualCameraView+Capture.h"
