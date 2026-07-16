import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:typed_data';

class PixelsterService {
  PixelsterService._internal();
  static final PixelsterService instance = PixelsterService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://ahm7xmakki.com',
    headers: {'Content-Type': 'application/json'},
  ));

  /// Text to Image (/api/tti)
  Future<String> generateImage({required String prompt, String ratio = '1:1'}) async {
    final response = await _dio.post(
      "/api/tti",
      data: {
        "prompt": prompt,
        "ratio": ratio,
      },
    );
    return response.data["imageUrl"]; 
  }

  /// Helper: Downloads an image URL and converts it to Base64
  Future<String> _imageUrlToBase64(String url) async {
    final res = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(res.data!);
    return base64Encode(bytes);
  }

  /// Image to Video (/api/ptv)
  /// The API requires a base64 image. We generate an image first, convert it, then animate it.
  Future<String> generateVideo({required String prompt, String ratio = '16:9'}) async {
    // Step 1: Generate a starting image from the prompt
    final imageUrl = await generateImage(prompt: prompt, ratio: ratio);
    
    // Step 2: Download image and convert to Base64
    final base64Image = await _imageUrlToBase64(imageUrl);

    // Step 3: Animate the image
    final response = await _dio.post(
      "/api/ptv",
      data: {
        "prompt": "animate the scene: $prompt",
        "ratio": ratio,
        "duration": 5, // 5 seconds
        "imageBase64": base64Image,
      },
    );
    
    return response.data["videoUrl"];
  }
}