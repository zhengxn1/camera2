import { memo } from 'react';
import { type StyleProp, type ViewStyle } from 'react-native';
import { CAMERA_MODE, type AspectRatio, type CameraMode, type CameraSide } from '../constants';
import { styles } from '../styles';
import { clamp } from '../utils';
import { AreaDivider } from './AreaDivider';
import { ZoomDial, ZoomDialOverlay } from './ZoomDial';

export interface PipPosition {
  x: number;
  y: number;
}

interface PreviewRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface CameraControlsOverlayProps {
  cameraMode: CameraMode;
  aspect: AspectRatio;
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
  layoutInteractionDisabled?: boolean;
}

const ZOOM_PILL_W = 48;
const ZOOM_PILL_H = 32;
const ZOOM_PILL_COMPACT_W = 40;
const ZOOM_PILL_COMPACT_H = 28;

function canvasRectForAspect(aspect: AspectRatio, screenWidth: number, screenHeight: number): PreviewRect {
  let width = screenWidth;
  let height = screenHeight;

  if (aspect === '9:16') {
    height = width * 16 / 9;
    if (height > screenHeight) {
      height = screenHeight;
      width = height * 9 / 16;
    }
  } else if (aspect === '3:4') {
    height = width * 4 / 3;
    if (height > screenHeight) {
      height = screenHeight;
      width = height * 3 / 4;
    }
  } else if (aspect === '1:1') {
    width = Math.min(screenWidth, screenHeight);
    height = width;
  }

  return {
    left: (screenWidth - width) / 2,
    top: (screenHeight - height) / 2,
    width,
    height,
  };
}

function zoomPositionForRect(rect: PreviewRect, bottomReserve = 0): { style: StyleProp<ViewStyle>; compact: boolean } {
  const compact = rect.width < 96 || rect.height < 96;
  const width = compact ? ZOOM_PILL_COMPACT_W : ZOOM_PILL_W;
  const height = compact ? ZOOM_PILL_COMPACT_H : ZOOM_PILL_H;
  const bottomInset = (compact ? 8 : 14) + bottomReserve;
  const minTop = rect.top + 4;
  const maxTop = rect.top + rect.height - height - 4;
  const targetTop = rect.top + rect.height - height - bottomInset;
  const top = maxTop >= minTop ? clamp(targetTop, minTop, maxTop) : rect.top + Math.max(0, (rect.height - height) / 2);

  return {
    compact,
    style: {
      left: rect.left + rect.width / 2 - width / 2,
      top,
      width,
      height,
    },
  };
}

function renderZoom(
  camera: CameraSide,
  rect: PreviewRect,
  backZoom: number,
  frontZoom: number,
  onZoomChange: (camera: CameraSide, level: number) => void,
  bottomReserve = 0,
) {
  if (rect.width <= 0 || rect.height <= 0) return null;
  const { style, compact } = zoomPositionForRect(rect, bottomReserve);

  return (
    <ZoomDialOverlay key={camera} positionStyle={style}>
      <ZoomDial
        camera={camera}
        currentZoom={camera === 'back' ? backZoom : frontZoom}
        onZoomChange={onZoomChange}
        compact={compact}
      />
    </ZoomDialOverlay>
  );
}

