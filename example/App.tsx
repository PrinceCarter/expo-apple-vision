import React, { useState } from "react";
import {
  Button,
  SafeAreaView,
  ScrollView,
  Text,
  View,
  Image,
  StyleSheet,
} from "react-native";
import * as ImagePicker from "expo-image-picker";
import { detectFaces, FaceFeatures } from "expo-apple-vision";

export default function App() {
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

    if (!result.canceled && result.assets && result.assets[0]?.uri) {
      const uri = result.assets[0].uri;
      setImage(uri);
      await analyzeImage(uri);
    }
  };

  const analyzeImage = async (uri: string) => {
    try {
      setIsLoading(true);
      setError(null);
      setFaceData(null);
      const result = await detectFaces(uri);
      setFaceData(result.faces);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "An unknown error occurred"
      );
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        <Text style={styles.header}>Expo Apple Vision Test</Text>
        <Button title="Pick an image" onPress={pickImage} />
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
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  header: {
    fontSize: 30,
    margin: 20,
    textAlign: "center",
  },
  scrollContent: {
    alignItems: "center",
    padding: 20,
  },
  image: {
    width: 300,
    height: 300,
    borderRadius: 10,
    marginVertical: 20,
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
  container: {
    flex: 1,
    backgroundColor: "#eee",
  },
});
