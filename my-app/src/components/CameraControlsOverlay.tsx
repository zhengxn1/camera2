import { memo } from 'react';
import { CAMERA_MODE, type CameraMode, type CameraSide, INTERACTION_TOP } from '../constants';
import { styles } from '../styles';
import { clamp } from '../utils';
import { AreaDivider } from './AreaDivider';
import { ZoomDial, ZoomDialOverlay } from './ZoomDial';

export interface PipPosition {
  x: number;
  y: number;
}

interface CameraControlsOverlayProps {
  cameraMode: CameraMode;
  isFlipped: boolean;
  dualLayoutRatio: number;
  onDualLayoutRatioChange: (ratio: number) => void;
  pipSize: number;
  pipPosition: PipPosition;
  screenWidth: number;
  screenHeight: number;
  backZoom: number;
  frontZoom: number;
  onZoomChange: (camera: CameraSide, level: number) => void;
}

function CameraControlsOverlayImpl({
  cameraMode,
  isFlipped,
  dualLayoutRatio,
  onDualLayoutRatioChange,
  pipSize,
  pipPosition,
  screenWidth,
  screenHeight,
  backZoom,
  frontZoom,
  onZoomChange,
}: CameraControlsOverlayProps) {
  if (cameraMode === CAMERA_MODE.BACK) {
    return (
      <ZoomDialOverlay positionStyle={styles.singleZoomPosition}>
        <ZoomDial camera="back" currentZoom={backZoom} onZoomChange={onZoomChange} />
      </ZoomDialOverlay>
    );
  }

  if (cameraMode === CAMERA_MODE.FRONT) {
    return (
      <ZoomDialOverlay positionStyle={styles.singleZoomPosition}>
        <ZoomDial camera="front" currentZoom={frontZoom} onZoomChange={onZoomChange} />
      </ZoomDialOverlay>
    );
  }

  if (cameraMode === CAMERA_MODE.LR) {
    const firstCamera: CameraSide = isFlipped ? 'front' : 'back';
    const secondCamera: CameraSide = isFlipped ? 'back' : 'front';
    // Usable pixel width inside each column (8px padding each side)
    const leftW = screenWidth * dualLayoutRatio - 16;
    const rightW = screenWidth * (1 - dualLayoutRatio) - 16;
    return (
      <>
        <ZoomDialOverlay positionStyle={[styles.splitZoomPosition, { left: 8, width: leftW + 16 }]}>
          <ZoomDial
            camera={firstCamera}
            currentZoom={firstCamera === 'back' ? backZoom : frontZoom}
            onZoomChange={onZoomChange}
            availableWidth={leftW}
          />
        </ZoomDialOverlay>
        <ZoomDialOverlay positionStyle={[styles.splitZoomPosition, { left: screenWidth * dualLayoutRatio + 8, width: rightW + 16 }]}>
          <ZoomDial
            camera={secondCamera}
            currentZoom={secondCamera === 'back' ? backZoom : frontZoom}
            onZoomChange={onZoomChange}
            availableWidth={rightW}
          />
        </ZoomDialOverlay>
        <AreaDivider
          mode="lr"
          ratio={dualLayoutRatio}
          onRatioChange={onDualLayoutRatioChange}
          screenWidth={screenWidth}
          screenHeight={screenHeight}
        />
      </>
    );
  }

  if (cameraMode === CAMERA_MODE.SX) {
    const firstCamera: CameraSide = isFlipped ? 'front' : 'back';
    const secondCamera: CameraSide = isFlipped ? 'back' : 'front';
    const isLandscape = screenWidth > screenHeight;
    if (isLandscape) {
      const leftW = screenWidth * dualLayoutRatio - 16;
      const rightW = screenWidth * (1 - dualLayoutRatio) - 16;
      return (
        <>
          <ZoomDialOverlay positionStyle={[styles.splitZoomPosition, { left: 8, width: leftW + 16 }]}>
            <ZoomDial
              camera={firstCamera}
              currentZoom={firstCamera === 'back' ? backZoom : frontZoom}
              onZoomChange={onZoomChange}
              availableWidth={leftW}
            />
          </ZoomDialOverlay>
          <ZoomDialOverlay positionStyle={[styles.splitZoomPosition, { left: screenWidth * dualLayoutRatio + 8, width: rightW + 16 }]}>
            <ZoomDial
              camera={secondCamera}
              currentZoom={secondCamera === 'back' ? backZoom : frontZoom}
              onZoomChange={onZoomChange}
              availableWidth={rightW}
            />
          </ZoomDialOverlay>
          <AreaDivider
            mode="lr"
            ratio={dualLayoutRatio}
            onRatioChange={onDualLayoutRatioChange}
            screenWidth={screenWidth}
            screenHeight={screenHeight}
          />
        </>
      );
    }

    // Portrait: zoom for top section sits near the divider; clamp so it never
    // overlaps the status bar area at the top of the screen.
    const sxTopZoomY = Math.max(INTERACTION_TOP, screenHeight * dualLayoutRatio - 96);
    return (
      <>
        <ZoomDialOverlay positionStyle={[styles.sxTopZoomPosition, { top: sxTopZoomY }]}>
          <ZoomDial
            camera={firstCamera}
            currentZoom={firstCamera === 'back' ? backZoom : frontZoom}
            onZoomChange={onZoomChange}
          />
        </ZoomDialOverlay>
        <ZoomDialOverlay positionStyle={styles.sxBottomZoomPosition}>
          <ZoomDial
            camera={secondCamera}
            currentZoom={secondCamera === 'back' ? backZoom : frontZoom}
            onZoomChange={onZoomChange}
          />
        </ZoomDialOverlay>
        <AreaDivider
          mode="sx"
          ratio={dualLayoutRatio}
          onRatioChange={onDualLayoutRatioChange}
          screenWidth={screenWidth}
          screenHeight={screenHeight}
        />
      </>
    );
  }

  // PIP modes
  const mainCamera: CameraSide = isFlipped ? 'front' : 'back';
  const pipCamera: CameraSide = isFlipped ? 'back' : 'front';
  // PIP is a square whose side = pipSize * screenWidth (mirrors native updateLayout).
  const pipSizePx = pipSize * screenWidth;
  const pipBtnWidth = Math.max(92, pipSizePx - 16);
  // pipPosition.{x,y} are fractions of the native view bounds (updated by pan gesture).
  const pipCenterX = pipPosition.x * screenWidth;
  const pipCenterY = pipPosition.y * screenHeight;
  const pipLeft = clamp(pipCenterX - pipBtnWidth / 2, 8, screenWidth - pipBtnWidth - 8);
  const pipTop = clamp(pipCenterY + pipSizePx / 2 + 4, INTERACTION_TOP, screenHeight - 132);

  return (
    <>
      <ZoomDialOverlay positionStyle={styles.singleZoomPosition}>
        <ZoomDial camera={mainCamera} currentZoom={mainCamera === 'back' ? backZoom : frontZoom} onZoomChange={onZoomChange} />
      </ZoomDialOverlay>
      <ZoomDialOverlay positionStyle={[styles.pipZoomPosition, { left: pipLeft, top: pipTop, width: pipBtnWidth }]}>
        <ZoomDial
          camera={pipCamera}
          currentZoom={pipCamera === 'back' ? backZoom : frontZoom}
          onZoomChange={onZoomChange}
          availableWidth={pipBtnWidth}
        />
      </ZoomDialOverlay>
    </>
  );
}

export const CameraControlsOverlay = memo(CameraControlsOverlayImpl);
CameraControlsOverlay.displayName = 'CameraControlsOverlay';
