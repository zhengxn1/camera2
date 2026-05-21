import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Platform } from 'react-native';
import { getNativeModuleDiagnostics, VideoUnlockModule, type VideoUnlockProduct } from '../native';

const STOREKIT_TIMEOUT_MS = 15000;

export interface VideoUnlockApi {
  unlocked: boolean;
  loading: boolean;
  purchasing: boolean;
  productLoading: boolean;
  productError: string | null;
  product: VideoUnlockProduct | null;
  purchase: () => Promise<boolean>;
  restore: () => Promise<boolean>;
  refresh: () => Promise<boolean>;
}

function withTimeout<T>(promise: Promise<T>, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`${label}超时，请稍后再试。`));
    }, STOREKIT_TIMEOUT_MS);

    promise
      .then(resolve, reject)
      .finally(() => clearTimeout(timer));
  });
}

export function useVideoUnlock(): VideoUnlockApi {
  const [unlocked, setUnlocked] = useState(false);
  const [loading, setLoading] = useState(true);
  const [purchasing, setPurchasing] = useState(false);
  const [productLoading, setProductLoading] = useState(true);
  const [productError, setProductError] = useState<string | null>(null);
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
      const next = await withTimeout(VideoUnlockModule.isVideoUnlocked(), '刷新解锁状态');
      unlockedRef.current = next;
      setUnlocked(next);
      return next;
    } catch {
      return false;
    } finally {
      setLoading(false);
    }
  }, [moduleAvailable]);

  const restore = useCallback(async () => {
    if (!moduleAvailable || !VideoUnlockModule?.restorePurchases) {
      Alert.alert('无法恢复购买', `购买模块暂不可用。\n\n${getNativeModuleDiagnostics()}`);
      return false;
    }

    setPurchasing(true);
    try {
      const result = await withTimeout(VideoUnlockModule.restorePurchases(), '恢复购买');
      const next = !!result?.unlocked;
      unlockedRef.current = next;
      setUnlocked(next);
      Alert.alert(next ? '已恢复购买' : '未找到可恢复的购买记录');
      return next;
    } catch {
      Alert.alert('恢复购买失败', '请稍后再试。');
      return false;
    } finally {
      setPurchasing(false);
    }
  }, [moduleAvailable]);

  const purchase = useCallback(async () => {
    if (!moduleAvailable || !VideoUnlockModule?.purchaseVideoUnlock) {
      Alert.alert('无法购买', `购买模块暂不可用。\n\n${getNativeModuleDiagnostics()}`);
      return false;
    }

    if (!product) {
      Alert.alert('暂时无法购买', productError ?? '暂时无法获取价格，请稍后再试。');
      return false;
    }

    setPurchasing(true);
    try {
      const result = await VideoUnlockModule.purchaseVideoUnlock();
      const next = !!result?.unlocked;
      unlockedRef.current = next;
      setUnlocked(next);

      if (result?.pending) {
        Alert.alert('购买等待确认', '购买正在等待确认，完成后将自动解锁。');
      }

      return next;
    } catch {
      Alert.alert('购买失败', '请稍后再试。');
      return false;
    } finally {
      setPurchasing(false);
    }
  }, [moduleAvailable, product, productError]);

  useEffect(() => {
    refresh();

    if (moduleAvailable && VideoUnlockModule?.getProduct) {
      setProductLoading(true);
      setProductError(null);
      withTimeout(VideoUnlockModule.getProduct(), '获取价格')
        .then((nextProduct) => {
          setProduct(nextProduct);
          setProductError(null);
        })
        .catch(() => {
          setProduct(null);
          setProductError('暂时无法获取价格，请稍后再试。');
        })
        .finally(() => setProductLoading(false));
    } else {
      setProductLoading(false);
      setProductError('当前设备暂不支持购买。');
    }
  }, [moduleAvailable, refresh]);

  return useMemo(() => ({
    unlocked,
    loading,
    purchasing,
    productLoading,
    productError,
    product,
    purchase,
    restore,
    refresh,
  }), [loading, product, productError, productLoading, purchase, purchasing, refresh, restore, unlocked]);
}
