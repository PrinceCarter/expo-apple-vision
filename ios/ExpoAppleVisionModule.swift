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

  // MARK: - Private Methods

  // New async function to load image from URI (file or ph://)
  private func loadImage(
    from uri: String,
    maxDimension: CGFloat = 1024
  ) async throws -> (cgImage: CGImage, width: CGFloat, height: CGFloat,
                     orientation: CGImagePropertyOrientation, uiImage: UIImage) {
    guard let url = URL(string: uri) else {
      throw NSError(domain: "ExpoAppleVision", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid image URI"])
    }
    if url.scheme == "ph" {
      return try await loadPhAsset(uri: uri)
    } else if url.scheme == "file" {
      let thumbOpts: CFDictionary = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
      ] as CFDictionary
      guard
        let src  = CGImageSourceCreateWithURL(url as CFURL, nil),
        let cg   = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts)
      else {
        throw NSError(domain: "ExpoAppleVision", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "CGImageSource decode failed"])
      }
      let img = UIImage(cgImage: cg, scale: 1, orientation: .up)
      return (cg, img.size.width, img.size.height, .up, img)
    } else {
      throw NSError(domain: "ExpoAppleVision", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unsupported image URI scheme: \(url.scheme ?? "nil"). Only 'file://' and 'ph://' are supported."])
    }
  }

  private func loadPhAsset(
    uri: String
  ) async throws -> (
    cgImage: CGImage,
    width: CGFloat,
    height: CGFloat,
    orientation: CGImagePropertyOrientation,
    uiImage: UIImage
  ) {
    let localIdentifier = String(uri.dropFirst("ph://".count))
    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
    guard let asset = fetchResult.firstObject else {
      throw NSError(
        domain: "ExpoAppleVision",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey:
          "Failed to fetch PHAsset with local identifier: \(localIdentifier)"]
      )
    }
    return try await withCheckedThrowingContinuation { continuation in
      let opts = PHImageRequestOptions()
      opts.isNetworkAccessAllowed = true
      opts.deliveryMode           = .highQualityFormat
      opts.resizeMode             = .exact
      let target = CGSize(width: 1024, height: 1024)
      PHImageManager.default().requestImage(
        for: asset,
        targetSize: target,
        contentMode: .aspectFit,
        options: opts
      ) { maybeImage, info in
        guard let uiImage = maybeImage else {
          let err = info?[PHImageErrorKey] as? Error
          continuation.resume(
            throwing: err ?? NSError(
              domain: "ExpoAppleVision",
              code: 6,
              userInfo: [NSLocalizedDescriptionKey:
                "Failed to request image data for PHAsset: \(localIdentifier)"]
            )
          )
          return
        }
        let normalized = uiImage.withUpOrientation()
        guard let cg = normalized.cgImage else {
          continuation.resume(
            throwing: NSError(
              domain: "ExpoAppleVision",
              code: 7,
              userInfo: [NSLocalizedDescriptionKey: "UIImage had no CGImage backing"]
            )
          )
          return
        }
        continuation.resume(returning: (
          cg,
          normalized.size.width,
          normalized.size.height,
          .up,
          normalized
        ))
      }
    }
  }

  private func imageOrientationToCGImagePropertyOrientation(_ uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch uiOrientation {
      case .up: return .up
      case .down: return .down
      case .left: return .left
      case .right: return .right
      case .upMirrored: return .upMirrored
      case .downMirrored: return .downMirrored
      case .leftMirrored: return .leftMirrored
      case .rightMirrored: return .rightMirrored
      @unknown default: return .up // Default to up
    }
  }

  // Updated to detect and crop faces in one operation, including rotation normalization
  private func detectAndCropFacesInImage(
    cgImage: CGImage,
    uiImage: UIImage,
    imageWidth: CGFloat,
    imageHeight: CGFloat,
    orientation: CGImagePropertyOrientation,
    imageUri: String,
    paddingFactor: CGFloat = 0.0,
    rollCorrectionFactor: CGFloat = 1.0
  ) async throws -> [[String: Any]] {
    #if DEBUG
    // ── Dimension diagnostics ────────────────────────────────────────
    // Thoroughly log all dimension information to help track down any
    // inconsistencies between the various image representations.
    os_log("🔍 ExpoAppleVision | Processing image URI: %{public}@",
           type: .info,
           imageUri)

    os_log("📐 cgImage dimensions   → width: %d px, height: %d px",
           type: .debug,
           cgImage.width,
           cgImage.height)

    os_log("📐 uiImage dimensions   → width: %.2f px, height: %.2f px",
           type: .debug,
           Double(uiImage.size.width),
           Double(uiImage.size.height))

    os_log("📐 Passed-in dimensions → imageWidth: %.2f px, imageHeight: %.2f px",
           type: .debug,
           Double(imageWidth),
           Double(imageHeight))
    #endif


    let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    #if targetEnvironment(simulator)
    faceLandmarksRequest.usesCPUOnly = true
    #endif
    faceLandmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3

    let humanRectanglesRequest = VNDetectHumanRectanglesRequest()
    humanRectanglesRequest.revision = VNDetectHumanRectanglesRequestRevision2
    humanRectanglesRequest.upperBodyOnly = true
    #if targetEnvironment(simulator)
    humanRectanglesRequest.usesCPUOnly = true
    #endif

    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: orientation,
      options: [:]
    )
    try handler.perform([faceLandmarksRequest, humanRectanglesRequest])

    guard let landmarkObservations = faceLandmarksRequest.results else {
      os_log("No landmarks detected.", type: .error)
      return []
    }

    guard let humanRectangles = humanRectanglesRequest.results else {
      os_log("No human rectangles detected.", type: .debug)
      return []
    }

    // Flag indicating whether the original image contains (at least one) human upper-body rectangle
    let containsUpperBody = !humanRectangles.isEmpty

        // -------- 2️⃣   CAPTURE-QUALITY  ------------------------------------------
    //
    // Vision returns a *new* array of observations whose `faceCaptureQuality`
    // is filled.  We copy those numbers into an array that lines up with
    // `landmarkObservations` by index.
    //
    var captureQualityPerFace = Array<Float?>(repeating: nil,
                                              count: landmarkObservations.count)

    if #available(iOS 13.0, *) {                   // feature is iOS 15+
      let qualityRequest = VNDetectFaceCaptureQualityRequest()
      #if targetEnvironment(simulator)
      qualityRequest.usesCPUOnly = true
      #endif
      qualityRequest.inputFaceObservations = landmarkObservations

      let qualityHandler = VNImageRequestHandler(
        cgImage: cgImage,
        orientation: orientation,
        options: [:]
      )
      try qualityHandler.perform([qualityRequest])

      if let qResults = qualityRequest.results as? [VNFaceObservation] {
        for (idx, qObs) in qResults.enumerated() {
          captureQualityPerFace[idx] = qObs.faceCaptureQuality
        }
      }
    }

    let nativeW = CGFloat(cgImage.width)
    let nativeH = CGFloat(cgImage.height)
    let (imageW, imageH) = ([.left, .right, .leftMirrored, .rightMirrored].contains(orientation))
      ? (nativeH, nativeW)
      : (nativeW, nativeH)

    // Convert to integer for pixel-based calculations
    let iw = Int(imageWidth)
    let ih = Int(imageHeight)
    // Log converted dimensions
    os_log("Converted image dimensions (Int) - iw: %d, ih: %d", type: .debug, iw, ih)

    var facesResult: [[String: Any]] = []

    for (index, observation) in landmarkObservations.enumerated() {

      // ---- Basic per–observation diagnostics ---------------------------------
      let bb             = observation.boundingBox
      let confidence      = Double(observation.confidence)
      let rollValue       = observation.roll?.doubleValue  ?? .nan
      let yawValue        = observation.yaw?.doubleValue   ?? .nan
      let captureQValue   = Double(captureQualityPerFace[index] ?? -1)

      guard let landmarks = observation.landmarks else {

        #if DEBUG
        os_log(
          "Raw VNFaceObservation %d | bb(x:%.4f,y:%.4f,w:%.4f,h:%.4f) conf:%.3f capQ:%.3f roll(rad):%.4f yaw(rad):%.4f landmarks:none",
          type: .debug,
          index,
          Double(bb.origin.x), Double(bb.origin.y), Double(bb.width), Double(bb.height),
          confidence,
          captureQValue,
          rollValue,
          yawValue
        )
        #endif
        continue
      }

      // ---- Determine which landmark groups are present -----------------------
      let landmarkPairs: [(label: String, region: VNFaceLandmarkRegion2D?)] = [
        ("faceContour",  landmarks.faceContour),
        ("leftEye",      landmarks.leftEye),
        ("rightEye",     landmarks.rightEye),
        ("leftEyebrow",  landmarks.leftEyebrow),
        ("rightEyebrow", landmarks.rightEyebrow),
        ("nose",         landmarks.nose),
        ("noseCrest",    landmarks.noseCrest),
        ("medianLine",   landmarks.medianLine),
        ("outerLips",    landmarks.outerLips),
        ("innerLips",    landmarks.innerLips),
        ("leftPupil",    landmarks.leftPupil),
        ("rightPupil",   landmarks.rightPupil)
      ]

      let presentGroups  = landmarkPairs.compactMap { $0.region == nil ? nil : $0.label }
      let landmarkSummary = presentGroups.isEmpty ? "none" : presentGroups.joined(separator: ", ")

      #if DEBUG
      os_log(
        "Raw VNFaceObservation %d | bb(x:%.4f,y:%.4f,w:%.4f,h:%.4f) conf:%.3f capQ:%.3f roll(rad):%.4f yaw(rad):%.4f landmarks:%{public}@",
        type: .debug,
        index,
        Double(bb.origin.x), Double(bb.origin.y), Double(bb.width), Double(bb.height),
        confidence,
        captureQValue,
        rollValue,
        yawValue,
        landmarkSummary
      )
      #endif

      // ---- Exhaustive per–landmark dump --------------------------------------
      let imageSize = CGSize(width: imageW, height: imageH)

      #if DEBUG
      for (regionName, regionOptional) in landmarkPairs {
        guard let region = regionOptional else { continue }

        // Basic properties
        let pointCount      = region.pointCount
        let normalizedStr   = region.normalizedPoints
          .map { String(format: "(%.4f,%.4f)", $0.x, $0.y) }
          .joined(separator: ", ")

        let imagePointsStr  = region.pointsInImage(imageSize: imageSize)
          .map { String(format: "(%.1f,%.1f)", $0.x, $0.y) }
          .joined(separator: ", ")

        // Reflective dump of *all* stored vars for completeness
        let mirrorDump      = Mirror(reflecting: region).children.compactMap { child -> String? in
          guard let label = child.label else { return nil }
          return "\(label):\(child.value)"
        }.joined(separator: ", ")

        os_log(
          """
          Landmark[%{public}@] obsIdx:%d | pointCount:%d
            • normalized: [%{public}@]
            • imagePts  : [%{public}@]
            • mirror    : {%{public}@}
          """,
          type: .debug,
          regionName,
          index,
          pointCount,
          normalizedStr,
          imagePointsStr,
          mirrorDump
        )
      }
      #endif

      var faceDict: [String: Any] = [:]
      // 1) compute raw bounding box pixels (top-left origin)
      let uiRect = visionRectToUIKit(
        bb,
        orientation: orientation,
        imageWidth: imageWidth,
        imageHeight: imageHeight
      )

      #if DEBUG
      // Thoroughly log uiRect and its properties
      os_log(
        """
        📝 uiRect properties:
          origin.x    = %.2f
          origin.y    = %.2f
          size.width  = %.2f
          size.height = %.2f
          minX        = %.2f
          midX        = %.2f
          maxX        = %.2f
          minY        = %.2f
          midY        = %.2f
          maxY        = %.2f
          description = %{public}@ 
        """,
        type: .debug,
        uiRect.origin.x,
        uiRect.origin.y,
        uiRect.size.width,
        uiRect.size.height,
        uiRect.minX,
        uiRect.midX,
        uiRect.maxX,
        uiRect.minY,
        uiRect.midY,
        uiRect.maxY,
        NSCoder.string(for: uiRect)
      )
      #endif

      let x = uiRect.origin.x
      let y = uiRect.origin.y
      let w = uiRect.width
      let h = uiRect.height
      let faceCenter = CGPoint(x: x + w/2, y: y + h/2)

      var rollAngle: CGFloat = 0
 
      if let L = observation.landmarks?.leftPupil?.normalizedPoints.first,
       let R = observation.landmarks?.rightPupil?.normalizedPoints.first {
        // Calculate roll from eyes using VNImagePointForFaceLandmarkPoint
        // a) Pupils in Vision space  (origin: *bottom-left*)
      let vL = VNImagePointForFaceLandmarkPoint(
        vector_float2(Float(L.x), Float(L.y)),
        bb,
        Int(imageSize.width),
        Int(imageSize.height)
      )
      let vR = VNImagePointForFaceLandmarkPoint(
        vector_float2(Float(R.x), Float(R.y)),
        bb,
        Int(imageSize.width),
        Int(imageSize.height)
      )

      let dx = CGFloat(vR.x - vL.x)
      let dy = CGFloat(vL.y - vR.y)  // <- inverted

      if (dx != 0 || dy != 0) {
        rollAngle = atan2(dy, dx)
      }
      } else {
        rollAngle = observation.roll?.doubleValue ?? 0
      }
      
      faceDict["rollAngle"] = rollAngle
      os_log("Roll for face %d: %f", type: .debug, index, rollAngle)

      // 3) build cropRect in UIKit‐points
      let side = max(w, h) * (1 + paddingFactor)
      let originX = max(0, faceCenter.x - side/2)
      let originY = max(0, faceCenter.y - side/2)
      let availableW = imageWidth  - originX
      let availableH = imageHeight - originY
      let cropSide   = min(side, availableW, availableH)
      let cropRect   = CGRect(x: originX, y: originY, width: cropSide, height: cropSide)

      // Thoroughly log cropRect and its properties
      #if DEBUG
      os_log(
        """
        📝 cropRect properties:
          origin    = (%.2f, %.2f)
          size      = (%.2f, %.2f)
          minX      = %.2f
          midX      = %.2f
          maxX      = %.2f
          minY      = %.2f
          midY      = %.2f
          maxY      = %.2f
          description = %{public}@ 
        """,
        type: .debug,
        cropRect.origin.x,
        cropRect.origin.y,
        cropRect.size.width,
        cropRect.size.height,
        cropRect.minX,
        cropRect.midX,
        cropRect.maxX,
        cropRect.minY,
        cropRect.midY,
        cropRect.maxY,
        NSCoder.string(for: cropRect)
      )
      #endif

      // 4) compute the *pixel*‐based crop rect we actually used
      let scale = uiImage.scale
      let pixelCropRect = CGRect(
        x: cropRect.origin.x * scale,
        y: cropRect.origin.y * scale,
        width: cropRect.width  * scale,
        height: cropRect.height * scale
      )

      #if DEBUG
      // Thoroughly log pixelCropRect and its properties
      os_log(
        """
        📝 pixelCropRect properties:
          origin    = (%.2f, %.2f)
          size      = (%.2f, %.2f)
          minX      = %.2f
          midX      = %.2f
          maxX      = %.2f
          minY      = %.2f
          midY      = %.2f
          maxY      = %.2f
          description = %{public}@ 
        """,
        type: .debug,
        pixelCropRect.origin.x,
        pixelCropRect.origin.y,
        pixelCropRect.size.width,
        pixelCropRect.size.height,
        pixelCropRect.minX,
        pixelCropRect.midX,
        pixelCropRect.maxX,
        pixelCropRect.minY,
        pixelCropRect.midY,
        pixelCropRect.maxY,
        NSCoder.string(for: pixelCropRect)
      )
      #endif

      // 5) crop & rotate exactly that pixel rect
      let croppedUri = try cropAndRotateImage(
        uiImage: uiImage,
        rect: cropRect,
        rollAngle: rollAngle * rollCorrectionFactor,
        imageUri: imageUri,
        faceIndex: index,
        leftPupil: observation.landmarks?.leftPupil,
        rightPupil: observation.landmarks?.rightPupil,
        boundingBox: bb,
        imageSize: CGSize(width: imageW, height: imageH)
      )
      faceDict["croppedUri"] = croppedUri

      if let landmarks = observation.landmarks {
        var lmDict: [String: Any] = [:]
        let imgSize = CGSize(width: imageW, height: imageH)

        if let r = landmarks.leftEye {
          lmDict["leftEye"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        if let r = landmarks.leftPupil {
          lmDict["leftPupil"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        if let r = landmarks.rightEye {
          lmDict["rightEye"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        if let r = landmarks.rightPupil {
          lmDict["rightPupil"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        if let r = landmarks.leftEyebrow {
          lmDict["leftEyebrow"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        if let r = landmarks.rightEyebrow {
          lmDict["rightEyebrow"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        if let r = landmarks.nose {
          lmDict["nose"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        if let r = landmarks.noseCrest {
          lmDict["noseCrest"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        if let r = landmarks.outerLips {
          lmDict["mouth"] = mapRegion(
            r, boundingBox: bb, imageSize: imgSize,
            pixelCropRect: pixelCropRect, rollAngle: rollAngle
          )
        }
        faceDict["landmarks"] = lmDict
      }

      os_log("Face %d confidence: %f", type: .debug, index, confidence)
      faceDict["confidence"] = Double(confidence)

      // Insert the quality value (now guaranteed Double→JS)  ────────────────
      if let q = captureQualityPerFace[index] {
        os_log("Face %d quality: %f", type: .debug, index, q)
        faceDict["faceCaptureQuality"] = Double(q)
      }

      faceDict["originalAssetContainsHumanUpperBody"] = containsUpperBody

      facesResult.append(faceDict)
    }

    return facesResult
  }

  // New helper to average CGPoints
  private func averageCGPoints(_ pts: [CGPoint]) -> CGPoint {
    guard !pts.isEmpty else { return .zero }
    let sum = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
    return CGPoint(x: sum.x / CGFloat(pts.count), y: sum.y / CGFloat(pts.count))
  }

  /// Returns `point` rotated ***around `pivot`*** by `angle` rad (counter-clockwise).
private func rotate(_ point: CGPoint,
                    around pivot: CGPoint,
                    by angle: CGFloat) -> CGPoint {
  let dx = point.x - pivot.x, dy = point.y - pivot.y
  let ca = cos(angle),        sa = sin(angle)
  return CGPoint(
    x: dx * ca - dy * sa + pivot.x,
    y: dx * sa + dy * ca + pivot.y
  )
}

  /// Crop + rotate + scale so that interpupil distance = 35.2px
  private func cropAndRotateImage(
    uiImage: UIImage,
    rect: CGRect,
    rollAngle: CGFloat,
    imageUri: String,
    faceIndex: Int,
    leftPupil: VNFaceLandmarkRegion2D?,
    rightPupil: VNFaceLandmarkRegion2D?,
    boundingBox: CGRect,
    imageSize: CGSize,
    desiredPupilDistance: CGFloat = 35.2
  ) throws -> String {

  // ---------------------------------------------------------------------------
  // ①  Straighten the whole photo (eyes → horizontal)
  // ---------------------------------------------------------------------------
  let srcSize      = uiImage.size
  let imageCenter  = CGPoint(x: srcSize.width / 2, y: srcSize.height / 2)
  
  let straightenFmt = UIGraphicsImageRendererFormat.default()
  straightenFmt.scale = uiImage.scale            // *** critical fix ***  
  let straightened = UIGraphicsImageRenderer(size: srcSize, format: straightenFmt).image { ctx in
    ctx.cgContext.translateBy(x: imageCenter.x, y: imageCenter.y)
    ctx.cgContext.rotate(by: -rollAngle)                 // counter-rotate
    uiImage.draw(in: CGRect(origin: .init(x: -imageCenter.x,
                                          y: -imageCenter.y),
                            size: srcSize))
  }

var cropRect: CGRect

if let lp = leftPupil?.normalizedPoints.first,
   let rp = rightPupil?.normalizedPoints.first
{
  // a) Vision-space (origin bottom-left, units = pixels)
  let vLeft = VNImagePointForFaceLandmarkPoint(
    vector_float2(Float(lp.x), Float(lp.y)),
    boundingBox,
    Int(imageSize.width),
    Int(imageSize.height)
  )
  let vRight = VNImagePointForFaceLandmarkPoint(
    vector_float2(Float(rp.x), Float(rp.y)),
    boundingBox,
    Int(imageSize.width),
    Int(imageSize.height)
  )

  // b) convert to UIKit top-left *points*
  let pxToPt = 1 / uiImage.scale
  var eyeL = CGPoint(
    x: CGFloat(vLeft.x) * pxToPt,
    y: (imageSize.height - CGFloat(vLeft.y)) * pxToPt
  )
  var eyeR = CGPoint(
    x: CGFloat(vRight.x) * pxToPt,
    y: (imageSize.height - CGFloat(vRight.y)) * pxToPt
  )

  // c) rotate into the straightened coordinate space
  eyeL = rotate(eyeL, around: imageCenter, by: -rollAngle)
  eyeR = rotate(eyeR, around: imageCenter, by: -rollAngle)

  // d) uniform scale so pupils are ≈35.24 px apart in 112×112
  let dAct = hypot(eyeR.x - eyeL.x, eyeR.y - eyeL.y)
  let dRef: CGFloat = 65.5318 - 30.2946    // = 35.2372 px
  guard dAct > 0.1 else {
    throw NSError(
      domain: "ExpoAppleVision",
      code: 98,
      userInfo: [NSLocalizedDescriptionKey: "Pupil distance too small"]
    )
  }
  let s = dRef / dAct                   // <1 = shrink, >1 = enlarge
  let side = 112 / s                    // crop size in *points*

  // e) anchor the left eye at canonical (x,y) inside 112×112
  let refLX: CGFloat = (30.2946 + 8) / 112    // ≈0.270
  let refLY: CGFloat = 51.6963 / 112    // ≈0.462
  var origin = CGPoint(
    x: eyeL.x - side * refLX,
    y: eyeL.y - side * refLY
  )

  // f) clamp the square to the image bounds
  origin.x = max(0, min(origin.x, srcSize.width  - side))
  origin.y = max(0, min(origin.y, srcSize.height - side))

  cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))
               .integral
} else {
  // ② Bring the face centre & crop-rect into the straightened coordinate space
  let faceCenter = CGPoint(x: rect.midX, y: rect.midY)
  let centerRotated = rotate(faceCenter, around: imageCenter, by: -rollAngle)

  let side = rect.width  // `rect` is already square
  cropRect = CGRect(
    x: centerRotated.x - side / 2,
    y: centerRotated.y - side / 2,
    width: side,
    height: side
  )
  .integral
}

// make it pixel-aligned
// Clamp to the image bounds (faces on the rim of the frame)
let boundedCropRect = cropRect.intersection(
  CGRect(origin: .zero, size: srcSize)
)

  // Pixel space ⇢ multiply by the *original* scale
  let pixelScale = straightened.scale
  let pixelCropRect   = CGRect(x: boundedCropRect.origin.x * pixelScale,
                               y: boundedCropRect.origin.y * pixelScale,
                               width: boundedCropRect.size.width * pixelScale,
                               height: boundedCropRect.size.height * pixelScale)

  guard let cg = straightened.cgImage?.cropping(to: pixelCropRect) else {
    throw NSError(domain: "ExpoAppleVision", code: 99,
                  userInfo: [NSLocalizedDescriptionKey: "Crop after rotation failed"])
  }
  // The patch is now upright – no further rotation needed ✅
    let cropped = UIImage(cgImage: cg, scale: 1, orientation: .up)

    #if DEBUG
    os_log(
      """
      Cropped UIImage (cropped) properties:
        size.width      = %.2f
        size.height     = %.2f
        scale           = %.2f
        imageOrientation= %{public}@
        renderingMode   = %{public}@
        hasCGImage      = %{public}@
        cgImage.width   = %d
        cgImage.height  = %d
      """,
      type: .debug,
      Double(cropped.size.width),
      Double(cropped.size.height),
      Double(cropped.scale),
      String(describing: cropped.imageOrientation),
      String(describing: cropped.renderingMode),
      cropped.cgImage != nil ? "true" : "false",
      cropped.cgImage?.width ?? -1,
      cropped.cgImage?.height ?? -1
    )
    #endif

    // ────────────────────────────────────────────────────────
    // 4️⃣  **final HQ down-sample → 112 × 112 px**
    // ────────────────────────────────────────────────────────
    let targetSide: CGFloat = 112          // pixels   (because scale = 1 below)
    let fmtFinal          = UIGraphicsImageRendererFormat.default()
    fmtFinal.scale        = 1              // 1 pixel per pt  → 112 px
    let finalImg = UIGraphicsImageRenderer(
        size: CGSize(width: targetSide, height: targetSide),
        format: fmtFinal
      ).image { ctx in
        ctx.cgContext.interpolationQuality = .high
        // draw stretched → UIKit performs high-quality down-sample
        cropped.draw(in: CGRect(origin: .zero,
                                    size: CGSize(width: targetSide,
                                                 height: targetSide)))
      }

    // ────────────────────────────────────────────────────────
    // 5️⃣  write JPEG & return URI
    // ────────────────────────────────────────────────────────
    let filename = "face_\(UUID().uuidString)_\(faceIndex).jpg"
    let outURL   = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(filename)
    guard let data = finalImg.jpegData(compressionQuality: 1.0) else {
      throw NSError(domain: "ExpoAppleVision", code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "JPEG conversion failed"])
    }
    try data.write(to: outURL)
    return "file://" + outURL.path
  }

  /// Maps a Vision landmark region into the *112×112* output image's coordinate space.
  private func mapRegion(
    _ region: VNFaceLandmarkRegion2D,
    boundingBox: CGRect,
    imageSize: CGSize,          // original CGImage size in pixels
    pixelCropRect: CGRect,      // pixel‐space rect you fed to cgImage.cropping(to:)
    rollAngle: CGFloat          // radians, as used in cropAndRotateImage
  ) -> [[String: CGFloat]] {
    let targetSize = CGSize(width: 112, height: 112)
    // how much we scale the cropped pixels to fit 112×112
    let scaleX = targetSize.width  / pixelCropRect.width
    let scaleY = targetSize.height / pixelCropRect.height
    // center of our cropped patch in pixel coords
    let centerCrop = CGPoint(x: pixelCropRect.width/2, y: pixelCropRect.height/2)

    return region.normalizedPoints.map { p in
      // 1) landmark → global pixel coords (origin bottom‐left)
      let visionPt = VNImagePointForFaceLandmarkPoint(
        vector_float2(Float(p.x), Float(p.y)),
        boundingBox,
        Int(imageSize.width),
        Int(imageSize.height)
      )
      // 2) flip to top‐left origin
      var pt = CGPoint(x: visionPt.x, y: imageSize.height - visionPt.y)
      // 3) bring into our cropRect origin
      pt.x -= pixelCropRect.origin.x
      pt.y -= pixelCropRect.origin.y
      // 4) reverse the face‐rotation about the patch's center
      let t = CGPoint(x: pt.x - centerCrop.x, y: pt.y - centerCrop.y)
      let ca = cos(-rollAngle), sa = sin(-rollAngle)
      let rotated = CGPoint(
        x: t.x * ca - t.y * sa,
        y: t.x * sa + t.y * ca
      )
      let finalRaw = CGPoint(x: rotated.x + centerCrop.x, y: rotated.y + centerCrop.y)
      // 5) scale into the 0…112 output
      let scaled = CGPoint(x: finalRaw.x * scaleX, y: finalRaw.y * scaleY)
      return ["x": scaled.x, "y": scaled.y]
    }
  }

  // MARK: - Orientation helpers
  private func visionRectToUIKit(
    _ r: CGRect,
    orientation: CGImagePropertyOrientation,
    imageWidth w: CGFloat,
    imageHeight h: CGFloat
  ) -> CGRect {
    // Vision's r is in *normalized* (0-1) coordinates and its origin is
    // the bottom-left **of the pixel buffer as it was supplied to Vision**.
    // We convert to a UIKit rect (origin top-left) that matches the pixel
    // layout inside `cgImage`.
    var rect = r

    switch orientation {
    case .up, .upMirrored:
      rect.origin.y = 1 - rect.origin.y - rect.height       // flip Y

    case .down, .downMirrored:
      rect.origin.x = 1 - rect.origin.x - rect.width        // flip X
      // Y stays because pixel data is upside-down already

    case .left, .leftMirrored:
      let tmp = rect.origin.x
      rect.origin.x = rect.origin.y
      rect.origin.y = tmp
      rect.origin.y = 1 - rect.origin.y - rect.height       // then flip Y

    case .right, .rightMirrored:
      let tmp = rect.origin.x
      rect.origin.x = rect.origin.y
      rect.origin.y = tmp
      rect.origin.x = 1 - rect.origin.x - rect.width        // then flip X

    @unknown default:
      rect.origin.y = 1 - rect.origin.y - rect.height       // assume `.up`
    }

    // scale out of the 0-1 space
    rect.origin.x *= w
    rect.origin.y *= h
    rect.size.width  *= w
    rect.size.height *= h
    return rect
  }

  // MARK: - NEW ──────────────────────────────────────────────
  // Helper used by the TaskGroup in detectFacesInMultipleImagesAsync.
  private func detectFacesInternal(uri: String) async throws -> [String: Any] {
    let (cgImage, width, height, orientation, uiImage) = try await loadImage(from: uri)
    let faces = try await detectAndCropFacesInImage(
      cgImage: cgImage,
      uiImage: uiImage,
      imageWidth: width,
      imageHeight: height,
      orientation: orientation,
      imageUri: uri
    )
    return ["uri": uri, "faces": faces]
  }
}

// MARK: - UIImage orientation helper  ──────────────────────
private extension UIImage {
  /// Returns an image whose `.imageOrientation == .up`.
  func withUpOrientation() -> UIImage {
    guard imageOrientation != .up else { return self }

    UIGraphicsBeginImageContextWithOptions(size, false, scale)
    draw(in: CGRect(origin: .zero, size: size))
    let normalized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    // `normalized` is guaranteed non-nil because size > 0
    return normalized!
  }
}