function CameraControlsOverlayImpl({
  cameraMode,
  aspect,
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
  layoutInteractionDisabled = false,
}: CameraControlsOverlayProps) {
  const canvas = canvasRectForAspect(aspect, screenWidth, screenHeight);
  const ratio = clamp(dualLayoutRatio || 0.5, 0.1, 0.9);
  const bottomControlReserve = aspect === '9:16' ? 70 : 0;

  if (cameraMode === CAMERA_MODE.BACK) {
    return renderZoom('back', canvas, backZoom, frontZoom, onZoomChange, bottomControlReserve);
  }

  if (cameraMode === CAMERA_MODE.FRONT) {
    return renderZoom('front', canvas, backZoom, frontZoom, onZoomChange, bottomControlReserve);
  }

  if (cameraMode === CAMERA_MODE.LR) {
    const primaryW = canvas.width * ratio;
    const secondaryW = canvas.width - primaryW;
    const leadingRect = { left: canvas.left, top: canvas.top, width: primaryW, height: canvas.height };
    const trailingRect = { left: canvas.left + primaryW, top: canvas.top, width: secondaryW, height: canvas.height };
    const firstCamera: CameraSide = isFlipped ? 'front' : 'back';
    const secondCamera: CameraSide = isFlipped ? 'back' : 'front';

    return (
      <>
        {renderZoom(firstCamera, leadingRect, backZoom, frontZoom, onZoomChange, bottomControlReserve)}
        {renderZoom(secondCamera, trailingRect, backZoom, frontZoom, onZoomChange, bottomControlReserve)}
        {!layoutInteractionDisabled ? (
          <AreaDivider
            mode="lr"
            ratio={dualLayoutRatio}
            onRatioChange={onDualLayoutRatioChange}
            screenWidth={screenWidth}
            screenHeight={screenHeight}
          />
        ) : null}
      </>
    );
  }

  if (cameraMode === CAMERA_MODE.SX) {
    const firstCamera: CameraSide = isFlipped ? 'front' : 'back';
    const secondCamera: CameraSide = isFlipped ? 'back' : 'front';
    const isLandscape = screenWidth > screenHeight;

    if (isLandscape) {
      const primaryW = canvas.width * ratio;
      const secondaryW = canvas.width - primaryW;
      const leadingRect = { left: canvas.left, top: canvas.top, width: primaryW, height: canvas.height };
      const trailingRect = { left: canvas.left + primaryW, top: canvas.top, width: secondaryW, height: canvas.height };

      return (
        <>
          {renderZoom(firstCamera, leadingRect, backZoom, frontZoom, onZoomChange, bottomControlReserve)}
          {renderZoom(secondCamera, trailingRect, backZoom, frontZoom, onZoomChange, bottomControlReserve)}
          {!layoutInteractionDisabled ? (
            <AreaDivider
              mode="lr"
              ratio={dualLayoutRatio}
              onRatioChange={onDualLayoutRatioChange}
              screenWidth={screenWidth}
              screenHeight={screenHeight}
            />
          ) : null}
        </>
      );
    }

    const primaryH = canvas.height * ratio;
    const secondaryH = canvas.height - primaryH;
    const topRect = { left: canvas.left, top: canvas.top, width: canvas.width, height: primaryH };
    const bottomRect = { left: canvas.left, top: canvas.top + primaryH, width: canvas.width, height: secondaryH };

    return (
      <>
        {renderZoom(firstCamera, topRect, backZoom, frontZoom, onZoomChange)}
        {renderZoom(secondCamera, bottomRect, backZoom, frontZoom, onZoomChange, bottomControlReserve)}
        {!layoutInteractionDisabled ? (
          <AreaDivider
            mode="sx"
            ratio={dualLayoutRatio}
            onRatioChange={onDualLayoutRatioChange}
            screenWidth={screenWidth}
            screenHeight={screenHeight}
          />
        ) : null}
      </>
    );
  }

  const mainCamera: CameraSide = isFlipped ? 'front' : 'back';
  const pipCamera: CameraSide = isFlipped ? 'back' : 'front';
  const pipSide = canvas.width * clamp(pipSize || 0.28, 0.05, 0.5);
  const pipCenterX = canvas.left + canvas.width * clamp(pipPosition.x, 0, 1);
  const pipCenterY = canvas.top + canvas.height * clamp(pipPosition.y, 0, 1);
  const pipLeft = clamp(pipCenterX - pipSide / 2, canvas.left, canvas.left + canvas.width - pipSide);
  const pipTop = clamp(pipCenterY - pipSide / 2, canvas.top, canvas.top + canvas.height - pipSide);
  const pipRect = { left: pipLeft, top: pipTop, width: pipSide, height: pipSide };

  return (
    <>
      {renderZoom(mainCamera, canvas, backZoom, frontZoom, onZoomChange, bottomControlReserve)}
      {renderZoom(pipCamera, pipRect, backZoom, frontZoom, onZoomChange)}
    </>
  );
}

export const CameraControlsOverlay = memo(CameraControlsOverlayImpl);
CameraControlsOverlay.displayName = 'CameraControlsOverlay';
