#import "DualCameraView+Layout.h"
#import "DualCameraView_Internal.h"

static CGFloat BeautyProbeAspectRatio(CGSize size) {
  if (size.width <= 1.0 || size.height <= 1.0) return 0.0;
  return size.width / size.height;
}

static BOOL BeautyPreviewSizesMatch(CGSize a, CGSize b) {
  return fabs(a.width - b.width) <= 2.0 && fabs(a.height - b.height) <= 2.0;
}

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
	  CGFloat previewScale = UIScreen.mainScreen.scale ?: 1.0;
	  @synchronized(self) {
	    self.beautyPreviewTargetSize = CGSizeMake(MAX(1, self.frontPreviewView.bounds.size.width * previewScale),
	                                             MAX(1, self.frontPreviewView.bounds.size.height * previewScale));
	  }

	  CFTimeInterval now = CACurrentMediaTime();
  BOOL shouldLogLayout = self.frontBeautyEnabled &&
                         (now - self.lastBeautyLayoutDiagLogTime > 0.5 || self.beautyLayoutChanging);
	  if (shouldLogLayout) {
	    self.lastBeautyLayoutDiagLogTime = now;
    NSLog(@"[BeautyLayoutDiag] layout=%@ ratio=%.3f canvas=%@ frontFrame=%@ frontBounds=%@ frontHidden=%d backFrame=%@ backHidden=%d frontLayerHidden=%d frontLayerFrame=%@ beautyHidden=%d beautyFrame=%@ beautyDrawable=%@ beautySuperview=%@ subviews=%lu changing=%d",
          self.currentLayout ?: @"nil",
          self.dualLayoutRatio,
          NSStringFromCGRect(canvas),
          NSStringFromCGRect(self.frontPreviewView.frame),
          NSStringFromCGRect(self.frontPreviewView.bounds),
          self.frontPreviewView.hidden,
          NSStringFromCGRect(self.backPreviewView.frame),
          self.backPreviewView.hidden,
          self.frontPreviewLayer ? self.frontPreviewLayer.hidden : YES,
          self.frontPreviewLayer ? NSStringFromCGRect(self.frontPreviewLayer.frame) : @"nil",
          self.beautyPreviewView ? self.beautyPreviewView.hidden : YES,
          self.beautyPreviewView ? NSStringFromCGRect(self.beautyPreviewView.frame) : @"nil",
          self.beautyPreviewView ? NSStringFromCGSize(self.beautyPreviewView.drawableSize) : @"nil",
          self.beautyPreviewView.superview == self.frontPreviewView ? @"frontPreviewView" : NSStringFromClass(self.beautyPreviewView.superview.class),
	          (unsigned long)self.frontPreviewView.subviews.count,
	          self.beautyLayoutChanging);
	  }
	  BOOL rawFrontVisible = self.frontPreviewLayer && !self.frontPreviewLayer.hidden && !self.frontPreviewView.hidden;
	  BOOL beautyVisible = self.beautyPreviewView && !self.beautyPreviewView.hidden;
	  if (self.frontBeautyEnabled && (self.frontPreviewView.subviews.count > 1 || (rawFrontVisible && beautyVisible))) {
	    NSLog(@"[BeautyProbe][LayerConflict] layout=%@ rawFrontVisible=%d beautyVisible=%d frontSubviews=%lu frontLayerHidden=%d beautySuperview=%@ beautyFrame=%@ frontBounds=%@",
	          self.currentLayout ?: @"nil",
	          rawFrontVisible,
	          beautyVisible,
	          (unsigned long)self.frontPreviewView.subviews.count,
	          self.frontPreviewLayer ? self.frontPreviewLayer.hidden : YES,
	          self.beautyPreviewView.superview == self.frontPreviewView ? @"frontPreviewView" : NSStringFromClass(self.beautyPreviewView.superview.class),
	          self.beautyPreviewView ? NSStringFromCGRect(self.beautyPreviewView.frame) : @"nil",
	          NSStringFromCGRect(self.frontPreviewView.bounds));
	  }
	  [self updateBeautyPreviewVisibility];
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
}

- (void)clearPreviewLayersOnMainQueue {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self removePreviewLayers];
  });
}

