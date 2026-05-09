import { useCallback, useEffect, useState } from 'react';
import { eventEmitter } from '../native';
import type { PipPosition } from '../components/CameraControlsOverlay';

const DEFAULT_PIP_POSITION: PipPosition = { x: 0.85, y: 0.80 };
const DEFAULT_PIP_SIZE = 0.28;

export interface DualCameraViewApi {
  audioLevel: number;
  pipPosition: PipPosition;
  pipSize: number;
  resetPip: () => void;
}

/**
 * Owns the high-frequency view-only state pushed from the native side
 * (audio metering + PIP gesture feedback). Isolating this state keeps
 * its frequent setState calls from re-rendering the rest of the app.
 */
export function useDualCameraView(): DualCameraViewApi {
  const [audioLevel, setAudioLevel] = useState(0);
  const [pipPosition, setPipPosition] = useState<PipPosition>(DEFAULT_PIP_POSITION);
  const [pipSize, setPipSize] = useState(DEFAULT_PIP_SIZE);

  useEffect(() => {
    if (!eventEmitter) return undefined;

    const subAudio = eventEmitter.addListener('onAudioLevel', (event: { average?: number }) => {
      setAudioLevel(event.average ?? 0);
    });
    const subPipPos = eventEmitter.addListener('onPipPositionChanged', (event: { x?: number; y?: number }) => {
      setPipPosition({
        x: event.x ?? DEFAULT_PIP_POSITION.x,
        y: event.y ?? DEFAULT_PIP_POSITION.y,
      });
    });
    const subPipSize = eventEmitter.addListener('onPipSizeChanged', (event: { size?: number }) => {
      setPipSize(event.size ?? DEFAULT_PIP_SIZE);
    });

    return () => {
      subAudio.remove();
      subPipPos.remove();
      subPipSize.remove();
    };
  }, []);

  const resetPip = useCallback(() => {
    setPipPosition(DEFAULT_PIP_POSITION);
    setPipSize(DEFAULT_PIP_SIZE);
  }, []);

  return { audioLevel, pipPosition, pipSize, resetPip };
}
