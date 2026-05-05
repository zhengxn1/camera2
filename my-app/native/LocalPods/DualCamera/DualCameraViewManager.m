#import "DualCameraViewManager.h"
#import "DualCameraView.h"

@implementation DualCameraViewManager

RCT_EXPORT_MODULE()

- (UIView *)view {
  return [[DualCameraView alloc] init];
}

RCT_CUSTOM_VIEW_PROPERTY(layoutMode, NSString, DualCameraView) {
  view.layoutMode = json ? [RCTConvert NSString:json] : @"back";
}

RCT_CUSTOM_VIEW_PROPERTY(saveAspectRatio, NSString, DualCameraView) {
  view.saveAspectRatio = json ? [RCTConvert NSString:json] : @"9:16";
}

RCT_CUSTOM_VIEW_PROPERTY(dualLayoutRatio, CGFloat, DualCameraView) {
  view.dualLayoutRatio = json ? [RCTConvert CGFloat:json] : 0.5;
}

RCT_CUSTOM_VIEW_PROPERTY(pipSize, CGFloat, DualCameraView) {
  view.pipSize = json ? [RCTConvert CGFloat:json] : 0.28;
}

RCT_CUSTOM_VIEW_PROPERTY(pipPositionX, CGFloat, DualCameraView) {
  view.pipPositionX = json ? [RCTConvert CGFloat:json] : 0.85;
}

RCT_CUSTOM_VIEW_PROPERTY(pipPositionY, CGFloat, DualCameraView) {
  view.pipPositionY = json ? [RCTConvert CGFloat:json] : 0.80;
}

RCT_CUSTOM_VIEW_PROPERTY(sxBackOnTop, BOOL, DualCameraView) {
  view.sxBackOnTop = json ? [RCTConvert BOOL:json] : YES;
}

RCT_CUSTOM_VIEW_PROPERTY(pipMainIsBack, BOOL, DualCameraView) {
  view.pipMainIsBack = json ? [RCTConvert BOOL:json] : YES;
}

@end
