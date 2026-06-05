import { useCallback, useEffect, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { VIDEO_SAVE_MODES, type VideoSaveMode } from '../constants';

const STORAGE_KEY = 'dualcam_video_save_mode';
const DEFAULT_MODE: VideoSaveMode = 'combined';

function isVideoSaveMode(value: unknown): value is VideoSaveMode {
  return typeof value === 'string' && (VIDEO_SAVE_MODES as readonly string[]).includes(value);
}

export function useVideoSaveMode(): [VideoSaveMode, (next: VideoSaveMode) => Promise<void>] {
  const [mode, setMode] = useState<VideoSaveMode>(DEFAULT_MODE);

  useEffect(() => {
    (async () => {
      try {
        const saved = await AsyncStorage.getItem(STORAGE_KEY);
        if (isVideoSaveMode(saved)) setMode(saved);
      } catch (_) {}
    })();
  }, []);

  const update = useCallback(async (next: VideoSaveMode) => {
    setMode(next);
    try { await AsyncStorage.setItem(STORAGE_KEY, next); } catch (_) {}
  }, []);

  return [mode, update];
}
