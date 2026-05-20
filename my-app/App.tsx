import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';
import { StatusBar } from 'expo-status-bar';

import {
  CAMERA_MODE,
  type CameraMode,
  type CameraSide,
  type CaptureMode,
} from './src/constants';
import { DualCameraModule } from './src/native';
import { styles } from './src/styles';
import { clamp } from './src/utils';

import { useAspectRatio } from './src/hooks/useAspectRatio';
import { useCameraPermission } from './src/hooks/useCameraPermission';
import { useDualCameraSession } from './src/hooks/useDualCameraSession';
import { useDualCameraView } from './src/hooks/useDualCameraView';
import { useMediaPermission } from './src/hooks/useMediaPermission';
import { useScreenSize } from './src/hooks/useScreenSize';
import { useVideoUnlock } from './src/hooks/useVideoUnlock';

import { AudioLevelIndicator } from './src/components/AudioLevelIndicator';
import { BottomBar } from './src/components/BottomBar';
import { CameraControlsOverlay } from './src/components/CameraControlsOverlay';
import { CameraSurface } from './src/components/CameraSurface';
import { MediaPermissionBanner } from './src/components/MediaPermissionBanner';
import { PermissionGate } from './src/components/PermissionGate';
import { RecordingIndicator } from './src/components/RecordingIndicator';
import { SavingOverlay } from './src/components/SavingOverlay';
import { SettingsPopup } from './src/components/SettingsPopup';
import { VideoUnlockSheet } from './src/components/VideoUnlockSheet';

