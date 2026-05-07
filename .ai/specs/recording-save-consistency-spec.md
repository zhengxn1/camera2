# Dual Camera Recording/Save Consistency Spec

> Status: Implemented
> Created: 2026-05-07
> Scope: Dual-camera SX/LR/PiP recording and saved-video layout consistency.

## 1. Problem

In dual-camera split modes, the on-screen recording preview can look correct while the saved video can appear with a different SX top/bottom arrangement, different landscape remapping, or swapped primary/secondary placement.

The current native code has two competing composition models:

- The newer realtime recording path composites `AVCaptureVideoDataOutput` frames through `compositedImageForLayoutState`.
- The older export path `compositeDualVideosForCurrentLayout:backPath:` still has hard-coded portrait canvas and separate LR/SX transforms.

Even inside the realtime path, recording state is not fully immutable. `appendRealtimeVideoFrameAtTime:` rebuilds `DualCameraLayoutState` on every frame from live view properties, including current device orientation. Output size is also always portrait for `9:16` and `3:4`, even when the preview is in a landscape SX display geometry.

## 2. Root Cause Analysis

### 2.1 Layout State Is Live, Not Snapshotted

Current code:

- `startRealtimeRecordingWithCanvasSize:` stores `canvasSizeAtRecording`, `realtimeOutputSize`, and `realtimeRecordingAspectRatio`.
- `appendRealtimeVideoFrameAtTime:` calls `currentLayoutStateForCanvasSize:outputSize:` every frame.
- `currentLayoutStateForCanvasSize:outputSize:` reads live `currentLayout`, `dualLayoutRatio`, `sxBackOnTop`, `pipMainIsBack`, `frontOutputMirrored`, `backOutputMirrored`, `deviceOrientation`, and `primaryOnLeadingEdge`.

Risk:

- Orientation changes while recording can change SX from top/bottom to left/right mid-file.
- Native orientation and JS window orientation can disagree temporarily.
- Saved frame geometry can be derived from a different state than the visual state the user considered "recording".

### 2.2 Output Size Is Always Portrait

Current `realtimeRecordingOutputSizeForAspectRatio:` returns:

- `9:16` -> `1080x1920`
- `3:4` -> `1080x1440`
- `1:1` -> `1080x1080`

Risk:

- In landscape SX preview, native layout maps SX to left/right, but the saved canvas remains portrait. The saved result can look like a tall portrait left/right split instead of the visible landscape recording.
- If product expectation is "what I saw while recording", output canvas orientation must be part of the same snapshot as preview geometry.

### 2.3 Old Export Path Is a Consistency Trap

`compositeDualVideosForCurrentLayout:backPath:` still computes layout independently:

- It forces portrait canvas dimensions.
- It computes LR/SX transforms manually.
- It ignores `rectsForLayoutState:canvasSize:`.
- It does not use the realtime `preparedCameraImage` / `compositedImageForLayoutState` pipeline.

Risk:

- If any fallback or future code path calls it again, saved video layout can diverge from preview immediately.
- It makes debugging hard because there are two definitions of "SX top/bottom".

### 2.4 Naming Ambiguity Increases Risk

`sxBackOnTop` is used for both `sx` and `lr`.

In practice it means "back camera owns the primary split area", not literally "back is on top". This is manageable internally, but it should be renamed or wrapped in a clearer snapshot field to avoid future mistakes.

## 3. Desired Contract

For any recording:

1. Saved video must match the native preview geometry at recording start.
2. Recording output must use one immutable layout snapshot for the whole file.
3. Photo capture should use a capture-time snapshot, not live properties read later on a background queue.
4. Realtime recording and any fallback export must share the same geometry helper.
5. UI overlays should follow native layout, but native remains the source of truth for saved output.

Recommended first-pass behavior:

- Lock orientation and layout at recording start.
- Disable UI layout changes while recording, as JS already does.
- Ignore device rotation for saved-video geometry until recording ends.
- Keep preview either locked to the same snapshot during recording, or allow preview rotation only if the recording also rotates. The safer first pass is to lock preview layout during active recording.

## 4. Proposed Native Model

Add a durable recording snapshot:

```objc
@property (nonatomic, strong, nullable) DualCameraLayoutState *recordingLayoutState;
@property (nonatomic, assign) DualCameraDeviceOrientation recordingDeviceOrientation;
@property (nonatomic, assign) CGRect recordingPreviewCanvas;
```

Add one explicit snapshot builder:

```objc
- (DualCameraLayoutState *)layoutStateSnapshotForCanvasSize:(CGSize)canvasSize
                                                 outputSize:(CGSize)outputSize
                                                orientation:(DualCameraDeviceOrientation)orientation;
```

Rules:

- The snapshot copies all fields required for layout:
  - `layoutMode`
  - `dualLayoutRatio`
  - `pipSize`
  - `pipPositionX/Y`
  - `sxBackOnTop`
  - `pipMainIsBack`
  - `frontOutputMirrored`
  - `backOutputMirrored`
  - `deviceOrientation`
  - `isLandscape`
  - `primaryOnLeadingEdge`
