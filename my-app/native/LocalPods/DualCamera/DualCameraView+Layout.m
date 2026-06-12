#import "DualCameraView+Layout.h"
#import "DualCameraView_Internal.h"

@implementation DualCameraView (Layout)

#pragma mark - Canvas

- (CGRect)canvasBoundsForAspectRatio {
  CGFloat screenW = self.bounds.size.width;
  CGFloat screenH = self.bounds.size.height;
  CGFloat canvasW, canvasH;

  if ([self.saveAspectRatio isEqualToString:@"9:16"]) {
    canvasW = screenW;
    canvasH = canvasW * 16.0 / 9.0;
    if (canvasH > screenH) {
      canvasH = screenH;
      canvasW = canvasH * 9.0 / 16.0;
    }
  } else if ([self.saveAspectRatio isEqualToString:@"3:4"]) {
    canvasW = screenW;
    canvasH = canvasW * 4.0 / 3.0;
    if (canvasH > screenH) {
      canvasH = screenH;
      canvasW = canvasH * 3.0 / 4.0;
    }
  } else if ([self.saveAspectRatio isEqualToString:@"1:1"]) {
    CGFloat minDim = MIN(screenW, screenH);
    canvasW = canvasH = minDim;
  } else {
    return self.bounds;
  }

  CGFloat ox = (screenW - canvasW) / 2.0;
  CGFloat oy = (screenH - canvasH) / 2.0;
  return CGRectMake(ox, oy, canvasW, canvasH);
}

#pragma mark - Layout state snapshot

- (DualCameraLayoutState *)currentLayoutStateForCanvasSize:(CGSize)canvasSize outputSize:(CGSize)outputSize {
  return [self layoutStateSnapshotForCanvasSize:canvasSize
                                     outputSize:outputSize
                                    orientation:self.deviceOrientation];
}

- (DualCameraLayoutState *)layoutStateSnapshotForCanvasSize:(CGSize)canvasSize
                                                 outputSize:(CGSize)outputSize
                                                orientation:(NSInteger)orientation {
  DualCameraLayoutState *state = [[DualCameraLayoutState alloc] init];
  state.layoutMode = self.currentLayout ?: @"back";
  state.dualLayoutRatio = self.dualLayoutRatio > 0 ? self.dualLayoutRatio : 0.5;
  state.pipSize = self.pipSize > 0 ? self.pipSize : 0.28;
  state.pipPositionX = self.pipPositionX;
  state.pipPositionY = self.pipPositionY;
  state.sxBackOnTop = self.sxBackOnTop;
  state.pipMainIsBack = self.pipMainIsBack;
  state.canvasSize = canvasSize;
  state.outputSize = outputSize;
  state.frontMirrored = self.frontOutputMirrored;
  state.backMirrored = self.backOutputMirrored;
  state.isLandscape = [self isDeviceOrientationLandscape:orientation];
  state.primaryOnLeadingEdge = [self primaryOnLeadingEdgeForDeviceOrientation:orientation];
  return state;
}

#pragma mark - Rect calculation

