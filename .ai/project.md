status: draft
last-verified: 2026-05-21

# Project Context

## Stack Summary

- Root repository contains an Expo/React Native app scaffold.
- `my-app/` contains the active camera app opened in the IDE.
- `my-app/package.json` uses Expo SDK `~54.0.33`, React Native `0.81.5`, `expo-camera`, and `expo-media-library`.
- `my-app/app.json` disables the React Native new architecture and declares the custom iOS config plugin `./plugin/withDualCamera`.

## Key Modules

- `my-app/App.js`: React Native UI and runtime checks for `NativeModules.CameraPermissionModule`, `NativeModules.DualCameraModule`, `NativeModules.DualCameraEventEmitter`, and `requireNativeComponent('DualCameraView')`.
- `my-app/plugin/withDualCamera.js`: Expo config plugin that copies `native/LocalPods/DualCamera` into `ios/LocalPods/DualCamera` during iOS prebuild and patches the generated Podfile with a local `DualCamera` pod.
- `my-app/native/LocalPods/DualCamera/`: Objective-C native iOS camera module, view manager, event emitter, permission module, and podspec.
- `my-app/eas.json`: EAS build profiles for development, preview, and production.

## ADRs

- Custom iOS camera behavior is implemented as a local CocoaPods pod instead of relying solely on `expo-camera`.
- The app depends on Expo prebuild/config-plugin execution for iOS native module inclusion.
- React Native new architecture is disabled in `my-app/app.json`, which aligns with the current Objective-C bridge modules using `RCT_EXPORT_MODULE`.
- `my-app/plugin/withDualCamera.js` intentionally fails prebuild when native sources or the generated Podfile are missing, so EAS does not produce an iOS binary without the required native camera module.

## External Contracts

- iOS builds must run from `my-app/` or otherwise use `my-app/app.json`, `my-app/plugin/withDualCamera.js`, and `my-app/native/LocalPods/DualCamera`.
- Generated iOS projects must include a `pod 'DualCamera', :path => './LocalPods/DualCamera'` entry inside the app target in `ios/Podfile`.
- Runtime JS expects native module names exported by Objective-C: `CameraPermissionModule`, `DualCameraModule`, `DualCameraEventEmitter`, and `DualCameraView`.

## Change Notes

- 2026-04-25: Hardened `my-app/plugin/withDualCamera.js` to copy the local DualCamera pod recursively, patch the app target deterministically after `use_expo_modules!`, avoid duplicate pod entries, and fail early on missing native sources or Podfile. Local Windows verification cannot generate the iOS native project; use macOS/Linux or EAS for final iOS prebuild/build validation.
- 2026-05-07: Reworked `my-app/App.js` camera controls per `.ai/specs/ui-redesign-spec.md`: aspect ratio moved into a top settings popup, LR/SX layout uses a draggable snapping divider, and zoom controls are now independent per camera area. Native DualCamera module contracts remain unchanged.
- 2026-05-07: Fixed a first-launch black preview race by having `DualCameraSessionManager` remember pending JS start requests until `DualCameraView` registers. Refined the right-side mode rail in `my-app/App.js` from text labels to icon-only controls with right margin and lighter selected styling.
- 2026-05-07: Added `.ai/specs/orientation-mirroring-spec.md` and implemented orientation-aware native camera connections, explicit front preview/output mirroring defaults, SX landscape geometry mapping, responsive JS overlay dimensions, and unlocked Expo orientation from portrait to default.
- 2026-05-07: Implemented `.ai/specs/recording-save-consistency-spec.md` in `DualCameraView.m`: dual-camera recording now captures an immutable layout/orientation snapshot at start, uses orientation-aware output dimensions, and removes old duplicate saved-video/photo composition compatibility paths so saved media follows the same geometry helper as preview/realtime composition.
- 2026-05-07: Added `.ai/specs/recording-start-failure-investigation-spec.md` and hardened native recording start: dual-camera realtime recording now uses the back camera stream as the writer clock, drops non-monotonic PTS frames, emits `onRecordingStarted` only after the first successful video frame append, includes structured recording error diagnostics, and respects `AVErrorRecordingSuccessfullyFinishedKey` for single-camera movie output completion.
- 2026-05-09: Reworked the dual-camera save pipeline after MultiCam quality/orientation investigation: still capture now returns to WYSIWYG video-frame compositing instead of parallel `AVCapturePhotoOutput`, realtime video compositing runs on a dedicated render queue, and JPEG/video outputs use explicit sRGB/BT.709 color settings with higher quality encoding.
- 2026-05-09: Fixed iOS photo capture failure in `my-app/native/LocalPods/DualCamera/DualCameraView+Capture.m` by clamping `AVCapturePhotoSettings.photoQualityPrioritization` to each `AVCapturePhotoOutput.maxPhotoQualityPrioritization`; single-camera photo capture now also uses the shared safe photo settings helper.
- 2026-05-09: Implemented the dual-camera recording optimization plan: added realtime recording pipeline warmup, reused warmed writer settings on first record, made WYSIWYG still output sizing source-aware, improved MultiCam format diagnostics/selection, and kept all finish paths on the dedicated render queue.
- 2026-05-09: Diagnosed first-record freeze logs and fixed realtime warmup in `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m` by using a standalone warmup pixel buffer instead of a nil adaptor pool, plus gated auto warmup while recording in `DualCameraView+Capture.m`.
- 2026-05-09: Upgraded `my-app/native/LocalPods/DualCamera/DualCameraView+Recording.m` warmup to perform a hidden real `AVAssetWriter` start/session/append/finish cycle so the first user recording no longer pays encoder initialization cost.
- 2026-05-14: Added `.ai/specs/split-pip-gesture-fix-20260514.md` and fixed LR/SX divider drag ratio calculation plus PIP pan coordinate mapping so native PIP position is normalized to the camera canvas and RN overlay controls follow the same canvas geometry.
- 2026-05-15: Adjusted `my-app/src/components/ZoomDial.tsx` so constrained split/PIP zoom controls keep the standard circular preset button format and collapse to two buttons: the active preset plus a cycle-to-next preset button.
- 2026-05-15: Added `.ai/specs/zoom-pill-canvas-placement-20260515.md` and reworked zoom controls into single tap-to-cycle pills positioned at the bottom center of each actual preview rect, including PIP-internal placement.
- 2026-05-21: Added `.ai/specs/ios-permission-unlock-purchase-ui-20260521.md` and implemented Chinese iOS-style camera/media permission dialogs, centered video unlock purchase card, StoreKit localized `displayPrice` purchase button, visible App Store waiting state, red unlocked video shutter state, and removal of `[VideoUnlock]` payment debug logs. Verified with `npx tsc --noEmit` in `my-app/`.
