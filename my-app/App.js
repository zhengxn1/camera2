import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  AsyncStorage,
  NativeEventEmitter,
  NativeModules,
  PanResponder,
  Platform,
  Pressable,
  requireNativeComponent,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as MediaLibrary from 'expo-media-library';

const CAMERA_MODE = {
  BACK: 'back',
  FRONT: 'front',
  PIP_SQUARE: 'pip_square',
  PIP_CIRCLE: 'pip_circle',
  LR: 'lr',
  SX: 'sx',
};

const LAYOUT_MAP = {
  [CAMERA_MODE.BACK]: 'back',
  [CAMERA_MODE.FRONT]: 'front',
  [CAMERA_MODE.PIP_SQUARE]: 'pip_square',
  [CAMERA_MODE.PIP_CIRCLE]: 'pip_circle',
  [CAMERA_MODE.LR]: 'lr',
  [CAMERA_MODE.SX]: 'sx',
};

const ASPECT_RATIOS = ['9:16', '3:4', '1:1'];
const BACK_ZOOM_LEVELS = [0.5, 1, 2, 3, 5];
const FRONT_ZOOM_LEVELS = [1, 2];
const SNAP_POINTS = [0.3, 0.5, 0.7];
const ZOOM_ACTIVE = '#FFD60A';
const INTERACTION_TOP = Platform.OS === 'ios' ? 60 : 44;
const MODE_OPTIONS = [
  { mode: CAMERA_MODE.PIP_SQUARE, label: 'Picture in picture', icon: 'pipSquare' },
  { mode: CAMERA_MODE.PIP_CIRCLE, label: 'Circle picture in picture', icon: 'pipCircle' },
  { mode: CAMERA_MODE.LR, label: 'Left right split', icon: 'lr' },
  { mode: CAMERA_MODE.SX, label: 'Top bottom split', icon: 'sx' },
];

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

let NativeDualCameraView;
try {
  NativeDualCameraView = requireNativeComponent('DualCameraView');
} catch (e) {
  NativeDualCameraView = null;
}

const { DualCameraModule, DualCameraEventEmitter, CameraPermissionModule } = NativeModules;

let eventEmitter = null;
if (DualCameraEventEmitter) {
  eventEmitter = new NativeEventEmitter(DualCameraEventEmitter);
}

