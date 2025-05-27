import { NativeModule, requireNativeModule } from "expo";

import {
  AppleVisionModuleEvents,
  FaceDetectionResult,
} from "./ExpoAppleVision.types";

declare class ExpoAppleVisionModule extends NativeModule<AppleVisionModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;

  /**
   * Detects faces in the provided image using Apple's Vision framework
   * @param imageUri Local URI of the image to process
   * @param paddingFactor Optional padding around detected faces (0.0 to 1.0), defaults to 0.0
   * @returns Promise with face detection results
   */
  detectFacesAsync(imageUri: string): Promise<FaceDetectionResult>;

  /**
   * Detects faces in multiple images using Apple's Vision framework
   * @param imageUris Array of local URIs of images to process
   * @returns Promise with an array of face detection results
   */
  detectFacesInMultipleImagesAsync(
    imageUris: string[]
  ): Promise<FaceDetectionResult[]>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoAppleVisionModule>("ExpoAppleVision");
