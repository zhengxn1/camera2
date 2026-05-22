import { memo } from 'react';
import { ActivityIndicator, Linking, Pressable, Text, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import type { CameraStatus } from '../hooks/useCameraPermission';
import { styles } from '../styles';

interface PermissionGateProps {
  status: CameraStatus;
  requesting: boolean;
  onRequest: () => void;
}

function PermissionGateImpl({ status, requesting, onRequest }: PermissionGateProps) {
  if (status === 'loading' || status === 'not_determined' || requesting) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color="#fff" />
        <Text style={styles.permissionWaitingText}>
          {status === 'not_determined' || requesting ? '正在请求相机权限...' : '正在检查相机权限...'}
        </Text>
        <StatusBar style="light" />
      </View>
    );
  }

  const denied = status === 'denied';

  return (
    <View style={styles.permissionScreen}>
      <View style={styles.systemPermissionCard}>
        <View style={styles.systemPermissionIcon}>
          <View style={styles.permissionCameraBodyDark} />
          <View style={styles.permissionCameraLensDark} />
        </View>
        <Text style={styles.systemPermissionTitle}>{denied ? '“KIRO 分屏相机”无法访问相机。' : '相机暂不可用。'}</Text>
        <Text style={styles.systemPermissionBody}>
          {denied ? '需要在系统设置中允许相机权限，以进行全屏预览与拍照。' : '原生相机模块未加载，请重新构建应用。'}
        </Text>
        {denied ? (
          <View style={styles.systemPermissionActions}>
            <Pressable style={styles.systemPermissionButton} onPress={onRequest}>
              <Text style={styles.systemPermissionButtonText}>再试一次</Text>
            </Pressable>
            <Pressable style={styles.systemPermissionButton} onPress={() => Linking.openSettings()}>
              <Text style={styles.systemPermissionButtonText}>打开设置</Text>
            </Pressable>
          </View>
        ) : null}
      </View>
      <StatusBar style="light" />
    </View>
  );
}

export const PermissionGate = memo(PermissionGateImpl);
PermissionGate.displayName = 'PermissionGate';
