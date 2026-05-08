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

let NativeDualCameraView: HostComponent<NativeDualCameraViewProps> | null = null;
try {
  NativeDualCameraView = requireNativeComponent<NativeDualCameraViewProps>('DualCameraView');
} catch (_e) {
  NativeDualCameraView = null;
}

const DualCameraModule: DualCameraModuleSpec | undefined = NativeModules.DualCameraModule;
const CameraPermissionModule: CameraPermissionModuleSpec | undefined =
  NativeModules.CameraPermissionModule;

const DualCameraEventEmitter = NativeModules.DualCameraEventEmitter;
const eventEmitter: NativeEventEmitter | null = DualCameraEventEmitter
  ? new NativeEventEmitter(DualCameraEventEmitter)
  : null;

export {
  NativeDualCameraView,
  DualCameraModule,
  CameraPermissionModule,
  eventEmitter,
};
