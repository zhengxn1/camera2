#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

@class DualCameraEventEmitter;

NS_ASSUME_NONNULL_BEGIN

@interface DualCameraView : UIView

@property (nonatomic, copy) NSString *layoutMode;

// Layout ratio: 0.0 - 1.0 (LR/SX split ratio, 0.5 = 50:50)
@property (nonatomic, assign) CGFloat dualLayoutRatio;

// PiP controls: size as ratio of canvasW, position as normalized 0-1
@property (nonatomic, assign) CGFloat pipSize;
@property (nonatomic, assign) CGFloat pipPositionX;
@property (nonatomic, assign) CGFloat pipPositionY;

// Zoom factors
@property (nonatomic, assign) CGFloat frontZoomFactor; // front camera zoom
@property (nonatomic, assign) CGFloat backZoomFactor;  // back camera zoom

// Save aspect ratio for dual-cam photo output: @"9:16" | @"3:4" | @"1:1"
@property (nonatomic, copy) NSString *saveAspectRatio;

// Flip state: controls camera allocation in preview and save
// SX: YES=back on top, NO=front on top
@property (nonatomic, assign) BOOL sxBackOnTop;
// PiP: YES=back is main (full-screen), NO=front is main
@property (nonatomic, assign) BOOL pipMainIsBack;

- (void)dc_startSession;
- (void)dc_stopSession;
- (void)dc_takePhoto;
- (void)dc_startRecording;
- (void)dc_stopRecording;
- (void)dc_flipCamera;
- (void)dc_setFrontZoom:(CGFloat)factor;
- (void)dc_setBackZoom:(CGFloat)factor;

@end

NS_ASSUME_NONNULL_END
