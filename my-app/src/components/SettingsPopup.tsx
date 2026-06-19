import { memo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { ASPECT_RATIOS, type AspectRatio } from '../constants';
import { styles } from '../styles';

export type SaveFormat = 'merged' | 'segments';

interface SettingsPopupProps {
  visible: boolean;
  onClose: () => void;
  aspectRatio: AspectRatio;
  onAspectChange: (ratio: AspectRatio) => void;
  saveFormat: SaveFormat;
  onSaveFormatChange: (format: SaveFormat) => void;
  disabled: boolean;
}

const SAVE_FORMATS: Array<{ value: SaveFormat; title: string; subtitle: string }> = [
  { value: 'merged', title: '合并', subtitle: '所见即所得' },
  { value: 'segments', title: '分段', subtitle: '前置、后置、合并' },
];

function SettingsPopupImpl({
  visible,
  onClose,
  aspectRatio,
  onAspectChange,
  saveFormat,
  onSaveFormatChange,
  disabled,
}: SettingsPopupProps) {
  if (!visible) return null;

  return (
    <View style={styles.settingsOverlay}>
      <Pressable style={StyleSheet.absoluteFillObject} onPress={onClose} />
      <View style={styles.settingsPanel}>
        <View style={styles.settingsHeader}>
          <Text style={styles.settingsTitle}>设置</Text>
          <Pressable accessibilityRole="button" accessibilityLabel="关闭设置" style={styles.closeButton} onPress={onClose}>
            <Text style={styles.closeButtonText}>×</Text>
          </Pressable>
        </View>
        <View style={styles.settingRow}>
          <Text style={styles.settingLabel}>画幅比例</Text>
          <View style={styles.aspectOptions}>
            {ASPECT_RATIOS.map(ratio => (
              <Pressable
                key={ratio}
                disabled={disabled}
                style={[styles.aspectBtn, aspectRatio === ratio && styles.aspectBtnActive, disabled && styles.disabledControl]}
                onPress={() => onAspectChange(ratio)}
              >
                <Text style={[styles.aspectBtnText, aspectRatio === ratio && styles.aspectBtnTextActive]}>
                  {ratio}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>
        <View style={styles.settingRow}>
          <Text style={styles.settingLabel}>保存格式</Text>
          <View style={styles.saveFormatOptions}>
            {SAVE_FORMATS.map(format => {
              const selected = saveFormat === format.value;
              return (
                <Pressable
                  key={format.value}
                  disabled={disabled}
                  style={[styles.saveFormatBtn, selected && styles.saveFormatBtnActive, disabled && styles.disabledControl]}
                  onPress={() => onSaveFormatChange(format.value)}
                >
                  <Text style={[styles.saveFormatTitle, selected && styles.saveFormatTitleActive]}>
                    {format.title}
                  </Text>
                  <Text style={[styles.saveFormatSubtitle, selected && styles.saveFormatSubtitleActive]}>
                    {format.subtitle}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        </View>
      </View>
    </View>
  );
}

export const SettingsPopup = memo(SettingsPopupImpl);
SettingsPopup.displayName = 'SettingsPopup';
