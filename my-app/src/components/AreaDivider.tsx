import { memo, useRef, useState } from 'react';
import { PanResponder, Text, View } from 'react-native';
import { SNAP_POINTS } from '../constants';
import { styles } from '../styles';
import { clamp } from '../utils';

export type DividerMode = 'lr' | 'sx';

interface AreaDividerProps {
  mode: DividerMode;
  ratio: number;
  onRatioChange: (ratio: number) => void;
  screenWidth: number;
  screenHeight: number;
}

function AreaDividerImpl({ mode, ratio, onRatioChange, screenWidth, screenHeight }: AreaDividerProps) {
  const [active, setActive] = useState(false);
  const latestRatioRef = useRef(ratio);
  const modeRef = useRef(mode);
  const screenWidthRef = useRef(screenWidth);
  const screenHeightRef = useRef(screenHeight);
  const limitMin = 0.2;
  const limitMax = 0.8;
  latestRatioRef.current = ratio;
  modeRef.current = mode;
  screenWidthRef.current = screenWidth;
  screenHeightRef.current = screenHeight;

  const ratioFromGesture = (gesture: { moveX: number; moveY: number; dx: number; dy: number }) => {
    if (modeRef.current === 'lr') {
      const width = Math.max(1, screenWidthRef.current);
      const position = Number.isFinite(gesture.moveX) && gesture.moveX > 0
        ? gesture.moveX
        : latestRatioRef.current * width + gesture.dx;
      return clamp(position / width, limitMin, limitMax);
    }

    const height = Math.max(1, screenHeightRef.current);
    const position = Number.isFinite(gesture.moveY) && gesture.moveY > 0
      ? gesture.moveY
      : latestRatioRef.current * height + gesture.dy;
    return clamp(position / height, limitMin, limitMax);
  };

  const panResponder = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: () => {
      setActive(true);
    },
    onPanResponderMove: (_, gesture) => {
      onRatioChange(ratioFromGesture(gesture));
    },
    onPanResponderRelease: (_, gesture) => {
      const raw = ratioFromGesture(gesture);
      const nearest = SNAP_POINTS.reduce((best, point) => (
        Math.abs(point - raw) < Math.abs(best - raw) ? point : best
      ), raw);
      onRatioChange(Math.abs(nearest - raw) <= 0.05 ? nearest : raw);
      setActive(false);
    },
    onPanResponderTerminate: () => setActive(false),
  })).current;

  if (mode === 'lr') {
    return (
      <View style={[styles.dividerVertical, { left: `${ratio * 100}%` }]} pointerEvents="box-none">
        <View style={styles.dividerLineVertical} />
        <View {...panResponder.panHandlers} style={[styles.dividerHitVertical, active && styles.dividerHitActive]}>
          <View style={[styles.dividerHandleVertical, active && styles.dividerHandleActive]}>
            <Text style={styles.dividerHandleText}>‹ ›</Text>
          </View>
        </View>
      </View>
    );
  }

  return (
    <View style={[styles.dividerHorizontal, { top: `${ratio * 100}%` }]} pointerEvents="box-none">
      <View style={styles.dividerLineHorizontal} />
      <View {...panResponder.panHandlers} style={[styles.dividerHitHorizontal, active && styles.dividerHitActive]}>
        <View style={[styles.dividerHandleHorizontal, active && styles.dividerHandleActive]}>
          <Text style={styles.dividerHandleText}>⌃⌄</Text>
        </View>
      </View>
    </View>
  );
}

export const AreaDivider = memo(AreaDividerImpl);
AreaDivider.displayName = 'AreaDivider';
