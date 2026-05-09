import { useCallback, useEffect, useState } from 'react';
import { CameraPermissionModule } from '../native';

export type CameraStatus = 'loading' | 'authorized' | 'not_determined' | 'denied' | 'unavailable';

export interface CameraPermissionApi {
  status: CameraStatus;
  request: () => Promise<void>;
}

export function useCameraPermission(): CameraPermissionApi {
  const [status, setStatus] = useState<CameraStatus>('loading');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!CameraPermissionModule) {
        setStatus('unavailable');
        return;
      }
      try {
        const next = await CameraPermissionModule.getCameraAuthorizationStatus?.();
        if (cancelled) return;
        if (next === 'authorized') setStatus('authorized');
        else if (next === 'not_determined') setStatus('not_determined');
        else setStatus('denied');
      } catch (_e) {
        if (!cancelled) setStatus('unavailable');
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const request = useCallback(async () => {
    if (!CameraPermissionModule?.requestCameraPermission) return;
    try {
      const granted = await CameraPermissionModule.requestCameraPermission();
      setStatus(granted ? 'authorized' : 'denied');
    } catch (_e) {
      setStatus('denied');
    }
  }, []);

  return { status, request };
}