export default function App() {
  const [cameraMode, setCameraMode] = useState(CAMERA_MODE.SX);
  const [screenWidth, setScreenWidth] = useState(0);
  const [screenHeight, setScreenHeight] = useState(0);
  const [captureMode, setCaptureMode] = useState('picture');
  const [saving, setSaving] = useState(false);
  const [recordingStarting, setRecordingStarting] = useState(false);
  const [recording, setRecording] = useState(false);
  const [recordingStopping, setRecordingStopping] = useState(false);
  const recordingStopRequestedRef = useRef(false);
  const [cameraStatus, setCameraStatus] = useState('loading');
  const [audioLevel, setAudioLevel] = useState(0);
  const [mediaPermission, requestMediaPermission] = MediaLibrary.usePermissions({
    writeOnly: true,
    granularPermissions: ['photo'],
  });
  const [dualLayoutRatio, setDualLayoutRatio] = useState(0.5);
  const [pipSize, setPipSize] = useState(0.28);
  const [pipPosition, setPipPosition] = useState({ x: 0.85, y: 0.80 });
  const [frontZoom, setFrontZoom] = useState(1);
  const [backZoom, setBackZoom] = useState(1);
  const [menuExpanded, setMenuExpanded] = useState(false);
  const [saveAspectRatio, setSaveAspectRatio] = useState('9:16');
  const [isFlipped, setIsFlipped] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!CameraPermissionModule) {
        setCameraStatus('unavailable');
        return;
      }
      try {
        const status = await CameraPermissionModule.getCameraAuthorizationStatus();
        if (cancelled) return;
        if (status === 'authorized') setCameraStatus('authorized');
        else if (status === 'not_determined') setCameraStatus('not_determined');
        else setCameraStatus('denied');
      } catch (e) {
        if (!cancelled) setCameraStatus('unavailable');
      }
    })();
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    (async () => {
      try {
        const saved = await AsyncStorage.getItem('dualcam_save_aspect');
        if (ASPECT_RATIOS.includes(saved)) setSaveAspectRatio(saved);
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

    const subPhotoSaved = eventEmitter.addListener('onPhotoSaved', async (event) => {
      setSaving(false);
      try {
        const ok = await ensureMediaPermission();
        if (ok) {
          await MediaLibrary.saveToLibraryAsync(event.uri);
          Alert.alert('Saved', 'Photo saved to library.');
        }
      } catch (e) {
        Alert.alert('Save failed', e?.message ?? String(e));
      }
    });

    const subPhotoError = eventEmitter.addListener('onPhotoError', (event) => {
      setSaving(false);
      Alert.alert('Photo failed', event.error ?? 'Unknown error');
    });

    const subRecordingStarted = eventEmitter.addListener('onRecordingStarted', () => {
      setRecordingStarting(false);
      setRecording(true);
      if (!recordingStopRequestedRef.current) setRecordingStopping(false);
    });

    const subRecordingFinished = eventEmitter.addListener('onRecordingFinished', async (event) => {
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
      } catch (e) {
        Alert.alert('Save failed', e?.message ?? String(e));
      }
    });

    const subRecordingError = eventEmitter.addListener('onRecordingError', (event) => {
      recordingStopRequestedRef.current = false;
      setRecordingStarting(false);
      setRecording(false);
      setRecordingStopping(false);
      console.warn('[DualCamera] Recording error', event);
      Alert.alert('Recording failed', event.error ?? 'Unknown error');
    });

    const subSessionError = eventEmitter.addListener('onSessionError', (event) => {
      recordingStopRequestedRef.current = false;
      setSaving(false);
      setRecordingStarting(false);
      setRecording(false);
      setRecordingStopping(false);
      Alert.alert('Camera error', event.error ?? 'Camera session failed.');
    });

    const subAudioLevel = eventEmitter.addListener('onAudioLevel', (event) => {
      setAudioLevel(event.average ?? 0);
    });

    const subPipPositionChanged = eventEmitter.addListener('onPipPositionChanged', (event) => {
      setPipPosition({ x: event.x ?? 0.85, y: event.y ?? 0.80 });
    });

    const subPipSizeChanged = eventEmitter.addListener('onPipSizeChanged', (event) => {
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
      DualCameraModule.startAudioMetering();
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
    } catch (e) {
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

  const handleZoomChange = useCallback((camera, level) => {
    const min = camera === 'back' ? 0.5 : 1;
    const max = camera === 'back' ? 5 : 2;
    const next = Math.round(clamp(level, min, max) * 10) / 10;
    DualCameraModule?.setZoom?.(camera, next);
    if (camera === 'back') setBackZoom(next);
    else setFrontZoom(next);
  }, []);

  const handleAspectChange = useCallback(async (ratio) => {
    setSaveAspectRatio(ratio);
    try { await AsyncStorage.setItem('dualcam_save_aspect', ratio); } catch (_) {}
  }, []);

  const handleModeSwitch = useCallback((mode) => {
    if (interactionDisabled) return;
    setCameraMode(mode);
    setDualLayoutRatio(0.5);
    setPipSize(0.28);
    setPipPosition({ x: 0.85, y: 0.80 });
    setMenuExpanded(false);
    setIsFlipped(false);
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
        onCaptureModeChange={(m) => { if (!interactionDisabled) setCaptureMode(m); }}
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

function SettingsPopup({ visible, onClose, onOpen, aspectRatio, onAspectChange, disabled }) {
  return (
    <>
      <View style={styles.topBar} pointerEvents="box-none">
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Open settings"
          disabled={disabled}
          style={[styles.settingsButton, disabled && styles.disabledControl]}
          onPress={onOpen}
        >
          <Text style={styles.settingsIcon}>...</Text>
        </Pressable>
      </View>
      {visible ? (
        <View style={styles.settingsOverlay}>
          <Pressable style={StyleSheet.absoluteFillObject} onPress={onClose} />
          <View style={styles.settingsPanel}>
            <View style={styles.settingsHeader}>
              <Text style={styles.settingsTitle}>Settings</Text>
              <Pressable accessibilityRole="button" accessibilityLabel="Close settings" style={styles.closeButton} onPress={onClose}>
                <Text style={styles.closeButtonText}>x</Text>
              </Pressable>
            </View>
            <View style={styles.settingRow}>
              <Text style={styles.settingLabel}>Aspect</Text>
              <View style={styles.aspectOptions}>
                {ASPECT_RATIOS.map(ratio => (
                  <Pressable
                    key={ratio}
                    style={[styles.aspectBtn, aspectRatio === ratio && styles.aspectBtnActive]}
                    onPress={() => onAspectChange(ratio)}
                  >
                    <Text style={[styles.aspectBtnText, aspectRatio === ratio && styles.aspectBtnTextActive]}>
                      {ratio}
                    </Text>
                  </Pressable>
                ))}
              </View>
            </View>
          </View>
        </View>
      ) : null}
    </>
  );
}

function CameraControlsOverlay({
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
}) {
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
    const firstCamera = isFlipped ? 'front' : 'back';
    const secondCamera = isFlipped ? 'back' : 'front';
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
    const firstCamera = isFlipped ? 'front' : 'back';
    const secondCamera = isFlipped ? 'back' : 'front';
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
  const mainCamera = isFlipped ? 'front' : 'back';
  const pipCamera = isFlipped ? 'back' : 'front';
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

function ZoomDialOverlay({ positionStyle, children }) {
  return (
    <View style={[styles.zoomDialOverlay, positionStyle]} pointerEvents="box-none">
      {children}
    </View>
  );
}

function AreaDivider({ mode, ratio, onRatioChange, screenWidth, screenHeight }) {
  const [active, setActive] = useState(false);
  const latestRatioRef = useRef(ratio);
  const startRatioRef = useRef(ratio);
  const limitMin = 0.2;
  const limitMax = 0.8;
  latestRatioRef.current = ratio;

  const panResponder = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: () => {
      startRatioRef.current = latestRatioRef.current;
      setActive(true);
    },
    onPanResponderMove: (_, gesture) => {
      const delta = mode === 'lr' ? gesture.dx / screenWidth : gesture.dy / screenHeight;
      onRatioChange(clamp(startRatioRef.current + delta, limitMin, limitMax));
    },
    onPanResponderRelease: (_, gesture) => {
      const delta = mode === 'lr' ? gesture.dx / screenWidth : gesture.dy / screenHeight;
      const raw = clamp(startRatioRef.current + delta, limitMin, limitMax);
      const nearest = SNAP_POINTS.reduce((best, point) => (
        Math.abs(point - raw) < Math.abs(best - raw) ? point : best
      ), raw);
      onRatioChange(Math.abs(nearest - raw) <= 0.05 ? nearest : raw);
      setActive(false);
    },
    onPanResponderTerminate: () => setActive(false),
  })).current;

  if (mode === 'lr') {
    return (
      <View style={[styles.dividerVertical, { left: `${ratio * 100}%` }]} pointerEvents="box-none">
        <View style={styles.dividerLineVertical} />
        <View {...panResponder.panHandlers} style={[styles.dividerHitVertical, active && styles.dividerHitActive]}>
          <View style={[styles.dividerHandleVertical, active && styles.dividerHandleActive]}>
            <Text style={styles.dividerHandleText}>‹ ›</Text>
          </View>
        </View>
      </View>
    );
  }

  return (
    <View style={[styles.dividerHorizontal, { top: `${ratio * 100}%` }]} pointerEvents="box-none">
      <View style={styles.dividerLineHorizontal} />
      <View {...panResponder.panHandlers} style={[styles.dividerHitHorizontal, active && styles.dividerHitActive]}>
        <View style={[styles.dividerHandleHorizontal, active && styles.dividerHandleActive]}>
          <Text style={styles.dividerHandleText}>⌃⌄</Text>
        </View>
      </View>
    </View>
  );
}

/**
 * Adaptive zoom control.
 *
 * Display modes chosen from availableWidth (px):
 *   normal  — full-size 36 px buttons (default when no constraint)
 *   compact — small 28 px buttons (medium columns / PIP overlay)
 *   mini    — single badge showing current zoom; tap cycles presets (very narrow columns)
 *   hidden  — nothing rendered (< 44 px)
 */
function ZoomDial({ camera, currentZoom, onZoomChange, availableWidth = Infinity }) {
  const [expanded, setExpanded] = useState(false);
  const latestZoomRef = useRef(currentZoom);
  const startZoomRef = useRef(currentZoom);
  const levels = camera === 'back' ? BACK_ZOOM_LEVELS : FRONT_ZOOM_LEVELS;
  const min = camera === 'back' ? 0.5 : 1;
  const max = camera === 'back' ? 5 : 2;
  latestZoomRef.current = currentZoom;

  // Pixel width required for each mode's button row (buttons + gaps + horizontal padding).
  const n = levels.length;
  const normalMinW  = n * 36 + (n - 1) * 6 + 16;  // e.g. back=220, front=94
  const compactMinW = n * 28 + (n - 1) * 4 + 10;  // e.g. back=166, front=74

  const mode =
    availableWidth >= normalMinW  ? 'normal'  :
    availableWidth >= compactMinW ? 'compact' :
    availableWidth >= 44          ? 'mini'    : 'hidden';

  const isCompact = mode === 'compact';
  const sliderWidth = isCompact ? 116 : 180;

  const sliderPanResponder = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: () => { startZoomRef.current = latestZoomRef.current; },
    onPanResponderMove: (_, gesture) => {
      const range = max - min;
      onZoomChange(camera, startZoomRef.current + (gesture.dx / sliderWidth) * range);
    },
    onPanResponderRelease: () => setExpanded(false),
    onPanResponderTerminate: () => setExpanded(false),
  })).current;

  if (mode === 'hidden') return null;

  // Mini mode: single badge, tap cycles to next preset level.
  if (mode === 'mini') {
    const nearest = levels.reduce((b, l) =>
      Math.abs(l - currentZoom) < Math.abs(b - currentZoom) ? l : b, levels[0]);
    const nextLevel = levels[(levels.indexOf(nearest) + 1) % levels.length];
    const label = currentZoom < 1
      ? currentZoom.toFixed(1)
      : String(+(currentZoom.toFixed(1))).replace(/\.0$/, '');
    return (
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`${camera} ${label}x zoom`}
        style={styles.zoomMiniBadge}
        onPress={() => onZoomChange(camera, nextLevel)}
      >
        <Text style={styles.zoomMiniBadgeText}>{label}x</Text>
      </Pressable>
    );
  }

  return (
    <View style={[styles.zoomDial, isCompact && styles.zoomDialCompact]}>
      <View style={styles.zoomPresetRow}>
        {levels.map(level => {
          const active = Math.abs(currentZoom - level) < 0.05;
          return (
            <Pressable
              key={level}
              accessibilityRole="button"
              accessibilityLabel={`${camera} ${level}x zoom`}
              style={[styles.zoomPreset, isCompact && styles.zoomPresetCompact, active && styles.zoomPresetActive]}
              onPress={() => onZoomChange(camera, level)}
              onLongPress={() => setExpanded(true)}
              delayLongPress={260}
            >
              <Text style={[styles.zoomPresetText, isCompact && styles.zoomPresetTextCompact, active && styles.zoomPresetTextActive]}>
                {level}x
              </Text>
            </Pressable>
          );
        })}
      </View>
      {expanded ? (
        <View style={[styles.zoomSlider, { width: sliderWidth }]} {...sliderPanResponder.panHandlers}>
          <View style={styles.zoomSliderTrack}>
            <View style={[styles.zoomSliderFill, { width: `${((currentZoom - min) / (max - min)) * 100}%` }]} />
          </View>
          <Text style={styles.zoomSliderValue}>{currentZoom.toFixed(1)}x</Text>
        </View>
      ) : null}
    </View>
  );
}

