import { memo, type ReactNode } from 'react';
import { Pressable, Text, View, type StyleProp, type ViewStyle } from 'react-native';
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

interface ZoomDialProps {
  camera: CameraSide;
  currentZoom: number;
  onZoomChange: (camera: CameraSide, level: number) => void;
  compact?: boolean;
}

function formatZoomLabel(level: number): string {
  return level < 1 ? level.toFixed(1) : String(+(level.toFixed(1))).replace(/\.0$/, '');
}

function ZoomDialImpl({ camera, currentZoom, onZoomChange, compact = false }: ZoomDialProps) {
  const levels = camera === 'back' ? BACK_ZOOM_LEVELS : FRONT_ZOOM_LEVELS;
  const nearestLevel = levels.reduce((best, level) =>
    Math.abs(level - currentZoom) < Math.abs(best - currentZoom) ? level : best, levels[0]);
  const nextLevel = levels[(levels.indexOf(nearestLevel) + 1) % levels.length];

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`${camera} ${formatZoomLabel(nearestLevel)}x zoom`}
      style={[styles.zoomPill, compact && styles.zoomPillCompact]}
      onPress={() => onZoomChange(camera, nextLevel)}
    >
      <Text style={[styles.zoomPillText, compact && styles.zoomPillTextCompact]}>
        {formatZoomLabel(nearestLevel)}x
      </Text>
    </Pressable>
  );
}

export const ZoomDial = memo(ZoomDialImpl);
ZoomDial.displayName = 'ZoomDial';
