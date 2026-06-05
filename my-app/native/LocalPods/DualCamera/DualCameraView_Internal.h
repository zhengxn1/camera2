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
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Vision/Vision.h>
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
@property (nonatomic, strong) dispatch_queue_t realtimeRenderQueue;
@property (nonatomic, strong) dispatch_queue_t beautyProcessingQueue;
@property (nonatomic, strong) CIImage *latestRawFrontFrame;
@property (nonatomic, strong) CIImage *latestFrontFrame;
@property (nonatomic, strong) CIImage *latestBackFrame;
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) id<MTLDevice> metalDevice;
@property (nonatomic, strong) id<MTLCommandQueue> metalCommandQueue;
@property (nonatomic, strong) MTKView *beautyPreviewView;
@property (nonatomic, strong) CIImage *latestBeautyPreviewFrame;
@property (nonatomic, assign) CGSize beautyPreviewTargetSize;
@property (nonatomic, assign) NSInteger beautyLayoutGeneration;
@property (nonatomic, assign) NSInteger latestBeautyPreviewGeneration;
@property (nonatomic, copy) NSString *latestBeautyPreviewLayoutMode;
@property (nonatomic, assign) CGSize latestBeautyPreviewTargetSize;
@property (nonatomic, assign) BOOL latestBeautyPreviewMirrored;
@property (nonatomic, assign) BOOL beautyProcessingInFlight;
@property (nonatomic, assign) BOOL beautyProcessingNeedsAnotherFrame;
@property (nonatomic, assign) BOOL beautyPreviewFrameScheduled;
@property (nonatomic, assign) BOOL layoutUpdateScheduled;
@property (nonatomic, assign) BOOL beautyLayoutChanging;
@property (nonatomic, assign) CFTimeInterval lastBeautyLayoutChangeTime;
@property (nonatomic, assign) CFTimeInterval lastBeautyPreviewRenderTime;
@property (nonatomic, assign) NSInteger beautyPreviewSkippedRenderCount;
@property (nonatomic, assign) CFTimeInterval lastBeautyLayoutDiagLogTime;
@property (nonatomic, assign) CFTimeInterval lastBeautyPreviewDiagLogTime;
@property (nonatomic, assign) CFTimeInterval lastBeautyRenderDiagLogTime;
@property (nonatomic, assign) CFTimeInterval lastBeautyFaceDiagLogTime;
@property (nonatomic, strong) CIImage *frontBeautyMask;
@property (nonatomic, assign) CGRect frontBeautyMaskFaceBounds;
@property (nonatomic, assign) CGSize frontBeautyMaskImageSize;
@property (nonatomic, assign) NSInteger frontBeautyFrameCounter;
@property (nonatomic, strong) VNFaceObservation *frontBeautyFaceObservation;
@property (nonatomic, assign) NSInteger frontBeautyFramesSinceFace;

// Dual compositing state
@property (nonatomic, strong) NSMutableDictionary *pendingDualPhotos;
@property (nonatomic, assign) BOOL pendingDualPhotosFront;
@property (nonatomic, assign) BOOL pendingDualPhotosBack;
@property (nonatomic, assign) BOOL isDualRecordingActive;
@property (nonatomic, strong) AVAssetExportSession *videoExportSession;
@property (nonatomic, strong) dispatch_queue_t compositingQueue;
@property (nonatomic, strong) AVAssetWriter *realtimeAssetWriter;
@property (nonatomic, strong) AVAssetWriterInput *realtimeVideoInput;
@property (nonatomic, strong) AVAssetWriterInput *realtimeAudioInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *realtimePixelBufferAdaptor;
@property (nonatomic, strong) AVAssetWriter *frontRealtimeAssetWriter;
@property (nonatomic, strong) AVAssetWriterInput *frontRealtimeVideoInput;
@property (nonatomic, strong) AVAssetWriterInput *frontRealtimeAudioInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *frontRealtimePixelBufferAdaptor;
@property (nonatomic, strong) AVAssetWriter *backRealtimeAssetWriter;
@property (nonatomic, strong) AVAssetWriterInput *backRealtimeVideoInput;
@property (nonatomic, strong) AVAssetWriterInput *backRealtimeAudioInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *backRealtimePixelBufferAdaptor;
@property (nonatomic, strong) NSDictionary *warmedRealtimeVideoSettings;
@property (nonatomic, strong) NSDictionary *warmedRealtimePixelBufferAttributes;
@property (nonatomic, strong) NSDictionary *warmedRealtimeAudioSettings;
@property (nonatomic, copy) NSString *warmedRealtimeAspectRatio;
@property (nonatomic, assign) CGSize warmedRealtimeCanvasSize;
@property (nonatomic, assign) CGSize warmedRealtimeOutputSize;
@property (nonatomic, assign) BOOL realtimePipelineWarmupInProgress;
@property (nonatomic, assign) BOOL realtimePipelineWarmed;
@property (nonatomic, assign) BOOL pendingStartRecordingAfterWarmup;
@property (nonatomic, assign) CGSize pendingStartRecordingCanvasSize;
@property (nonatomic, copy) NSString *realtimeRecordingPath;
@property (nonatomic, copy) NSString *frontRealtimeRecordingPath;
@property (nonatomic, copy) NSString *backRealtimeRecordingPath;
@property (nonatomic, copy) NSString *realtimeRecordingAspectRatio;
@property (nonatomic, assign) CGSize realtimeOutputSize;
@property (nonatomic, assign) CGSize frontRealtimeOutputSize;
@property (nonatomic, assign) CGSize backRealtimeOutputSize;
@property (nonatomic, assign) DualCameraRealtimeRecordingState realtimeRecordingState;
@property (nonatomic, assign) BOOL realtimeWriterStarted;
@property (nonatomic, assign) BOOL frontRealtimeWriterStarted;
@property (nonatomic, assign) BOOL backRealtimeWriterStarted;
@property (nonatomic, assign) BOOL realtimeFinishRequested;
@property (nonatomic, assign) BOOL realtimeFinishWhenFirstFrameWritten;
@property (nonatomic, assign) BOOL realtimeRecordingStartedEventEmitted;
@property (nonatomic, assign) NSInteger realtimeDroppedFrameCount;
@property (nonatomic, assign) NSInteger realtimeWrittenVideoFrameCount;
@property (nonatomic, assign) NSInteger frontRealtimeWrittenVideoFrameCount;
@property (nonatomic, assign) NSInteger backRealtimeWrittenVideoFrameCount;
@property (nonatomic, assign) NSInteger realtimeDroppedAudioSampleCount;
@property (nonatomic, strong) DualCameraLayoutState *recordingLayoutState;
@property (nonatomic, assign) CMTime lastRealtimeVideoPTS;
@property (nonatomic, assign) BOOL hasLastRealtimeVideoPTS;
@property (nonatomic, assign) BOOL shouldSaveSeparateCameraVideos;

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

@interface DualCameraView (BeautyPreviewInvalidation)
- (void)invalidateBeautyPreviewForLayoutChange:(NSString *)reason;
@end
