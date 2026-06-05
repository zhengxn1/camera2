import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { PanResponder, Pressable, StyleSheet, Text, View } from 'react-native';
import { ASPECT_RATIOS, type AspectRatio, type VideoSaveMode } from '../constants';
import type { FrontBeautySettings } from '../hooks/useFrontBeautyEnabled';
import { styles } from '../styles';

interface SettingsPopupProps {
  visible: boolean;
  onOpen: () => void;
  onClose: () => void;
  aspectRatio: AspectRatio;
  onAspectChange: (ratio: AspectRatio) => void;
  videoSaveMode: VideoSaveMode;
  onVideoSaveModeChange: (mode: VideoSaveMode) => void;
  frontBeautyEnabled: boolean;
  onFrontBeautyEnabledChange: (enabled: boolean) => void;
  frontBeautySettings: FrontBeautySettings;
  onFrontBeautySettingsChange: (settings: Partial<FrontBeautySettings>) => void;
  disabled: boolean;
}

interface BeautySliderProps {
  label: string;
  value: number;
  onChange: (value: number) => void;
}

function BeautySlider({ label, value, onChange }: BeautySliderProps) {
  const [trackWidth, setTrackWidth] = useState(1);
  const [localValue, setLocalValue] = useState(value);
  const trackRef = useRef<View | null>(null);
  const trackXRef = useRef(0);
  const draggingRef = useRef(false);
  const latestValueRef = useRef(value);
  const animationFrameRef = useRef<number | null>(null);

  useEffect(() => {
    latestValueRef.current = value;
    if (!draggingRef.current) {
      setLocalValue(value);
    }
  }, [value]);

  useEffect(() => {
    return () => {
      if (animationFrameRef.current !== null) {
        cancelAnimationFrame(animationFrameRef.current);
      }
    };
  }, []);

  const measureTrack = useCallback(() => {
    trackRef.current?.measure((_x, _y, width, _height, pageX) => {
      trackXRef.current = pageX;
      setTrackWidth(Math.max(1, width));
    });
  }, []);

  const emitChange = useCallback((next: number) => {
    if (next === latestValueRef.current) return;
    latestValueRef.current = next;
    if (animationFrameRef.current !== null) {
      cancelAnimationFrame(animationFrameRef.current);
    }
    animationFrameRef.current = requestAnimationFrame(() => {
      animationFrameRef.current = null;
      onChange(next);
    });
  }, [onChange]);

  const updateFromX = useCallback((x: number) => {
    const next = Math.round(Math.max(0, Math.min(trackWidth, x)) / trackWidth * 100);
    setLocalValue(next);
    emitChange(next);
  }, [emitChange, trackWidth]);

  const updateFromPageX = useCallback((pageX: number) => {
    updateFromX(pageX - trackXRef.current);
  }, [updateFromX]);

  const responder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: event => {
      draggingRef.current = true;
      measureTrack();
      updateFromPageX(event.nativeEvent.pageX);
    },
    onPanResponderMove: event => updateFromPageX(event.nativeEvent.pageX),
    onPanResponderRelease: event => {
      updateFromPageX(event.nativeEvent.pageX);
      draggingRef.current = false;
    },
    onPanResponderTerminate: () => {
      draggingRef.current = false;
      setLocalValue(latestValueRef.current);
    },
  }), [measureTrack, updateFromPageX]);

  const displayValue = Math.max(0, Math.min(100, localValue));
  const progressWidth = displayValue / 100 * trackWidth;

  return (
    <View style={styles.beautySliderRow}>
      <Text style={styles.beautySliderLabel}>{label}</Text>
      <View
        ref={trackRef}
        style={styles.beautySliderTrackWrap}
        onLayout={event => {
          setTrackWidth(Math.max(1, event.nativeEvent.layout.width));
          requestAnimationFrame(measureTrack);
        }}
        {...responder.panHandlers}
      >
        <View pointerEvents="none" style={styles.beautySliderTrack} />
        <View pointerEvents="none" style={[styles.beautySliderFill, { width: progressWidth }]} />
        <View pointerEvents="none" style={[styles.beautySliderThumb, { transform: [{ translateX: progressWidth - 9 }] }]} />
      </View>
      <View style={styles.beautyValueBox}>
        <Text style={styles.beautyValueText}>{displayValue}</Text>
      </View>
    </View>
  );
}

