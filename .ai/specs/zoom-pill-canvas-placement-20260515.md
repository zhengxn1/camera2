# Zoom Pill Canvas Placement Spec

**spec_id**: zoom-pill-canvas-placement-20260515
**status**: draft

## Goal

Refine camera zoom controls so each visible camera area has one compact iPhone-style zoom pill. The pill shows the current preset and cycles to the next available preset on tap. The available zoom preset sets remain unchanged.

## UX Contract

- Back camera presets remain `0.5x`, `1x`, `2x`, `3x`, `5x`.
- Front camera presets remain `1x`, `2x`.
- Each rendered camera area shows at most one zoom pill.
- Tapping the pill cycles to the next preset in that camera's preset list.
- The pill is positioned at the bottom center of the actual preview rect it controls.
- In PIP modes, the PIP camera zoom pill is inside the PIP preview, not outside it.

## Technical Contract

- Keep native camera module APIs unchanged.
- Mirror native canvas sizing and preview rect calculation from `DualCameraView+Layout.m` in the React Native overlay.
- Restrict implementation to the React Native overlay and style layer.

## Target Files

- `my-app/src/components/ZoomDial.tsx`
- `my-app/src/components/CameraControlsOverlay.tsx`
- `my-app/src/styles.ts`
- `.ai/project.md`
