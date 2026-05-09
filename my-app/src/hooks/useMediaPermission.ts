import { useCallback } from 'react';
import { Alert } from 'react-native';
import * as MediaLibrary from 'expo-media-library';

export interface MediaPermissionApi {
  granted: boolean;
  request: () => Promise<void>;
  ensure: () => Promise<boolean>;
}

export function useMediaPermission(): MediaPermissionApi {
  const [permission, requestPermission] = MediaLibrary.usePermissions({
    writeOnly: true,
    granularPermissions: ['photo'],
  });

  const granted = !!permission?.granted;

  const request = useCallback(async () => {
    await requestPermission();
  }, [requestPermission]);

  const ensure = useCallback(async () => {
    if (granted) return true;
    const result = await requestPermission();
    if (result.granted) return true;
    Alert.alert(
      'Media permission required',
      'Saving photos and videos requires photo library access.',
    );
    return false;
  }, [granted, requestPermission]);

  return { granted, request, ensure };
}
