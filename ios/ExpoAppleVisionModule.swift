import ExpoModulesCore
import Vision
import UIKit
import Photos // Import Photos framework

public class ExpoAppleVisionModule: Module {
  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.
  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('ExpoAppleVision')` in JavaScript.
    Name("ExpoAppleVision")

    // Sets constant properties on the module. Can take a dictionary or a closure that returns a dictionary.
    Constants([
      "PI": Double.pi
    ])

    // Defines event names that the module can send to JavaScript.
    Events("onChange")

    // Defines a JavaScript synchronous function that runs the native code on the JavaScript thread.
    Function("hello") {
      return "Hello world! 👋"
    }

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
    AsyncFunction("setValueAsync") { (value: String) in
      // Send an event to JavaScript.
      self.sendEvent("onChange", [
        "value": value
      ])
    }

    // Detect faces in a single image
    AsyncFunction("detectFacesAsync") { (imageUri: String, promise: Promise) in
      Task {
        do {
          let padding = 0.0
          let rollCorrection = 1.0

          let (cgImage, width, height, orientation, uiImage) = try await loadImage(from: imageUri)
          let faces = try await detectAndCropFacesInImage(
            cgImage: cgImage, 
            uiImage: uiImage,
            imageWidth: width, 
            imageHeight: height, 
            orientation: orientation,
            imageUri: imageUri,
            paddingFactor: CGFloat(padding),
            rollCorrectionFactor: CGFloat(rollCorrection)
          )
          promise.resolve(["faces": faces])
        } catch {
          promise.reject(error)
        }
      }
    }
    
    // Detect faces in multiple images
    AsyncFunction("detectFacesInMultipleImagesAsync") { (uris: [String]) async throws -> [[String: Any]] in
      try await withThrowingTaskGroup(of: [String: Any].self) { group in
        for uri in uris {
          group.addTask { try await self.detectFacesInternal(uri: uri) }
        }
        return try await group.reduce(into: []) { $0.append($1) }
      }
    }
  }
}