- (BOOL)layoutContainsFrontCamera:(NSString *)layout {
  return [layout isEqualToString:@"front"] || [self isDualLayout:layout ?: @"back"];
}

- (CGSize)currentBeautyPreviewTargetSize {
  CGFloat scale = UIScreen.mainScreen.scale ?: 1.0;
  return CGSizeMake(MAX(1, self.frontPreviewView.bounds.size.width * scale),
                    MAX(1, self.frontPreviewView.bounds.size.height * scale));
}

- (BOOL)beautyPreviewMetadataMatchesCurrentTarget:(CGSize)currentTarget dropReason:(NSString **)dropReason {
  NSString *reason = nil;
  BOOL matches = NO;
  @synchronized(self) {
    BOOL hasFrame = self.latestBeautyPreviewFrame != nil;
    BOOL generationMatches = self.latestBeautyPreviewGeneration == self.beautyLayoutGeneration;
    NSString *currentLayout = self.currentLayout ?: @"back";
    NSString *latestLayout = self.latestBeautyPreviewLayoutMode ?: @"back";
    BOOL layoutMatches = [latestLayout isEqualToString:currentLayout];
    BOOL targetMatches = BeautyPreviewSizesMatch(self.latestBeautyPreviewTargetSize, currentTarget);
    BOOL mirrorMatches = self.latestBeautyPreviewMirrored == self.frontPreviewMirrored;
    matches = hasFrame && generationMatches && layoutMatches && targetMatches && mirrorMatches;
    if (!hasFrame) {
      reason = @"noFrame";
    } else if (!generationMatches) {
      reason = @"staleGeneration";
    } else if (!layoutMatches) {
      reason = @"layoutMismatch";
    } else if (!targetMatches) {
      reason = @"targetMismatch";
    } else if (!mirrorMatches) {
      reason = @"mirrorMismatch";
    } else {
      reason = @"ok";
    }
  }
  if (dropReason) {
    *dropReason = reason;
  }
  return matches;
}

- (BOOL)shouldShowBeautyPreview {
  if (!self.frontBeautyEnabled || !self.metalDevice || !self.metalCommandQueue) return NO;
  if (!self.usingMultiCam || ![self layoutContainsFrontCamera:self.currentLayout]) return NO;
  if (self.frontPreviewView.hidden) return NO;

  CFTimeInterval now = CACurrentMediaTime();
  BOOL layoutStillChanging = self.beautyLayoutChanging && (now - self.lastBeautyLayoutChangeTime < 0.45);
  if (layoutStillChanging) return NO;
  if (self.beautyLayoutChanging && !layoutStillChanging) {
    self.beautyLayoutChanging = NO;
  }

  NSString *dropReason = nil;
  return [self beautyPreviewMetadataMatchesCurrentTarget:[self currentBeautyPreviewTargetSize]
                                              dropReason:&dropReason];
}

