import { registerWebModule, NativeModule } from "expo";

import {
  ChangeEventPayload,
  FaceDetectionResult,
} from "./ExpoAppleVision.types";

type AppleVisionModuleEvents = {
  onChange: (params: ChangeEventPayload) => void;
};

class ExpoAppleVisionModule extends NativeModule<AppleVisionModuleEvents> {
  PI = Math.PI;

  async setValueAsync(value: string): Promise<void> {
    this.emit("onChange", { value });
  }

  hello() {
    return "Hello world! 👋";
  }

  async detectFacesAsync(
    _imageUri: string,
    _paddingFactor?: number
  ): Promise<FaceDetectionResult> {
    throw new Error(
      "Face detection is only available on iOS devices using Apple's Vision framework"
    );
  }

  async detectFacesInMultipleImagesAsync(
    _imageUris: string[]
  ): Promise<FaceDetectionResult[]> {
    throw new Error(
      "Face detection is only available on iOS devices using Apple's Vision framework"
    );
  }
}

export default registerWebModule(ExpoAppleVisionModule, "ExpoAppleVision");
