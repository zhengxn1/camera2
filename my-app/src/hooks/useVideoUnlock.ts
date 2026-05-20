import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Platform } from 'react-native';
import { VideoUnlockModule, type VideoUnlockProduct } from '../native';

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
    if (!moduleAvailable || !VideoUnlockModule?.isVideoUnlocked) {
      setLoading(false);
      return false;
    }

    try {
      const next = await VideoUnlockModule.isVideoUnlocked();
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
    if (!moduleAvailable || !VideoUnlockModule?.restorePurchases) {
      Alert.alert('Restore unavailable', 'Purchases are only available on iOS builds from App Store or TestFlight.');
      return false;
    }

    setPurchasing(true);
    try {
      const result = await VideoUnlockModule.restorePurchases();
      const next = !!result?.unlocked;
      unlockedRef.current = next;
      setUnlocked(next);
      Alert.alert(next ? 'Restored' : 'No purchase found', next ? 'Video recording is unlocked.' : 'No previous video unlock purchase was found for this Apple ID.');
      return next;
    } catch (e: any) {
      Alert.alert('Restore failed', e?.message ?? String(e));
      return false;
    } finally {
      setPurchasing(false);
    }
  }, [moduleAvailable]);

  const purchase = useCallback(async () => {
    if (!moduleAvailable || !VideoUnlockModule?.purchaseVideoUnlock) {
      Alert.alert('Purchase unavailable', 'Purchases are only available on iOS builds from App Store or TestFlight.');
      return false;
    }

    setPurchasing(true);
    try {
      const result = await VideoUnlockModule.purchaseVideoUnlock();
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
      setPurchasing(false);
    }
  }, [moduleAvailable]);

  useEffect(() => {
    refresh();

    if (moduleAvailable && VideoUnlockModule?.getProduct) {
      VideoUnlockModule.getProduct()
        .then(setProduct)
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
