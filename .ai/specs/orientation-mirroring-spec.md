# Orientation and Mirroring Optimization Spec

> Status: Draft
> Created: 2026-05-07
> Scope: Dual camera preview, recording, photo capture, and overlay layout orientation behavior.

## 1. Problem

The current camera implementation treats orientation, layout, and front-camera mirroring as implicit side effects:

- Native preview and capture connections are fixed to `AVCaptureVideoOrientationPortrait`.
- Front camera preview/data output is explicitly not mirrored.
- JS overlay dimensions are read once with `Dimensions.get('window')`, so controls do not react to device rotation.
- `sxBackOnTop` represents camera slot ownership, but no rule maps a portrait top/bottom split to a landscape left/right visual presentation.

This creates a mismatch when the device is held landscape: the selected camera slots may remain logically correct, but the front preview can appear reversed or rotated relative to user expectation.

## 2. Design Principles

1. Layout identity must remain stable.
   - User choice of camera slot ownership must not change because the device rotates.
   - Example: if front is the primary area and back is secondary, those identities remain front/back after rotation.

2. Orientation is a separate state.
   - Preview, video data outputs, photo/video export, and JS controls must all consume the same normalized orientation.

3. Front-camera mirror policy is explicit.
   - Preview mirror and saved-output mirror are separate policies.
   - Default should match iPhone user expectation: front preview mirrored, saved output not mirrored unless user enables mirror save.

4. SX/LR visual mapping must be deterministic.
   - Portrait SX means primary area appears above secondary.
   - Landscape SX means primary area appears on the physical left in landscape-left and on the physical right in landscape-right, unless product decides otherwise.
   - Camera ownership does not swap; only the frame geometry changes.

## 3. Proposed Model

### 3.1 Orientation State

Introduce a native orientation enum:

```objc
typedef NS_ENUM(NSInteger, DualCameraDeviceOrientation) {
  DualCameraDeviceOrientationPortrait,
  DualCameraDeviceOrientationPortraitUpsideDown,
  DualCameraDeviceOrientationLandscapeLeft,
  DualCameraDeviceOrientationLandscapeRight
};
```

Native `DualCameraView` owns the canonical orientation. It updates from `UIDeviceOrientationDidChangeNotification` and ignores face-up, face-down, and unknown states.

Map device orientation to `AVCaptureVideoOrientation` carefully:

| UIDeviceOrientation | AVCaptureVideoOrientation |
|---|---|
| Portrait | Portrait |
| PortraitUpsideDown | PortraitUpsideDown |
| LandscapeLeft | LandscapeRight |
| LandscapeRight | LandscapeLeft |

This inverse landscape mapping is the standard camera coordinate convention.

### 3.2 Connection Updates

Add one central method:

```objc
- (void)applyCurrentVideoOrientationAndMirroring;
```

It must update every relevant connection:

- `frontPreviewLayer.connection`
- `backPreviewLayer.connection`
- `singlePreviewLayer.connection`
- `frontVideoDataOutput` connections
- `backVideoDataOutput` connections
- `singleMovieOutput` connections
- photo/movie output connections where applicable

Rules:

- Set `videoOrientation` to the current mapped `AVCaptureVideoOrientation` whenever supported.
- For front preview connection:
  - `automaticallyAdjustsVideoMirroring = NO`
  - `videoMirrored = frontPreviewMirrored`
- For front data/movie/photo output:
  - `videoMirrored = frontOutputMirrored`
- Back camera is never mirrored by default.

Default policy:

```objc
frontPreviewMirrored = YES;
frontOutputMirrored = NO;
backPreviewMirrored = NO;
backOutputMirrored = NO;
```

### 3.3 Layout Geometry

Keep `layoutMode` as user intent:

- `back`
- `front`
- `pip_square`
- `pip_circle`
- `lr`
- `sx`

Add a derived display geometry mode inside native layout calculation:

```objc
DisplayAxis displayAxisForLayout(layoutMode, deviceOrientation)
```

Rules:

- `lr` remains left/right in portrait and landscape.
- `sx` is top/bottom in portrait.
- `sx` becomes left/right in landscape, because physically the phone is sideways and the user expects a stable primary/secondary relationship on screen.
- The primary slot is still controlled by `sxBackOnTop`:
  - `sxBackOnTop=YES`: back is primary.
  - `sxBackOnTop=NO`: front is primary.
- In landscape:
  - LandscapeLeft: primary area maps to physical left.
  - LandscapeRight: primary area maps to physical right.

This prevents camera ownership from swapping while matching the user's physical perception.

### 3.4 JS Overlay Layout

Replace one-time `Dimensions.get('window')` with reactive dimensions:

```js
const { width: screenWidth, height: screenHeight } = useWindowDimensions();
```

Then derive:

```js
const isLandscape = screenWidth > screenHeight;
const effectiveSplitAxis = cameraMode === CAMERA_MODE.SX && isLandscape ? 'lr' : cameraMode;
```

