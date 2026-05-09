import { memo } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { styles } from '../styles';

function SavingOverlayImpl() {
  return (
    <View style={styles.savingOverlay} pointerEvents="none">
      <ActivityIndicator size="large" color="#fff" />
    </View>
  );
}

export const SavingOverlay = memo(SavingOverlayImpl);
SavingOverlay.displayName = 'SavingOverlay';
