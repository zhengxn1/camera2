import { memo } from 'react';
import { Text, View } from 'react-native';
import { styles } from '../styles';

interface AudioLevelIndicatorProps {
  level: number;
}

function AudioLevelIndicatorImpl({ level }: AudioLevelIndicatorProps) {
  const barCount = 12;
  const activeCount = Math.round(level * barCount);

  return (
    <View style={styles.audioIndicator} pointerEvents="none">
      <Text style={styles.audioLabel}>声音</Text>
      <View style={styles.audioBars}>
        {Array.from({ length: barCount }).map((_, i) => (
          <View key={i} style={[styles.audioBar, i < activeCount ? styles.audioBarActive : null]} />
        ))}
      </View>
    </View>
  );
}

export const AudioLevelIndicator = memo(AudioLevelIndicatorImpl);
AudioLevelIndicator.displayName = 'AudioLevelIndicator';
