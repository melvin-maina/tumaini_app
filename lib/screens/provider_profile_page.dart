import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:mime/mime.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/document_upload_service.dart';
import '../widgets/app_home_action.dart';
import '../widgets/notification_bell_button.dart';

class ProviderProfilePage extends StatefulWidget {
  const ProviderProfilePage({super.key});

  @override
  State<ProviderProfilePage> createState() => _ProviderProfilePageState();
}

class _ProviderProfilePageState extends State<ProviderProfilePage> {
  final AuthService _auth = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _specialtyController;
  late TextEditingController _bioController;

  List<String> _certifications = [];
  List<String> _serviceAreas = [];
  bool _isAvailable = true;
  bool _notificationsEnabled = true;
  bool _jobAlerts = true;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isVerified = false;
  bool _isUploadingDocument = false;
  bool _isSubmittingReapplication = false;
  bool _showReapplyGuidance = false;
  String _providerStatus = 'pending';
  String _verificationNote = '';
  List<Map<String, dynamic>> _documents = <Map<String, dynamic>>[];
  final DocumentUploadService _uploadService = DocumentUploadService();
  final GlobalKey _verificationDocumentsKey = GlobalKey();

  String _normalizeProviderStatus(dynamic rawStatus, bool verified) {
    final status = (rawStatus ?? '').toString().trim().toLowerCase();
    if (status.isNotEmpty) return status;
    return verified ? 'active' : 'pending';
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _specialtyController = TextEditingController();
    _bioController = TextEditingController();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.getCurrentUser();
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['fullName'] ?? '';
          _emailController.text = data['email'] ?? user.email ?? '';
          _phoneController.text = data['phone'] ?? '';
          _specialtyController.text = (data['specialty'] ?? '').toString();
          _bioController.text = data['bio'] ?? '';
          _certifications = List<String>.from(data['certifications'] ?? []);
          _serviceAreas = List<String>.from(data['serviceAreas'] ?? []);
          _documents = <Map<String, dynamic>>[];
          _isAvailable = data['isAvailable'] ?? true;
          _notificationsEnabled = data['notificationsEnabled'] ?? true;
          _jobAlerts = data['jobAlerts'] ?? true;
          _isVerified = data['verified'] ?? false;
          _providerStatus = _normalizeProviderStatus(data['status'], _isVerified);
          _verificationNote = (data['verificationNote'] ?? '').toString();
          _isLoading = false;
        });
        await _loadProviderUploads(
          user.uid,
          legacyDocuments: (data['documents'] as List<dynamic>? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(),
        );
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveChanges() async {
    final user = _auth.getCurrentUser();
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'fullName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'specialty': _specialtyController.text.trim(),
        'bio': _bioController.text.trim(),
        'certifications': _certifications,
        'serviceAreas': _serviceAreas,
        'isAvailable': _isAvailable,
        'notificationsEnabled': _notificationsEnabled,
        'jobAlerts': _jobAlerts,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _addCertification() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Certification'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g., RIBA Chartered Architect',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                setState(() => _certifications.add(value));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _removeCertification(int index) {
    setState(() => _certifications.removeAt(index));
  }

  void _addServiceArea() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Service Area'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g., Phase 1, Westlands',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                setState(() => _serviceAreas.add(value));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _removeServiceArea(int index) {
    setState(() => _serviceAreas.removeAt(index));
  }

  String _profileDisplayName() {
    final name = _nameController.text.trim();
    return name.isEmpty ? 'Service Provider' : name;
  }

  String _profileFirstName() {
    final name = _profileDisplayName();
    return name.split(' ').first;
  }

  String _profileSpecialtyLabel() {
    final specialty = _specialtyController.text.trim();
    return specialty.isEmpty ? 'Specialty not set yet' : specialty;
  }

  Future<void> _createAdminNotification({
    required String type,
    required String title,
    required String message,
    Map<String, dynamic>? extras,
  }) async {
    final currentUser = _auth.getCurrentUser();
    await _firestore.collection('notifications').add({
      'userId': 'admin',
      'audience': 'admin',
      'type': type,
      'title': title,
      'message': message,
      'createdBy': currentUser?.uid ?? '',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...?extras,
    });
  }

  String _readableSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String? _extractUploadedFileUrl(String responseBody) {
    final body = responseBody.trim();
    if (body.isEmpty) return null;

    String? parseAsUrl(dynamic value) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      final uri = Uri.tryParse(text);
      if (uri == null || !uri.hasScheme) return null;
      return text;
    }

    String? parseDriveFileId(dynamic value) {
      final id = value?.toString().trim() ?? '';
      if (id.isEmpty) return null;
      final looksLikeId = RegExp(r'^[a-zA-Z0-9_-]{10,}$').hasMatch(id);
      if (!looksLikeId) return null;
      return 'https://drive.google.com/file/d/$id/view';
    }

    String? findDriveIdInText(String text) {
      final fromPath = RegExp(r'file/d/([a-zA-Z0-9_-]{10,})').firstMatch(text);
      if (fromPath != null) {
        return 'https://drive.google.com/file/d/${fromPath.group(1)!}/view';
      }

      final fromKey = RegExp(
        "(?:fileId|fileID|driveFileId|id)\\s*[:=]\\s*['\\\"]?([a-zA-Z0-9_-]{10,})",
      ).firstMatch(text);
      if (fromKey != null) {
        return 'https://drive.google.com/file/d/${fromKey.group(1)!}/view';
      }
      return null;
    }

    String? extractFromDynamic(dynamic node) {
      if (node == null) return null;

      if (node is Map) {
        final known = parseAsUrl(node['fileUrl']) ??
            parseAsUrl(node['downloadUrl']) ??
            parseAsUrl(node['url']) ??
            parseAsUrl(node['viewUrl']) ??
            parseAsUrl(node['webViewLink']) ??
            parseAsUrl(node['link']) ??
            parseAsUrl(node['fileLink']) ??
            parseDriveFileId(node['fileId']) ??
            parseDriveFileId(node['fileID']) ??
            parseDriveFileId(node['driveFileId']) ??
            parseDriveFileId(node['id']);
        if (known != null) return known;

        for (final value in node.values) {
          final nested = extractFromDynamic(value);
          if (nested != null) return nested;
        }
        return null;
      }

      if (node is Iterable) {
        for (final item in node) {
          final nested = extractFromDynamic(item);
          if (nested != null) return nested;
        }
        return null;
      }

      final text = node.toString().trim();
      if (text.isEmpty) return null;

      final direct = parseAsUrl(text);
      if (direct != null) return direct;

      final idUrl = findDriveIdInText(text);
      if (idUrl != null) return idUrl;

      try {
        final decoded = jsonDecode(text);
        return extractFromDynamic(decoded);
      } catch (_) {
        return null;
      }
    }

    return extractFromDynamic(body);
  }

  String? _extractUploadedFileId(String responseBody) {
    final body = responseBody.trim();
    if (body.isEmpty) return null;

    String? parseDriveFileId(dynamic value) {
      final id = value?.toString().trim() ?? '';
      final looksLikeId = RegExp(r'^[a-zA-Z0-9_-]{10,}$').hasMatch(id);
      return looksLikeId ? id : null;
    }

    String? findDriveIdInText(String text) {
      final fromPath = RegExp(r'file/d/([a-zA-Z0-9_-]{10,})').firstMatch(text);
      if (fromPath != null) return fromPath.group(1);

      final fromKey = RegExp(
        "(?:fileId|fileID|driveFileId|id)\\s*[:=]\\s*['\\\"]?([a-zA-Z0-9_-]{10,})",
      ).firstMatch(text);
      return fromKey?.group(1);
    }

    String? extractFromDynamic(dynamic node) {
      if (node == null) return null;
      if (node is Map) {
        final known = parseDriveFileId(node['fileId']) ??
            parseDriveFileId(node['fileID']) ??
            parseDriveFileId(node['driveFileId']) ??
            parseDriveFileId(node['id']);
        if (known != null) return known;
        for (final value in node.values) {
          final nested = extractFromDynamic(value);
          if (nested != null) return nested;
        }
        return null;
      }
      if (node is Iterable) {
        for (final item in node) {
          final nested = extractFromDynamic(item);
          if (nested != null) return nested;
        }
        return null;
      }

      final text = node.toString().trim();
      if (text.isEmpty) return null;
      final fromText = findDriveIdInText(text);
      if (fromText != null) return fromText;

      try {
        final decoded = jsonDecode(text);
        return extractFromDynamic(decoded);
      } catch (_) {
        return null;
      }
    }

    return extractFromDynamic(body);
  }

  String? _buildDriveDownloadUrl(String? fileId) {
    if (fileId == null || fileId.isEmpty) return null;
    return 'https://drive.google.com/uc?export=download&id=$fileId';
  }

  Future<Map<String, String>?> _promptDocumentDetails({
    required String providerName,
    required String fileName,
  }) async {
    final purposeController = TextEditingController();
    final notesController = TextEditingController();

    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload Document'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  providerName.isEmpty ? fileName : '$providerName\n$fileName',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: purposeController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Purpose',
                    hintText: 'e.g. Business License Renewal',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Additional Notes',
                    hintText: 'Optional context for the admin email',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final purpose = purposeController.text.trim();
                if (purpose.isEmpty) {
                  return;
                }
                Navigator.pop(ctx, <String, String>{
                  'purpose': purpose,
                  'notes': notesController.text.trim(),
                });
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } finally {
      purposeController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _loadProviderUploads(
    String userId, {
    List<Map<String, dynamic>> legacyDocuments = const <Map<String, dynamic>>[],
  }) async {
    try {
      final snapshot = await _firestore
          .collection('uploads')
          .where('userId', isEqualTo: userId)
          .get();

      if (snapshot.docs.isEmpty && legacyDocuments.isNotEmpty) {
        await _migrateLegacyDocumentsToUploads(userId, legacyDocuments);
        final migratedSnapshot = await _firestore
            .collection('uploads')
            .where('userId', isEqualTo: userId)
            .get();
        final migratedUploads = migratedSnapshot.docs
            .map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              return <String, dynamic>{
                ...data,
                'id': doc.id,
                'name': data['fileName'] ?? data['name'] ?? 'document',
                'size': data['size'] ??
                    _readableSize((data['sizeBytes'] as num?)?.toInt() ?? 0),
                'mimeType': data['fileMimeType'] ?? data['mimeType'] ?? '',
              };
            })
            .where((item) => (item['status'] ?? '').toString().toLowerCase() != 'failed')
            .toList();

        if (!mounted) return;
        setState(() {
          _documents = migratedUploads.isNotEmpty ? migratedUploads : legacyDocuments;
        });
        return;
      }

      final uploads = snapshot.docs
          .map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            return <String, dynamic>{
              ...data,
              'id': doc.id,
              'name': data['fileName'] ?? data['name'] ?? 'document',
              'size': data['size'] ??
                  _readableSize((data['sizeBytes'] as num?)?.toInt() ?? 0),
              'mimeType': data['fileMimeType'] ?? data['mimeType'] ?? '',
            };
          })
          .where((item) => (item['status'] ?? '').toString().toLowerCase() != 'failed')
          .toList();

      if (!mounted) return;
      setState(() {
        _documents = uploads.isNotEmpty ? uploads : legacyDocuments;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _documents = legacyDocuments;
      });
    }
  }

  Future<void> _migrateLegacyDocumentsToUploads(
    String userId,
    List<Map<String, dynamic>> legacyDocuments,
  ) async {
    final user = _auth.getCurrentUser();
    final userRef = _firestore.collection('users').doc(userId);
    final batch = _firestore.batch();

    for (final docItem in legacyDocuments) {
      final uploadRef = _firestore.collection('uploads').doc();
      batch.set(uploadRef, {
        'userId': userId,
        'userEmail': _emailController.text.trim().isEmpty
            ? (user?.email ?? '')
            : _emailController.text.trim(),
        'providerName': _nameController.text.trim(),
        'fileName': docItem['name'] ?? 'document',
        'fileMimeType': docItem['mimeType'] ?? '',
        'sizeBytes': (docItem['sizeBytes'] as num?)?.toInt() ?? 0,
        'purpose': docItem['purpose'] ?? '',
        'notes': docItem['notes'] ?? '',
        'status': 'sent',
        'responseBody': docItem['responseBody'] ?? '',
        'fileUrl': docItem['fileUrl'] ?? '',
        'downloadUrl': docItem['downloadUrl'] ?? '',
        'fileId': docItem['fileId'],
        'createdAt': FieldValue.serverTimestamp(),
        'migratedFromLegacy': true,
        'legacyUploadedAt': docItem['uploadedAt'],
      });
    }

    batch.update(userRef, {
      'documents': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<String?> _promptDocumentLink({required String fileName}) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add Document Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upload succeeded for "$fileName", but no shareable link was returned.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Document URL',
                  hintText: 'https://...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                final uri = Uri.tryParse(value);
                if (uri == null || !uri.hasScheme) return;
                Navigator.pop(ctx, value);
              },
              child: const Text('Save Link'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _pickAndUploadDocument() async {
    if (_isUploadingDocument) return;
    final user = _auth.getCurrentUser();
    if (user == null) return;

    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (picked == null) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Could not read file.');
      }

      final mimeType = lookupMimeType(file.name);
      if (mimeType == null) {
        throw Exception('Could not determine file type.');
      }

      final providerName = _nameController.text.trim();
      final details = await _promptDocumentDetails(
        providerName: providerName,
        fileName: file.name,
      );
      if (details == null) return;

      final purpose = (details['purpose'] ?? '').trim();
      final notes = (details['notes'] ?? '').trim();
      if (purpose.isEmpty) {
        throw Exception('Document purpose is required.');
      }

      setState(() => _isUploadingDocument = true);
      final uploaded = await _uploadService.uploadDocument(
        bytes: bytes,
        fileName: file.name,
        mimeType: mimeType,
        userId: user.uid,
        userEmail: user.email ?? '',
        providerName: providerName.isEmpty ? 'Service Provider' : providerName,
        purpose: purpose,
        notes: notes,
      );
      final responseBody = uploaded.responseBody;
      final extractedUrl = uploaded.fileUrl ?? _extractUploadedFileUrl(responseBody);
      final extractedFileId = uploaded.fileId ?? _extractUploadedFileId(responseBody);
      final extractedDownloadUrl =
          uploaded.downloadUrl ?? _buildDriveDownloadUrl(extractedFileId);
      final manualUrl = extractedUrl == null
          ? await _promptDocumentLink(fileName: file.name)
          : null;
      final fileUrl = extractedUrl ?? manualUrl;
      final downloadUrl = extractedDownloadUrl ??
          ((manualUrl != null && manualUrl.trim().isNotEmpty) ? manualUrl : null);
      if (fileUrl == null || fileUrl.trim().isEmpty) {
        throw Exception('No document URL was saved. Please provide a valid link.');
      }
      final parsedFileUrl = Uri.tryParse(fileUrl);
      if (parsedFileUrl == null || !parsedFileUrl.hasScheme) {
        throw Exception('The saved document URL is invalid.');
      }
      if ((downloadUrl == null || downloadUrl.trim().isEmpty) && extractedFileId == null) {
        throw Exception(
          'No downloadable link was found for this file. Please use a shareable direct file link.',
        );
      }

      final docEntry = <String, dynamic>{
        'name': uploaded.fileName,
        'size': _readableSize(uploaded.sizeBytes),
        'sizeBytes': uploaded.sizeBytes,
        'mimeType': uploaded.fileMimeType,
        'providerName': providerName,
        'purpose': purpose,
        'notes': notes,
        'responseBody': responseBody,
        'fileUrl': fileUrl,
        'downloadUrl': downloadUrl,
        'fileId': extractedFileId,
        'expired': false,
        'uploadedAt': DateTime.now().toIso8601String(),
      };

      final uploadRef = await _firestore.collection('uploads').add({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'providerName': providerName,
        'fileName': uploaded.fileName,
        'fileMimeType': uploaded.fileMimeType,
        'sizeBytes': uploaded.sizeBytes,
        'purpose': purpose,
        'notes': notes,
        'status': 'sent',
        'responseBody': responseBody,
        'fileUrl': fileUrl,
        'downloadUrl': downloadUrl,
        'fileId': extractedFileId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final nextDocuments = <Map<String, dynamic>>[
        ..._documents,
        {
          ...docEntry,
          'id': uploadRef.id,
          'status': 'sent',
        },
      ];

      await _createAdminNotification(
        type: 'provider_application_submitted',
        title: 'New provider verification document',
        message:
            '${providerName.isEmpty ? 'A provider' : providerName} uploaded "$purpose" for verification review.',
        extras: {
          'providerId': user.uid,
          'providerName': providerName,
          'fileName': uploaded.fileName,
          'purpose': purpose,
        },
      );

      if (!mounted) return;
      setState(() => _documents = nextDocuments);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document uploaded and sent to admin.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      await _firestore.collection('uploads').add({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'providerName': _nameController.text.trim(),
        'status': 'failed',
        'error': e.toString(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isUploadingDocument = false);
    }
  }

  Future<void> _removeDocument(int index) async {
    final user = _auth.getCurrentUser();
    if (user == null) return;

    final docToRemove = _documents[index];
    final updated = <Map<String, dynamic>>[..._documents]..removeAt(index);
    final uploadId = (docToRemove['id'] ?? '').toString();
    if (uploadId.isNotEmpty) {
      await _firestore.collection('uploads').doc(uploadId).delete();
    } else {
      await _firestore.collection('users').doc(user.uid).update({
        'documents': updated,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (!mounted) return;
    setState(() => _documents = updated);
  }

  Future<void> _showChangePasswordDialog() async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    try {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Change Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New password'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirm password'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Update'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;

      final newPassword = newPasswordController.text.trim();
      final confirmPassword = confirmPasswordController.text.trim();

      if (newPassword.length < 6) {
        throw FirebaseAuthException(
          code: 'weak-password',
          message: 'Password must be at least 6 characters.',
        );
      }

      if (newPassword != confirmPassword) {
        throw FirebaseAuthException(
          code: 'password-mismatch',
          message: 'Passwords do not match.',
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await user.updatePassword(newPassword);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to update password'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    }
  }

  Future<void> _showNotificationSettingsDialog() async {
    var notificationsEnabled = _notificationsEnabled;
    var jobAlerts = _jobAlerts;

    final saved = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Notification Settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: notificationsEnabled,
                    title: const Text('Enable notifications'),
                    onChanged: (value) => setDialogState(() => notificationsEnabled = value),
                  ),
                  SwitchListTile(
                    value: jobAlerts,
                    title: const Text('New assignment alerts'),
                    onChanged: notificationsEnabled
                        ? (value) => setDialogState(() => jobAlerts = value)
                        : null,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!saved) return;

    final user = _auth.getCurrentUser();
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      'notificationsEnabled': notificationsEnabled,
      'jobAlerts': jobAlerts,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    setState(() {
      _notificationsEnabled = notificationsEnabled;
      _jobAlerts = jobAlerts;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notification settings updated'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Log out'),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Log out'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) return;
    await _auth.signOut();
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _scrollToVerificationDocuments({bool openUploadIfEmpty = false}) async {
    setState(() => _showReapplyGuidance = true);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    final targetContext = _verificationDocumentsKey.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.08,
      );
    }

    if (!mounted) return;
    if (openUploadIfEmpty && _documents.isEmpty && !_isUploadingDocument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload your verification documents, then submit for review.'),
          backgroundColor: AppColors.primary,
        ),
      );
      await _pickAndUploadDocument();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Update or review your verification documents, then submit for review.'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Future<void> _reapplyForVerification() async {
    final user = _auth.getCurrentUser();
    if (user == null) return;
    if (_documents.isEmpty) {
      await _scrollToVerificationDocuments(openUploadIfEmpty: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload at least one verification document before re-applying.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmittingReapplication = true);
    try {
      final batch = _firestore.batch();
      final userRef = _firestore.collection('users').doc(user.uid);
      final notificationRef = _firestore.collection('notifications').doc();
      final providerName = _nameController.text.trim();

      batch.update(userRef, {
        'verified': false,
        'status': 'pending',
        'verificationDecision': FieldValue.delete(),
        'verificationNote': FieldValue.delete(),
        'rejectedAt': FieldValue.delete(),
        'resubmittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(notificationRef, {
        'userId': 'admin',
        'audience': 'admin',
        'type': 'provider_application_submitted',
        'title': 'Provider verification re-submitted',
        'message':
            '${providerName.isEmpty ? 'A provider' : providerName} re-submitted their verification for review.',
        'createdBy': user.uid,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'providerId': user.uid,
        'providerName': providerName,
      });
      await batch.commit();

      if (!mounted) return;
      setState(() {
        _isVerified = false;
        _providerStatus = 'pending';
        _verificationNote = '';
        _showReapplyGuidance = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Re-application submitted for review.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to re-apply: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingReapplication = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _specialtyController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isWide = screenWidth >= 768; // ← added this line (fixes the error)
    final padding = isMobile ? 16.0 : 24.0;

    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final surfaceContainer = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final surfaceContainerHigh = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFe8e8ea);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final primaryContainer = AppColors.primary;
    final outline = isDark ? AppColors.textMutedDark : const Color(0xFF737686);
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text('Provider Profile'),
        actions: [
          const AppHomeAction(),
          NotificationBellButton(iconColor: textOnSurfaceVariant),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage(
                _auth.getCurrentUser()?.photoURL ??
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuCfbrkgwr-Y2I-54yVCdPJGOlj54PpOOLttyuf71VKp_7sdJUQ76y1CsPlf4MkQdSETJf5gbT-KePm1YzMJ2gI6f3gPEZ3BOoMuQD_fDLZX6s2ESE3Q0MQcO7LxslFex019sEXU7viqKw4vaYxXDcIGQd8qQU6OeOqRVXBKLLxJ6YSV3wBfOZAv__R9V396627nOngLf7trMonUyva-17c9mjZFlvkSsu2bhN9Qw6ljYHZsNNPnPhbpTgHihX8wFZXuh_NUlRTIigk',
              ),
              onBackgroundImageError: (_, __) {},
            ),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final content = _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
            // Hero Profile Card
             Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: surfaceContainerLowest,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(
                            _auth.getCurrentUser()?.photoURL ??
                                'https://lh3.googleusercontent.com/aida-public/AB6AXuCfbrkgwr-Y2I-54yVCdPJGOlj54PpOOLttyuf71VKp_7sdJUQ76y1CsPlf4MkQdSETJf5gbT-KePm1YzMJ2gI6f3gPEZ3BOoMuQD_fDLZX6s2ESE3Q0MQcO7LxslFex019sEXU7viqKw4vaYxXDcIGQd8qQU6OeOqRVXBKLLxJ6YSV3wBfOZAv__R9V396627nOngLf7trMonUyva-17c9mjZFlvkSsu2bhN9Qw6ljYHZsNNPnPhbpTgHihX8wFZXuh_NUlRTIigk',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 60),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -4,
                        right: -4,
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Photo upload coming soon')),
                            );
                          },
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: primary,
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        TextFormField(
                          controller: _specialtyController,
                          style: TextStyle(
                            fontSize: 15,
                            color: primary,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Add your specialty',
                            hintStyle: TextStyle(
                              color: primary.withOpacity(0.55),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          'Welcome back, ${_profileFirstName()}. Keep your professional details current so admin can assign you faster and with confidence.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : const Color(0xFF434654),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              _isAvailable ? 'Available' : 'Unavailable',
                              style: TextStyle(
                                color: _isAvailable ? AppColors.success : AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Switch(
                              value: _isAvailable,
                              onChanged: (val) => setState(() => _isAvailable = val),
                              activeColor: AppColors.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildLiveRatingBadge(_auth.getCurrentUser()?.uid ?? ''),
                            _buildStatBadge(
                              icon: (_providerStatus == 'rejected')
                                  ? Icons.gpp_bad
                                  : (_isVerified ? Icons.verified : Icons.pending_outlined),
                              label: (_providerStatus == 'rejected')
                                  ? 'Verification rejected'
                                  : (_isVerified ? 'Verified provider' : 'Verification pending'),
                              color: (_providerStatus == 'rejected')
                                  ? AppColors.error
                                  : (_isVerified ? AppColors.success : AppColors.warning),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildVerificationStatusBanner(),
            const SizedBox(height: 24),
            _buildProfessionalSnapshotCard(),
            const SizedBox(height: 24),

            // Bio
            _buildSectionCard(
              title: 'Professional Biography',
              child: TextFormField(
                controller: _bioController,
                maxLines: 5,
                decoration: _providerInputDecoration(
                  hintText:
                      'Tell residents and admins about your experience, service style, and the kinds of jobs you handle best...',
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Certifications
            _buildSectionCard(
              title: 'Certifications & Accreditations',
              action: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _addCertification,
                color: primary,
              ),
              child: Column(
                children: [
                  ..._certifications.asMap().entries.map((e) {
                    final index = e.key;
                    final cert = e.value;
                    return ListTile(
                      leading: const Icon(Icons.verified, color: AppColors.success),
                      title: TextFormField(
                        initialValue: cert,
                        onChanged: (v) => _certifications[index] = v,
                        decoration: _providerInputDecoration(),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () => _removeCertification(index),
                      ),
                    );
                  }),
                  if (_certifications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No certifications added yet',
                        style: TextStyle(color: AppColors.neutral500),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Container(
              key: _verificationDocumentsKey,
              child: _buildSectionCard(
                title: 'Verification Documents',
                action: TextButton.icon(
                  onPressed: _isUploadingDocument ? null : _pickAndUploadDocument,
                  icon: _isUploadingDocument
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(_isUploadingDocument ? 'Uploading...' : 'Upload'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_providerStatus == 'rejected' || _showReapplyGuidance) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Next step',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _documents.isEmpty
                                  ? 'Upload the documents the admin asked for, then submit your application again.'
                                  : 'Review your uploaded documents, replace anything that was rejected if needed, then submit for review.',
                              style: const TextStyle(height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _isUploadingDocument || _isSubmittingReapplication
                                  ? null
                                  : _reapplyForVerification,
                              icon: _isSubmittingReapplication
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.verified_outlined),
                              label: Text(
                                _isSubmittingReapplication
                                    ? 'Submitting...'
                                    : 'Submit for review',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    _documents.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'No documents uploaded yet.',
                              style: TextStyle(color: AppColors.neutral500),
                            ),
                          )
                        : Column(
                        children: _documents.asMap().entries.map((entry) {
                          final index = entry.key;
                          final doc = entry.value;
                          final docName = (doc['name'] ?? 'document').toString();
                          final docSize = (doc['size'] ?? 'Unknown size').toString();
                          final purpose = (doc['purpose'] ?? '').toString();
                          final mime = (doc['mimeType'] ?? '').toString();
                          final isPdf = mime == 'application/pdf' ||
                              docName.toLowerCase().endsWith('.pdf');
                          return ListTile(
                            leading: Icon(
                            isPdf ? Icons.picture_as_pdf : Icons.image,
                            color: AppColors.primary,
                          ),
                            title: Text(
                              docName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              purpose.isEmpty ? docSize : '$purpose • $docSize',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error),
                              onPressed: _isUploadingDocument ? null : () => _removeDocument(index),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Service Areas & Contact
            isWide
                ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildServiceAreasCard()),
                const SizedBox(width: 24),
                Expanded(child: _buildContactCard()),
              ],
            )
                : Column(
              children: [
                _buildServiceAreasCard(),
                const SizedBox(height: 24),
                _buildContactCard(),
              ],
            ),

            const SizedBox(height: 24),
            _buildAccountSettingsCard(),

            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveChanges,
                icon: _isSaving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.save),
                label: Text(
                  _isSaving ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 80),
                    ],
                  ),
                );

          if (isMobile) {
            return content;
          }

          return Row(
            children: [
              _buildDesktopSideNav(context),
              Expanded(child: content),
            ],
          );
        },
      ),
      bottomNavigationBar: isMobile ? _buildBottomNavBar(context) : null,
    );
  }

  Widget _buildDesktopSideNav(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDarkElevated : Colors.white;
    final borderColor =
        isDark ? AppColors.borderDark : const Color(0xFFe2e2e4);

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: surface,
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Provider Menu',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1a1c1d),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _buildDesktopNavTile(
                context,
                icon: Icons.dashboard,
                label: 'Dashboard',
                isSelected: false,
                onTap: () => context.go('/provider-dashboard'),
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.assignment_ind_outlined,
                label: 'New Assignments',
                isSelected: false,
                onTap: () => context.go('/provider-dashboard?tab=0'),
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.build_circle_outlined,
                label: 'Active Jobs',
                isSelected: false,
                onTap: () => context.go('/provider-dashboard?tab=1'),
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.person,
                label: 'Profile',
                isSelected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, Widget? action, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.borderDark : const Color(0xFFE2E2E4);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.borderDark,
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildServiceAreasCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _buildSectionCard(
      title: 'Service Areas',
      action: IconButton(
        icon: Icon(Icons.add_circle, color: AppColors.primary),
        onPressed: _addServiceArea,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _serviceAreas.asMap().entries.map((e) {
          final index = e.key;
          final area = e.value;
          return Chip(
            label: Text(area),
            onDeleted: () => _removeServiceArea(index),
            backgroundColor: isDark ? AppColors.surfaceDarkElevated : AppColors.neutral100,
            deleteIconColor: AppColors.error,
            side: BorderSide(
              color: isDark ? AppColors.borderDark : const Color(0xFFE2E2E4),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContactCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _buildSectionCard(
      title: 'Contact Information',
      child: Column(
        children: [
          _buildReadOnlyField('Email', _emailController.text),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: _providerInputDecoration(labelText: 'Phone Number'),
          ),
        ],
      ),
    );
  }

  InputDecoration _providerInputDecoration({
    String? labelText,
    String? hintText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.borderDark : const Color(0xFFE2E2E4);

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: isDark ? AppColors.surfaceDarkElevated : AppColors.neutral50,
      hintStyle: TextStyle(
        color: isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.primary, width: 1.7),
      ),
    );
  }

  Widget _buildProfessionalSnapshotCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    final items = [
      _buildSnapshotItem(
        icon: Icons.handyman_outlined,
        title: 'Specialty',
        value: _profileSpecialtyLabel(),
      ),
      _buildSnapshotItem(
        icon: Icons.place_outlined,
        title: 'Service Areas',
        value: _serviceAreas.isEmpty ? 'Not added yet' : '${_serviceAreas.length} area${_serviceAreas.length == 1 ? '' : 's'} listed',
      ),
      _buildSnapshotItem(
        icon: Icons.workspace_premium_outlined,
        title: 'Certifications',
        value: _certifications.isEmpty ? 'None added yet' : '${_certifications.length} certification${_certifications.length == 1 ? '' : 's'}',
      ),
      _buildSnapshotItem(
        icon: Icons.upload_file_outlined,
        title: 'Documents',
        value: _documents.isEmpty ? 'No uploads yet' : '${_documents.length} file${_documents.length == 1 ? '' : 's'} uploaded',
      ),
    ];

    return _buildSectionCard(
      title: 'Professional Snapshot',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This is the professional summary admin uses to understand your readiness, coverage, and verification progress.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: textOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: items,
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tips_and_updates_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile quality tip',
                        style: TextStyle(
                          color: textOnSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Complete your specialty, service areas, and verification documents so admins can assign you faster and with more confidence.',
                        style: TextStyle(
                          color: textOnSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.neutral50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textOnSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textOnSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildVerificationStatusBanner() {
    final status = _providerStatus.toLowerCase();
    final note = _verificationNote.trim();

    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String title;
    late final String message;

    if (_isVerified || status == 'active') {
      bg = AppColors.success.withOpacity(0.12);
      fg = AppColors.successStrong;
      icon = Icons.verified;
      title = 'Verified';
      message = 'Your provider account is active.';
    } else if (status == 'rejected') {
      bg = AppColors.error.withOpacity(0.12);
      fg = AppColors.errorStrong;
      icon = Icons.gpp_bad;
      title = 'Rejected';
      message = note.isEmpty
          ? 'Your last verification was rejected. Please update details and re-apply.'
          : 'Rejected reason: $note';
    } else {
      bg = AppColors.warning.withOpacity(0.14);
      fg = AppColors.warningStrong;
      icon = Icons.pending_actions;
      title = 'Pending Verification';
      message = 'Your account is under review. You will get access once approved.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(message, style: TextStyle(color: fg)),
          if (status == 'rejected') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _scrollToVerificationDocuments(openUploadIfEmpty: true),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Update documents'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountSettingsCard() {
    return _buildSectionCard(
      title: 'Account Settings',
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_reset, color: AppColors.primary),
            title: const Text('Change Password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showChangePasswordDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined, color: AppColors.primary),
            title: const Text('Notification Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showNotificationSettingsDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Log Out', style: TextStyle(color: AppColors.error)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildLiveRatingBadge(String providerId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('feedback')
          .where('providerId', isEqualTo: providerId)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        var total = 0.0;
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          total += ((data['rating'] as num?)?.toDouble() ?? 0);
        }
        final average = docs.isEmpty ? 0.0 : total / docs.length;
        return _buildStatBadge(
          icon: Icons.star_rounded,
          label: docs.isEmpty ? 'No ratings yet' : '${average.toStringAsFixed(1)} rating',
          color: AppColors.warningStrong,
        );
      },
    );
  }

  Widget _buildStatBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textSecondaryDark : AppColors.borderDark,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDarkElevated : AppColors.neutral100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(value.isEmpty ? 'Not set' : value),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: surface.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                context,
                icon: Icons.dashboard,
                label: 'Dashboard',
                isSelected: false,
                onTap: () => context.go('/provider-dashboard'),
              ),
              _buildNavItem(
                context,
                icon: Icons.assignment_ind_outlined,
                label: 'New',
                isSelected: false,
                onTap: () => context.go('/provider-dashboard?tab=0'),
              ),
              _buildNavItem(
                context,
                icon: Icons.build_circle_outlined,
                label: 'Active',
                isSelected: false,
                onTap: () => context.go('/provider-dashboard?tab=1'),
              ),
              _buildNavItem(
                context,
                icon: Icons.person,
                label: 'Profile',
                isSelected: true,
                onTap: () {}, // already here
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      BuildContext context, {
        required IconData icon,
        required String label,
        required bool isSelected,
        required VoidCallback onTap,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isSelected ? AppColors.primary : (isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopNavTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isSelected
        ? AppColors.primary.withOpacity(0.12)
        : Colors.transparent;
    final fgColor = isSelected
        ? AppColors.primary
        : (isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: fgColor),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}





