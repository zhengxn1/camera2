import { memo } from 'react';
import { Pressable, Text, View } from 'react-native';
import { styles } from '../styles';

interface MediaPermissionBannerProps {
  onRequest: () => void;
}

function MediaPermissionBannerImpl({ onRequest }: MediaPermissionBannerProps) {
  return (
    <View style={styles.mediaPermissionOverlay} pointerEvents="box-none">
      <View style={styles.mediaPermissionCard}>
        <Text style={styles.permissionTitle}>需要相册权限</Text>
        <Text style={styles.permissionBody}>请允许访问相册，用于保存照片和视频。</Text>
        <Pressable style={styles.primaryButton} onPress={onRequest}>
          <Text style={styles.primaryButtonLabel}>允许访问相册</Text>
        </Pressable>
      </View>
    </View>
  );
}

export const MediaPermissionBanner = memo(MediaPermissionBannerImpl);
MediaPermissionBanner.displayName = 'MediaPermissionBanner';
