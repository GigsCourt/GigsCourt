import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class ImageService {
  static const String _publicKey = 'public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=';
  static const String _uploadUrl = 'https://upload.imagekit.io/api/v1/files/upload';

  final ImagePicker _picker = ImagePicker();

  Future<File?> pickFromGallery({bool crop = true}) async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (xFile == null) return null;
    if (crop) return _cropImage(File(xFile.path));
    return File(xFile.path);
  }

  Future<File?> takePhoto({bool crop = true}) async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (xFile == null) return null;
    if (crop) return _cropImage(File(xFile.path));
    return File(xFile.path);
  }

  Future<File?> _cropImage(File file) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: const Color(0xFF2D3BA0),
          toolbarWidgetColor: Colors.white,
          backgroundColor: const Color(0xFF121212),
          cropFrameColor: const Color(0xFF2D3BA0),
          hideBottomControls: true,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
        ),
      ],
    );
    return croppedFile != null ? File(croppedFile.path) : null;
  }

  Future<ImageKitUploadResult> uploadToImageKit(File file, String userId, {String folder = '/profile_photos'}) async {
    try {
      // Get a fresh Firebase ID token for authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');
      final idToken = await user.getIdToken(true);

      final authResponse = await http.get(
        Uri.parse('https://ohysatmlieiatzwqwjyt.supabase.co/functions/v1/imagekit-auth'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      );

      if (authResponse.statusCode != 200) {
        throw Exception('Failed to get upload authorization');
      }

      final authData = jsonDecode(authResponse.body);
      final token = authData['token'] as String;
      final expire = authData['expire'] as int;
      final signature = authData['signature'] as String;

      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
      request.fields['publicKey'] = _publicKey;
      request.fields['token'] = token;
      request.fields['expire'] = expire.toString();
      request.fields['signature'] = signature;
      request.fields['fileName'] = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      request.fields['folder'] = folder;
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final uploadResponse = await request.send();
      final responseBody = await uploadResponse.stream.bytesToString();
      final uploadData = jsonDecode(responseBody);

      if (uploadResponse.statusCode == 200) {
        return ImageKitUploadResult(
          url: uploadData['url'],
          fileId: uploadData['fileId'],
        );
      } else {
        throw Exception(uploadData['message'] ?? 'Upload failed');
      }
    } catch (e) {
      rethrow;
    }
  }
}

class ImageKitUploadResult {
  final String url;
  final String fileId;

  ImageKitUploadResult({required this.url, required this.fileId});
}
