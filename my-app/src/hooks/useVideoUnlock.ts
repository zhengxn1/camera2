import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Platform } from 'react-native';
import { getNativeModuleDiagnostics, VideoUnlockModule, type VideoUnlockProduct } from '../native';

export interface VideoUnlockApi {
  unlocked: boolean;
  loading: boolean;
  purchasing: boolean;
  product: VideoUnlockProduct | null;
  purchase: () => Promise<boolean>;
  restore: () => Promise<boolean>;
  refresh: () => Promise<boolean>;
}

export function useVideoUnlock(): VideoUnlockApi {
  const [unlocked, setUnlocked] = useState(false);
  const [loading, setLoading] = useState(true);
  const [purchasing, setPurchasing] = useState(false);
  const [product, setProduct] = useState<VideoUnlockProduct | null>(null);
  const unlockedRef = useRef(false);

  useEffect(() => {
    unlockedRef.current = unlocked;
  }, [unlocked]);

  const moduleAvailable = Platform.OS === 'ios' && !!VideoUnlockModule;

  const refresh = useCallback(async () => {
    console.log('[VideoUnlock] refresh entitlement start', { moduleAvailable });
    if (!moduleAvailable || !VideoUnlockModule?.isVideoUnlocked) {
      console.warn('[VideoUnlock] refresh skipped; native module unavailable');
      setLoading(false);
      return false;
    }

    try {
      const next = await VideoUnlockModule.isVideoUnlocked();
      console.log('[VideoUnlock] refresh entitlement result', { unlocked: next });
      unlockedRef.current = next;
      setUnlocked(next);
      return next;
    } catch (e) {
      console.warn('[VideoUnlock] Entitlement check failed', e);
      return false;
    } finally {
      setLoading(false);
    }
  }, [moduleAvailable]);

  const restore = useCallback(async () => {
    console.log('[VideoUnlock] restore start', { moduleAvailable });
    if (!moduleAvailable || !VideoUnlockModule?.restorePurchases) {
      console.warn('[VideoUnlock] restore skipped; native module unavailable');
      Alert.alert('Restore unavailable', `Native purchase module is unavailable.\n\n${getNativeModuleDiagnostics()}`);
      return false;
    }

    setPurchasing(true);
    try {
      const result = await VideoUnlockModule.restorePurchases();
      console.log('[VideoUnlock] restore result', result);
      const next = !!result?.unlocked;
      unlockedRef.current = next;
      setUnlocked(next);
      Alert.alert(next ? 'Restored' : 'No purchase found', next ? 'Video recording is unlocked.' : 'No previous video unlock purchase was found for this Apple ID.');
      return next;
    } catch (e: any) {
      Alert.alert('Restore failed', e?.message ?? String(e));
      return false;
    } finally {
      console.log('[VideoUnlock] restore finished');
      setPurchasing(false);
    }
  }, [moduleAvailable]);

  const purchase = useCallback(async () => {
    console.log('[VideoUnlock] purchase start', { moduleAvailable, hasProduct: !!product });
    if (!moduleAvailable || !VideoUnlockModule?.purchaseVideoUnlock) {
      console.warn('[VideoUnlock] purchase skipped; native module unavailable');
      Alert.alert('Purchase unavailable', `Native purchase module is unavailable.\n\n${getNativeModuleDiagnostics()}`);
      return false;
    }

    setPurchasing(true);
    try {
      const result = await VideoUnlockModule.purchaseVideoUnlock();
      console.log('[VideoUnlock] purchase result', result);
      const next = !!result?.unlocked;
      unlockedRef.current = next;
      setUnlocked(next);

      if (result?.pending) {
        Alert.alert('Purchase pending', 'The purchase is waiting for approval. Video recording will unlock after Apple completes the transaction.');
      }

      return next;
    } catch (e: any) {
      Alert.alert('Purchase failed', e?.message ?? String(e));
      return false;
    } finally {
      console.log('[VideoUnlock] purchase finished');
      setPurchasing(false);
    }
  }, [moduleAvailable, product]);

  useEffect(() => {
    refresh();

    if (moduleAvailable && VideoUnlockModule?.getProduct) {
      console.log('[VideoUnlock] product load start');
      VideoUnlockModule.getProduct()
        .then((nextProduct) => {
          console.log('[VideoUnlock] product load result', nextProduct);
          setProduct(nextProduct);
        })
        .catch((e) => console.warn('[VideoUnlock] Product load failed', e));
    }
  }, [moduleAvailable, refresh]);

  return useMemo(() => ({
    unlocked,
    loading,
    purchasing,
    product,
    purchase,
    restore,
    refresh,
  }), [loading, product, purchase, purchasing, refresh, restore, unlocked]);
}
