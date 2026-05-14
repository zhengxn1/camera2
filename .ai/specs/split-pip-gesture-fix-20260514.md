# Split and PIP Gesture Fix Spec

## Goal

Fix two camera layout interaction defects:

- LR/SX divider dragging must change the visible leading/top panel in the same direction as the user's drag, including both left and right movement.
- PIP dragging and resizing must use the same coordinate space as native layout/compositing, so the PIP can move across the whole camera canvas and resize up to roughly 45%-50% of the canvas width.

## Design Contract

- `dualLayoutRatio` continues to mean "primary/first visible panel size fraction" in native layout.
- RN divider gestures must compute ratio from the finger's absolute page coordinate when available, not only accumulated `dx`/`dy`, so moving a divider left/right or up/down is symmetric even while the divider view itself moves.
- Native PIP position remains stored as normalized canvas coordinates (`0..1`), matching `rectsForLayoutState`.
- Native PIP size may range from `0.05` to `0.5` of canvas width.
- When panning, clamp the PIP inside the current camera canvas, not against unrelated full view bounds.

## Target File List

- `my-app/src/components/AreaDivider.tsx`
- `my-app/App.tsx`
- `my-app/src/components/CameraControlsOverlay.tsx`
- `my-app/native/LocalPods/DualCamera/DualCameraView.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Gestures.m`
- `my-app/native/LocalPods/DualCamera/DualCameraView+Layout.m`