function BottomBar({ cameraMode, captureMode, recording, recordingStarting, recordingStopping, saving, onShutterPress, onModeSwitch, onCaptureModeChange, isFlipped, onFlip }) {
  const disabled = recording || recordingStarting || recordingStopping;
  return (
    <>
      <View style={styles.rightPanel} pointerEvents="box-none">
        {MODE_OPTIONS.map(item => (
          <ModeButton
            key={item.mode}
            selected={cameraMode === item.mode}
            disabled={disabled}
            onPress={() => onModeSwitch(item.mode)}
            label={item.label}
            icon={item.icon}
          />
        ))}
      </View>

      <View style={styles.bottomBar} pointerEvents="box-none">
        <View style={styles.modeToggle}>
          <Pressable style={[styles.modeBtn, captureMode === 'picture' && styles.modeBtnActive]} onPress={() => onCaptureModeChange('picture')}>
            <Text style={[styles.modeBtnText, captureMode === 'picture' && styles.modeBtnTextActive]}>Photo</Text>
          </Pressable>
          <Pressable style={[styles.modeBtn, captureMode === 'video' && styles.modeBtnActive]} onPress={() => onCaptureModeChange('video')}>
            <Text style={[styles.modeBtnText, captureMode === 'video' && styles.modeBtnTextActive]}>Video</Text>
          </Pressable>
        </View>

        <Pressable
          accessibilityRole="button"
          accessibilityLabel={recording ? 'Stop' : (captureMode === 'picture' ? 'Take photo' : 'Record')}
          style={({ pressed }) => [
            styles.shutterOuter,
            pressed && styles.shutterOuterMuted,
            saving && styles.shutterOuterMuted,
            recordingStarting && styles.shutterOuterMuted,
            recordingStopping && styles.shutterOuterMuted,
            recording && styles.shutterOuterRecording,
          ]}
          onPress={onShutterPress}
        >
          <View style={[styles.shutterInner, (recording || recordingStarting) && styles.shutterInnerRecording]} />
        </Pressable>

        <Pressable
          style={[styles.flipBtn, isFlipped && styles.flipBtnActive]}
          onPress={onFlip}
          accessibilityRole="button"
          accessibilityLabel="Flip cameras"
        >
          <Text style={styles.flipBtnText}>↻</Text>
        </Pressable>
      </View>
    </>
  );
}

