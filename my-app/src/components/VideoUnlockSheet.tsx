import { memo, useEffect, useState } from 'react';
import { ActivityIndicator, Modal, Pressable, Text, View } from 'react-native';
import type { VideoUnlockProduct } from '../native';
import { styles } from '../styles';

interface VideoUnlockSheetProps {
  visible: boolean;
  product: VideoUnlockProduct | null;
  productLoading: boolean;
  productError: string | null;
  purchasing: boolean;
  onPurchase: () => void;
  onRestore: () => void;
  onClose: () => void;
}

function VideoUnlockSheetImpl({
  visible,
  product,
  productLoading,
  productError,
  purchasing,
  onPurchase,
  onRestore,
  onClose,
}: VideoUnlockSheetProps) {
  const [waitingText, setWaitingText] = useState('正在连接 App Store...');

  useEffect(() => {
    if (!purchasing) {
      setWaitingText('正在连接 App Store...');
      return undefined;
    }

    const timer = setTimeout(() => {
      setWaitingText('正在确认购买，请稍候...');
    }, 1500);
    return () => clearTimeout(timer);
  }, [purchasing]);

  const canPurchase = !!product && !productLoading && !productError && !purchasing;
  const purchaseLabel = productLoading || (!product && !productError)
    ? '正在获取价格...'
    : productError
      ? '暂时无法获取价格'
      : `立即解锁 ${product?.displayPrice ?? ''}`;

  const handleClose = () => {
    if (!purchasing) onClose();
  };

  return (
    <Modal animationType="fade" transparent visible={visible} onRequestClose={handleClose}>
      <View style={styles.unlockOverlay}>
        <Pressable style={styles.unlockScrim} disabled={purchasing} onPress={handleClose} />
        <View style={styles.unlockCard}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="关闭解锁窗口"
            disabled={purchasing}
            style={[styles.unlockCloseIconButton, purchasing && styles.disabledControl]}
            onPress={handleClose}
          >
            <Text style={styles.unlockCloseIconText}>×</Text>
          </Pressable>

          <View style={styles.unlockIconWrap}>
            <View style={styles.unlockIconPlate}>
              <View style={styles.unlockRecorderFrame}>
                <View style={styles.unlockRecorderLeftPane} />
                <View style={styles.unlockRecorderDivider} />
                <View style={styles.unlockRecorderRecDot} />
                <Text style={styles.unlockRecorderRecText}>REC</Text>
              </View>
            </View>
          </View>

          <Text style={styles.unlockTitle}>解锁视频录制</Text>
          <Text style={styles.unlockBody}>开启 2K 视频录制。一次购买，终身使用。</Text>
          <View style={styles.unlockDivider} />

          {purchasing ? (
            <View style={styles.unlockWaiting}>
              <ActivityIndicator color="#f2f2f7" />
              <Text style={styles.unlockWaitingText}>{waitingText}</Text>
            </View>
          ) : (
            <>
              {productError ? <Text style={styles.unlockErrorText}>{productError}</Text> : null}
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="立即解锁视频录制"
                disabled={!canPurchase}
                style={[styles.unlockPrimaryButton, !canPurchase && styles.disabledControl]}
                onPress={onPurchase}
              >
                <Text style={styles.unlockPrimaryText}>{purchaseLabel}</Text>
              </Pressable>
            </>
          )}

          <Pressable
            accessibilityRole="button"
            accessibilityLabel="恢复购买"
            disabled={purchasing}
            style={[styles.unlockTextButton, purchasing && styles.disabledControl]}
            onPress={onRestore}
          >
            <Text style={styles.unlockTextButtonLabel}>恢复购买</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}

export const VideoUnlockSheet = memo(VideoUnlockSheetImpl);
VideoUnlockSheet.displayName = 'VideoUnlockSheet';
