import { memo } from 'react';
import { Modal, Pressable, Text, View } from 'react-native';
import type { VideoUnlockProduct } from '../native';
import { styles } from '../styles';

interface VideoUnlockSheetProps {
  visible: boolean;
  product: VideoUnlockProduct | null;
  purchasing: boolean;
  onPurchase: () => void;
  onRestore: () => void;
  onClose: () => void;
}

function VideoUnlockSheetImpl({
  visible,
  product,
  purchasing,
  onPurchase,
  onRestore,
  onClose,
}: VideoUnlockSheetProps) {
  const price = product?.displayPrice ? ` ${product.displayPrice}` : '';

  return (
    <Modal animationType="fade" transparent visible={visible} onRequestClose={onClose}>
      <View style={styles.unlockOverlay}>
        <Pressable style={styles.unlockScrim} onPress={onClose} />
        <View style={styles.unlockSheet}>
          <Text style={styles.unlockTitle}>解锁视频录制</Text>
          <Text style={styles.unlockBody}>拍照免费，视频录制需一次购买解锁。</Text>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Unlock video recording"
            disabled={purchasing}
            style={[styles.unlockPrimaryButton, purchasing && styles.disabledControl]}
            onPress={onPurchase}
          >
            <Text style={styles.unlockPrimaryText}>{purchasing ? '处理中...' : `解锁视频${price}`}</Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Restore purchases"
            disabled={purchasing}
            style={[styles.unlockTextButton, purchasing && styles.disabledControl]}
            onPress={onRestore}
          >
            <Text style={styles.unlockTextButtonLabel}>恢复购买</Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Close unlock sheet"
            disabled={purchasing}
            style={styles.unlockCloseButton}
            onPress={onClose}
          >
            <Text style={styles.unlockCloseText}>稍后</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}

export const VideoUnlockSheet = memo(VideoUnlockSheetImpl);
VideoUnlockSheet.displayName = 'VideoUnlockSheet';
