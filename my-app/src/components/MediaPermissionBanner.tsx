import { memo } from 'react';
import { Pressable, Text, View } from 'react-native';
import { styles } from '../styles';

interface MediaPermissionBannerProps {
  onRequest: () => void;
}

function MediaPermissionBannerImpl({ onRequest }: MediaPermissionBannerProps) {
  return (
    <View style={styles.mediaBanner}>
      <Text style={styles.mediaBannerText}>Photo library permission is required to save.</Text>
      <Pressable style={styles.secondaryButton} onPress={onRequest}>
        <Text style={styles.secondaryButtonLabel}>Allow</Text>
      </Pressable>
    </View>
  );
}

export const MediaPermissionBanner = memo(MediaPermissionBannerImpl);
MediaPermissionBanner.displayName = 'MediaPermissionBanner';
