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
 *   compact - small 28 px buttons (medium columns / PIP overlay)
 *   mini    - single badge showing current zoom; tap cycles presets (very narrow columns)
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

  // Pixel width required for each mode's button row (buttons + gaps + horizontal padding).
  const n = levels.length;
  const normalMinW  = n * 36 + (n - 1) * 6 + 16;  // e.g. back=220, front=94
  const compactMinW = n * 28 + (n - 1) * 4 + 10;  // e.g. back=166, front=74

  const mode: 'normal' | 'compact' | 'mini' | 'hidden' =
    availableWidth >= normalMinW  ? 'normal'  :
    availableWidth >= compactMinW ? 'compact' :
    availableWidth >= 44          ? 'mini'    : 'hidden';

  const isCompact = mode === 'compact';
  const sliderWidth = isCompact ? 116 : 180;

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

  // Mini mode: single badge, tap cycles to next preset level.
  if (mode === 'mini') {
    const nearest = levels.reduce((b, l) =>
      Math.abs(l - currentZoom) < Math.abs(b - currentZoom) ? l : b, levels[0]);
    const nextLevel = levels[(levels.indexOf(nearest) + 1) % levels.length];
    const label = currentZoom < 1
      ? currentZoom.toFixed(1)
      : String(+(currentZoom.toFixed(1))).replace(/\.0$/, '');
    return (
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`${camera} ${label}x zoom`}
        style={styles.zoomMiniBadge}
        onPress={() => onZoomChange(camera, nextLevel)}
      >
        <Text style={styles.zoomMiniBadgeText}>{label}x</Text>
      </Pressable>
    );
  }

  return (
    <View style={[styles.zoomDial, isCompact && styles.zoomDialCompact]}>
      <View style={styles.zoomPresetRow}>
        {levels.map(level => {
          const active = Math.abs(currentZoom - level) < 0.05;
          return (
            <Pressable
              key={level}
              accessibilityRole="button"
              accessibilityLabel={`${camera} ${level}x zoom`}
              style={[styles.zoomPreset, isCompact && styles.zoomPresetCompact, active && styles.zoomPresetActive]}
              onPress={() => onZoomChange(camera, level)}
              onLongPress={() => setExpanded(true)}
              delayLongPress={260}
            >
              <Text style={[styles.zoomPresetText, isCompact && styles.zoomPresetTextCompact, active && styles.zoomPresetTextActive]}>
                {level}x
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