export default function App() {
  const { status: cameraStatus, request: requestCamera } = useCameraPermission();
  const media = useMediaPermission();
  const screen = useScreenSize();
  const { audioLevel, pipPosition, pipSize, resetPip } = useDualCameraView();
  const session = useDualCameraSession({ ensureMedia: media.ensure });
  const videoUnlock = useVideoUnlock();
  const [aspect, setAspect] = useAspectRatio();

  const [cameraMode, setCameraMode] = useState<CameraMode>(CAMERA_MODE.SX);
  const [captureMode, setCaptureMode] = useState<CaptureMode>('picture');
  const [dualLayoutRatio, setDualLayoutRatio] = useState(0.5);
  const [frontZoom, setFrontZoom] = useState(1);
  const [backZoom, setBackZoom] = useState(1);
  const [menuExpanded, setMenuExpanded] = useState(false);
  const [unlockSheetVisible, setUnlockSheetVisible] = useState(false);
  const [isFlipped, setIsFlipped] = useState(false);

  // Start the native session as soon as camera permission is granted; the
  // matching teardown runs on unmount or status change.
  useEffect(() => {
    if (cameraStatus === 'authorized' && DualCameraModule?.startSession) {
      DualCameraModule.startSession();
      DualCameraModule.startAudioMetering?.();
    }
    return () => {
      DualCameraModule?.stopAudioMetering?.();
      DualCameraModule?.stopSession?.();
    };
  }, [cameraStatus]);

  const handleZoomChange = useCallback((cam: CameraSide, level: number) => {
    const min = cam === 'back' ? 0.5 : 1;
    const max = cam === 'back' ? 5 : 2;
    const next = Math.round(clamp(level, min, max) * 10) / 10;
    DualCameraModule?.setZoom?.(cam, next);
    if (cam === 'back') setBackZoom(next);
    else setFrontZoom(next);
  }, []);

  const handleFlip = useCallback(() => {
    if (!DualCameraModule?.flipCamera) return;
    DualCameraModule.flipCamera();
    setIsFlipped(v => !v);
  }, []);

  const handleModeSwitch = useCallback((mode: CameraMode) => {
    if (session.interactionDisabled) return;
    setCameraMode(mode);
    setDualLayoutRatio(0.5);
    resetPip();
    setMenuExpanded(false);
    setIsFlipped(false);
  }, [session.interactionDisabled, resetPip]);

  const handleCaptureModeChange = useCallback((mode: CaptureMode) => {
    if (session.interactionDisabled || videoUnlock.purchasing) return;
    setCaptureMode(mode);
  }, [session.interactionDisabled, videoUnlock]);

  const videoLocked = captureMode === 'video' && !videoUnlock.unlocked;

  const onShutterPress = useCallback(() => {
    if (videoLocked && !session.recording && !session.recordingStarting) {
      setUnlockSheetVisible(true);
      return;
    }
    session.handleShutterPress(captureMode);
  }, [session, captureMode, videoLocked]);

  const handlePurchaseVideo = useCallback(() => {
    console.log('[VideoUnlock] unlock button pressed; closing sheet before purchase');
    setUnlockSheetVisible(false);
    setTimeout(() => {
      console.log('[VideoUnlock] invoking purchase after sheet close');
      videoUnlock.purchase();
    }, 250);
  }, [videoUnlock]);

  const handleRestorePurchases = useCallback(() => {
    console.log('[VideoUnlock] restore button pressed; closing sheet before restore');
    setUnlockSheetVisible(false);
    setTimeout(() => {
      console.log('[VideoUnlock] invoking restore after sheet close');
      videoUnlock.restore();
    }, 250);
  }, [videoUnlock]);

  const openMenu = useCallback(() => setMenuExpanded(true), []);
  const closeMenu = useCallback(() => setMenuExpanded(false), []);

  if (cameraStatus !== 'authorized') {
    return <PermissionGate status={cameraStatus} onRequest={requestCamera} />;
  }

  return (
    <View style={styles.root} onLayout={screen.onLayout}>
      <CameraSurface
        cameraMode={cameraMode}
        aspect={aspect}
        dualLayoutRatio={dualLayoutRatio}
        pipSize={pipSize}
        pipPosition={pipPosition}
        isFlipped={isFlipped}
      />

      <BottomBar
        cameraMode={cameraMode}
        captureMode={captureMode}
        recording={session.recording}
        recordingStarting={session.recordingStarting}
        recordingStopping={session.recordingStopping}
        saving={session.saving}
        videoLocked={videoLocked}
        onShutterPress={onShutterPress}
        onModeSwitch={handleModeSwitch}
        onCaptureModeChange={handleCaptureModeChange}
        isFlipped={isFlipped}
        onFlip={handleFlip}
      />

      <SettingsPopup
        visible={menuExpanded}
        onOpen={openMenu}
        onClose={closeMenu}
        aspectRatio={aspect}
        onAspectChange={setAspect}
        disabled={session.interactionDisabled || session.saving || videoUnlock.purchasing}
      />

      <VideoUnlockSheet
        visible={unlockSheetVisible}
        product={videoUnlock.product}
        purchasing={videoUnlock.purchasing}
        onPurchase={handlePurchaseVideo}
        onRestore={handleRestorePurchases}
        onClose={() => setUnlockSheetVisible(false)}
      />

      {screen.width > 0 ? (
        <CameraControlsOverlay
          cameraMode={cameraMode}
          aspect={aspect}
          isFlipped={isFlipped}
          dualLayoutRatio={dualLayoutRatio}
          onDualLayoutRatioChange={setDualLayoutRatio}
          pipSize={pipSize}
          pipPosition={pipPosition}
          screenWidth={screen.width}
          screenHeight={screen.height}
          backZoom={backZoom}
          frontZoom={frontZoom}
          onZoomChange={handleZoomChange}
          layoutInteractionDisabled={session.interactionDisabled}
        />
      ) : null}

      {!media.granted ? <MediaPermissionBanner onRequest={media.request} /> : null}
      {session.saving ? <SavingOverlay /> : null}
      {(session.recording || session.recordingStarting) ? (
        <RecordingIndicator starting={session.recordingStarting} />
      ) : null}
      {session.recording && audioLevel > 0.05 ? <AudioLevelIndicator level={audioLevel} /> : null}

      <StatusBar style="light" />
    </View>
  );
}
