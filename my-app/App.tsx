import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  Text,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as MediaLibrary from 'expo-media-library';
import AsyncStorage from '@react-native-async-storage/async-storage';

import {
  ASPECT_RATIOS,
  type AspectRatio,
  CAMERA_MODE,
  type CameraMode,
  type CameraSide,
  type CaptureMode,
  LAYOUT_MAP,
} from './src/constants';
import { styles } from './src/styles';
import { clamp } from './src/utils';
import {
  CameraPermissionModule,
  DualCameraModule,
  NativeDualCameraView,
  eventEmitter,
} from './src/native';
import { AudioLevelIndicator } from './src/components/AudioLevelIndicator';
import { BottomBar } from './src/components/BottomBar';
import {
  CameraControlsOverlay,
  type PipPosition,
} from './src/components/CameraControlsOverlay';
import { SettingsPopup } from './src/components/SettingsPopup';

type CameraStatus = 'loading' | 'authorized' | 'not_determined' | 'denied' | 'unavailable';

const STORAGE_KEY_ASPECT = 'dualcam_save_aspect';

function isAspectRatio(value: unknown): value is AspectRatio {
  return typeof value === 'string' && (ASPECT_RATIOS as readonly string[]).includes(value);
}

export default function App() {
  const [cameraMode, setCameraMode] = useState<CameraMode>(CAMERA_MODE.SX);
  const [screenWidth, setScreenWidth] = useState(0);
  const [screenHeight, setScreenHeight] = useState(0);
  const [captureMode, setCaptureMode] = useState<CaptureMode>('picture');
  const [saving, setSaving] = useState(false);
  const [recordingStarting, setRecordingStarting] = useState(false);
  const [recording, setRecording] = useState(false);
  const [recordingStopping, setRecordingStopping] = useState(false);
  const recordingStopRequestedRef = useRef(false);
  const [cameraStatus, setCameraStatus] = useState<CameraStatus>('loading');
  const [audioLevel, setAudioLevel] = useState(0);
  const [mediaPermission, requestMediaPermission] = MediaLibrary.usePermissions({
    writeOnly: true,
    granularPermissions: ['photo'],
  });
  const [dualLayoutRatio, setDualLayoutRatio] = useState(0.5);
  const [pipSize, setPipSize] = useState(0.28);
  const [pipPosition, setPipPosition] = useState<PipPosition>({ x: 0.85, y: 0.80 });
  const [frontZoom, setFrontZoom] = useState(1);
  const [backZoom, setBackZoom] = useState(1);
  const [menuExpanded, setMenuExpanded] = useState(false);
  const [saveAspectRatio, setSaveAspectRatio] = useState<AspectRatio>('9:16');
  const [isFlipped, setIsFlipped] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!CameraPermissionModule) {
        setCameraStatus('unavailable');
        return;
      }
      try {
        const status = await CameraPermissionModule.getCameraAuthorizationStatus?.();
        if (cancelled) return;
        if (status === 'authorized') setCameraStatus('authorized');
        else if (status === 'not_determined') setCameraStatus('not_determined');
        else setCameraStatus('denied');
      } catch (_e) {
        if (!cancelled) setCameraStatus('unavailable');
      }
    })();
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    (async () => {
      try {
        const saved = await AsyncStorage.getItem(STORAGE_KEY_ASPECT);
        if (isAspectRatio(saved)) setSaveAspectRatio(saved);
      } catch (_) {}
    })();
  }, []);

  const ensureMediaPermission = useCallback(async () => {
    if (mediaPermission?.granted) return true;
    const result = await requestMediaPermission();
    if (result.granted) return true;
    Alert.alert('Media permission required', 'Saving photos and videos requires photo library access.');
    return false;
  }, [mediaPermission?.granted, requestMediaPermission]);

  useEffect(() => {
    if (!eventEmitter) return undefined;

    const subPhotoSaved = eventEmitter.addListener('onPhotoSaved', async (event: { uri: string }) => {
      setSaving(false);
      try {
        const ok = await ensureMediaPermission();
        if (ok) {
          await MediaLibrary.saveToLibraryAsync(event.uri);
          Alert.alert('Saved', 'Photo saved to library.');
        }
      } catch (e: any) {
        Alert.alert('Save failed', e?.message ?? String(e));
      }
    });

    const subPhotoError = eventEmitter.addListener('onPhotoError', (event: { error?: string }) => {
      setSaving(false);
      Alert.alert('Photo failed', event.error ?? 'Unknown error');
    });

    const subRecordingStarted = eventEmitter.addListener('onRecordingStarted', () => {
      setRecordingStarting(false);
      setRecording(true);
      if (!recordingStopRequestedRef.current) setRecordingStopping(false);
    });

    const subRecordingFinished = eventEmitter.addListener('onRecordingFinished', async (event: { uri: string }) => {
      recordingStopRequestedRef.current = false;
      setRecordingStarting(false);
      setRecording(false);
      setRecordingStopping(false);
      try {
        const ok = await ensureMediaPermission();
        if (ok) {
          await MediaLibrary.saveToLibraryAsync(event.uri);
          Alert.alert('Saved', 'Video saved to library.');
        }
      } catch (e: any) {
        Alert.alert('Save failed', e?.message ?? String(e));
      }
    });

    const subRecordingError = eventEmitter.addListener('onRecordingError', (event: { error?: string }) => {
      recordingStopRequestedRef.current = false;
      setRecordingStarting(false);
      setRecording(false);
      setRecordingStopping(false);
      console.warn('[DualCamera] Recording error', event);
      Alert.alert('Recording failed', event.error ?? 'Unknown error');
    });

    const subSessionError = eventEmitter.addListener('onSessionError', (event: { error?: string }) => {
      recordingStopRequestedRef.current = false;
      setSaving(false);
      setRecordingStarting(false);
      setRecording(false);
      setRecordingStopping(false);
      Alert.alert('Camera error', event.error ?? 'Camera session failed.');
    });

    const subAudioLevel = eventEmitter.addListener('onAudioLevel', (event: { average?: number }) => {
      setAudioLevel(event.average ?? 0);
    });

    const subPipPositionChanged = eventEmitter.addListener('onPipPositionChanged', (event: { x?: number; y?: number }) => {
      setPipPosition({ x: event.x ?? 0.85, y: event.y ?? 0.80 });
    });

    const subPipSizeChanged = eventEmitter.addListener('onPipSizeChanged', (event: { size?: number }) => {
      setPipSize(event.size ?? 0.28);
    });

    return () => {
      subPhotoSaved.remove();
      subPhotoError.remove();
      subRecordingStarted.remove();
      subRecordingFinished.remove();
      subRecordingError.remove();
      subSessionError.remove();
      subAudioLevel.remove();
      subPipPositionChanged.remove();
      subPipSizeChanged.remove();
    };
  }, [ensureMediaPermission]);

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

  const requestCamera = useCallback(async () => {
    if (!CameraPermissionModule?.requestCameraPermission) return;
    try {
      const granted = await CameraPermissionModule.requestCameraPermission();
      setCameraStatus(granted ? 'authorized' : 'denied');
    } catch (_e) {
      setCameraStatus('denied');
    }
  }, []);

  const takePhoto = useCallback(async () => {
    if (!DualCameraModule?.takePhoto) {
      Alert.alert('Error', 'Native camera module is unavailable.');
      return;
    }
    const ok = await ensureMediaPermission();
    if (!ok) return;
    setSaving(true);
    DualCameraModule.takePhoto();
  }, [ensureMediaPermission]);

  const startRecording = useCallback(() => {
    if (!DualCameraModule?.startRecording) {
      Alert.alert('Error', 'Native camera module is unavailable.');
      return;
    }
    recordingStopRequestedRef.current = false;
    setRecordingStarting(true);
    setRecordingStopping(false);
    DualCameraModule.startRecording();
  }, []);

  const stopRecording = useCallback(() => {
    if (recordingStopping || !DualCameraModule?.stopRecording) return;
    recordingStopRequestedRef.current = true;
    setRecordingStopping(true);
    DualCameraModule.stopRecording();
  }, [recordingStopping]);

  const handleShutterPress = useCallback(() => {
    if (recordingStopping) return;
    if (recording || recordingStarting) stopRecording();
    else if (captureMode === 'picture') takePhoto();
    else startRecording();
  }, [recordingStarting, recording, recordingStopping, captureMode, takePhoto, startRecording, stopRecording]);

  const handleFlip = useCallback(() => {
    if (!DualCameraModule?.flipCamera) return;
    DualCameraModule.flipCamera();
    setIsFlipped(v => !v);
  }, []);

  const interactionDisabled = recording || recordingStarting || recordingStopping;

  const handleZoomChange = useCallback((camera: CameraSide, level: number) => {
    const min = camera === 'back' ? 0.5 : 1;
    const max = camera === 'back' ? 5 : 2;
    const next = Math.round(clamp(level, min, max) * 10) / 10;
    DualCameraModule?.setZoom?.(camera, next);
    if (camera === 'back') setBackZoom(next);
    else setFrontZoom(next);
  }, []);

  const handleAspectChange = useCallback(async (ratio: AspectRatio) => {
    setSaveAspectRatio(ratio);
    try { await AsyncStorage.setItem(STORAGE_KEY_ASPECT, ratio); } catch (_) {}
  }, []);

  const handleModeSwitch = useCallback((mode: CameraMode) => {
    if (interactionDisabled) return;
    setCameraMode(mode);
    setDualLayoutRatio(0.5);
    setPipSize(0.28);
    setPipPosition({ x: 0.85, y: 0.80 });
    setMenuExpanded(false);
    setIsFlipped(false);
  }, [interactionDisabled]);

  const handleCaptureModeChange = useCallback((m: CaptureMode) => {
    if (!interactionDisabled) setCaptureMode(m);
  }, [interactionDisabled]);

  if (cameraStatus === 'loading') {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color="#fff" />
        <StatusBar style="light" />
      </View>
    );
  }

  if (cameraStatus === 'not_determined') {
    return (
      <View style={styles.centered}>
        <Text style={styles.permissionTitle}>Camera permission required</Text>
        <Text style={styles.permissionBody}>Dual camera needs access to the front and back cameras.</Text>
        <Pressable style={styles.primaryButton} onPress={requestCamera}>
          <Text style={styles.primaryButtonLabel}>Allow camera</Text>
        </Pressable>
        <StatusBar style="light" />
      </View>
    );
  }

  if (cameraStatus === 'denied' || cameraStatus === 'unavailable') {
    return (
      <View style={styles.centered}>
        <Text style={styles.permissionTitle}>Camera unavailable</Text>
        <Text style={styles.permissionBody}>
          {cameraStatus === 'denied'
            ? 'Enable camera permission in system settings.'
            : 'Native camera module is not loaded. Rebuild the app.'}
        </Text>
        <StatusBar style="light" />
      </View>
    );
  }

  return (
    <View
      style={styles.root}
      onLayout={e => {
        const { width, height } = e.nativeEvent.layout;
        setScreenWidth(width);
        setScreenHeight(height);
      }}
    >
      {NativeDualCameraView ? (
        <NativeDualCameraView
          style={styles.nativeCamera}
          layoutMode={LAYOUT_MAP[cameraMode]}
          saveAspectRatio={saveAspectRatio}
          dualLayoutRatio={cameraMode === CAMERA_MODE.LR || cameraMode === CAMERA_MODE.SX ? dualLayoutRatio : 0.5}
          pipSize={cameraMode === CAMERA_MODE.PIP_SQUARE || cameraMode === CAMERA_MODE.PIP_CIRCLE ? pipSize : 0.28}
          pipPositionX={pipPosition.x}
          pipPositionY={pipPosition.y}
          sxBackOnTop={cameraMode === CAMERA_MODE.LR || cameraMode === CAMERA_MODE.SX ? !isFlipped : true}
          pipMainIsBack={cameraMode === CAMERA_MODE.PIP_SQUARE || cameraMode === CAMERA_MODE.PIP_CIRCLE ? !isFlipped : true}
        />
      ) : (
        <View style={styles.fallbackContainer}>
          <Text style={styles.fallbackTitle}>Dual Camera</Text>
          <Text style={styles.fallbackText}>Loading native camera module...</Text>
        </View>
      )}

      <BottomBar
        cameraMode={cameraMode}
        captureMode={captureMode}
        recording={recording}
        recordingStarting={recordingStarting}
        recordingStopping={recordingStopping}
        saving={saving}
        onShutterPress={handleShutterPress}
        onModeSwitch={handleModeSwitch}
        onCaptureModeChange={handleCaptureModeChange}
        isFlipped={isFlipped}
        onFlip={handleFlip}
      />

      <SettingsPopup
        visible={menuExpanded}
        onOpen={() => setMenuExpanded(true)}
        onClose={() => setMenuExpanded(false)}
        aspectRatio={saveAspectRatio}
        onAspectChange={handleAspectChange}
        disabled={interactionDisabled || saving}
      />

      {!interactionDisabled && screenWidth > 0 ? (
        <CameraControlsOverlay
          cameraMode={cameraMode}
          isFlipped={isFlipped}
          dualLayoutRatio={dualLayoutRatio}
          onDualLayoutRatioChange={setDualLayoutRatio}
          pipSize={pipSize}
          pipPosition={pipPosition}
          screenWidth={screenWidth}
          screenHeight={screenHeight}
          backZoom={backZoom}
          frontZoom={frontZoom}
          onZoomChange={handleZoomChange}
        />
      ) : null}

      {!mediaPermission?.granted ? (
        <View style={styles.mediaBanner}>
          <Text style={styles.mediaBannerText}>Photo library permission is required to save.</Text>
          <Pressable style={styles.secondaryButton} onPress={requestMediaPermission}>
            <Text style={styles.secondaryButtonLabel}>Allow</Text>
          </Pressable>
        </View>
      ) : null}

      {saving ? (
        <View style={styles.savingOverlay} pointerEvents="none">
          <ActivityIndicator size="large" color="#fff" />
        </View>
      ) : null}

      {(recording || recordingStarting) ? (
        <View style={styles.recordingIndicator} pointerEvents="none">
          <View style={styles.recordingDot} />
          <Text style={styles.recordingText}>{recordingStarting ? 'Preparing' : 'Recording'}</Text>
        </View>
      ) : null}

      {recording && audioLevel > 0.05 ? <AudioLevelIndicator level={audioLevel} /> : null}
      <StatusBar style="light" />
    </View>
  );
}
