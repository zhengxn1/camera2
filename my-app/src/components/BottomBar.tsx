import { memo } from 'react';
import { Pressable, Text, View } from 'react-native';
import {
  type CameraMode,
  type CaptureMode,
  MODE_OPTIONS,
  type ModeIconName,
} from '../constants';
import { styles } from '../styles';

interface BottomBarProps {
  cameraMode: CameraMode;
  captureMode: CaptureMode;
  recording: boolean;
  recordingStarting: boolean;
  recordingStopping: boolean;
  saving: boolean;
  videoLocked: boolean;
  onShutterPress: () => void;
  onModeSwitch: (mode: CameraMode) => void;
  onCaptureModeChange: (mode: CaptureMode) => void;
  isFlipped: boolean;
  onFlip: () => void;
  beautyActive: boolean;
  beautyPanelVisible: boolean;
  beautyAvailable: boolean;
  onBeautyOpen: () => void;
}

function BottomBarImpl({
  cameraMode,
  captureMode,
  recording,
  recordingStarting,
  recordingStopping,
  saving,
  videoLocked,
  onShutterPress,
  onModeSwitch,
  onCaptureModeChange,
  isFlipped,
  onFlip,
  beautyActive,
  beautyPanelVisible,
  beautyAvailable,
  onBeautyOpen,
}: BottomBarProps) {
  const disabled = recording || recordingStarting || recordingStopping;
  const videoReady = captureMode === 'video' && !videoLocked;

  return (
    <>
      <View style={styles.rightPanel} pointerEvents="box-none">
        {MODE_OPTIONS.map(item => (
          <ModeButton
            key={item.mode}
            selected={cameraMode === item.mode}
            disabled={disabled}
            onPress={() => onModeSwitch(item.mode)}
            label={item.label}
            icon={item.icon}
          />
        ))}
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="打开美颜"
          disabled={disabled || !beautyAvailable}
          style={[
            styles.modeButton,
            (beautyActive || beautyPanelVisible) && styles.modeButtonSelected,
            (disabled || !beautyAvailable) && styles.disabledControl,
          ]}
          onPress={onBeautyOpen}
        >
          <BeautyIcon selected={beautyActive || beautyPanelVisible} />
        </Pressable>
      </View>

      <View style={styles.bottomBar} pointerEvents="box-none">
        <View style={styles.modeToggle}>
          <Pressable style={[styles.modeBtn, captureMode === 'picture' && styles.modeBtnActive]} onPress={() => onCaptureModeChange('picture')}>
            <Text style={[styles.modeBtnText, captureMode === 'picture' && styles.modeBtnTextActive]}>拍照</Text>
          </Pressable>
          <Pressable style={[styles.modeBtn, captureMode === 'video' && styles.modeBtnActive]} onPress={() => onCaptureModeChange('video')}>
            <Text style={[styles.modeBtnText, captureMode === 'video' && styles.modeBtnTextActive]}>视频</Text>
          </Pressable>
        </View>

        <Pressable
          accessibilityRole="button"
          accessibilityLabel={videoLocked ? '解锁视频录制' : (recording ? '停止录制' : (captureMode === 'picture' ? '拍照' : '开始录制'))}
          style={({ pressed }) => [
            styles.shutterOuter,
            videoLocked && styles.shutterOuterLocked,
            videoReady && !recording && !recordingStarting && styles.shutterOuterVideoReady,
            pressed && styles.shutterOuterMuted,
            saving && styles.shutterOuterMuted,
            recordingStarting && styles.shutterOuterMuted,
            recordingStopping && styles.shutterOuterMuted,
            recording && styles.shutterOuterRecording,
          ]}
          onPress={onShutterPress}
        >
          {videoLocked ? (
            <View style={styles.videoLockBadge}>
              <View style={styles.videoLockShackle} />
              <View style={styles.videoLockBody} />
            </View>
          ) : (
            <View
              style={[
                styles.shutterInner,
                videoReady && !recording && !recordingStarting && styles.shutterInnerVideoReady,
                (recording || recordingStarting) && styles.shutterInnerRecording,
              ]}
            />
          )}
        </Pressable>

        <Pressable
          style={[styles.flipBtn, isFlipped && styles.flipBtnActive]}
          onPress={onFlip}
          accessibilityRole="button"
          accessibilityLabel="切换前后画面"
        >
          <FlipIcon active={isFlipped} />
        </Pressable>
      </View>
    </>
  );
}

