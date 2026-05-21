import { memo } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import type { CameraStatus } from '../hooks/useCameraPermission';
import { styles } from '../styles';

interface PermissionGateProps {
  status: CameraStatus;
  onRequest: () => void;
}

function PermissionGateImpl({ status, onRequest }: PermissionGateProps) {
  if (status === 'loading') {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color="#fff" />
        <StatusBar style="light" />
      </View>
    );
  }

  if (status === 'not_determined') {
    return (
      <View style={styles.permissionScreen}>
        <View style={styles.permissionCard}>
          <View style={styles.permissionIcon}>
            <View style={styles.permissionCameraBody} />
            <View style={styles.permissionCameraLens} />
          </View>
          <Text style={styles.permissionTitle}>需要相机权限</Text>
          <Text style={styles.permissionBody}>请允许访问前后摄像头，用于分屏预览、拍照和视频录制。</Text>
          <Pressable style={styles.primaryButton} onPress={onRequest}>
            <Text style={styles.primaryButtonLabel}>允许访问相机</Text>
          </Pressable>
        </View>
        <StatusBar style="light" />
      </View>
    );
  }

  return (
    <View style={styles.permissionScreen}>
      <View style={styles.permissionCard}>
        <Text style={styles.permissionTitle}>{status === 'denied' ? '权限未开启' : '相机不可用'}</Text>
        <Text style={styles.permissionBody}>
          {status === 'denied'
            ? '请在系统设置中开启相机权限。'
            : '原生相机模块未加载，请重新构建应用。'}
        </Text>
      </View>
      <StatusBar style="light" />
    </View>
  );
}

export const PermissionGate = memo(PermissionGateImpl);
PermissionGate.displayName = 'PermissionGate';