- (NSDictionary<NSString *, NSValue *> *)rectsForLayoutState:(DualCameraLayoutState *)state canvasSize:(CGSize)canvasSize {
  CGFloat w = canvasSize.width;
  CGFloat h = canvasSize.height;
  CGFloat ratio = MAX(0.1, MIN(0.9, state.dualLayoutRatio > 0 ? state.dualLayoutRatio : 0.5));
  NSString *layout = state.layoutMode ?: @"back";

  CGRect backRect = CGRectZero;
  CGRect frontRect = CGRectZero;

  if ([layout isEqualToString:@"back"]) {
    backRect = CGRectMake(0, 0, w, h);
  } else if ([layout isEqualToString:@"front"]) {
    frontRect = CGRectMake(0, 0, w, h);
  } else if ([layout isEqualToString:@"lr"]) {
    CGFloat primaryW = w * ratio;
    CGFloat secondaryW = w * (1 - ratio);
    if (state.sxBackOnTop) {
      backRect = CGRectMake(0, 0, primaryW, h);
      frontRect = CGRectMake(primaryW, 0, secondaryW, h);
    } else {
      frontRect = CGRectMake(0, 0, primaryW, h);
      backRect = CGRectMake(primaryW, 0, secondaryW, h);
    }
  } else if ([layout isEqualToString:@"sx"]) {
    if (state.isLandscape) {
      CGFloat primaryW = w * ratio;
      CGFloat secondaryW = w * (1 - ratio);
      CGRect leadingRect = CGRectMake(0, 0, primaryW, h);
      CGRect trailingRect = CGRectMake(primaryW, 0, secondaryW, h);
      CGRect primaryRect = state.primaryOnLeadingEdge ? leadingRect : trailingRect;
      CGRect secondaryRect = state.primaryOnLeadingEdge ? trailingRect : leadingRect;
      if (state.sxBackOnTop) {
        backRect = primaryRect;
        frontRect = secondaryRect;
      } else {
        frontRect = primaryRect;
        backRect = secondaryRect;
      }
    } else {
      CGFloat primaryH = h * ratio;
      CGFloat secondaryH = h * (1 - ratio);
      if (state.sxBackOnTop) {
        backRect = CGRectMake(0, 0, w, primaryH);
        frontRect = CGRectMake(0, primaryH, w, secondaryH);
      } else {
        frontRect = CGRectMake(0, 0, w, primaryH);
        backRect = CGRectMake(0, primaryH, w, secondaryH);
      }
    }
  } else if ([layout isEqualToString:@"pip_square"] || [layout isEqualToString:@"pip_circle"]) {
    CGFloat s = w * MAX(0.05, MIN(0.5, state.pipSize));
    CGFloat cx = w * MAX(0, MIN(1, state.pipPositionX));
    CGFloat cy = h * MAX(0, MIN(1, state.pipPositionY));
    cx = MAX(s / 2, MIN(w - s / 2, cx));
    cy = MAX(s / 2, MIN(h - s / 2, cy));
    CGRect pipRect = CGRectMake(cx - s / 2, cy - s / 2, s, s);
    CGRect fullRect = CGRectMake(0, 0, w, h);
    if (state.pipMainIsBack) {
      backRect = fullRect;
      frontRect = pipRect;
    } else {
      frontRect = fullRect;
      backRect = pipRect;
    }
  } else {
    backRect = CGRectMake(0, 0, w, h);
  }

  return @{
    @"back": [NSValue valueWithCGRect:backRect],
    @"front": [NSValue valueWithCGRect:frontRect]
  };
}

#pragma mark - View update

- (void)updateLayout {
  CGRect canvas = [self canvasBoundsForAspectRatio];
  CGFloat ox = canvas.origin.x;
  CGFloat oy = canvas.origin.y;
  DualCameraLayoutState *state = [self currentLayoutStateForCanvasSize:canvas.size outputSize:canvas.size];
  NSDictionary<NSString *, NSValue *> *rects = [self rectsForLayoutState:state canvasSize:canvas.size];
  CGRect backRect = [rects[@"back"] CGRectValue];
  CGRect frontRect = [rects[@"front"] CGRectValue];
  CGRect backFrame = CGRectOffset(backRect, ox, oy);
  CGRect frontFrame = CGRectOffset(frontRect, ox, oy);

  self.frontPreviewView.layer.masksToBounds = YES;
  self.backPreviewView.layer.masksToBounds = YES;
  self.frontPreviewView.layer.cornerRadius = 0;
  self.backPreviewView.layer.cornerRadius = 0;

  if ([self.currentLayout isEqualToString:@"back"]) {
    self.frontPreviewView.hidden = YES;
    self.backPreviewView.hidden = NO;
    self.backPreviewView.frame = backFrame;

  } else if ([self.currentLayout isEqualToString:@"front"]) {
    self.backPreviewView.hidden = YES;
    self.frontPreviewView.hidden = NO;
    self.frontPreviewView.frame = frontFrame;

  } else if ([self.currentLayout isEqualToString:@"lr"]) {
    self.backPreviewView.hidden = NO;
    self.frontPreviewView.hidden = NO;
    self.backPreviewView.frame = backFrame;
    self.frontPreviewView.frame = frontFrame;

  } else if ([self.currentLayout isEqualToString:@"sx"]) {
    self.backPreviewView.hidden = NO;
    self.frontPreviewView.hidden = NO;
    self.backPreviewView.frame = backFrame;
    self.frontPreviewView.frame = frontFrame;

  } else if ([self.currentLayout isEqualToString:@"pip_square"] || [self.currentLayout isEqualToString:@"pip_circle"]) {
    self.backPreviewView.hidden = NO;
    self.frontPreviewView.hidden = NO;
    self.backPreviewView.frame = backFrame;
    self.frontPreviewView.frame = frontFrame;

    // Always keep the PIP view on top regardless of which camera is in PIP,
    // and ensure the pan/pinch gestures are attached to the correct view.
    UIView *pipView = self.pipMainIsBack ? self.frontPreviewView : self.backPreviewView;
    [self bringSubviewToFront:pipView];
    [self setupPipGestures];

    CGFloat pipW = canvas.size.width;
    CGFloat pipS = pipW * MAX(0.05, MIN(0.5, self.pipSize));
    CGFloat pipCX = pipW * MAX(0, MIN(1, self.pipPositionX));
    CGFloat pipCY = canvas.size.height * MAX(0, MIN(1, self.pipPositionY));
    pipCX = MAX(pipS / 2, MIN(pipW - pipS / 2, pipCX));
    pipCY = MAX(pipS / 2, MIN(canvas.size.height - pipS / 2, pipCY));
    CGRect pipRect = CGRectMake(pipCX - pipS / 2, pipCY - pipS / 2, pipS, pipS);

    if ([self.currentLayout isEqualToString:@"pip_circle"]) {
      CGFloat radius = pipRect.size.width / 2;
      if (self.pipMainIsBack) {
        self.frontPreviewView.layer.cornerRadius = radius;
      } else {
        self.backPreviewView.layer.cornerRadius = radius;
      }
    } else {
      self.frontPreviewView.layer.cornerRadius = 8;
      self.backPreviewView.layer.cornerRadius = 8;
    }

  } else {
    self.frontPreviewView.hidden = YES;
    self.backPreviewView.hidden = NO;
    self.backPreviewView.frame = canvas;
  }

  if (self.frontPreviewLayer) self.frontPreviewLayer.frame = self.frontPreviewView.bounds;
  if (self.backPreviewLayer) self.backPreviewLayer.frame = self.backPreviewView.bounds;
  if (self.singlePreviewLayer) self.singlePreviewLayer.frame = [self targetPreviewViewForPosition:self.singleCameraPosition].bounds;
  if (self.frontBeautyPreviewImageView) {
    self.frontBeautyPreviewImageView.frame = self.frontPreviewView.bounds;
    [self.frontPreviewView bringSubviewToFront:self.frontBeautyPreviewImageView];
  }
}

