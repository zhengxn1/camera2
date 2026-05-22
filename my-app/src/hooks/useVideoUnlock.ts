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
  refreshProduct: () => Promise<boolean>;
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
  const productRequestRef = useRef(0);
  const purchasingRef = useRef(false);

  useEffect(() => {
    unlockedRef.current = unlocked;
  }, [unlocked]);

  const moduleAvailable = Platform.OS === 'ios' && !!VideoUnlockModule;

  const refreshProduct = useCallback(async () => {
    const requestId = productRequestRef.current + 1;
    productRequestRef.current = requestId;

    if (!moduleAvailable || !VideoUnlockModule?.getProduct) {
      setProductLoading(false);
      setProduct(null);
      setProductError('当前设备暂不支持购买。');
      return false;
    }

    setProductLoading(true);
    setProduct(null);
    setProductError(null);
    try {
      const nextProduct = await withTimeout(VideoUnlockModule.getProduct(), '获取价格');
      if (productRequestRef.current !== requestId) return false;
      setProduct(nextProduct);
      setProductError(null);
      return true;
    } catch {
      if (productRequestRef.current !== requestId) return false;
      setProduct(null);
      setProductError('暂时无法获取价格，请稍后再试。');
      return false;
    } finally {
      if (productRequestRef.current === requestId) {
        setProductLoading(false);
      }
    }
  }, [moduleAvailable]);

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

    if (purchasingRef.current) {
      return false;
    }

    purchasingRef.current = true;
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
      purchasingRef.current = false;
      setPurchasing(false);
    }
  }, [moduleAvailable]);

  const purchase = useCallback(async () => {
    if (!moduleAvailable || !VideoUnlockModule?.purchaseVideoUnlock) {
      Alert.alert('无法购买', `购买模块暂不可用。\n\n${getNativeModuleDiagnostics()}`);
      return false;
    }

    if (purchasingRef.current) {
      return false;
    }

    if (unlockedRef.current) {
      return true;
    }

    if (productLoading || !product) {
      Alert.alert('暂时无法购买', productError ?? '暂时无法获取价格，请稍后再试。');
      return false;
    }

    purchasingRef.current = true;
    setPurchasing(true);
    try {
      const result = await VideoUnlockModule.purchaseVideoUnlock(product.id);
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
      purchasingRef.current = false;
      setPurchasing(false);
    }
  }, [moduleAvailable, product, productError, productLoading]);

  useEffect(() => {
    refresh();
    refreshProduct();
  }, [refresh, refreshProduct]);

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
    refreshProduct,
  }), [loading, product, productError, productLoading, purchase, purchasing, refresh, refreshProduct, restore, unlocked]);
}