- (void)updateBeautyPreviewVisibility {
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateBeautyPreviewVisibility];
    });
    return;
  }

	  CGSize currentTarget = [self currentBeautyPreviewTargetSize];
	  @synchronized(self) {
	    self.beautyPreviewTargetSize = currentTarget;
	  }
	  NSString *dropReason = nil;
	  BOOL metadataMatches = [self beautyPreviewMetadataMatchesCurrentTarget:currentTarget dropReason:&dropReason];
	  BOOL shouldShow = [self shouldShowBeautyPreview];
	  if (self.frontPreviewLayer) {
	    self.frontPreviewLayer.hidden = shouldShow || self.frontPreviewView.hidden;
	  }

	  CFTimeInterval now = CACurrentMediaTime();
	  BOOL hasMetal = self.metalDevice && self.metalCommandQueue;
	  BOOL layoutHasFront = [self layoutContainsFrontCamera:self.currentLayout];
	  if (now - self.lastBeautyPreviewDiagLogTime > 0.5 || self.beautyLayoutChanging) {
	    self.lastBeautyPreviewDiagLogTime = now;
	    NSLog(@"[BeautyProbe][PreviewGate] shouldShow=%d enabled=%d hasMetal=%d usingMultiCam=%d layout=%@ layoutHasFront=%d latestFront=%d frontViewHidden=%d frontLayerHidden=%d beautyHidden=%d beautySuperview=%@ frontSubviews=%lu scheduled=%d changing=%d",
	          shouldShow,
	          self.frontBeautyEnabled,
	          hasMetal,
	          self.usingMultiCam,
	          self.currentLayout ?: @"nil",
	          layoutHasFront,
		          self.latestBeautyPreviewFrame != nil,
	          self.frontPreviewView.hidden,
	          self.frontPreviewLayer ? self.frontPreviewLayer.hidden : YES,
	          self.beautyPreviewView ? self.beautyPreviewView.hidden : YES,
	          self.beautyPreviewView.superview == self.frontPreviewView ? @"frontPreviewView" : NSStringFromClass(self.beautyPreviewView.superview.class),
	          (unsigned long)self.frontPreviewView.subviews.count,
	          self.beautyPreviewFrameScheduled,
	          self.beautyLayoutChanging);
		  }
	  if (now - self.lastBeautyPreviewDiagLogTime > 0.5 || !metadataMatches || self.beautyLayoutChanging) {
	    NSLog(@"[BeautyProbe][PreviewVersion] show=%d dropReason=%@ currentGen=%ld latestGen=%ld layout=%@ latestLayout=%@ target=%@ latestTarget=%@ mirrored=%d latestMirrored=%d",
	          shouldShow,
	          dropReason ?: @"unknown",
	          (long)self.beautyLayoutGeneration,
	          (long)self.latestBeautyPreviewGeneration,
	          self.currentLayout ?: @"nil",
	          self.latestBeautyPreviewLayoutMode ?: @"nil",
	          NSStringFromCGSize(currentTarget),
	          NSStringFromCGSize(self.latestBeautyPreviewTargetSize),
	          self.frontPreviewMirrored,
	          self.latestBeautyPreviewMirrored);
	  }

		  if (!shouldShow) {
		    if (self.beautyPreviewView) {
		      self.beautyPreviewView.hidden = YES;
    }
    return;
  }

  if (shouldShow && !self.beautyPreviewView) {
    MTKView *preview = [[MTKView alloc] initWithFrame:CGRectZero device:self.metalDevice];
    preview.backgroundColor = UIColor.blackColor;
    preview.clearColor = MTLClearColorMake(0, 0, 0, 1);
    preview.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    preview.framebufferOnly = NO;
    preview.paused = YES;
    preview.enableSetNeedsDisplay = NO;
    preview.userInteractionEnabled = NO;
    preview.opaque = YES;
    [self.frontPreviewView addSubview:preview];
    self.beautyPreviewView = preview;
  }

  if (!self.beautyPreviewView) return;

  CGFloat scale = UIScreen.mainScreen.scale ?: 1.0;
  if (self.beautyPreviewView.superview != self.frontPreviewView) {
    [self.beautyPreviewView removeFromSuperview];
    [self.frontPreviewView addSubview:self.beautyPreviewView];
  }
		  self.beautyPreviewView.frame = self.frontPreviewView.bounds;
		  self.beautyPreviewView.drawableSize = CGSizeMake(MAX(1, self.frontPreviewView.bounds.size.width * scale),
		                                                   MAX(1, self.frontPreviewView.bounds.size.height * scale));
		  @synchronized(self) {
		    self.beautyPreviewTargetSize = self.beautyPreviewView.drawableSize;
		  }
		  self.beautyPreviewView.layer.cornerRadius = self.frontPreviewView.layer.cornerRadius;
		  self.beautyPreviewView.layer.masksToBounds = YES;
		  self.beautyPreviewView.hidden = !shouldShow;
  if (shouldShow) {
    [self.frontPreviewView bringSubviewToFront:self.beautyPreviewView];
  }

	  if (now - self.lastBeautyPreviewDiagLogTime > 0.5 || self.beautyLayoutChanging) {
    self.lastBeautyPreviewDiagLogTime = now;
    NSLog(@"[BeautyPreviewDiag] shouldShow=%d enabled=%d usingMultiCam=%d layout=%@ latestFront=%d frontViewHidden=%d frontLayerHidden=%d beautyHidden=%d beautyFrame=%@ beautyDrawable=%@ frontSubviews=%lu scheduled=%d changing=%d",
          shouldShow,
          self.frontBeautyEnabled,
          self.usingMultiCam,
          self.currentLayout ?: @"nil",
	          self.latestBeautyPreviewFrame != nil,
          self.frontPreviewView.hidden,
          self.frontPreviewLayer ? self.frontPreviewLayer.hidden : YES,
          self.beautyPreviewView ? self.beautyPreviewView.hidden : YES,
          self.beautyPreviewView ? NSStringFromCGRect(self.beautyPreviewView.frame) : @"nil",
          self.beautyPreviewView ? NSStringFromCGSize(self.beautyPreviewView.drawableSize) : @"nil",
          (unsigned long)self.frontPreviewView.subviews.count,
          self.beautyPreviewFrameScheduled,
          self.beautyLayoutChanging);
  }
}

