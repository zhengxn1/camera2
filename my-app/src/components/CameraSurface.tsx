import { memo } from 'react';
import { Text, View } from 'react-native';
import {
  type AspectRatio,
  CAMERA_MODE,
  type CameraMode,
  LAYOUT_MAP,
} from '../constants';
import { NativeDualCameraView } from '../native';
import { styles } from '../styles';
import type { PipPosition } from './CameraControlsOverlay';

interface CameraSurfaceProps {
  cameraMode: CameraMode;
  aspect: AspectRatio;
  dualLayoutRatio: number;
  pipSize: number;
  pipPosition: PipPosition;
  isFlipped: boolean;
  frontBeautyEnabled: boolean;
  frontBeautySmooth: number;
  frontBeautyBrighten: number;
  frontBeautyWhiten: number;
}

function CameraSurfaceImpl({
  cameraMode,
  aspect,
  dualLayoutRatio,
  pipSize,
  pipPosition,
  isFlipped,
  frontBeautyEnabled,
  frontBeautySmooth,
  frontBeautyBrighten,
  frontBeautyWhiten,
}: CameraSurfaceProps) {
  if (!NativeDualCameraView) {
    return (
      <View style={styles.fallbackContainer}>
        <Text style={styles.fallbackTitle}>双摄相机</Text>
        <Text style={styles.fallbackText}>正在加载原生相机模块...</Text>
      </View>
    );
  }

  const isSplit = cameraMode === CAMERA_MODE.LR || cameraMode === CAMERA_MODE.SX;
  const isPip = cameraMode === CAMERA_MODE.PIP_SQUARE || cameraMode === CAMERA_MODE.PIP_CIRCLE;

  return (
    <NativeDualCameraView
      style={styles.nativeCamera}
      layoutMode={LAYOUT_MAP[cameraMode]}
      saveAspectRatio={aspect}
      dualLayoutRatio={isSplit ? dualLayoutRatio : 0.5}
      pipSize={isPip ? pipSize : 0.28}
      pipPositionX={pipPosition.x}
      pipPositionY={pipPosition.y}
      sxBackOnTop={isSplit ? !isFlipped : true}
      pipMainIsBack={isPip ? !isFlipped : true}
      frontBeautyEnabled={frontBeautyEnabled}
      frontBeautySmooth={frontBeautySmooth}
      frontBeautyBrighten={frontBeautyBrighten}
      frontBeautyWhiten={frontBeautyWhiten}
    />
  );
}

export const CameraSurface = memo(CameraSurfaceImpl);
CameraSurface.displayName = 'CameraSurface';
