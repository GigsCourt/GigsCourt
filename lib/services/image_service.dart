import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ImageService {
  static const String _publicKey = 'public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=';
  static const String _uploadUrl = 'https://upload.imagekit.io/api/v1/files/upload';

  final ImagePicker _picker = ImagePicker();

  // Pick from gallery
  Future<File?> pickFromGallery() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    return xFile != null ? File(xFile.path) : null;
  }

  // Take photo with camera
  Future<File?> takePhoto() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1024,
    );
    return xFile != null ? File(xFile.path) : null;
  }

  // Upload to ImageKit via our Supabase Edge Function
  Future<ImageKitUploadResult> uploadToImageKit(File file, String userId) async {
    try {
      // Get auth params from our edge function
      final authResponse = await http.get(
        Uri.parse('https://ohysatmlieiatzwqwjyt.supabase.co/functions/v1/imagekit-auth'),
        headers: {
          'Authorization': 'Bearer ${userId}',
        },
      );

      if (authResponse.statusCode != 200) {
        throw Exception('Failed to get upload authorization');
      }

      final authData = jsonDecode(authResponse.body);
      final token = authData['token'];
      final expire = authData['expire'].toString();
      final signature = authData['signature'];

      // Upload file to ImageKit
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
      request.fields['publicKey'] = _publicKey;
      request.fields['token'] = token;
      request.fields['expire'] = expire;
      request.fields['signature'] = signature;
      request.fields['fileName'] = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      request.fields['folder'] = '/profile_photos';
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
