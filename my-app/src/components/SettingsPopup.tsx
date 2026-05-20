import { memo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { ASPECT_RATIOS, type AspectRatio } from '../constants';
import { styles } from '../styles';

interface SettingsPopupProps {
  visible: boolean;
  onOpen: () => void;
  onClose: () => void;
  aspectRatio: AspectRatio;
  onAspectChange: (ratio: AspectRatio) => void;
  disabled: boolean;
}

function SettingsPopupImpl({
  visible,
  onClose,
  onOpen,
  aspectRatio,
  onAspectChange,
  disabled,
}: SettingsPopupProps) {
  return (
    <>
      <View style={styles.topBar} pointerEvents="box-none">
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Open settings"
          disabled={disabled}
          style={[styles.settingsButton, disabled && styles.disabledControl]}
          onPress={onOpen}
        >
          <Text style={styles.settingsIcon}>...</Text>
        </Pressable>
      </View>
      {visible ? (
        <View style={styles.settingsOverlay}>
          <Pressable style={StyleSheet.absoluteFillObject} onPress={onClose} />
          <View style={styles.settingsPanel}>
            <View style={styles.settingsHeader}>
              <Text style={styles.settingsTitle}>Settings</Text>
              <Pressable accessibilityRole="button" accessibilityLabel="Close settings" style={styles.closeButton} onPress={onClose}>
                <Text style={styles.closeButtonText}>x</Text>
              </Pressable>
            </View>
            <View style={styles.settingRow}>
              <Text style={styles.settingLabel}>Aspect</Text>
              <View style={styles.aspectOptions}>
                {ASPECT_RATIOS.map(ratio => (
                  <Pressable
                    key={ratio}
                    style={[styles.aspectBtn, aspectRatio === ratio && styles.aspectBtnActive]}
                    onPress={() => onAspectChange(ratio)}
                  >
                    <Text style={[styles.aspectBtnText, aspectRatio === ratio && styles.aspectBtnTextActive]}>
                      {ratio}
                    </Text>
                  </Pressable>
                ))}
              </View>
            </View>
          </View>
        </View>
      ) : null}
    </>
  );
}

export const SettingsPopup = memo(SettingsPopupImpl);
SettingsPopup.displayName = 'SettingsPopup';
