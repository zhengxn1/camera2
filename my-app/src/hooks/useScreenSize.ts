import { useCallback, useState } from 'react';
import type { LayoutChangeEvent } from 'react-native';

export interface ScreenSizeApi {
  width: number;
  height: number;
  onLayout: (event: LayoutChangeEvent) => void;
}

export function useScreenSize(): ScreenSizeApi {
  const [size, setSize] = useState({ width: 0, height: 0 });

  const onLayout = useCallback((event: LayoutChangeEvent) => {
    const { width, height } = event.nativeEvent.layout;
    setSize(prev => (prev.width === width && prev.height === height ? prev : { width, height }));
  }, []);

  return { width: size.width, height: size.height, onLayout };
}
