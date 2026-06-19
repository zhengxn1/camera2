import { memo, useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { styles } from '../styles';
import { clamp } from '../utils';

export type BeautyKey = 'smooth' | 'brighten' | 'whiten';

export interface BeautySettings {
  smooth: number;
  brighten: number;
  whiten: number;
}

export const DEFAULT_BEAUTY_SETTINGS: BeautySettings = {
  smooth: 0,
  brighten: 0,
  whiten: 0,
};

const BEAUTY_VALUE_STEP = 2;

const BEAUTY_ITEMS: Array<{ key: BeautyKey; label: string }> = [
  { key: 'smooth', label: '磨皮' },
  { key: 'brighten', label: '提亮' },
  { key: 'whiten', label: '美白' },
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
  const [selectedKey, setSelectedKey] = useState<BeautyKey>('whiten');
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
                <BeautyItemIcon type={item.key} selected={selected} />
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
  type: BeautyKey;
  selected: boolean;
}

function BeautyItemIcon({ type, selected }: BeautyItemIconProps) {
  const glyph = type === 'smooth' ? '◌' : type === 'brighten' ? '✦' : '◐';
  return (
    <View style={[styles.beautyItemIcon, selected && styles.beautyItemIconSelected]}>
      <Text style={[styles.beautyItemIconGlyph, selected && styles.beautyItemIconGlyphSelected]}>
        {glyph}
      </Text>
    </View>
  );
}
