import { useCallback, useEffect, useRef, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

const STORAGE_KEY = 'dualcam_front_beauty_enabled';
const SMOOTH_STORAGE_KEY = 'dualcam_front_beauty_smooth';
const WHITEN_STORAGE_KEY = 'dualcam_front_beauty_whiten';
const EVEN_STORAGE_KEY = 'dualcam_front_beauty_even';
const PLUMP_STORAGE_KEY = 'dualcam_front_beauty_plump';
const LEGACY_TONE_STORAGE_KEY = 'dualcam_front_beauty_tone';
const DEFAULT_ENABLED = true;
const DEFAULT_SETTINGS: FrontBeautySettings = {
  smooth: 60,
  whiten: 45,
  even: 50,
  plump: 55,
};

export interface FrontBeautySettings {
  smooth: number;
  whiten: number;
  even: number;
  plump: number;
}

function parseSavedBoolean(value: string | null): boolean | null {
  if (value === 'true') return true;
  if (value === 'false') return false;
  return null;
}

function clampBeautyValue(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value)));
}

function parseSavedBeautyValue(value: string | null): number | null {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return clampBeautyValue(parsed);
}

export function useFrontBeautyEnabled(): [
  boolean,
  (next: boolean) => Promise<void>,
  FrontBeautySettings,
  (next: Partial<FrontBeautySettings>) => Promise<void>,
] {
  const [enabled, setEnabled] = useState(DEFAULT_ENABLED);
  const [settings, setSettings] = useState<FrontBeautySettings>(DEFAULT_SETTINGS);
  const persistTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const saved = parseSavedBoolean(await AsyncStorage.getItem(STORAGE_KEY));
        if (saved !== null) setEnabled(saved);
        const smooth = parseSavedBeautyValue(await AsyncStorage.getItem(SMOOTH_STORAGE_KEY));
        const whiten = parseSavedBeautyValue(await AsyncStorage.getItem(WHITEN_STORAGE_KEY));
        const even = parseSavedBeautyValue(await AsyncStorage.getItem(EVEN_STORAGE_KEY));
        const plump =
          parseSavedBeautyValue(await AsyncStorage.getItem(PLUMP_STORAGE_KEY)) ??
          parseSavedBeautyValue(await AsyncStorage.getItem(LEGACY_TONE_STORAGE_KEY));
        setSettings(current => ({
          smooth: smooth ?? current.smooth,
          whiten: whiten ?? current.whiten,
          even: even ?? current.even,
          plump: plump ?? current.plump,
        }));
      } catch (_) {}
    })();
  }, []);

  useEffect(() => {
    return () => {
      if (persistTimerRef.current) {
        clearTimeout(persistTimerRef.current);
      }
    };
  }, []);

  const update = useCallback(async (next: boolean) => {
    setEnabled(next);
    try { await AsyncStorage.setItem(STORAGE_KEY, String(next)); } catch (_) {}
  }, []);

  const persistSettings = useCallback((next: FrontBeautySettings) => {
    if (persistTimerRef.current) {
      clearTimeout(persistTimerRef.current);
    }
    persistTimerRef.current = setTimeout(() => {
      persistTimerRef.current = null;
      void Promise.all([
        AsyncStorage.setItem(SMOOTH_STORAGE_KEY, String(next.smooth)),
        AsyncStorage.setItem(WHITEN_STORAGE_KEY, String(next.whiten)),
        AsyncStorage.setItem(EVEN_STORAGE_KEY, String(next.even)),
        AsyncStorage.setItem(PLUMP_STORAGE_KEY, String(next.plump)),
      ]).catch(() => {});
    }, 240);
  }, []);

  const updateSettings = useCallback(async (next: Partial<FrontBeautySettings>) => {
    let clamped: FrontBeautySettings | null = null;
    setSettings(current => {
      const merged = {
        ...current,
        ...next,
      };
      clamped = {
        smooth: clampBeautyValue(merged.smooth),
        whiten: clampBeautyValue(merged.whiten),
        even: clampBeautyValue(merged.even),
        plump: clampBeautyValue(merged.plump),
      };
      return clamped;
    });
    if (clamped) {
      persistSettings(clamped);
    }
  }, [persistSettings]);

  return [enabled, update, settings, updateSettings];
}
