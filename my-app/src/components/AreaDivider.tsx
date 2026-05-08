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
  const startRatioRef = useRef(ratio);
  const limitMin = 0.2;
  const limitMax = 0.8;
  latestRatioRef.current = ratio;

  const panResponder = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: () => {
      startRatioRef.current = latestRatioRef.current;
      setActive(true);
    },
    onPanResponderMove: (_, gesture) => {
      const delta = mode === 'lr' ? gesture.dx / screenWidth : gesture.dy / screenHeight;
      onRatioChange(clamp(startRatioRef.current + delta, limitMin, limitMax));
    },
    onPanResponderRelease: (_, gesture) => {
      const delta = mode === 'lr' ? gesture.dx / screenWidth : gesture.dy / screenHeight;
      const raw = clamp(startRatioRef.current + delta, limitMin, limitMax);
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
