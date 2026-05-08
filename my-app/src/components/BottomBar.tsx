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
  onShutterPress: () => void;
  onModeSwitch: (mode: CameraMode) => void;
  onCaptureModeChange: (mode: CaptureMode) => void;
  isFlipped: boolean;
  onFlip: () => void;
}

function BottomBarImpl({
  cameraMode,
  captureMode,
  recording,
  recordingStarting,
  recordingStopping,
  saving,
  onShutterPress,
  onModeSwitch,
  onCaptureModeChange,
  isFlipped,
  onFlip,
}: BottomBarProps) {
  const disabled = recording || recordingStarting || recordingStopping;
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
      </View>

      <View style={styles.bottomBar} pointerEvents="box-none">
        <View style={styles.modeToggle}>
          <Pressable style={[styles.modeBtn, captureMode === 'picture' && styles.modeBtnActive]} onPress={() => onCaptureModeChange('picture')}>
            <Text style={[styles.modeBtnText, captureMode === 'picture' && styles.modeBtnTextActive]}>Photo</Text>
          </Pressable>
          <Pressable style={[styles.modeBtn, captureMode === 'video' && styles.modeBtnActive]} onPress={() => onCaptureModeChange('video')}>
            <Text style={[styles.modeBtnText, captureMode === 'video' && styles.modeBtnTextActive]}>Video</Text>
          </Pressable>
        </View>

        <Pressable
          accessibilityRole="button"
          accessibilityLabel={recording ? 'Stop' : (captureMode === 'picture' ? 'Take photo' : 'Record')}
          style={({ pressed }) => [
            styles.shutterOuter,
            pressed && styles.shutterOuterMuted,
            saving && styles.shutterOuterMuted,
            recordingStarting && styles.shutterOuterMuted,
            recordingStopping && styles.shutterOuterMuted,
            recording && styles.shutterOuterRecording,
          ]}
          onPress={onShutterPress}
        >
          <View style={[styles.shutterInner, (recording || recordingStarting) && styles.shutterInnerRecording]} />
        </Pressable>

        <Pressable
          style={[styles.flipBtn, isFlipped && styles.flipBtnActive]}
          onPress={onFlip}
          accessibilityRole="button"
          accessibilityLabel="Flip cameras"
        >
          <Text style={styles.flipBtnText}>↻</Text>
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