#pragma mark - Preview view / layer management

- (void)createPlaceholderViews {
  [self.frontPreviewView removeFromSuperview];
  [self.backPreviewView removeFromSuperview];

  UIView *bv = [[UIView alloc] init];
  bv.backgroundColor = [UIColor blackColor];
  bv.clipsToBounds = YES;
  bv.frame = self.bounds;
  [self addSubview:bv];
  self.backPreviewView = bv;

  UIView *fv = [[UIView alloc] init];
  fv.backgroundColor = [UIColor blackColor];
  fv.clipsToBounds = YES;
  fv.frame = self.bounds;
  [self addSubview:fv];
  self.frontPreviewView = fv;

  UIImageView *beautyPreview = [[UIImageView alloc] initWithFrame:fv.bounds];
  beautyPreview.backgroundColor = [UIColor clearColor];
  beautyPreview.contentMode = UIViewContentModeScaleAspectFill;
  beautyPreview.clipsToBounds = YES;
  beautyPreview.hidden = YES;
  [fv addSubview:beautyPreview];
  self.frontBeautyPreviewImageView = beautyPreview;

  [self setupPipGestures];

  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateLayout];
  });
}

- (void)removePreviewLayers {
  [self.frontPreviewLayer removeFromSuperlayer];
  [self.backPreviewLayer removeFromSuperlayer];
  [self.singlePreviewLayer removeFromSuperlayer];
  self.frontPreviewLayer = nil;
  self.backPreviewLayer = nil;
  self.singlePreviewLayer = nil;
  if (self.frontBeautyPreviewImageView) {
    [self.frontPreviewView bringSubviewToFront:self.frontBeautyPreviewImageView];
  }
}

- (void)clearPreviewLayersOnMainQueue {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self removePreviewLayers];
  });
}

#pragma mark - Convenience helpers

- (BOOL)isDualLayout:(NSString *)layout {
  return ![layout isEqualToString:@"back"] && ![layout isEqualToString:@"front"];
}

- (AVCaptureDevicePosition)primaryCameraPosition {
  return [self.currentLayout isEqualToString:@"front"] ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
}

- (UIView *)targetPreviewViewForPosition:(AVCaptureDevicePosition)position {
  return position == AVCaptureDevicePositionFront ? self.frontPreviewView : self.backPreviewView;
}

@end
