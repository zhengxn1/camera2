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
      <View style={styles.centered}>
        <Text style={styles.permissionTitle}>Camera permission required</Text>
        <Text style={styles.permissionBody}>Dual camera needs access to the front and back cameras.</Text>
        <Pressable style={styles.primaryButton} onPress={onRequest}>
          <Text style={styles.primaryButtonLabel}>Allow camera</Text>
        </Pressable>
        <StatusBar style="light" />
      </View>
    );
  }

  return (
    <View style={styles.centered}>
      <Text style={styles.permissionTitle}>Camera unavailable</Text>
      <Text style={styles.permissionBody}>
        {status === 'denied'
          ? 'Enable camera permission in system settings.'
          : 'Native camera module is not loaded. Rebuild the app.'}
      </Text>
      <StatusBar style="light" />
    </View>
  );
}

export const PermissionGate = memo(PermissionGateImpl);
PermissionGate.displayName = 'PermissionGate';
