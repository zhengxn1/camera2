import { memo, useEffect } from 'react';
import { Text, View } from 'react-native';
import {
  type AspectRatio,
  CAMERA_MODE,
  type CameraMode,
  LAYOUT_MAP,
  type VideoSaveMode,
} from '../constants';
import { NativeDualCameraView } from '../native';
import { styles } from '../styles';
import type { FrontBeautySettings } from '../hooks/useFrontBeautyEnabled';
import type { PipPosition } from './CameraControlsOverlay';

let lastBeautyProbeLogAt = 0;

interface CameraSurfaceProps {
  cameraMode: CameraMode;
  aspect: AspectRatio;
  dualLayoutRatio: number;
  pipSize: number;
  pipPosition: PipPosition;
  isFlipped: boolean;
  videoSaveMode: VideoSaveMode;
  frontBeautyEnabled: boolean;
  frontBeautySettings: FrontBeautySettings;
}

function CameraSurfaceImpl({
  cameraMode,
  aspect,
  dualLayoutRatio,
  pipSize,
  pipPosition,
  isFlipped,
  videoSaveMode,
  frontBeautyEnabled,
  frontBeautySettings,
}: CameraSurfaceProps) {
  useEffect(() => {
    const now = Date.now();
    if (now - lastBeautyProbeLogAt < 500) return;
    lastBeautyProbeLogAt = now;
    console.log('[BeautyProbe][JS] props', {
      enabled: frontBeautyEnabled,
      smooth: frontBeautySettings.smooth,
      whiten: frontBeautySettings.whiten,
      even: frontBeautySettings.even,
      plump: frontBeautySettings.plump,
      layoutMode: LAYOUT_MAP[cameraMode],
      videoSaveMode,
    });
  }, [cameraMode, frontBeautyEnabled, frontBeautySettings, videoSaveMode]);

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
      videoSaveMode={videoSaveMode}
      frontBeautyEnabled={frontBeautyEnabled}
      frontBeautySmooth={frontBeautySettings.smooth}
      frontBeautyWhiten={frontBeautySettings.whiten}
      frontBeautyEven={frontBeautySettings.even}
      frontBeautyPlump={frontBeautySettings.plump}
    />
  );
}

export const CameraSurface = memo(CameraSurfaceImpl);
CameraSurface.displayName = 'CameraSurface';