function ModeButton({ selected, disabled, onPress, label, icon }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      style={[styles.modeButton, selected && styles.modeButtonSelected, disabled && styles.disabledControl]}
      onPress={onPress}
    >
      <ModeIcon name={icon} selected={selected} />
    </Pressable>
  );
}

function ModeIcon({ name, selected }) {
  const tone = selected ? styles.modeIconSelected : styles.modeIcon;
  const fill = selected ? styles.modeIconFillSelected : styles.modeIconFill;

  if (name === 'back' || name === 'front') {
    return (
      <View style={[styles.cameraIconBody, tone]}>
        <View style={[styles.cameraIconLens, tone]} />
        <View style={[styles.cameraIconDot, name === 'front' && styles.cameraIconDotRight, fill]} />
      </View>
    );
  }

  if (name === 'pipSquare' || name === 'pipCircle') {
    return (
      <View style={[styles.pipIconFrame, tone]}>
        <View style={[styles.pipIconInset, name === 'pipCircle' && styles.pipIconInsetCircle, fill]} />
      </View>
    );
  }

  if (name === 'lr') {
    return (
      <View style={[styles.splitIconFrame, tone]}>
        <View style={[styles.splitIconLeft, fill]} />
        <View style={[styles.splitIconDividerVertical, tone]} />
      </View>
    );
  }

  return (
    <View style={[styles.splitIconFrame, tone]}>
      <View style={[styles.splitIconTop, fill]} />
      <View style={[styles.splitIconDividerHorizontal, tone]} />
    </View>
  );
}

