#import "DualCameraView+Orientation.h"
#import "DualCameraView_Internal.h"

@implementation DualCameraView (Orientation)

- (void)startDeviceOrientationMonitoring {
  [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(deviceOrientationDidChange:)
                                               name:UIDeviceOrientationDidChangeNotification
                                             object:nil];
  [self updateDeviceOrientation:[UIDevice currentDevice].orientation];
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
  [self updateDeviceOrientation:[UIDevice currentDevice].orientation];
}

- (void)updateDeviceOrientation:(UIDeviceOrientation)orientation {
  DualCameraDeviceOrientation next = self.deviceOrientation;
  switch (orientation) {
    case UIDeviceOrientationPortrait:
      next = DualCameraDeviceOrientationPortrait;
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      next = DualCameraDeviceOrientationPortraitUpsideDown;
      break;
    case UIDeviceOrientationLandscapeLeft:
      next = DualCameraDeviceOrientationLandscapeLeft;
      break;
    case UIDeviceOrientationLandscapeRight:
      next = DualCameraDeviceOrientationLandscapeRight;
      break;
    default:
      return;
  }

  if (next == self.deviceOrientation) return;
  if (self.isDualRecordingActive || self.realtimeAssetWriter) return;
  self.deviceOrientation = next;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
    [self applyCurrentVideoOrientationAndMirroring];
  });
}

- (AVCaptureVideoOrientation)currentCaptureVideoOrientation {
  switch (self.deviceOrientation) {
    case DualCameraDeviceOrientationPortraitUpsideDown:
      return AVCaptureVideoOrientationPortraitUpsideDown;
    case DualCameraDeviceOrientationLandscapeLeft:
      return AVCaptureVideoOrientationLandscapeRight;
    case DualCameraDeviceOrientationLandscapeRight:
      return AVCaptureVideoOrientationLandscapeLeft;
    case DualCameraDeviceOrientationPortrait:
    default:
      return AVCaptureVideoOrientationPortrait;
  }
}

- (BOOL)isCurrentDeviceLandscape {
  return self.deviceOrientation == DualCameraDeviceOrientationLandscapeLeft ||
         self.deviceOrientation == DualCameraDeviceOrientationLandscapeRight;
}

- (BOOL)isDeviceOrientationLandscape:(NSInteger)orientation {
  return orientation == DualCameraDeviceOrientationLandscapeLeft ||
         orientation == DualCameraDeviceOrientationLandscapeRight;
}

- (BOOL)primaryOnLeadingEdgeForDeviceOrientation:(NSInteger)orientation {
  return orientation != DualCameraDeviceOrientationLandscapeRight;
}

- (void)applyOrientation:(AVCaptureVideoOrientation)orientation
             mirrored:(BOOL)mirrored
         toConnection:(AVCaptureConnection *)connection {
  if (!connection) return;
  if (connection.isVideoOrientationSupported) {
    connection.videoOrientation = orientation;
  }
  if (connection.isVideoMirroringSupported) {
    connection.automaticallyAdjustsVideoMirroring = NO;
    connection.videoMirrored = mirrored;
  }
}

- (void)applyOrientation:(AVCaptureVideoOrientation)orientation
             mirrored:(BOOL)mirrored
            toOutput:(AVCaptureOutput *)output {
  for (AVCaptureConnection *connection in output.connections) {
    [self applyOrientation:orientation mirrored:mirrored toConnection:connection];
  }
}

- (void)applyCurrentVideoOrientationAndMirroring {
  AVCaptureVideoOrientation orientation = [self currentCaptureVideoOrientation];

  [self applyOrientation:orientation
                mirrored:self.backPreviewMirrored
            toConnection:self.backPreviewLayer.connection];
  [self applyOrientation:orientation
                mirrored:self.frontPreviewMirrored
            toConnection:self.frontPreviewLayer.connection];

  BOOL singlePreviewMirrored = self.singleCameraPosition == AVCaptureDevicePositionFront
    ? self.frontPreviewMirrored
    : self.backPreviewMirrored;
  [self applyOrientation:orientation
                mirrored:singlePreviewMirrored
            toConnection:self.singlePreviewLayer.connection];

  [self applyOrientation:orientation mirrored:self.backOutputMirrored toOutput:self.backPhotoOutput];
  [self applyOrientation:orientation mirrored:self.frontOutputMirrored toOutput:self.frontPhotoOutput];
  [self applyOrientation:orientation mirrored:self.backOutputMirrored toOutput:self.backVideoDataOutput];
  [self applyOrientation:orientation mirrored:self.frontOutputMirrored toOutput:self.frontVideoDataOutput];

  BOOL singleOutputMirrored = self.singleCameraPosition == AVCaptureDevicePositionFront
    ? self.frontOutputMirrored
    : self.backOutputMirrored;
  [self applyOrientation:orientation mirrored:singleOutputMirrored toOutput:self.singlePhotoOutput];
  [self applyOrientation:orientation mirrored:singleOutputMirrored toOutput:self.singleMovieOutput];
}

@end
