// Reexport the native module. On web, it will be resolved to ExpoAppleVisionModule.web.ts
// and on native platforms to ExpoAppleVisionModule.ts
import ExpoAppleVisionModule from "./ExpoAppleVisionModule";
export * from "./ExpoAppleVision.types";

/**
 * Detects faces in an image using Apple's Vision framework (iOS only)
 * @param imageUri Local URI of the image to analyze
 * @param paddingFactor Optional padding around detected faces (0.0 to 1.0), defaults to 0.0
 * @returns Promise with face detection results
 * @throws Error on Android platforms with "not implemented" message
 */
export const detectFaces = (imageUri: string) => {
  return ExpoAppleVisionModule.detectFacesAsync(imageUri);
};

/**
 * Detects faces in multiple images using Apple's Vision framework (iOS only)
 * @param imageUris Array of local URIs of images to analyze
 * @returns Promise with an array of face detection results
 * @throws Error on Android platforms with "not implemented" message
 */
export const detectFacesInMultipleImages = (imageUris: string[]) => {
  return ExpoAppleVisionModule.detectFacesInMultipleImagesAsync(imageUris);
};

export default ExpoAppleVisionModule;
