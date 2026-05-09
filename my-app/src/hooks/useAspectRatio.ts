import { useCallback, useEffect, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { ASPECT_RATIOS, type AspectRatio } from '../constants';

const STORAGE_KEY = 'dualcam_save_aspect';
const DEFAULT_ASPECT: AspectRatio = '9:16';

function isAspectRatio(value: unknown): value is AspectRatio {
  return typeof value === 'string' && (ASPECT_RATIOS as readonly string[]).includes(value);
}

export function useAspectRatio(): [AspectRatio, (next: AspectRatio) => Promise<void>] {
  const [aspect, setAspect] = useState<AspectRatio>(DEFAULT_ASPECT);

  useEffect(() => {
    (async () => {
      try {
        const saved = await AsyncStorage.getItem(STORAGE_KEY);
        if (isAspectRatio(saved)) setAspect(saved);
      } catch (_) {}
    })();
  }, []);

  const update = useCallback(async (next: AspectRatio) => {
    setAspect(next);
    try { await AsyncStorage.setItem(STORAGE_KEY, next); } catch (_) {}
  }, []);

  return [aspect, update];
}
