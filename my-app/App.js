import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as MediaLibrary from 'expo-media-library';

export default function App() {
  const cameraRef = useRef(null);
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const [mediaPermission, requestMediaPermission] = MediaLibrary.usePermissions({
    writeOnly: true,
    granularPermissions: ['photo'],
  });
  const [cameraReady, setCameraReady] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (cameraPermission?.granted) {
      requestMediaPermission();
    }
  }, [cameraPermission?.granted, requestMediaPermission]);

  const ensureMediaPermission = useCallback(async () => {
    if (mediaPermission?.granted) return true;
    const result = await requestMediaPermission();
    if (result.granted) return true;
    Alert.alert(
      '需要相册权限',
      '保存照片到相册需要获得相应授权。若已拒绝，请在系统设置中为本应用开启存储/相册权限。',
    );
    return false;
  }, [mediaPermission?.granted, requestMediaPermission]);

  const takePicture = useCallback(async () => {
    if (Platform.OS === 'web') return;
    if (!cameraRef.current || !cameraReady || saving) return;

    const okMedia = await ensureMediaPermission();
    if (!okMedia) return;

    try {
      setSaving(true);
      const photo = await cameraRef.current.takePictureAsync({
        quality: 1,
        skipProcessing: Platform.OS === 'android',
      });
      await MediaLibrary.saveToLibraryAsync(photo.uri);
      Alert.alert('已保存', '照片已保存到相册');
    } catch (e) {
      const message = e?.message ?? String(e);
      Alert.alert('拍照或保存失败', message);
    } finally {
      setSaving(false);
    }
  }, [cameraReady, saving, ensureMediaPermission]);

  if (Platform.OS === 'web') {
    return (
      <View style={styles.centered}>
        <Text style={styles.hint}>相机预览与拍照请在 iOS 或 Android 设备（含模拟器）上运行。</Text>
        <StatusBar style="dark" />
      </View>
    );
  }

  if (cameraPermission == null || mediaPermission == null) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color="#fff" />
        <StatusBar style="light" />
      </View>
    );
  }

  if (!cameraPermission.granted) {
    return (
      <View style={styles.centered}>
        <Text style={styles.permissionTitle}>需要相机权限</Text>
        <Text style={styles.permissionBody}>用于全屏预览与拍照。</Text>
        <Pressable style={styles.primaryButton} onPress={requestCameraPermission}>
          <Text style={styles.primaryButtonLabel}>请求相机权限</Text>
        </Pressable>
        <StatusBar style="light" />
      </View>
    );
  }

  return (
    <View style={styles.root}>
      <CameraView
        ref={cameraRef}
        style={styles.camera}
        facing="back"
        mode="picture"
        onCameraReady={() => setCameraReady(true)}
      />

      <View style={styles.footer} pointerEvents="box-none">
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="拍照"
          style={({ pressed }) => [
            styles.shutterOuter,
            (!cameraReady || saving || pressed) && styles.shutterOuterMuted,
          ]}
          onPress={takePicture}
          disabled={!cameraReady || saving}
        >
          <View style={styles.shutterInner} />
        </Pressable>
      </View>

      {!mediaPermission.granted ? (
        <View style={styles.mediaBanner}>
          <Text style={styles.mediaBannerText}>保存照片需要相册/存储权限</Text>
          <Pressable style={styles.secondaryButton} onPress={requestMediaPermission}>
            <Text style={styles.secondaryButtonLabel}>去授权</Text>
          </Pressable>
        </View>
      ) : null}

      {saving ? (
        <View style={styles.savingOverlay} pointerEvents="none">
          <ActivityIndicator size="large" color="#fff" />
        </View>
      ) : null}

      <StatusBar style="light" />
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#000',
  },
  camera: {
    flex: 1,
  },
  footer: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    alignItems: 'center',
    justifyContent: 'center',
    paddingBottom: Platform.OS === 'ios' ? 34 : 28,
    paddingTop: 12,
  },
  shutterOuter: {
    width: 76,
    height: 76,
    borderRadius: 38,
    borderWidth: 4,
    borderColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  shutterOuterMuted: {
    opacity: 0.55,
  },
  shutterInner: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#fff',
  },
  mediaBanner: {
    position: 'absolute',
    left: 16,
    right: 16,
    bottom: Platform.OS === 'ios' ? 120 : 112,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  mediaBannerText: {
    flex: 1,
    color: '#fff',
    fontSize: 14,
  },
  secondaryButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    backgroundColor: '#fff',
  },
  secondaryButtonLabel: {
    color: '#000',
    fontSize: 14,
    fontWeight: '600',
  },
  savingOverlay: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.25)',
  },
  centered: {
    flex: 1,
    backgroundColor: '#000',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  hint: {
    color: '#fff',
    textAlign: 'center',
    fontSize: 16,
    lineHeight: 22,
  },
  permissionTitle: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 8,
    textAlign: 'center',
  },
  permissionBody: {
    color: 'rgba(255,255,255,0.75)',
    fontSize: 15,
    textAlign: 'center',
    marginBottom: 20,
  },
  primaryButton: {
    paddingHorizontal: 18,
    paddingVertical: 12,
    borderRadius: 999,
    backgroundColor: '#fff',
  },
  primaryButtonLabel: {
    color: '#000',
    fontSize: 16,
    fontWeight: '600',
  },
});