- (void)renderBeautyPreviewIfNeeded {
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self renderBeautyPreviewIfNeeded];
    });
    return;
  }

  MTKView *preview = self.beautyPreviewView;
  if (!preview || preview.hidden) return;
  CFTimeInterval now = CACurrentMediaTime();
	  BOOL layoutStillChanging = self.beautyLayoutChanging && (now - self.lastBeautyLayoutChangeTime < 0.80);
  if (layoutStillChanging) {
    preview.hidden = YES;
    if (self.frontPreviewLayer && !self.frontPreviewView.hidden) {
      self.frontPreviewLayer.hidden = NO;
    }
    return;
  }
  if (self.beautyLayoutChanging && !layoutStillChanging) self.beautyLayoutChanging = NO;
  CFTimeInterval minRenderInterval = layoutStillChanging ? (1.0 / 24.0) : (1.0 / 30.0);
  if (self.lastBeautyPreviewRenderTime > 0 &&
      now - self.lastBeautyPreviewRenderTime < minRenderInterval) {
    self.beautyPreviewSkippedRenderCount += 1;
    return;
  }
  self.lastBeautyPreviewRenderTime = now;

	  CIImage *previewFrame = nil;
	  NSInteger frameGeneration = -1;
	  NSString *frameLayout = nil;
	  CGSize frameTarget = CGSizeZero;
	  BOOL frameMirrored = NO;
	  @synchronized(self) {
	    previewFrame = self.latestBeautyPreviewFrame;
	    frameGeneration = self.latestBeautyPreviewGeneration;
	    frameLayout = [self.latestBeautyPreviewLayoutMode copy];
	    frameTarget = self.latestBeautyPreviewTargetSize;
	    frameMirrored = self.latestBeautyPreviewMirrored;
	  }

	  NSString *layout = self.currentLayout ?: @"back";
	  if (![self layoutContainsFrontCamera:layout] || !previewFrame) return;

	  CGSize drawableSize = preview.drawableSize;
	  if (drawableSize.width <= 1 || drawableSize.height <= 1) return;
	  NSString *dropReason = nil;
	  BOOL metadataMatches = [self beautyPreviewMetadataMatchesCurrentTarget:drawableSize dropReason:&dropReason];
	  if (!metadataMatches) {
	    preview.hidden = YES;
	    if (self.frontPreviewLayer && !self.frontPreviewView.hidden) {
	      self.frontPreviewLayer.hidden = NO;
	    }
	    NSLog(@"[BeautyProbe][PreviewVersion] renderDrop=%@ currentGen=%ld frameGen=%ld layout=%@ frameLayout=%@ drawable=%@ frameTarget=%@ mirrored=%d frameMirrored=%d",
	          dropReason ?: @"unknown",
	          (long)self.beautyLayoutGeneration,
	          (long)frameGeneration,
	          layout,
	          frameLayout ?: @"nil",
	          NSStringFromCGSize(drawableSize),
	          NSStringFromCGSize(frameTarget),
	          self.frontPreviewMirrored,
	          frameMirrored);
	    return;
	  }

  id<CAMetalDrawable> drawable = preview.currentDrawable;
  if (!drawable) return;

	  CGFloat viewAspect = BeautyProbeAspectRatio(self.frontPreviewView.bounds.size);
	  CGFloat beautyFrameAspect = BeautyProbeAspectRatio(preview.frame.size);
	  CGFloat drawableAspect = BeautyProbeAspectRatio(drawableSize);
		  CGFloat frontFrameAspect = BeautyProbeAspectRatio(previewFrame.extent.size);
	  if ((viewAspect > 0.0 && drawableAspect > 0.0 && fabs(viewAspect - drawableAspect) > 0.03) ||
	      (beautyFrameAspect > 0.0 && drawableAspect > 0.0 && fabs(beautyFrameAspect - drawableAspect) > 0.03)) {
	    NSLog(@"[BeautyProbe][AspectMismatch] layout=%@ viewAspect=%.4f beautyFrameAspect=%.4f drawableAspect=%.4f frontFrameAspect=%.4f frontBounds=%@ beautyFrame=%@ drawable=%@ frontExtent=%@",
	          self.currentLayout ?: @"nil",
	          viewAspect,
	          beautyFrameAspect,
	          drawableAspect,
	          frontFrameAspect,
	          NSStringFromCGRect(self.frontPreviewView.bounds),
	          NSStringFromCGRect(preview.frame),
	          NSStringFromCGSize(drawableSize),
		          NSStringFromCGRect(previewFrame.extent));
	  }

	  CGRect targetRect = CGRectMake(0, 0, drawableSize.width, drawableSize.height);
	  CFTimeInterval renderStart = CACurrentMediaTime();
	  CIImage *image = previewFrame;
	  CGSize previewExtentSize = previewFrame.extent.size;
	  if (previewExtentSize.width > 1 && previewExtentSize.height > 1 &&
	      (fabs(previewExtentSize.width - drawableSize.width) > 1 ||
	       fabs(previewExtentSize.height - drawableSize.height) > 1)) {
	    CGAffineTransform transform = CGAffineTransformMakeTranslation(-previewFrame.extent.origin.x, -previewFrame.extent.origin.y);
	    transform = CGAffineTransformScale(transform,
	                                       drawableSize.width / previewExtentSize.width,
	                                       drawableSize.height / previewExtentSize.height);
	    image = [previewFrame imageByApplyingTransform:transform];
	  }
	  if (!image) return;

  id<MTLCommandBuffer> commandBuffer = [self.metalCommandQueue commandBuffer];
  if (!drawable || !commandBuffer) return;

  CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  [self.ciContext render:image
            toMTLTexture:drawable.texture
           commandBuffer:commandBuffer
                  bounds:CGRectMake(0, 0, drawableSize.width, drawableSize.height)
              colorSpace:srgb];
  CGColorSpaceRelease(srgb);
  [commandBuffer presentDrawable:drawable];
  [commandBuffer commit];

	  CFTimeInterval renderMs = (CACurrentMediaTime() - renderStart) * 1000.0;
	  if (renderMs > 33.0) {
	    NSLog(@"[BeautyProbe][SlowRender] renderMs=%.2f layout=%@ drawable=%@ frontExtent=%@ skipped=%ld changing=%d",
	          renderMs,
	          self.currentLayout ?: @"nil",
	          NSStringFromCGSize(drawableSize),
		          NSStringFromCGRect(previewFrame.extent),
	          (long)self.beautyPreviewSkippedRenderCount,
	          layoutStillChanging);
	  }
	  if (now - self.lastBeautyRenderDiagLogTime > 0.5 || layoutStillChanging) {
    self.lastBeautyRenderDiagLogTime = now;
    NSLog(@"[BeautyRenderDiag] layout=%@ drawable=%@ frontExtent=%@ target=%@ renderMs=%.2f skipped=%ld changing=%d frontViewBounds=%@",
          self.currentLayout ?: @"nil",
          NSStringFromCGSize(drawableSize),
	          NSStringFromCGRect(previewFrame.extent),
          NSStringFromCGRect(targetRect),
          renderMs,
          (long)self.beautyPreviewSkippedRenderCount,
          layoutStillChanging,
          NSStringFromCGRect(self.frontPreviewView.bounds));
    self.beautyPreviewSkippedRenderCount = 0;
  }
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
