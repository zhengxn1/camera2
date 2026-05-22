import { memo } from 'react';
import { Pressable, Text, View } from 'react-native';
import { styles } from '../styles';

interface MediaPermissionBannerProps {
  onRequest: () => void;
  onDismiss: () => void;
}

function MediaPermissionBannerImpl({ onRequest, onDismiss }: MediaPermissionBannerProps) {
  return (
    <View style={styles.mediaPermissionOverlay}>
      <View style={styles.systemPermissionCard}>
        <View style={styles.photosPermissionIcon}>
          <View style={styles.photosPetalRed} />
          <View style={styles.photosPetalOrange} />
          <View style={styles.photosPetalYellow} />
          <View style={styles.photosPetalGreen} />
          <View style={styles.photosPetalBlue} />
          <View style={styles.photosPetalPurple} />
        </View>
        <Text style={styles.systemPermissionTitle}>“KIRO 分屏相机”想要添加到你的“照片”。</Text>
        <Text style={styles.systemPermissionBody}>需要授权以将照片和视频保存到系统相册。</Text>
        <View style={styles.systemPermissionActions}>
          <Pressable style={styles.systemPermissionButton} onPress={onDismiss}>
            <Text style={styles.systemPermissionButtonText}>不允许</Text>
          </Pressable>
          <Pressable style={styles.systemPermissionButton} onPress={onRequest}>
            <Text style={styles.systemPermissionButtonText}>允许</Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}

export const MediaPermissionBanner = memo(MediaPermissionBannerImpl);
MediaPermissionBanner.displayName = 'MediaPermissionBanner';
