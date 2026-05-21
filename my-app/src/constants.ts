import { Platform } from 'react-native';

export const CAMERA_MODE = {
  BACK: 'back',
  FRONT: 'front',
  PIP_SQUARE: 'pip_square',
  PIP_CIRCLE: 'pip_circle',
  LR: 'lr',
  SX: 'sx',
} as const;

export type CameraMode = (typeof CAMERA_MODE)[keyof typeof CAMERA_MODE];

export const LAYOUT_MAP: Record<CameraMode, string> = {
  [CAMERA_MODE.BACK]: 'back',
  [CAMERA_MODE.FRONT]: 'front',
  [CAMERA_MODE.PIP_SQUARE]: 'pip_square',
  [CAMERA_MODE.PIP_CIRCLE]: 'pip_circle',
  [CAMERA_MODE.LR]: 'lr',
  [CAMERA_MODE.SX]: 'sx',
};

export const ASPECT_RATIOS = ['9:16', '3:4', '1:1'] as const;
export type AspectRatio = (typeof ASPECT_RATIOS)[number];

export const BACK_ZOOM_LEVELS = [0.5, 1, 2, 3, 5];
export const FRONT_ZOOM_LEVELS = [1, 2];
export const SNAP_POINTS = [0.3, 0.5, 0.7];

export const ZOOM_ACTIVE = '#FFD60A';
export const INTERACTION_TOP = Platform.OS === 'ios' ? 60 : 44;

export type ModeIconName = 'back' | 'front' | 'pipSquare' | 'pipCircle' | 'lr' | 'sx';

export interface ModeOption {
  mode: CameraMode;
  label: string;
  icon: ModeIconName;
}

export const MODE_OPTIONS: ModeOption[] = [
  { mode: CAMERA_MODE.PIP_SQUARE, label: '画中画', icon: 'pipSquare' },
  { mode: CAMERA_MODE.PIP_CIRCLE, label: '圆形画中画', icon: 'pipCircle' },
  { mode: CAMERA_MODE.LR, label: '左右分屏', icon: 'lr' },
  { mode: CAMERA_MODE.SX, label: '上下分屏', icon: 'sx' },
];

export type CameraSide = 'back' | 'front';
export type CaptureMode = 'picture' | 'video';