- `appendRealtimeVideoFrameAtTime:` must use `self.recordingLayoutState`, not rebuild from live state.
- `finishRealtimeRecording` clears the snapshot.
- `internalTakePhoto` builds a photo snapshot synchronously before dispatching composition work.

## 5. Output Size Policy

Choose one product policy and enforce it consistently.

Recommended policy for WYSIWYG recording:

- If recording snapshot is portrait:
  - `9:16` -> `1080x1920`
  - `3:4` -> `1080x1440`
  - `1:1` -> `1080x1080`
- If recording snapshot is landscape:
  - `9:16` -> `1920x1080`
  - `3:4` -> `1440x1080`
  - `1:1` -> `1080x1080`

This makes landscape saved video match landscape preview instead of forcing the saved file into a portrait canvas.

If the product wants saved media always portrait, then SX must stay top/bottom even in landscape preview. Do not mix "landscape preview remaps SX to LR" with "portrait-only saved output".

## 6. Layout Helper Contract

`rectsForLayoutState:canvasSize:` remains the only source of split/PiP rectangles.

Required changes:

- Do not compute saved-video LR/SX rectangles manually anywhere else.
- Remove or deprecate `compositeLRFront`, `compositeSXFront`, and the old transform block inside `compositeDualVideosForCurrentLayout:backPath:` if they are no longer called.
- If old export fallback must remain, rewrite it to call `rectsForLayoutState:canvasSize:` and `makeLayerTransformWithTargetRect:sourceSize:sourcePreferredTransform:mirrored:` per camera.

## 7. JS Contract

JS should continue passing:

- `layoutMode`
- `dualLayoutRatio`
- `sxBackOnTop`
- `pipMainIsBack`
- `saveAspectRatio`

No new prop is required for the first pass.

Recommended cleanup:

- Rename JS/local concepts in future docs from `sxBackOnTop` to `primaryIsBack`.
- Keep the bridge prop unchanged initially to avoid native-manager churn.

## 8. Validation Matrix

Test saved video against preview for:

| Scenario | Expected Result |
|---|---|
| SX portrait, back primary | Back top, front bottom in preview and saved video. |
| SX portrait, front primary | Front top, back bottom in preview and saved video. |
| SX landscape-left, back primary | Back occupies the same primary side in preview and saved video. |
| SX landscape-right, back primary | Back occupies the same primary side in preview and saved video. |
| SX recording then rotate device | Saved video keeps the recording-start layout for the entire file. |
| LR portrait, flipped/unflipped | Left/right ownership matches preview and saved video. |
| PiP square/circle | Main/PiP ownership and PiP position match preview and saved video. |
| Front output mirroring | Saved front output follows `frontOutputMirrored`, independent of preview mirroring. |

## 9. Implementation Phases

### Phase 1: Snapshot Contract

Files:

- `my-app/native/LocalPods/DualCamera/DualCameraView.m`

Tasks:

- Add immutable recording layout snapshot properties.
- Add snapshot builder that accepts explicit orientation.
- Capture snapshot at `startRealtimeRecordingWithCanvasSize:`.
- Use snapshot in `appendRealtimeVideoFrameAtTime:`.
- Clear snapshot in all finish/fail/reset paths.

### Phase 2: Output Size Orientation

Files:

- `my-app/native/LocalPods/DualCamera/DualCameraView.m`

Tasks:

- Replace `realtimeRecordingOutputSizeForAspectRatio:` with an orientation-aware variant.
- Use recording-start orientation to select portrait or landscape dimensions.
- Confirm `videoInput.transform` remains identity when buffer dimensions already match final orientation.

### Phase 3: Remove Duplicate Composition Logic

Files:

- `my-app/native/LocalPods/DualCamera/DualCameraView.m`

Tasks:

- Confirm whether `compositeDualVideosForCurrentLayout:backPath:` is still reachable.
- If unreachable, mark it for deletion after device validation.
- If reachable, rewrite it to use the same snapshot/rect helper instead of hard-coded LR/SX transforms.

### Phase 4: Device Verification Logs

Files:

- `my-app/native/LocalPods/DualCamera/DualCameraView.m`

Tasks:

- Temporarily log a compact snapshot at recording start:
  - layout
  - ratio
  - output size
  - orientation
  - back rect
  - front rect
- Temporarily log first saved frame extent.
- Remove noisy logs after validation.

## 10. Target File List

| File | Action |
|---|---|
| `my-app/native/LocalPods/DualCamera/DualCameraView.m` | Main fix: snapshot layout/orientation, orientation-aware output size, one geometry path for saved video. |
| `my-app/native/LocalPods/DualCamera/DualCameraView.h` | Optional only if snapshot helpers/properties need to be exposed; likely no public change. |
| `my-app/App.js` | Optional cleanup only; current JS already disables layout controls while recording. |
| `.ai/project.md` | Record ADR after implementation. |