export const BottomBar = memo(BottomBarImpl);
BottomBar.displayName = 'BottomBar';

interface ModeButtonProps {
  selected: boolean;
  disabled: boolean;
  onPress: () => void;
  label: string;
  icon: ModeIconName;
}

function ModeButtonImpl({ selected, disabled, onPress, label, icon }: ModeButtonProps) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      style={[styles.modeButton, selected && styles.modeButtonSelected, disabled && styles.disabledControl]}
      onPress={onPress}
    >
      <ModeIcon name={icon} selected={selected} />
    </Pressable>
  );
}

const ModeButton = memo(ModeButtonImpl);
ModeButton.displayName = 'ModeButton';

interface FlipIconProps {
  active: boolean;
}

function FlipIconImpl({ active }: FlipIconProps) {
  const tone = active ? styles.flipIconActive : styles.flipIconTone;

  return (
    <View style={styles.flipIcon}>
      <View style={[styles.flipCameraBody, tone]}>
        <View style={[styles.flipCameraLens, tone]} />
        <View style={[styles.flipCameraDot, tone]} />
      </View>
      <View style={[styles.flipArrowTop, tone]} />
      <View style={[styles.flipArrowTopHead, tone]} />
      <View style={[styles.flipArrowBottom, tone]} />
      <View style={[styles.flipArrowBottomHead, tone]} />
    </View>
  );
}

const FlipIcon = memo(FlipIconImpl);
FlipIcon.displayName = 'FlipIcon';

interface BeautyIconProps {
  selected: boolean;
}

function BeautyIconImpl({ selected }: BeautyIconProps) {
  const tone = selected ? styles.modeIconSelected : styles.modeIcon;
  const fill = selected ? styles.modeIconFillSelected : styles.modeIconFill;

  return (
    <View style={styles.beautyIconMagic}>
      <View style={[styles.beautyIconStarLarge, tone]} />
      <View style={[styles.beautyIconStarSmall, tone]} />
      <View style={[styles.beautyIconWand, tone]}>
        <View style={[styles.beautyIconWandTip, fill]} />
      </View>
    </View>
  );
}

const BeautyIcon = memo(BeautyIconImpl);
BeautyIcon.displayName = 'BeautyIcon';

interface ModeIconProps {
  name: ModeIconName;
  selected: boolean;
}

function ModeIconImpl({ name, selected }: ModeIconProps) {
  const tone = selected ? styles.modeIconSelected : styles.modeIcon;
  const fill = selected ? styles.modeIconFillSelected : styles.modeIconFill;

  if (name === 'back' || name === 'front') {
    return (
      <View style={[styles.cameraIconBody, tone]}>
        <View style={[styles.cameraIconLens, tone]} />
        <View style={[styles.cameraIconDot, name === 'front' && styles.cameraIconDotRight, fill]} />
      </View>
    );
  }

  if (name === 'pipSquare' || name === 'pipCircle') {
    return (
      <View style={[styles.pipIconFrame, tone]}>
        <View style={[styles.pipIconInset, name === 'pipCircle' && styles.pipIconInsetCircle, fill]} />
      </View>
    );
  }

  if (name === 'lr') {
    return (
      <View style={[styles.splitIconFrame, tone]}>
        <View style={[styles.splitIconLeft, fill]} />
        <View style={[styles.splitIconDividerVertical, tone]} />
      </View>
    );
  }

  return (
    <View style={[styles.splitIconFrame, tone]}>
      <View style={[styles.splitIconTop, fill]} />
      <View style={[styles.splitIconDividerHorizontal, tone]} />
    </View>
  );
}

const ModeIcon = memo(ModeIconImpl);
ModeIcon.displayName = 'ModeIcon';
