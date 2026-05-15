import { memo, type ReactNode, useRef, useState } from 'react';
import { PanResponder, Pressable, Text, View, type StyleProp, type ViewStyle } from 'react-native';
import { BACK_ZOOM_LEVELS, type CameraSide, FRONT_ZOOM_LEVELS } from '../constants';
import { styles } from '../styles';

interface ZoomDialOverlayProps {
  positionStyle: StyleProp<ViewStyle>;
  children: ReactNode;
}

function ZoomDialOverlayImpl({ positionStyle, children }: ZoomDialOverlayProps) {
  return (
    <View style={[styles.zoomDialOverlay, positionStyle]} pointerEvents="box-none">
      {children}
    </View>
  );
}

export const ZoomDialOverlay = memo(ZoomDialOverlayImpl);
ZoomDialOverlay.displayName = 'ZoomDialOverlay';

/**
 * Adaptive zoom control.
 *
 * Display modes chosen from availableWidth (px):
 *   normal  - full-size 36 px buttons (default when no constraint)
 *   narrow  - two full-size buttons: active preset + next preset cycle
 *   hidden  - nothing rendered (< 44 px)
 */
interface ZoomDialProps {
  camera: CameraSide;
  currentZoom: number;
  onZoomChange: (camera: CameraSide, level: number) => void;
  availableWidth?: number;
}

function ZoomDialImpl({ camera, currentZoom, onZoomChange, availableWidth = Infinity }: ZoomDialProps) {
  const [expanded, setExpanded] = useState(false);
  const latestZoomRef = useRef(currentZoom);
  const startZoomRef = useRef(currentZoom);
  const levels = camera === 'back' ? BACK_ZOOM_LEVELS : FRONT_ZOOM_LEVELS;
  const min = camera === 'back' ? 0.5 : 1;
  const max = camera === 'back' ? 5 : 2;
  latestZoomRef.current = currentZoom;

  const formatZoomLabel = (level: number) => (
    level < 1 ? level.toFixed(1) : String(+(level.toFixed(1))).replace(/\.0$/, '')
  );
  const nearestLevel = levels.reduce((best, level) =>
    Math.abs(level - currentZoom) < Math.abs(best - currentZoom) ? level : best, levels[0]);
  const nextLevel = levels[(levels.indexOf(nearestLevel) + 1) % levels.length];

  // Pixel width required for the full button row (buttons + gaps + horizontal padding).
  const n = levels.length;
  const normalMinW  = n * 36 + (n - 1) * 6 + 16;  // e.g. back=220, front=94

  const mode: 'normal' | 'narrow' | 'hidden' =
    availableWidth >= normalMinW  ? 'normal'  :
    availableWidth >= 44          ? 'narrow'  : 'hidden';

  const sliderWidth = 180;

  const sliderPanResponder = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: () => { startZoomRef.current = latestZoomRef.current; },
    onPanResponderMove: (_, gesture) => {
      const range = max - min;
      onZoomChange(camera, startZoomRef.current + (gesture.dx / sliderWidth) * range);
    },
    onPanResponderRelease: () => setExpanded(false),
    onPanResponderTerminate: () => setExpanded(false),
  })).current;

  if (mode === 'hidden') return null;

  if (mode === 'narrow') {
    return (
      <View style={styles.zoomDial}>
        <View style={styles.zoomPresetRow}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`${camera} ${formatZoomLabel(nearestLevel)}x zoom selected`}
            style={[styles.zoomPreset, styles.zoomPresetActive]}
            onPress={() => onZoomChange(camera, nearestLevel)}
          >
            <Text style={[styles.zoomPresetText, styles.zoomPresetTextActive]}>
              {formatZoomLabel(nearestLevel)}x
            </Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`${camera} switch to ${formatZoomLabel(nextLevel)}x zoom`}
            style={styles.zoomPreset}
            onPress={() => onZoomChange(camera, nextLevel)}
          >
            <Text style={styles.zoomPresetText}>{formatZoomLabel(nextLevel)}x</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  return (
    <View style={styles.zoomDial}>
      <View style={styles.zoomPresetRow}>
        {levels.map(level => {
          const active = Math.abs(currentZoom - level) < 0.05;
          return (
            <Pressable
              key={level}
              accessibilityRole="button"
              accessibilityLabel={`${camera} ${level}x zoom`}
              style={[styles.zoomPreset, active && styles.zoomPresetActive]}
              onPress={() => onZoomChange(camera, level)}
              onLongPress={() => setExpanded(true)}
              delayLongPress={260}
            >
              <Text style={[styles.zoomPresetText, active && styles.zoomPresetTextActive]}>
                {formatZoomLabel(level)}x
              </Text>
            </Pressable>
          );
        })}
      </View>
      {expanded ? (
        <View style={[styles.zoomSlider, { width: sliderWidth }]} {...sliderPanResponder.panHandlers}>
          <View style={styles.zoomSliderTrack}>
            <View style={[styles.zoomSliderFill, { width: `${((currentZoom - min) / (max - min)) * 100}%` }]} />
          </View>
          <Text style={styles.zoomSliderValue}>{currentZoom.toFixed(1)}x</Text>
        </View>
      ) : null}
    </View>
  );
}

export const ZoomDial = memo(ZoomDialImpl);
ZoomDial.displayName = 'ZoomDial';