function AudioLevelIndicator({ level }) {
  const barCount = 12;
  const activeCount = Math.round(level * barCount);

  return (
    <View style={styles.audioIndicator} pointerEvents="none">
      <Text style={styles.audioLabel}>Audio</Text>
      <View style={styles.audioBars}>
        {Array.from({ length: barCount }).map((_, i) => (
          <View key={i} style={[styles.audioBar, i < activeCount ? styles.audioBarActive : null]} />
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  nativeCamera: { flex: 1 },
  fallbackContainer: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 32 },
  fallbackTitle: { color: '#fff', fontSize: 28, fontWeight: '700', marginBottom: 12 },
  fallbackText: { color: 'rgba(255,255,255,0.7)', fontSize: 15, textAlign: 'center' },

  topBar: {
    position: 'absolute',
    top: INTERACTION_TOP,
    left: 12,
    right: 12,
    height: 44,
    justifyContent: 'center',
    alignItems: 'flex-start',
  },
  settingsButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(0,0,0,0.5)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  settingsIcon: { color: '#fff', fontSize: 20, fontWeight: '800', marginTop: -8 },
  settingsOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.28)',
    alignItems: 'center',
    paddingTop: INTERACTION_TOP + 54,
  },
  settingsPanel: {
    width: '84%',
    maxWidth: 360,
    borderRadius: 18,
    backgroundColor: 'rgba(0,0,0,0.74)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)',
    padding: 16,
  },
  settingsHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 },
  settingsTitle: { color: '#fff', fontSize: 16, fontWeight: '700' },
  closeButton: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  closeButtonText: { color: '#fff', fontSize: 17, fontWeight: '700' },
  settingRow: { gap: 10 },
  settingLabel: { color: 'rgba(255,255,255,0.7)', fontSize: 13, fontWeight: '600' },
  aspectOptions: { flexDirection: 'row', gap: 8 },
  aspectBtn: {
    minWidth: 62,
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.16)',
    alignItems: 'center',
  },
  aspectBtnActive: { backgroundColor: 'rgba(77,166,255,0.42)', borderColor: '#4da6ff' },
  aspectBtnText: { color: 'rgba(255,255,255,0.72)', fontSize: 13, fontWeight: '700' },
  aspectBtnTextActive: { color: '#fff' },

  rightPanel: {
    position: 'absolute',
    right: 12,
    top: 0,
    bottom: 0,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
    gap: 14,
  },
  modeButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: 'rgba(0,0,0,0.28)',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
  },
  modeButtonSelected: {
    borderColor: '#4da6ff',
    backgroundColor: 'rgba(77,166,255,0.18)',
    shadowColor: '#4da6ff',
    shadowOpacity: 0.35,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 0 },
  },
  modeIcon: { borderColor: 'rgba(255,255,255,0.58)' },
  modeIconSelected: { borderColor: '#7bb7ff' },
  modeIconFill: { backgroundColor: 'rgba(255,255,255,0.48)' },
  modeIconFillSelected: { backgroundColor: '#7bb7ff' },
  cameraIconBody: {
    width: 25,
    height: 18,
    borderRadius: 6,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  cameraIconLens: {
    width: 10,
    height: 10,
    borderRadius: 5,
    borderWidth: 2,
  },
  cameraIconDot: {
    position: 'absolute',
    left: 4,
    top: -4,
    width: 7,
    height: 7,
    borderRadius: 3.5,
  },
  cameraIconDotRight: { left: undefined, right: 4 },
  pipIconFrame: {
    width: 27,
    height: 21,
    borderRadius: 5,
    borderWidth: 2,
  },
  pipIconInset: {
    position: 'absolute',
    right: 3,
    top: 3,
    width: 9,
    height: 9,
    borderRadius: 2,
  },
  pipIconInsetCircle: { borderRadius: 4.5 },
  splitIconFrame: {
    width: 27,
    height: 21,
    borderRadius: 5,
    borderWidth: 2,
    overflow: 'hidden',
  },
  splitIconLeft: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: '50%',
  },
  splitIconTop: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    height: '50%',
  },
  splitIconDividerVertical: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: '50%',
    width: 2,
    marginLeft: -1,
    borderLeftWidth: 2,
  },
  splitIconDividerHorizontal: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: '50%',
    height: 2,
    marginTop: -1,
    borderTopWidth: 2,
  },
  disabledControl: { opacity: 0.38 },

  bottomBar: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    paddingBottom: Platform.OS === 'ios' ? 44 : 32,
    paddingTop: 16,
    paddingHorizontal: 20,
  },
  modeToggle: {
    flexDirection: 'row',
    backgroundColor: 'rgba(0,0,0,0.5)',
    borderRadius: 20,
    padding: 4,
    width: 118,
  },
  modeBtn: { flex: 1, paddingVertical: 6, alignItems: 'center', borderRadius: 16 },
  modeBtnActive: { backgroundColor: 'rgba(255,255,255,0.25)' },
  modeBtnText: { color: '#aaa', fontSize: 12, fontWeight: '600' },
  modeBtnTextActive: { color: '#fff', fontWeight: '700' },
  shutterOuter: {
    width: 72,
    height: 72,
    borderRadius: 36,
    borderWidth: 4,
    borderColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  shutterOuterMuted: { opacity: 0.5 },
  shutterOuterRecording: { borderColor: '#ff4444' },
  shutterInner: { width: 58, height: 58, borderRadius: 29, backgroundColor: '#fff' },
  shutterInnerRecording: { width: 28, height: 28, borderRadius: 6, backgroundColor: '#ff4444' },
  flipBtn: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: 'rgba(0,0,0,0.45)',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  flipBtnActive: { borderColor: '#4da6ff', backgroundColor: 'rgba(77,166,255,0.25)' },
  flipBtnText: { color: '#ccc', fontSize: 24, fontWeight: '700' },

  zoomDialOverlay: {
    position: 'absolute',
    alignItems: 'center',
  },
  singleZoomPosition: { left: 0, right: 0, bottom: Platform.OS === 'ios' ? 132 : 120 },
  splitZoomPosition: { bottom: Platform.OS === 'ios' ? 132 : 120, alignItems: 'center' },
  sxTopZoomPosition: { left: 0, right: 0 },
  sxBottomZoomPosition: { left: 0, right: 0, bottom: Platform.OS === 'ios' ? 132 : 120 },
  pipZoomPosition: { alignItems: 'center' },
  zoomDial: {
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.28)',
  },
  zoomDialCompact: { paddingHorizontal: 5, paddingVertical: 4, borderRadius: 16 },
  zoomPresetRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6 },
  zoomPreset: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(0,0,0,0.58)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.18)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  zoomPresetCompact: { width: 28, height: 28, borderRadius: 14 },
  zoomPresetActive: { backgroundColor: ZOOM_ACTIVE, borderColor: ZOOM_ACTIVE },
  zoomPresetText: { color: '#fff', fontSize: 12, fontWeight: '800' },
  zoomPresetTextCompact: { fontSize: 10 },
  zoomMiniBadge: {
    paddingHorizontal: 10,
    paddingVertical: 7,
    borderRadius: 16,
    backgroundColor: 'rgba(0,0,0,0.5)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  zoomMiniBadgeText: { color: '#fff', fontSize: 11, fontWeight: '800' },
  zoomPresetTextActive: { color: '#000' },
  zoomSlider: {
    marginTop: 8,
    paddingHorizontal: 8,
    paddingVertical: 8,
    borderRadius: 14,
    backgroundColor: 'rgba(0,0,0,0.68)',
    alignItems: 'center',
  },
  zoomSliderTrack: {
    width: '100%',
    height: 4,
    borderRadius: 2,
    backgroundColor: 'rgba(255,255,255,0.22)',
    overflow: 'hidden',
  },
  zoomSliderFill: { height: 4, borderRadius: 2, backgroundColor: ZOOM_ACTIVE },
  zoomSliderValue: { marginTop: 6, color: '#fff', fontSize: 11, fontWeight: '700' },

  dividerVertical: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    width: 1,
    alignItems: 'center',
  },
  dividerLineVertical: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    width: 1,
    backgroundColor: 'rgba(255,255,255,0.3)',
  },
  dividerHitVertical: {
    position: 'absolute',
    top: '50%',
    marginTop: -32,
    width: 56,
    height: 64,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dividerHandleVertical: {
    width: 36,
    height: 22,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.86)',
  },
  dividerHorizontal: {
    position: 'absolute',
    left: 0,
    right: 0,
    height: 1,
    alignItems: 'center',
  },
  dividerLineHorizontal: {
    position: 'absolute',
    left: 0,
    right: 0,
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.3)',
  },
  dividerHitHorizontal: {
    // Mirror the vertical handle: center the 56px hit area on the 1px line.
    // left: '50%' + marginLeft: -32 → horizontal center
    // top: -27 ≈ -(hitHeight/2 - lineHeight/2) = -(56/2 - 1/2) → vertical center on line
    position: 'absolute',
    left: '50%',
    marginLeft: -32,
    top: -27,
    width: 64,
    height: 56,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dividerHandleHorizontal: {
    width: 44,
    height: 22,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.86)',
  },
  dividerHitActive: { transform: [{ scale: 1.12 }] },
  dividerHandleActive: { backgroundColor: '#4da6ff' },
  dividerHandleText: { color: '#000', fontSize: 13, fontWeight: '900' },

  mediaBanner: {
    position: 'absolute',
    left: 16,
    right: 16,
    bottom: Platform.OS === 'ios' ? 140 : 130,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  mediaBannerText: { flex: 1, color: '#fff', fontSize: 13 },
  secondaryButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: '#fff',
  },
  secondaryButtonLabel: { color: '#000', fontSize: 13, fontWeight: '600' },
  savingOverlay: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.25)',
  },
  recordingIndicator: {
    position: 'absolute',
    top: INTERACTION_TOP,
    alignSelf: 'center',
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.6)',
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 16,
    gap: 6,
  },
  recordingDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#ff4444' },
  recordingText: { color: '#fff', fontSize: 13, fontWeight: '600' },
  audioIndicator: {
    position: 'absolute',
    top: INTERACTION_TOP,
    left: 66,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.55)',
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 12,
    gap: 6,
  },
  audioLabel: { color: '#aaa', fontSize: 11, fontWeight: '600' },
  audioBars: { flexDirection: 'row', alignItems: 'flex-end', gap: 2, height: 16 },
  audioBar: {
    width: 3,
    height: 4,
    borderRadius: 1.5,
    backgroundColor: 'rgba(255,255,255,0.2)',
  },
  audioBarActive: { backgroundColor: '#4dff4d' },

  centered: { flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 24 },
  permissionTitle: { color: '#fff', fontSize: 20, fontWeight: '700', marginBottom: 8, textAlign: 'center' },
  permissionBody: { color: 'rgba(255,255,255,0.75)', fontSize: 15, textAlign: 'center', marginBottom: 20, lineHeight: 22 },
  primaryButton: { paddingHorizontal: 18, paddingVertical: 12, borderRadius: 999, backgroundColor: '#fff' },
  primaryButtonLabel: { color: '#000', fontSize: 16, fontWeight: '600' },
});
