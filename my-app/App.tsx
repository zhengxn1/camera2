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
import {
  BeautyPanel,
  DEFAULT_BEAUTY_SETTINGS,
  type BeautySettings,
} from './src/components/BeautyPanel';
import { BottomBar } from './src/components/BottomBar';
import { CameraControlsOverlay } from './src/components/CameraControlsOverlay';
import { CameraSurface } from './src/components/CameraSurface';
import { MediaPermissionBanner } from './src/components/MediaPermissionBanner';
import { PermissionGate } from './src/components/PermissionGate';
import { RecordingIndicator } from './src/components/RecordingIndicator';
import { SavingOverlay } from './src/components/SavingOverlay';
import { SettingsPopup, type SaveFormat } from './src/components/SettingsPopup';
import { VideoUnlockSheet } from './src/components/VideoUnlockSheet';

export default function App() {
  const { status: cameraStatus, requesting: cameraRequesting, request: requestCamera } = useCameraPermission();
  const media = useMediaPermission();
  const screen = useScreenSize();
  const { audioLevel, pipPosition, pipSize, resetPip } = useDualCameraView();
  const videoUnlock = useVideoUnlock();
  const [aspect, setAspect] = useAspectRatio();
  const [saveFormat, setSaveFormat] = useState<SaveFormat>('merged');
  const session = useDualCameraSession({ ensureMedia: media.ensure, saveFormat });

  const [cameraMode, setCameraMode] = useState<CameraMode>(CAMERA_MODE.SX);
  const [captureMode, setCaptureMode] = useState<CaptureMode>('picture');
  const [dualLayoutRatio, setDualLayoutRatio] = useState(0.5);
  const [frontZoom, setFrontZoom] = useState(1);
  const [backZoom, setBackZoom] = useState(1);
  const [menuExpanded, setMenuExpanded] = useState(false);
  const [beautyPanelVisible, setBeautyPanelVisible] = useState(false);
  const [beautySettings, setBeautySettings] = useState<BeautySettings>(DEFAULT_BEAUTY_SETTINGS);
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

  useEffect(() => {
    if (cameraStatus === 'not_determined' && !cameraRequesting) {
      requestCamera();
    }
  }, [cameraRequesting, cameraStatus, requestCamera]);

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
    setBeautyPanelVisible(false);
    setIsFlipped(false);
  }, [session.interactionDisabled, resetPip]);

  const handleCaptureModeChange = useCallback((mode: CaptureMode) => {
    if (session.interactionDisabled || videoUnlock.purchasing) return;
    setCaptureMode(mode);
  }, [session.interactionDisabled, videoUnlock.purchasing]);

  const videoLocked = captureMode === 'video' && !videoUnlock.unlocked;

  const onShutterPress = useCallback(async () => {
    if (videoLocked && !session.recording && !session.recordingStarting) {
      const alreadyUnlocked = await videoUnlock.refresh();
      if (alreadyUnlocked) {
        session.handleShutterPress(captureMode);
        return;
      }

      void videoUnlock.refreshProduct();
      setUnlockSheetVisible(true);
      return;
    }
    session.handleShutterPress(captureMode);
  }, [session, captureMode, videoLocked, videoUnlock]);

  const handlePurchaseVideo = useCallback(async () => {
    const ok = await videoUnlock.purchase();
    if (ok) {
      setUnlockSheetVisible(false);
      setCaptureMode('video');
    }
  }, [videoUnlock]);

  const handleRestorePurchases = useCallback(async () => {
    const ok = await videoUnlock.restore();
    if (ok) {
      setUnlockSheetVisible(false);
      setCaptureMode('video');
    }
  }, [videoUnlock]);

  const openMenu = useCallback(() => {
    setBeautyPanelVisible(false);
    setMenuExpanded(true);
  }, []);
  const closeMenu = useCallback(() => setMenuExpanded(false), []);
  const beautyAvailable = cameraMode !== CAMERA_MODE.BACK;
  const beautyActive = beautyAvailable && (
    beautySettings.smooth > 0 ||
    beautySettings.brighten > 0 ||
    beautySettings.whiten > 0
  );

  useEffect(() => {
    console.info(
      `[BeautyJS] enabled=${beautyActive ? 1 : 0} smooth=${beautySettings.smooth} ` +
      `brighten=${beautySettings.brighten} whiten=${beautySettings.whiten} ` +
      `mode=${cameraMode} capture=${captureMode}`,
    );
  }, [beautyActive, beautySettings.smooth, beautySettings.brighten, beautySettings.whiten, cameraMode, captureMode]);
  const openBeautyPanel = useCallback(() => {
    if (session.interactionDisabled || !beautyAvailable) return;
    setMenuExpanded(false);
    setBeautyPanelVisible(true);
  }, [beautyAvailable, session.interactionDisabled]);
  const closeBeautyPanel = useCallback(() => setBeautyPanelVisible(false), []);

  if (cameraStatus !== 'authorized') {
    return <PermissionGate status={cameraStatus} requesting={cameraRequesting} onRequest={requestCamera} />;
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
        saveFormat={saveFormat}
        frontBeautyEnabled={beautyActive}
        frontBeautySmooth={beautySettings.smooth}
        frontBeautyBrighten={beautySettings.brighten}
        frontBeautyWhiten={beautySettings.whiten}
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
        beautyActive={beautyActive}
        beautyPanelVisible={beautyPanelVisible}
        beautyAvailable={beautyAvailable}
        onBeautyOpen={openBeautyPanel}
        settingsActive={menuExpanded}
        settingsDisabled={session.interactionDisabled || session.saving || videoUnlock.purchasing}
        onSettingsOpen={openMenu}
      />

      <SettingsPopup
        visible={menuExpanded}
        onClose={closeMenu}
        aspectRatio={aspect}
        onAspectChange={setAspect}
        saveFormat={saveFormat}
        onSaveFormatChange={setSaveFormat}
        disabled={session.interactionDisabled || session.saving || videoUnlock.purchasing}
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
          controlsHidden={beautyPanelVisible}
        />
      ) : null}

      <BeautyPanel
        visible={beautyPanelVisible}
        settings={beautySettings}
        disabled={session.interactionDisabled || session.saving || videoUnlock.purchasing}
        available={beautyAvailable}
        onChange={setBeautySettings}
        onClose={closeBeautyPanel}
      />

      <VideoUnlockSheet
        visible={unlockSheetVisible}
        product={videoUnlock.product}
        productLoading={videoUnlock.productLoading}
        productError={videoUnlock.productError}
        purchasing={videoUnlock.purchasing}
        onPurchase={handlePurchaseVideo}
        onRestore={handleRestorePurchases}
        onRetryPrice={videoUnlock.refreshProduct}
        onClose={() => {
          if (!videoUnlock.purchasing) setUnlockSheetVisible(false);
        }}
      />

      {media.blocked ? (
        <MediaPermissionBanner onRequest={media.request} onDismiss={media.dismissBlocked} />
      ) : null}
      {session.saving ? <SavingOverlay /> : null}
      {(session.recording || session.recordingStarting) ? (
        <RecordingIndicator starting={session.recordingStarting} />
      ) : null}
      {session.recording && audioLevel > 0.05 ? <AudioLevelIndicator level={audioLevel} /> : null}

      <StatusBar style="light" />
    </View>
  );
}
