import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'supabase_service.dart';

class VoiceUploadService {
  static const _bucket = 'voice-messages';
  static final _uuid = const Uuid();

  /// Uploads a local audio file to Supabase Storage and returns its public URL.
  static Future<String> uploadRecording(String localFilePath) async {
    final file = File(localFilePath);

    if (!await file.exists()) {
      throw Exception("Recording file not found at $localFilePath");
    }

    final bytes = await file.readAsBytes();
    final fileName = "voice_${_uuid.v4()}.m4a";

    await SupabaseService.client.storage.from(_bucket).uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'audio/m4a',
            upsert: false,
          ),
        );

    final publicUrl =
        SupabaseService.client.storage.from(_bucket).getPublicUrl(fileName);

    return publicUrl;
  }
}