import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_exception.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../../core/services/image_compression_service.dart';

class PinataUploadResult {
  const PinataUploadResult({
    required this.cid,
    required this.logoUrl,
    required this.fileName,
    required this.mimeType,
  });

  final String cid;
  final String logoUrl;
  final String fileName;
  final String mimeType;
}

class PinataUploadException implements Exception {
  const PinataUploadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Client-side Pinata upload orchestration. Secrets stay on the server.
abstract class PinataUploadService {
  Future<PinataUploadResult> uploadBusinessLogo({
    required String businessId,
    required CompressedImage image,
    void Function(double progress)? onProgress,
  });

  Future<PinataUploadResult> uploadExpenseReceipt({
    required String businessId,
    required CompressedImage image,
    void Function(double progress)? onProgress,
  });

  Future<PinataUploadResult> uploadFeedbackAttachment({
    required String businessId,
    required CompressedImage image,
    void Function(double progress)? onProgress,
  });
}

/// Uploads via Firebase callables (Pinata secrets live there), with Vercel fallback.
class FirebasePinataUploadService implements PinataUploadService {
  FirebasePinataUploadService({
    FirebaseFunctions? functions,
    AuthenticatedApiClient? apiClient,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? httpClient,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _api = apiClient ?? AuthenticatedApiClient(),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _http = httpClient ?? http.Client();

  final FirebaseFunctions _functions;
  final AuthenticatedApiClient _api;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final http.Client _http;

  @override
  Future<PinataUploadResult> uploadBusinessLogo({
    required String businessId,
    required CompressedImage image,
    void Function(double progress)? onProgress,
  }) =>
      _uploadImage(
        businessId: businessId,
        image: image,
        purpose: 'business_logo',
        onProgress: onProgress,
        persistLogoOnBusiness: true,
      );

  @override
  Future<PinataUploadResult> uploadExpenseReceipt({
    required String businessId,
    required CompressedImage image,
    void Function(double progress)? onProgress,
  }) =>
      _uploadImage(
        businessId: businessId,
        image: image,
        purpose: 'expense_receipt',
        onProgress: onProgress,
        persistLogoOnBusiness: false,
      );

  @override
  Future<PinataUploadResult> uploadFeedbackAttachment({
    required String businessId,
    required CompressedImage image,
    void Function(double progress)? onProgress,
  }) =>
      _uploadImage(
        businessId: businessId,
        image: image,
        purpose: 'feedback_attachment',
        onProgress: onProgress,
        persistLogoOnBusiness: false,
        allowFirebaseFallback: false,
      );

  Future<PinataUploadResult> _uploadImage({
    required String businessId,
    required CompressedImage image,
    required String purpose,
    void Function(double progress)? onProgress,
    required bool persistLogoOnBusiness,
    bool allowFirebaseFallback = true,
  }) async {
    if (_auth.currentUser == null) {
      throw const PinataUploadException(
        'Your session expired. Please sign in again.',
      );
    }

    onProgress?.call(0.08);
    PinataUploadResult? uploaded;
    Object? primaryError;

    // Prefer Vercel (always reachable on free tier). Fall back to Firebase callables.
    try {
      uploaded = await _uploadViaVercel(
        businessId: businessId,
        image: image,
        purpose: purpose,
        onProgress: onProgress,
      );
    } catch (error) {
      primaryError = error;
    }

    if (uploaded == null && allowFirebaseFallback) {
      try {
        uploaded = await _uploadViaFirebase(
          businessId: businessId,
          image: image,
          onProgress: onProgress,
        );
      } catch (fallbackError) {
        throw PinataUploadException(
          _friendlyMessage(primaryError) ??
              _friendlyMessage(fallbackError) ??
              'The image could not be uploaded. Please try again.',
        );
      }
    }

    if (uploaded == null) {
      throw PinataUploadException(
        _friendlyMessage(primaryError) ??
            'The image could not be uploaded. Please try again.',
      );
    }

    onProgress?.call(0.9);
    if (persistLogoOnBusiness) {
      await _firestore.collection('businesses').doc(businessId).set(
        <String, Object?>{
          'logoUrl': uploaded.logoUrl,
          'logoCid': uploaded.cid,
          'logoFileName': uploaded.fileName,
          'logoMimeType': uploaded.mimeType,
          'logoUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    onProgress?.call(1);
    return uploaded;
  }

  Future<PinataUploadResult> _uploadViaFirebase({
    required String businessId,
    required CompressedImage image,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.15);
    final sessionCallable = _functions.httpsCallable(
      'createPinataUploadUrl',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final sessionResponse = await sessionCallable.call(<String, dynamic>{
      'businessId': businessId,
      'fileName': image.fileName,
      'mimeType': image.mimeType,
      'fileSize': image.bytes.lengthInBytes,
    });
    final session = _asStringKeyedMap(sessionResponse.data);
    final uploadSessionId = session['uploadSessionId'] as String?;
    final uploadUrl = session['uploadUrl'] as String?;
    final gatewayBaseUrl = (session['gatewayBaseUrl'] as String?)?.replaceAll(
      RegExp(r'/$'),
      '',
    );
    final fileName = session['fileName'] as String? ?? image.fileName;
    final mimeType = session['mimeType'] as String? ?? image.mimeType;

    onProgress?.call(0.35);

    if (uploadSessionId != null && uploadSessionId.isNotEmpty) {
      final proxyCallable = _functions.httpsCallable(
        'uploadBusinessLogoViaProxy',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      final proxyResponse = await proxyCallable.call(<String, dynamic>{
        'businessId': businessId,
        'uploadSessionId': uploadSessionId,
        'base64Data': base64Encode(image.bytes),
      });
      final pinned = _asStringKeyedMap(proxyResponse.data);
      return _resultFromMap(pinned, fallbackFileName: fileName, fallbackMime: mimeType);
    }

    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const PinataUploadException(
        'Image upload is not configured yet. Please try again later.',
      );
    }

    final cid = await _uploadToSignedUrl(
      uploadUrl: uploadUrl,
      bytes: image.bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    if (cid == null || cid.isEmpty || gatewayBaseUrl == null) {
      throw const PinataUploadException(
        'The image could not be uploaded. Your previous business image has not been changed.',
      );
    }
    onProgress?.call(0.75);
    final gateway = (gatewayBaseUrl).replaceAll(RegExp(r'/$'), '');
    final base = gateway.replaceFirst(RegExp(r'/ipfs$', caseSensitive: false), '');
    return PinataUploadResult(
      cid: cid,
      logoUrl: '$base/ipfs/$cid',
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  Future<PinataUploadResult> _uploadViaVercel({
    required String businessId,
    required CompressedImage image,
    required String purpose,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.2);
    late final Map<String, dynamic> uploaded;
    try {
      uploaded = await _api.postJson(
        '/api/pinata/upload-url',
        body: <String, dynamic>{
          'businessId': businessId,
          'fileName': image.fileName,
          'mimeType': image.mimeType,
          'fileSize': image.bytes.lengthInBytes,
          'purpose': purpose,
          'fileBase64': base64Encode(image.bytes),
        },
        timeout: const Duration(seconds: 60),
      );
    } on ApiException catch (error) {
      throw PinataUploadException(error.message);
    }
    onProgress?.call(0.75);
    return _resultFromMap(
      uploaded,
      fallbackFileName: image.fileName,
      fallbackMime: image.mimeType,
    );
  }

  Future<String?> _uploadToSignedUrl({
    required String uploadUrl,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final uri = Uri.parse(uploadUrl);
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      )
      ..fields['network'] = 'public';

    final streamed = await _http.send(request).timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      // Some Pinata signed URLs expect a raw PUT body instead of multipart.
      final put = await _http
          .put(
            uri,
            headers: <String, String>{'Content-Type': mimeType},
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (put.statusCode < 200 || put.statusCode >= 300) {
        throw PinataUploadException(
          'The image could not be uploaded (${streamed.statusCode}).',
        );
      }
      return _extractCid(put.body) ?? _extractCid(body);
    }
    return _extractCid(body);
  }

  PinataUploadResult _resultFromMap(
    Map<String, dynamic> data, {
    required String fallbackFileName,
    required String fallbackMime,
  }) {
    final cid = data['cid'] as String?;
    final logoUrl = data['logoUrl'] as String?;
    if (cid == null || cid.isEmpty || logoUrl == null || logoUrl.isEmpty) {
      throw const PinataUploadException(
        'The image could not be uploaded. Your previous business image has not been changed.',
      );
    }
    return PinataUploadResult(
      cid: cid,
      logoUrl: logoUrl,
      fileName: data['fileName'] as String? ?? fallbackFileName,
      mimeType: data['mimeType'] as String? ?? fallbackMime,
    );
  }

  Map<String, dynamic> _asStringKeyedMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw const PinataUploadException(
      'The image could not be uploaded. Please try again.',
    );
  }

  String? _extractCid(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final data = map['data'];
      if (data is Map) {
        final nested = Map<String, dynamic>.from(data);
        final nestedCid = nested['cid'] as String? ?? nested['IpfsHash'] as String?;
        if (nestedCid != null && nestedCid.isNotEmpty) return nestedCid;
      }
      return map['cid'] as String? ?? map['IpfsHash'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _friendlyMessage(Object? error) {
    if (error == null) return null;
    if (error is PinataUploadException) return error.message;
    if (error is ApiException) return error.message;
    if (error is FirebaseFunctionsException) {
      return error.message?.trim().isNotEmpty == true
          ? error.message
          : 'Image upload failed. Please try again.';
    }
    return null;
  }
}

/// Backward-compatible alias.
typedef VercelPinataUploadService = FirebasePinataUploadService;

final pinataUploadServiceProvider = Provider<PinataUploadService>(
  (ref) => FirebasePinataUploadService(),
);
