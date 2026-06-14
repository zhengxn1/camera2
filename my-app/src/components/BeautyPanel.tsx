import { memo, useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { styles } from '../styles';
import { clamp } from '../utils';

export type BeautyKey = 'natural' | 'smooth' | 'brighten' | 'tone' | 'sharpness';

export interface BeautySettings {
  natural: number;
  smooth: number;
  brighten: number;
  tone: number;
  sharpness: number;
}

export const DEFAULT_BEAUTY_SETTINGS: BeautySettings = {
  natural: 0,
  smooth: 0,
  brighten: 0,
  tone: 0,
  sharpness: 0,
};

const BEAUTY_VALUE_STEP = 2;

const BEAUTY_ITEMS: Array<{ key: BeautyKey; label: string }> = [
  { key: 'natural', label: '自然' },
  { key: 'smooth', label: '磨皮' },
  { key: 'brighten', label: '提亮' },
  { key: 'tone', label: '肤色' },
  { key: 'sharpness', label: '清晰' },
];

interface BeautyPanelProps {
  visible: boolean;
  settings: BeautySettings;
  disabled: boolean;
  available: boolean;
  onChange: (settings: BeautySettings) => void;
  onClose: () => void;
}

function valueForKey(settings: BeautySettings, key: BeautyKey): number {
  return settings[key];
}

function nextSettingsForKey(settings: BeautySettings, key: BeautyKey, value: number): BeautySettings {
  const next = Math.round(clamp(value, 0, 100) / BEAUTY_VALUE_STEP) * BEAUTY_VALUE_STEP;
  if (key === 'natural') {
    return {
      natural: next,
      smooth: next,
      brighten: Math.round(next * 0.3),
      tone: Math.round(next * 0.3),
      sharpness: 0,
    };
  }
  return { ...settings, [key]: next };
}

function BeautyPanelImpl({
  visible,
  settings,
  disabled,
  available,
  onChange,
  onClose,
}: BeautyPanelProps) {
  const [selectedKey, setSelectedKey] = useState<BeautyKey>('smooth');
  const selectedValue = valueForKey(settings, selectedKey);
  const controlsDisabled = disabled || !available;

  const updateSelectedValue = (value: number) => {
    if (controlsDisabled) return;
    onChange(nextSettingsForKey(settings, selectedKey, value));
  };

  if (!visible) return null;

  return (
    <View style={styles.beautyOverlay} pointerEvents="box-none">
      <Pressable style={styles.beautyDismissArea} onPress={onClose} />
      <View style={styles.beautyPanel}>
        <View style={styles.beautyHeader}>
          <View style={styles.beautyHeaderSide} />
          <Text style={styles.beautyTitle}>美颜</Text>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="重置美颜"
            disabled={controlsDisabled}
            style={[styles.beautyResetButton, controlsDisabled && styles.disabledControl]}
            onPress={() => onChange(DEFAULT_BEAUTY_SETTINGS)}
          >
            <Text style={styles.beautyResetText}>↻ 重置</Text>
          </Pressable>
        </View>

        {!available ? <Text style={styles.beautyHint}>仅前置画面生效</Text> : null}

        <BeautySlider
          value={selectedValue}
          disabled={controlsDisabled}
          onChange={updateSelectedValue}
        />

        <View style={styles.beautyItems}>
          {BEAUTY_ITEMS.map(item => {
            const selected = selectedKey === item.key;
            return (
              <Pressable
                key={item.key}
                accessibilityRole="button"
                accessibilityLabel={item.label}
                disabled={controlsDisabled}
                style={[
                  styles.beautyItem,
                  selected && styles.beautyItemSelected,
                  controlsDisabled && styles.disabledControl,
                ]}
                onPress={() => setSelectedKey(item.key)}
              >
                <BeautyItemIcon selected={selected} />
                <Text style={[styles.beautyItemLabel, selected && styles.beautyItemLabelSelected]}>
                  {item.label}
                </Text>
              </Pressable>
            );
          })}
        </View>
      </View>
    </View>
  );
}

export const BeautyPanel = memo(BeautyPanelImpl);
BeautyPanel.displayName = 'BeautyPanel';

interface BeautySliderProps {
  value: number;
  disabled: boolean;
  onChange: (value: number) => void;
}

function BeautySlider({ value, disabled, onChange }: BeautySliderProps) {
  const [trackWidth, setTrackWidth] = useState(1);
  const percent = clamp(value, 0, 100);

  const handleTouch = (locationX: number) => {
    if (disabled || trackWidth <= 0) return;
    onChange((clamp(locationX, 0, trackWidth) / trackWidth) * 100);
  };

  return (
    <View style={styles.beautySliderWrap}>
      <Text style={styles.beautySliderValue}>{Math.round(percent)}</Text>
      <View
        style={styles.beautySliderTrack}
        onLayout={event => setTrackWidth(Math.max(1, event.nativeEvent.layout.width))}
        onStartShouldSetResponder={() => true}
        onMoveShouldSetResponder={() => true}
        onResponderTerminationRequest={() => false}
        onResponderGrant={event => handleTouch(event.nativeEvent.locationX)}
        onResponderMove={event => handleTouch(event.nativeEvent.locationX)}
      >
        <View pointerEvents="none" style={styles.beautySliderRail} />
        <View pointerEvents="none" style={[styles.beautySliderFill, { width: `${percent}%` }]} />
        <View pointerEvents="none" style={[styles.beautySliderThumb, { left: `${percent}%` }]} />
      </View>
    </View>
  );
}

interface BeautyItemIconProps {
  selected: boolean;
}

function BeautyItemIcon({ selected }: BeautyItemIconProps) {
  return (
    <View style={[styles.beautyItemIcon, selected && styles.beautyItemIconSelected]}>
      <View style={[styles.beautyItemIconDot, selected && styles.beautyItemIconDotSelected]} />
    </View>
  );
}
