import type { StyleProp, ViewStyle } from "react-native";

export type OnLoadEventPayload = {
  url: string;
};

export interface FaceDetectionResult {
  faces: FaceFeatures[];
}

export interface FaceFeatures {
  boundingBox: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
  croppedUri: string;
  rollAngle?: number;
  landmarks?: {
    leftEye?: { x: number; y: number };
    rightEye?: { x: number; y: number };
    leftPupil?: { x: number; y: number };
    rightPupil?: { x: number; y: number };
    leftEyebrow?: { x: number; y: number };
    rightEyebrow?: { x: number; y: number };
    nose?: { x: number; y: number };
    noseCrest?: { x: number; y: number };
    medianLine?: { x: number; y: number };
    mouth?: { x: number; y: number };
    leftCheek?: { x: number; y: number };
    rightCheek?: { x: number; y: number };
  };
  originalAssetContainsHumanUpperBody?: boolean;

  confidence?: number | null;
  /**
   * Overall quality of the face capture.
   * A value of 0 indicates low quality, 1 indicates high quality.
   * May be null or undefined if not available (e.g., older iOS versions).
   * Available iOS 11+.
   */
  faceCaptureQuality?: number | null;
}

export type AppleVisionModuleEvents = {
  onChange: (params: ChangeEventPayload) => void;
};

export type ChangeEventPayload = {
  value: string;
};

export type ExpoAppleVisionViewProps = {
  url: string;
  onLoad: (event: { nativeEvent: OnLoadEventPayload }) => void;
  style?: StyleProp<ViewStyle>;
};
