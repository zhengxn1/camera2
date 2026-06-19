import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert } from 'react-native';
import * as MediaLibrary from 'expo-media-library';
import type { CaptureMode } from '../constants';
import { DualCameraModule, eventEmitter } from '../native';

export type SaveFormat = 'merged' | 'segments';

export interface UseDualCameraSessionOptions {
  ensureMedia: () => Promise<boolean>;
  saveFormat?: SaveFormat;
}

export interface DualCameraSessionApi {
  saving: boolean;
  recording: boolean;
  recordingStarting: boolean;
  recordingStopping: boolean;
  interactionDisabled: boolean;
  takePhoto: () => Promise<void>;
  startRecording: () => void;
  stopRecording: () => void;
  handleShutterPress: (captureMode: CaptureMode) => void;
}

type NativeSaveEvent = {
  uri?: string;
  uris?: Partial<Record<'combined' | 'front' | 'back', string>>;
};

function collectSaveUris(event: NativeSaveEvent, saveFormat: SaveFormat): string[] {
  const ordered = saveFormat === 'segments'
    ? [
        event.uris?.combined,
        event.uris?.front,
        event.uris?.back,
        event.uri,
      ]
    : [
        event.uris?.combined,
        event.uri,
      ];

  const valid = ordered.filter((uri): uri is string => typeof uri === 'string' && uri.length > 0);

  return Array.from(new Set(valid));
}

/**
 * Owns the photo / recording lifecycle: capture commands, native event
 * subscriptions, and the resulting status flags. Uses a latest-ref for the
 * `ensureMedia` callback so events stay subscribed across permission changes.
 */
export function useDualCameraSession({ ensureMedia, saveFormat = 'merged' }: UseDualCameraSessionOptions): DualCameraSessionApi {
  const [saving, setSaving] = useState(false);
  const [recordingStarting, setRecordingStarting] = useState(false);
  const [recording, setRecording] = useState(false);
  const [recordingStopping, setRecordingStopping] = useState(false);
  const stopRequestedRef = useRef(false);

  const ensureMediaRef = useRef(ensureMedia);
  ensureMediaRef.current = ensureMedia;
  const saveFormatRef = useRef<SaveFormat>(saveFormat);
  saveFormatRef.current = saveFormat;

  useEffect(() => {
    if (!eventEmitter) return undefined;

    const subPhotoSaved = eventEmitter.addListener('onPhotoSaved', async (event: NativeSaveEvent) => {
      setSaving(false);
      try {
        const ok = await ensureMediaRef.current();
        if (ok) {
          const uris = collectSaveUris(event, saveFormatRef.current);
          for (const uri of uris) {
            await MediaLibrary.saveToLibraryAsync(uri);
          }
        }
      } catch (e: any) {
        Alert.alert('保存失败', e?.message ?? String(e));
      }
    });

    const subPhotoError = eventEmitter.addListener('onPhotoError', (event: { error?: string }) => {
      setSaving(false);
      Alert.alert('拍照失败', event.error ?? '未知错误');
    });

    const subRecordingStarted = eventEmitter.addListener('onRecordingStarted', () => {
      setRecordingStarting(false);
      setRecording(true);
      if (!stopRequestedRef.current) setRecordingStopping(false);
    });

    const subRecordingFinished = eventEmitter.addListener('onRecordingFinished', async (event: NativeSaveEvent) => {
      stopRequestedRef.current = false;
      setRecordingStarting(false);
      setRecording(false);
      setRecordingStopping(false);
      try {
        const ok = await ensureMediaRef.current();
        if (ok) {
          const uris = collectSaveUris(event, saveFormatRef.current);
          for (const uri of uris) {
            await MediaLibrary.saveToLibraryAsync(uri);
          }
        }
      } catch (e: any) {
        Alert.alert('保存失败', e?.message ?? String(e));
      }
    });

    const subRecordingError = eventEmitter.addListener('onRecordingError', (event: { error?: string }) => {
      stopRequestedRef.current = false;
      setRecordingStarting(false);
      setRecording(false);
      setRecordingStopping(false);
      Alert.alert('录制失败', event.error ?? '未知错误');
    });

    const subSessionError = eventEmitter.addListener('onSessionError', (event: { error?: string }) => {
      stopRequestedRef.current = false;
      setSaving(false);
      setRecordingStarting(false);
      setRecording(false);
      setRecordingStopping(false);
      Alert.alert('相机错误', event.error ?? '相机会话异常。');
    });

    return () => {
      subPhotoSaved.remove();
      subPhotoError.remove();
      subRecordingStarted.remove();
      subRecordingFinished.remove();
      subRecordingError.remove();
      subSessionError.remove();
    };
  }, []);

  const takePhoto = useCallback(async () => {
    if (!DualCameraModule?.takePhoto) {
      Alert.alert('无法拍照', '原生相机模块暂不可用。');
      return;
    }
    const ok = await ensureMediaRef.current();
    if (!ok) return;
    setSaving(true);
    DualCameraModule.takePhoto();
  }, []);

  const startRecording = useCallback(() => {
    if (!DualCameraModule?.startRecording) {
      Alert.alert('无法录制', '原生相机模块暂不可用。');
      return;
    }
    stopRequestedRef.current = false;
    setRecordingStarting(true);
    setRecordingStopping(false);
    DualCameraModule.startRecording();
  }, []);

  const stopRecording = useCallback(() => {
    if (recordingStopping || !DualCameraModule?.stopRecording) return;
    stopRequestedRef.current = true;
    setRecordingStopping(true);
    DualCameraModule.stopRecording();
  }, [recordingStopping]);

  const handleShutterPress = useCallback((captureMode: CaptureMode) => {
    if (recordingStopping) return;
    if (recording || recordingStarting) stopRecording();
    else if (captureMode === 'picture') takePhoto();
    else startRecording();
  }, [recording, recordingStarting, recordingStopping, takePhoto, startRecording, stopRecording]);

  const interactionDisabled = recording || recordingStarting || recordingStopping;

  return {
    saving,
    recording,
    recordingStarting,
    recordingStopping,
    interactionDisabled,
    takePhoto,
    startRecording,
    stopRecording,
    handleShutterPress,
  };
}