function SettingsPopupImpl({
  visible,
  onClose,
  onOpen,
  aspectRatio,
  onAspectChange,
  videoSaveMode,
  onVideoSaveModeChange,
  frontBeautyEnabled,
  onFrontBeautyEnabledChange,
  frontBeautySettings,
  onFrontBeautySettingsChange,
  disabled,
}: SettingsPopupProps) {
  return (
    <>
      <View style={styles.topBar} pointerEvents="box-none">
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="打开设置"
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
            <View style={styles.settingRow}>
              <Text style={styles.settingLabel}>视频保存</Text>
              <View style={styles.aspectOptions}>
                <Pressable
                  style={[styles.aspectBtn, videoSaveMode === 'combined' && styles.aspectBtnActive]}
                  onPress={() => onVideoSaveModeChange('combined')}
                >
                  <Text style={[styles.aspectBtnText, videoSaveMode === 'combined' && styles.aspectBtnTextActive]}>
                    合成
                  </Text>
                </Pressable>
                <Pressable
                  style={[styles.aspectBtn, videoSaveMode === 'all3' && styles.aspectBtnActive]}
                  onPress={() => onVideoSaveModeChange('all3')}
                >
                  <Text style={[styles.aspectBtnText, videoSaveMode === 'all3' && styles.aspectBtnTextActive]}>
                    三份
                  </Text>
                </Pressable>
              </View>
            </View>
            <View style={styles.settingRow}>
              <Text style={styles.settingLabel}>前置美颜</Text>
              <View style={styles.aspectOptions}>
                <Pressable
                  style={[styles.aspectBtn, frontBeautyEnabled && styles.aspectBtnActive]}
                  onPress={() => onFrontBeautyEnabledChange(true)}
                >
                  <Text style={[styles.aspectBtnText, frontBeautyEnabled && styles.aspectBtnTextActive]}>
                    开启
                  </Text>
                </Pressable>
                <Pressable
                  style={[styles.aspectBtn, !frontBeautyEnabled && styles.aspectBtnActive]}
                  onPress={() => onFrontBeautyEnabledChange(false)}
                >
                  <Text style={[styles.aspectBtnText, !frontBeautyEnabled && styles.aspectBtnTextActive]}>
                    关闭
                  </Text>
                </Pressable>
              </View>
            </View>
            {frontBeautyEnabled ? (
              <View style={styles.beautyPanel}>
                <View style={styles.beautySectionHeader}>
                  <Text style={styles.beautySectionTitle}>皮肤管理</Text>
                </View>
                <BeautySlider
                  label="磨皮"
                  value={frontBeautySettings.smooth}
                  onChange={smooth => onFrontBeautySettingsChange({ smooth })}
                />
                <BeautySlider
                  label="美白"
                  value={frontBeautySettings.whiten}
                  onChange={whiten => onFrontBeautySettingsChange({ whiten })}
                />
                <BeautySlider
                  label="均肤"
                  value={frontBeautySettings.even}
                  onChange={even => onFrontBeautySettingsChange({ even })}
                />
                <BeautySlider
                  label="丰盈"
                  value={frontBeautySettings.plump}
                  onChange={plump => onFrontBeautySettingsChange({ plump })}
                />
              </View>
            ) : null}
          </View>
        </View>
      ) : null}
    </>
  );
}

export const SettingsPopup = memo(SettingsPopupImpl);
SettingsPopup.displayName = 'SettingsPopup';
