# Expo Apple Vision Module

This Expo module provides a native bridge to Apple's Vision framework, enabling face detection and analysis functionality for iOS applications.

## Features

- Face detection in images
- Facial landmarks extraction (eyes, nose, mouth, etc.)
- Facial attributes detection (smiling, eye state)

## Installation

```bash
# Using npm
npm install expo-apple-vision

# Using yarn
yarn add expo-apple-vision

# Using expo
expo install expo-apple-vision
```

## Usage

### Detecting Faces in an Image

```typescript
import React, { useEffect, useState } from "react";
import { View, Text, Image, StyleSheet } from "react-native";
import * as ImagePicker from "expo-image-picker";
import {
  detectFaces,
  FaceDetectionResult,
  FaceFeatures,
} from "expo-apple-vision";

export default function FaceDetectionScreen() {
  const [image, setImage] = useState<string | null>(null);
  const [faceData, setFaceData] = useState<FaceFeatures[] | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pickImage = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      quality: 1,
    });

    if (!result.cancelled && result.uri) {
      setImage(result.uri);
      await analyzeImage(result.uri);
    }
  };

  const analyzeImage = async (uri: string) => {
    try {
      setIsLoading(true);
      setError(null);

      // Call the face detection function
      const result = await detectFaces(uri);
      setFaceData(result.faces);

      console.log("Face detection results:", result);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "An unknown error occurred"
      );
      console.error("Face detection error:", err);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Face Detection Demo</Text>

      {image && <Image source={{ uri: image }} style={styles.image} />}

      {isLoading && <Text>Analyzing image...</Text>}

      {error && <Text style={styles.error}>{error}</Text>}

      {faceData && (
        <View style={styles.resultsContainer}>
          <Text style={styles.resultTitle}>
            {faceData.length} {faceData.length === 1 ? "face" : "faces"}{" "}
            detected
          </Text>

          {faceData.map((face, index) => (
            <View key={index} style={styles.faceData}>
              <Text>Face #{index + 1}</Text>
              <Text>Position: {JSON.stringify(face.boundingBox)}</Text>
              {/* Add more face attributes here if needed */}
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: "bold",
    marginBottom: 20,
  },
  image: {
    width: 300,
    height: 300,
    borderRadius: 10,
    marginBottom: 20,
  },
  resultsContainer: {
    width: "100%",
    marginTop: 20,
  },
  resultTitle: {
    fontSize: 18,
    fontWeight: "bold",
    marginBottom: 10,
  },
  faceData: {
    backgroundColor: "#f0f0f0",
    padding: 10,
    borderRadius: 5,
    marginBottom: 10,
  },
  error: {
    color: "red",
    marginTop: 10,
  },
});
```

### Analyzing Multiple Images

```typescript
import { detectFacesInMultipleImages } from "expo-apple-vision";

const analyzeMultipleImages = async (uris: string[]) => {
  try {
    const results = await detectFacesInMultipleImages(uris);

    // Process results for each image
    results.forEach((result, index) => {
      console.log(`Image ${index + 1} has ${result.faces.length} faces`);
    });

    return results;
  } catch (error) {
    console.error("Error analyzing multiple images:", error);
    throw error;
  }
};
```

## API Reference

### Functions

#### `detectFaces(imageUri: string): Promise<FaceDetectionResult>`

Analyzes a single image and detects faces.

- **Parameters**:
  - `imageUri` (string): The local URI of the image to analyze
- **Returns**: Promise resolving to a `FaceDetectionResult` object
- **Platform Support**: iOS only (throws an error on Android and web)

#### `detectFacesInMultipleImages(imageUris: string[]): Promise<FaceDetectionResult[]>`

Analyzes multiple images and detects faces in each one.

- **Parameters**:
  - `imageUris` (string[]): An array of local URIs of images to analyze
- **Returns**: Promise resolving to an array of `FaceDetectionResult` objects
- **Platform Support**: iOS only (throws an error on Android and web)

### Types

#### `FaceDetectionResult`

```typescript
interface FaceDetectionResult {
  faces: FaceFeatures[];
}
```

#### `FaceFeatures`

```typescript
// ... existing code ...
```