Overlay controls should follow native display geometry:

- SX portrait: top zoom dial in primary top region, bottom zoom dial in secondary bottom region.
- SX landscape: primary/secondary zoom dials move to left/right regions according to the same landscape mapping rule.
- Divider drag direction follows the visible axis:
  - Portrait SX: vertical drag changes ratio.
  - Landscape SX: horizontal drag changes ratio.

Native still receives the same `layoutMode="sx"` and `dualLayoutRatio`; JS only changes overlay geometry and drag axis.

### 3.5 Capture and Save Consistency

For WYSIWYG photo and realtime recording, use the same layout state snapshot:

```objc
state.deviceOrientation
state.previewMirroringPolicy
state.outputMirroringPolicy
state.displayAxis
```

Photo composition must use display geometry, not raw `layoutMode` alone.

Video composition must no longer assume fixed portrait render transforms. It should either:

1. Prefer realtime frame compositing path using oriented CIImages, or
2. Update export transforms from the captured track `preferredTransform` plus current orientation snapshot.

For a first reliable implementation, prefer path 1 where possible because it keeps preview/photo/video geometry aligned.

## 4. UX Defaults

Initial defaults:

- Front preview: mirrored.
- Saved front output: not mirrored.
- Layout orientation: auto.
- No user-facing setting in the first pass unless testing proves a need.

Future setting reserved in `SettingsPopup`:

- Mirror front preview: on/off.
- Mirror saved selfie: on/off.
- Orientation lock: auto/portrait/landscape.

## 5. Implementation Phases

### Phase 1: Native Orientation Canonicalization

Files:

- `my-app/native/LocalPods/DualCamera/DualCameraView.h`
- `my-app/native/LocalPods/DualCamera/DualCameraView.m`

Tasks:

- Add native orientation state.
- Subscribe/unsubscribe to `UIDeviceOrientationDidChangeNotification`.
- Add `currentCaptureVideoOrientation`.
- Add `applyCurrentVideoOrientationAndMirroring`.
- Call it after every session configuration, preview layer creation, output connection creation, and orientation change.

### Phase 2: Native Layout Geometry

Files:

- `my-app/native/LocalPods/DualCamera/DualCameraView.m`

Tasks:

- Extend `DualCameraLayoutState` with device orientation and display axis.
- Update `rectsForLayoutState:canvasSize:` to derive visible SX geometry from orientation.
- Ensure `updateLayout`, photo compositing, and realtime frame compositing consume the same geometry helper.

### Phase 3: JS Overlay Alignment

Files:

- `my-app/App.js`

Tasks:

- Use `useWindowDimensions`.
- Derive landscape state.
- Make `CameraControlsOverlay` and `AreaDivider` consume the visible split axis.
- Keep Native props unchanged unless Phase 2 introduces a new prop.

### Phase 4: Save/Record Verification

Files:

- `my-app/native/LocalPods/DualCamera/DualCameraView.m`

Tasks:

- Verify photo output for all modes:
  - back
  - front
  - LR
  - SX portrait
  - SX landscape
  - PiP square/circle
- Verify video output uses the same camera placement as preview.
- Add temporary logs for orientation/layout snapshots during device testing; remove noisy logs after validation.

## 6. Acceptance Matrix

| Scenario | Expected Result |
|---|---|
| SX portrait, front primary | Front preview is top, back is bottom. |
| SX landscape-left, front primary | Front preview remains primary and appears on physical left. |
| SX landscape-right, front primary | Front preview remains primary and appears on physical right. |
| Rotate while in SX | Camera ownership does not swap; only geometry remaps. |
| Front preview portrait | Looks like iPhone selfie preview by default. |
| Front preview landscape | Does not appear unexpectedly reversed relative to device orientation. |
| Saved front photo | Not mirrored by default unless future setting enables it. |
| LR rotate | Left/right ownership remains deterministic. |
| PiP rotate | Main/small camera ownership remains stable; PiP position is clamped into visible canvas. |
| Recording rotate | Output matches preview orientation snapshot policy. |

## 7. Risk Notes

- Changing front preview mirroring may alter existing user perception. Keep output mirroring separate from preview mirroring.
- `AVCaptureVideoOrientation` is deprecated in newer SDKs in favor of rotation angle APIs, but the current codebase already uses orientation APIs; use the existing style for the first pass.
- Orientation changes during active recording should either be locked at recording start or explicitly supported. Recommended first pass: lock layout/orientation snapshot at recording start to avoid mid-file geometry discontinuities.

## 8. Target File List

| File | Action |
|---|---|
| `my-app/native/LocalPods/DualCamera/DualCameraView.h` | Add orientation/mirroring fields or private declarations if needed. |
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | Main native orientation, mirroring, layout geometry, and save/record consistency changes. |
| `my-app/App.js` | Make overlay dimensions responsive and match visible SX/LR geometry. |
| `.ai/project.md` | Record ADR after implementation. |

