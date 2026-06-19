import {
  NativeEventEmitter,
  NativeModules,
  requireNativeComponent,
  type HostComponent,
  type ViewProps,
} from 'react-native';
import type { CameraSide } from './constants';

export interface NativeDualCameraViewProps extends ViewProps {
  layoutMode: string;
  saveAspectRatio: string;
  dualLayoutRatio: number;
  pipSize: number;
  pipPositionX: number;
  pipPositionY: number;
  sxBackOnTop: boolean;
  pipMainIsBack: boolean;
  saveFormat: 'merged' | 'segments';
  frontBeautyEnabled: boolean;
  frontBeautySmooth: number;
  frontBeautyBrighten: number;
  frontBeautyWhiten: number;
}

export interface DualCameraModuleSpec {
  startSession?: () => void;
  stopSession?: () => void;
  startAudioMetering?: () => void;
  stopAudioMetering?: () => void;
  takePhoto?: () => void;
  startRecording?: () => void;
  stopRecording?: () => void;
  flipCamera?: () => void;
  setZoom?: (camera: CameraSide, level: number) => void;
}

export interface CameraPermissionModuleSpec {
  getCameraAuthorizationStatus?: () => Promise<string>;
  requestCameraPermission?: () => Promise<boolean>;
}

export interface VideoUnlockProduct {
  id: string;
  displayName: string;
  description: string;
  displayPrice: string;
}

export interface VideoUnlockResult {
  unlocked: boolean;
  cancelled?: boolean;
  pending?: boolean;
  alreadyPurchased?: boolean;
  unknown?: boolean;
  transactionId?: string;
}

export interface VideoUnlockModuleSpec {
  getProduct?: () => Promise<VideoUnlockProduct>;
  isVideoUnlocked?: () => Promise<boolean>;
  purchaseVideoUnlock?: () => Promise<VideoUnlockResult>;
  restorePurchases?: () => Promise<VideoUnlockResult>;
}

let NativeDualCameraView: HostComponent<NativeDualCameraViewProps> | null = null;
try {
  NativeDualCameraView = requireNativeComponent<NativeDualCameraViewProps>('DualCameraView');
} catch (_e) {
  NativeDualCameraView = null;
}

const DualCameraModule: DualCameraModuleSpec | undefined = NativeModules.DualCameraModule;
const CameraPermissionModule: CameraPermissionModuleSpec | undefined =
  NativeModules.CameraPermissionModule;
const VideoUnlockModule: VideoUnlockModuleSpec | undefined = NativeModules.VideoUnlockModule;

const DualCameraEventEmitter = NativeModules.DualCameraEventEmitter;
const eventEmitter: NativeEventEmitter | null = DualCameraEventEmitter
  ? new NativeEventEmitter(DualCameraEventEmitter)
  : null;

function getNativeModuleDiagnostics(): string {
  const moduleNames = Object.keys(NativeModules).sort();
  const cameraModules = moduleNames.filter(name =>
    name.toLowerCase().includes('camera') ||
    name.toLowerCase().includes('unlock') ||
    name.toLowerCase().includes('purchase') ||
    name.toLowerCase().includes('store'),
  );

  return [
    `视频解锁模块：${VideoUnlockModule ? '已加载' : '未加载'}`,
    `相关原生模块：${cameraModules.join(', ') || '未找到'}`,
  ].join('\n');
}

export {
  NativeDualCameraView,
  DualCameraModule,
  CameraPermissionModule,
  VideoUnlockModule,
  getNativeModuleDiagnostics,
  eventEmitter,
};
