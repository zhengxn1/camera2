import { memo } from 'react';
import { Text, View } from 'react-native';
import { styles } from '../styles';

interface RecordingIndicatorProps {
  starting: boolean;
}

function RecordingIndicatorImpl({ starting }: RecordingIndicatorProps) {
  return (
    <View style={styles.recordingIndicator} pointerEvents="none">
      <View style={styles.recordingDot} />
      <Text style={styles.recordingText}>{starting ? '准备录制' : '录制中'}</Text>
    </View>
  );
}

export const RecordingIndicator = memo(RecordingIndicatorImpl);
RecordingIndicator.displayName = 'RecordingIndicator';
