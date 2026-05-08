#import "DualCameraView.h"
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>

@class DualCameraLayoutState;

/**
 * DualCameraView+Composition
 *
 * Stateless CIImage compositing helpers, path/size utilities, and
 * realtime recording error-detail builder.
 * All methods are pure transforms on their inputs; no session state is
 * read or written here.
 */
@interface DualCameraView (Composition)

// ---------------------------------------------------------------------------
// Canvas / pixel-buffer helpers
// ---------------------------------------------------------------------------
- (CIImage *)blackCanvasSize:(CGSize)size;
- (CIImage *)clearCanvasSize:(CGSize)size;
- (CIImage *)scaledCIImage:(CIImage *)image toSize:(CGSize)size;
- (CIImage *)circleAlphaMaskForRect:(CGRect)rect canvasSize:(CGSize)canvasSize;

/// Scale-to-fill + optional horizontal mirror, placed inside targetRect on a canvasSize canvas.
- (CIImage *)preparedCameraImage:(CIImage *)image
                      targetRect:(CGRect)targetRect
                      canvasSize:(CGSize)canvasSize
                        mirrored:(BOOL)mirrored;

/// Full compositing pass: black canvas + back + front (respects PiP, circle mask).
- (CIImage *)compositedImageForLayoutState:(DualCameraLayoutState *)state
                                     front:(CIImage *)front
                                      back:(CIImage *)back;

// ---------------------------------------------------------------------------
// File / size utilities
// ---------------------------------------------------------------------------
- (NSString *)saveCIImageAsJPEG:(CIImage *)ciImage;
- (NSString *)tempPathWithPrefix:(NSString *)prefix;
- (NSString *)documentsPathWithPrefix:(NSString *)prefix;

- (CGSize)outputSizeForAspectRatio:(NSString *)aspectRatio
                     referenceWidth:(CGFloat)referenceWidth
                          landscape:(BOOL)landscape;

- (CGSize)realtimeRecordingOutputSizeForAspectRatio:(NSString *)aspectRatio
                                          landscape:(BOOL)landscape;

// ---------------------------------------------------------------------------
// AVFoundation layer helper
// ---------------------------------------------------------------------------
- (AVMutableVideoCompositionLayerInstruction *)layerForTrack:(AVMutableCompositionTrack *)track;

// ---------------------------------------------------------------------------
// Recording error-detail builder
// ---------------------------------------------------------------------------
- (NSNumber *)numberForCMTimeSeconds:(CMTime)time;

- (NSDictionary *)recordingErrorDetailsForError:(NSError *)error
                                        context:(NSString *)context
                                    rejectedPTS:(CMTime)rejectedPTS;

@end
