import { useCallback, useState } from 'react';
import * as MediaLibrary from 'expo-media-library';

export interface MediaPermissionApi {
  granted: boolean;
  blocked: boolean;
  request: () => Promise<void>;
  dismissBlocked: () => void;
  ensure: () => Promise<boolean>;
}

export function useMediaPermission(): MediaPermissionApi {
  const [permission, requestPermission] = MediaLibrary.usePermissions({
    writeOnly: true,
    granularPermissions: ['photo'],
  });
  const [blocked, setBlocked] = useState(false);

  const granted = !!permission?.granted;

  const request = useCallback(async () => {
    const result = await requestPermission();
    setBlocked(!result.granted);
  }, [requestPermission]);

  const dismissBlocked = useCallback(() => {
    setBlocked(false);
  }, []);

  const ensure = useCallback(async () => {
    if (granted) return true;
    const result = await requestPermission();
    setBlocked(!result.granted);
    if (result.granted) return true;
    return false;
  }, [granted, requestPermission]);

  return { granted, blocked, request, dismissBlocked, ensure };
}
