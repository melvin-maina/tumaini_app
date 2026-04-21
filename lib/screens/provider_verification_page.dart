
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/provider_verification_email_service.dart';
import '../theme/app_colors.dart';
import '../utils/export_file_helper.dart';
import '../widgets/admin_navigation_shell.dart';
import '../widgets/app_home_action.dart';

class ProviderVerificationPage extends StatefulWidget {
  const ProviderVerificationPage({
    super.key,
    this.focusProviderId,
    this.returnTo,
  });

  final String? focusProviderId;
  final String? returnTo;

  @override
  State<ProviderVerificationPage> createState() => _ProviderVerificationPageState();
}

class _ProviderVerificationPageState extends State<ProviderVerificationPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ProviderVerificationEmailService _verificationEmailService =
      ProviderVerificationEmailService();
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All Categories';
  String? _selectedProviderId;
  String? _lastAutoOpenedProviderId;

  final List<String> _categories = [
    'All Categories',
    'Electrical',
    'Plumbing',
    'Landscaping',
    'Security',
  ];

  @override
  void initState() {
    super.initState();
    _selectedProviderId = widget.focusProviderId;
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';
    final date = timestamp.toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} d ago';
  }

  Future<void> _createProviderNotification({
    required String providerId,
    required String type,
    required String title,
    required String message,
  }) async {
    await _firestore.collection('notifications').add({
      'userId': providerId,
      'type': type,
      'title': title,
      'message': message,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _logVerificationEmailActivity({
    required String providerId,
    required String providerName,
    required String providerEmail,
    required String decision,
    required String trigger,
    required bool success,
  }) async {
    await _firestore.collection('activities').add({
      'type': 'provider_verification_email',
      'title': success ? 'Verification email sent' : 'Verification email unconfirmed',
      'description':
          '$decision email for $providerName (${providerEmail.isEmpty ? 'no-email' : providerEmail}) via $trigger',
      'providerId': providerId,
      'providerName': providerName,
      'providerEmail': providerEmail,
      'decision': decision,
      'trigger': trigger,
      'success': success,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _currentAdminId(),
    });
  }

  String _verificationEmailTriggerLabel(String trigger) {
    switch (trigger) {
      case 'auto_after_approval':
        return 'Automatic after approval';
      case 'auto_after_rejection':
        return 'Automatic after rejection';
      case 'manual_resend':
        return 'Manual resend';
      default:
        return 'Email event';
    }
  }

  String _currentAdminId() {
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  void _handleBackNavigation() {
    final returnTo = widget.returnTo;
    if (returnTo != null && returnTo.isNotEmpty) {
      context.go(returnTo);
      return;
    }

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/admin-dashboard');
    }
  }

  Future<void> _setUploadStatus({
    required WriteBatch batch,
    required String providerId,
    required String nextStatus,
    String? note,
  }) async {
    final uploadsSnapshot = await _firestore
        .collection('uploads')
        .where('userId', isEqualTo: providerId)
        .get();

    for (final uploadDoc in uploadsSnapshot.docs) {
      final data = uploadDoc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'sent') {
        continue;
      }
      batch.update(uploadDoc.reference, <String, dynamic>{
        'status': nextStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
        if (note != null && note.isNotEmpty) 'reviewNote': note,
      });
    }
  }

  Future<void> _approveProvider({
    required String providerId,
    required String providerName,
    required String providerEmail,
    required bool notificationsEnabled,
    required int documentCount,
  }) async {
    if (documentCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload and review at least one provider document before approval.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Approve Provider'),
            content: Text(
              'Approve $providerName and mark this application as reviewed? The provider will be notified immediately.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Approve'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      final batch = _firestore.batch();
      final userRef = _firestore.collection('users').doc(providerId);
      batch.update(userRef, {
        'verified': true,
        'verifiedAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'verificationDecision': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': _currentAdminId(),
        'verificationNote': FieldValue.delete(),
        'rejectedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _setUploadStatus(
        batch: batch,
        providerId: providerId,
        nextStatus: 'verified',
      );
      await batch.commit();
      await _createProviderNotification(
        providerId: providerId,
        type: 'provider_verified',
        title: 'Provider application approved',
        message:
            'Your provider application has been approved. You can now receive service assignments in Tumaini Estate.',
      );
      final emailSent = notificationsEnabled
          ? await _verificationEmailService.sendVerificationDecisionEmail(
              providerName: providerName,
              providerEmail: providerEmail,
              decision: 'approved',
            )
          : false;
      await _logVerificationEmailActivity(
        providerId: providerId,
        providerName: providerName,
        providerEmail: providerEmail,
        decision: 'approved',
        trigger: 'auto_after_approval',
        success: emailSent,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notificationsEnabled && providerEmail.trim().isNotEmpty
                  ? emailSent
                      ? 'Provider approved, in-app notification sent, and confirmation email sent.'
                      : 'Provider approved and in-app notification sent. Email status could not be confirmed yet.'
                  : 'Provider approved and in-app notification sent.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _rejectProvider({
    required String providerId,
    required String providerName,
    required String providerEmail,
    required bool notificationsEnabled,
  }) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Provider'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add a reason for rejection (required).'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g., Missing valid operating license',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      reasonController.dispose();
      return;
    }

    try {
      final reason = reasonController.text.trim();
      final batch = _firestore.batch();
      final userRef = _firestore.collection('users').doc(providerId);
      batch.update(userRef, {
        'verified': false,
        'status': 'rejected',
        'verificationDecision': 'rejected',
        'verificationNote': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': _currentAdminId(),
        'verifiedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _setUploadStatus(
        batch: batch,
        providerId: providerId,
        nextStatus: 'rejected',
        note: reason,
      );
      await batch.commit();
      await _createProviderNotification(
        providerId: providerId,
        type: 'provider_rejected',
        title: 'Provider application needs changes',
        message: 'Your provider application was not approved. Reason: $reason',
      );
      final emailSent = notificationsEnabled
          ? await _verificationEmailService.sendVerificationDecisionEmail(
              providerName: providerName,
              providerEmail: providerEmail,
              decision: 'rejected',
              rejectionReason: reason,
            )
          : false;
      await _logVerificationEmailActivity(
        providerId: providerId,
        providerName: providerName,
        providerEmail: providerEmail,
        decision: 'rejected',
        trigger: 'auto_after_rejection',
        success: emailSent,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notificationsEnabled && providerEmail.trim().isNotEmpty
                  ? emailSent
                      ? 'Provider rejected, in-app notification sent, and confirmation email sent.'
                      : 'Provider rejected and in-app notification sent. Email status could not be confirmed yet.'
                  : 'Provider rejected and in-app notification sent.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _resendVerificationDecisionEmail({
    required String providerId,
    required String providerName,
    required String providerEmail,
    required String verificationDecision,
    required String verificationNote,
    required bool notificationsEnabled,
  }) async {
    final decision = verificationDecision.trim().toLowerCase();
    if (providerEmail.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This provider does not have an email address saved.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    if (!notificationsEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This provider has email notifications turned off.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    if (decision != 'approved' && decision != 'rejected') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only approved or rejected applications can resend a decision email.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    final emailSent = await _verificationEmailService.sendVerificationDecisionEmail(
      providerName: providerName,
      providerEmail: providerEmail,
      decision: decision,
      rejectionReason: decision == 'rejected' ? verificationNote : null,
    );
    await _logVerificationEmailActivity(
      providerId: providerId,
      providerName: providerName,
      providerEmail: providerEmail,
      decision: decision,
      trigger: 'manual_resend',
      success: emailSent,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          emailSent
              ? 'Decision email resent to $providerEmail.'
              : 'We could not confirm the resend request yet.',
        ),
        backgroundColor: emailSent ? AppColors.success : AppColors.warning,
      ),
    );
  }

  String? _extractDocumentUrl(Map<String, dynamic> data) {
    String? parseAsUrl(dynamic value) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      final uri = Uri.tryParse(text);
      if (uri == null || !uri.hasScheme) return null;
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return null;
      return text;
    }

    String? parseDriveFileId(dynamic value) {
      final id = value?.toString().trim() ?? '';
      if (id.isEmpty) return null;
      final looksLikeId = RegExp(r'^[a-zA-Z0-9_-]{10,}$').hasMatch(id);
      if (!looksLikeId) return null;
      return 'https://drive.google.com/file/d/$id/view';
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
            parseDriveFileId(node['fileId']);
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

      try {
        final decoded = jsonDecode(text);
        return extractFromDynamic(decoded);
      } catch (_) {
        return null;
      }
    }

    return extractFromDynamic(data);
  }

  Future<String?> _resolveDocumentUrl(Map<String, dynamic> doc) async {
    final direct = _extractDocumentUrl(doc);
    return direct;
  }

  String? _extractDocumentFileId(Map<String, dynamic> data) {
    String? parseDriveFileId(dynamic value) {
      final id = value?.toString().trim() ?? '';
      if (id.isEmpty) return null;
      final looksLikeId = RegExp(r'^[a-zA-Z0-9_-]{10,}$').hasMatch(id);
      return looksLikeId ? id : null;
    }

    String? extractFromDynamic(dynamic node) {
      if (node == null) return null;

      if (node is Map) {
        final known = parseDriveFileId(node['fileId']);
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

      try {
        final decoded = jsonDecode(text);
        return extractFromDynamic(decoded);
      } catch (_) {
        return null;
      }
    }

    return extractFromDynamic(data);
  }

  String? _extractDocumentDownloadUrl(Map<String, dynamic> doc) {
    String? parseAsUrl(dynamic value) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      final uri = Uri.tryParse(text);
      if (uri == null || !uri.hasScheme) return null;
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return null;
      return text;
    }

    final explicit = parseAsUrl(doc['downloadUrl']) ??
        parseAsUrl(doc['directDownloadUrl']) ??
        parseAsUrl(doc['fileDownloadUrl']);
    if (explicit != null) return explicit;

    final fileId = _extractDocumentFileId(doc);
    if (fileId != null) {
      return 'https://drive.google.com/uc?export=download&id=$fileId';
    }

    return null;
  }

  Future<bool> _launchWithFallback(Uri uri) async {
    final modes = <LaunchMode>[
      LaunchMode.externalApplication,
      LaunchMode.platformDefault,
      LaunchMode.inAppBrowserView,
    ];
    for (final mode in modes) {
      final launched = await launchUrl(
        uri,
        mode: mode,
        webOnlyWindowName: '_blank',
      );
      if (launched) return true;
    }
    return false;
  }

  Future<void> _openDocument(Map<String, dynamic> doc) async {
    final fileUrl = await _resolveDocumentUrl(doc);
    if (fileUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No document link was found for this file.')),
        );
      }
      return;
    }

    final uri = Uri.tryParse(fileUrl);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid document link format.')),
        );
      }
      return;
    }

    final launched = await _launchWithFallback(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open this document link.')),
      );
    }
  }

  Future<void> _downloadDocument(Map<String, dynamic> doc) async {
    final resolvedUrl = await _resolveDocumentUrl(doc);
    final downloadUrl = _extractDocumentDownloadUrl(doc) ?? resolvedUrl;
    if (downloadUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No downloadable link was found for this file.')),
        );
      }
      return;
    }

    final uri = Uri.tryParse(downloadUrl);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid download link format.')),
        );
      }
      return;
    }

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final fileName = (doc['fileName'] ?? doc['name'] ?? 'document').toString();
      final mimeType = (doc['fileMimeType'] ?? doc['mimeType'] ?? 'application/octet-stream')
          .toString();

      await exportBytesAsFile(
        bytes: response.bodyBytes,
        filename: fileName,
        mimeType: mimeType,
        text: 'Tumaini Estate verification document',
        subject: 'Verification document download',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Prepared $fileName for download'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      final launched = await _launchWithFallback(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to start download for this file.')),
        );
      }
    }
  }
  List<Map<String, dynamic>> _sortUploads(List<Map<String, dynamic>> uploads) {
    final sorted = [...uploads];
    sorted.sort((a, b) {
      final aTimestamp = a['createdAt'];
      final bTimestamp = b['createdAt'];
      if (aTimestamp is Timestamp && bTimestamp is Timestamp) {
        return bTimestamp.compareTo(aTimestamp);
      }
      if (aTimestamp is Timestamp) return -1;
      if (bTimestamp is Timestamp) return 1;
      return 0;
    });
    return sorted;
  }

  List<Map<String, dynamic>> _providerDocumentRecords({
    QuerySnapshot? uploadSnapshot,
    List<Map<String, dynamic>> legacyDocuments = const <Map<String, dynamic>>[],
  }) {
    final uploads = _sortUploads(
      uploadSnapshot?.docs
              .map((doc) => {
                    ...Map<String, dynamic>.from(doc.data() as Map<String, dynamic>),
                    'id': doc.id,
                    'name': (doc.data() as Map<String, dynamic>)['fileName'] ??
                        (doc.data() as Map<String, dynamic>)['name'] ??
                        'document',
                    'size': (doc.data() as Map<String, dynamic>)['size'] ??
                        _readableSize(
                          ((doc.data() as Map<String, dynamic>)['sizeBytes'] as num?)
                                  ?.toInt() ??
                              0,
                        ),
                    'mimeType': (doc.data() as Map<String, dynamic>)['fileMimeType'] ??
                        (doc.data() as Map<String, dynamic>)['mimeType'] ??
                        '',
                  })
              .where((item) => (item['status'] ?? '').toString().toLowerCase() != 'failed')
              .toList() ??
          <Map<String, dynamic>>[],
    );

    return uploads.isNotEmpty ? uploads : legacyDocuments;
  }

  String _formatUploadSubtitle(Map<String, dynamic> upload) {
    final purpose = (upload['purpose'] ?? '').toString().trim();
    final notes = (upload['notes'] ?? '').toString().trim();
    final parts = <String>[
      if (purpose.isNotEmpty) 'Purpose: $purpose',
      if (notes.isNotEmpty) 'Notes: $notes',
    ];
    return parts.isEmpty ? 'No extra details provided.' : parts.join('\n');
  }

  String _readableSize(int bytes) {
    if (bytes <= 0) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Color _uploadStatusColor(String status, Color primary, Color error) {
    switch (status) {
      case 'verified':
        return AppColors.success;
      case 'rejected':
        return error;
      case 'failed':
        return error;
      default:
        return primary;
    }
  }

  List<QueryDocumentSnapshot> _sortProviders(List<QueryDocumentSnapshot> providers) {
    final sorted = [...providers];
    sorted.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aDate = aData['createdAt'] as Timestamp?;
      final bDate = bData['createdAt'] as Timestamp?;
      final aMs = aDate?.millisecondsSinceEpoch ?? 0;
      final bMs = bDate?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    return sorted;
  }

  Color _providerStatusColor({
    required bool isVerified,
    required String providerStatus,
    required Color error,
  }) {
    if (isVerified) return AppColors.success;
    if (providerStatus == 'rejected') return error;
    return AppColors.warningStrong;
  }

  String _providerStatusLabel({
    required bool isVerified,
    required String providerStatus,
  }) {
    if (isVerified) return 'Verified';
    if (providerStatus == 'rejected') return 'Rejected';
    return 'Awaiting Verification';
  }

  String _formatExactDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Not available';
    final date = timestamp.toDate();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }

  Widget _buildUploadsSection({
    required String providerId,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
    required Color surfaceContainerLow,
    required Color primary,
    required Color error,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('uploads')
          .where('userId', isEqualTo: providerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Unable to load upload records.',
              style: TextStyle(color: error),
            ),
          );
        }

        final uploads = _sortUploads(
          snapshot.data?.docs
                  .map((doc) => {
                        ...Map<String, dynamic>.from(
                          doc.data() as Map<String, dynamic>,
                        ),
                        'id': doc.id,
                      })
                  .toList() ??
              <Map<String, dynamic>>[],
        );

        final pendingUploads = uploads
            .where((upload) => (upload['status'] ?? '').toString() == 'sent')
            .toList();

        if (uploads.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No upload records found for this provider yet.',
              style: TextStyle(color: textOnSurfaceVariant),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pendingUploads.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${pendingUploads.length} pending upload${pendingUploads.length == 1 ? '' : 's'} awaiting review',
                  style: TextStyle(
                    color: AppColors.warningStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ...uploads.map((upload) {
              final fileName = (upload['fileName'] ?? upload['name'] ?? 'document')
                  .toString();
              final status = (upload['status'] ?? 'sent').toString().toLowerCase();
              final createdAt = upload['createdAt'] as Timestamp?;
              final mimeType = (upload['fileMimeType'] ?? upload['mimeType'] ?? '')
                  .toString();

              return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.attach_file, color: primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textOnSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatUploadSubtitle(upload),
                              style: TextStyle(color: textOnSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (mimeType.isNotEmpty) mimeType,
                                if (createdAt != null) 'Uploaded ${_timeAgo(createdAt)}',
                              ].join(' | '),
                              style: TextStyle(
                                fontSize: 12,
                                color: textOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _uploadStatusColor(status, primary, error).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _uploadStatusColor(status, primary, error),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => _openDocument(upload),
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Open',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _downloadDocument(upload),
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Download',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
            }),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Helper method for responsive padding
  double _getResponsivePadding(double screenWidth) {
    if (screenWidth < 300) return 8;
    if (screenWidth < 400) return 12;
    if (screenWidth < 600) return 16;
    if (screenWidth < 900) return 20;
    return 24;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);
    final error = isDark ? AppColors.error : const Color(0xFFba1a1a);

    return AdminNavigationShell(
      title: 'Provider Verification',
      selectedSection: AdminNavSection.verifications,
      actions: [
        const AppHomeAction(),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.filter_list, size: 18),
          label: const Text('Filter'),
          style: OutlinedButton.styleFrom(side: BorderSide(color: outlineVariant)),
        ),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.sort, size: 18),
          label: const Text('Latest First'),
          style: OutlinedButton.styleFrom(side: BorderSide(color: outlineVariant)),
        ),
      ],
      body: SingleChildScrollView(
        padding: EdgeInsets.all(_getResponsivePadding(screenWidth)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Application Management', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: primary)),
            const SizedBox(height: 4),
            Text('Provider Verification', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textOnSurface)),
            const SizedBox(height: 8),
            Text('Review and verify professional service providers.', style: TextStyle(fontSize: 15, color: textOnSurfaceVariant)),
            const SizedBox(height: 32),

            // Filter bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
              child: isMobile
                  ? Column(
                children: [
                  _buildSearchField(surfaceContainerLowest),
                  const SizedBox(height: 12),
                  _buildCategoryDropdown(surfaceContainerLowest),
                ],
              )
                  : Row(
                children: [
                  Expanded(flex: 3, child: _buildSearchField(surfaceContainerLowest)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildCategoryDropdown(surfaceContainerLowest)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('users').where('role', isEqualTo: 'provider').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading providers: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  );
                }

                var providers = _sortProviders(snapshot.data?.docs ?? <QueryDocumentSnapshot>[]);
                final query = _searchController.text.trim().toLowerCase();
                if (query.isNotEmpty) {
                  providers = providers.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['fullName'] ?? '').toString().toLowerCase();
                    final email = (data['email'] ?? '').toString().toLowerCase();
                    final company = (data['companyName'] ?? '').toString().toLowerCase();
                    return name.contains(query) || email.contains(query) || company.contains(query);
                  }).toList();
                }
                if (_selectedCategory != 'All Categories') {
                  providers = providers.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final specialty = (data['specialty'] ?? '').toString().toLowerCase();
                    return specialty.contains(_selectedCategory.toLowerCase());
                  }).toList();
                }

                if (providers.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No providers match the current filters.'),
                    ),
                  );
                }

                final containsSelected = _selectedProviderId != null &&
                    providers.any((doc) => doc.id == _selectedProviderId);
            final selectedDoc = containsSelected
                    ? providers.firstWhere((doc) => doc.id == _selectedProviderId)
                    : providers.first;
                if (!containsSelected) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedProviderId = selectedDoc.id);
                  });
                }
                if (isMobile &&
                    widget.focusProviderId != null &&
                    selectedDoc.id == widget.focusProviderId &&
                    _lastAutoOpenedProviderId != selectedDoc.id) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _lastAutoOpenedProviderId = selectedDoc.id;
                    _showProviderDetailsSheet(selectedDoc);
                  });
                }

                return isMobile
                    ? _buildProviderListPanel(
                        providers: providers,
                        selectedId: selectedDoc.id,
                        textOnSurface: textOnSurface,
                        textOnSurfaceVariant: textOnSurfaceVariant,
                        surfaceContainerLow: surfaceContainerLow,
                        primary: primary,
                        error: error,
                        isMobile: true,
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: _buildProviderListPanel(
                              providers: providers,
                              selectedId: selectedDoc.id,
                              textOnSurface: textOnSurface,
                              textOnSurfaceVariant: textOnSurfaceVariant,
                              surfaceContainerLow: surfaceContainerLow,
                              primary: primary,
                              error: error,
                              isMobile: false,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 8,
                            child: _buildProviderDetailPanel(
                              doc: selectedDoc,
                              textOnSurface: textOnSurface,
                              textOnSurfaceVariant: textOnSurfaceVariant,
                              surfaceContainerLow: surfaceContainerLow,
                              outlineVariant: outlineVariant,
                              primary: primary,
                              error: error,
                              screenWidth: screenWidth,
                            ),
                          ),
                        ],
                      );
              },
            ),

            const SizedBox(height: 48),

            // Bottom cards
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildPolicyCard()),
                const SizedBox(width: 24),
                Expanded(child: _buildAutomatedCard()),
              ],
            ),
            const SizedBox(height: 48),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: outlineVariant.withOpacity(0.2)))),
              child: isMobile
                  ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('© 2024 Tumaini Estate Management | Provider Verification Portal', style: TextStyle(fontSize: 12, color: textOnSurfaceVariant)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: const [TextButton(onPressed: null, child: Text('Compliance Rules')), TextButton(onPressed: null, child: Text('System Logs')), TextButton(onPressed: null, child: Text('Privacy Policy'))]),
                ],
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('© 2024 Tumaini Estate Management | Provider Verification Portal', style: TextStyle(fontSize: 12, color: textOnSurfaceVariant)),
                  Wrap(spacing: 8, children: const [TextButton(onPressed: null, child: Text('Compliance Rules')), TextButton(onPressed: null, child: Text('System Logs')), TextButton(onPressed: null, child: Text('Privacy Policy'))]),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderListPanel({
    required List<QueryDocumentSnapshot> providers,
    required String selectedId,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
    required Color surfaceContainerLow,
    required Color primary,
    required Color error,
    required bool isMobile,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rowBaseColor = isDark ? const Color(0xFF1f232a) : Colors.white;
    final rowSelectedColor = isDark
        ? AppColors.primary.withOpacity(0.28)
        : AppColors.primary.withOpacity(0.10);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Awaiting Review',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textOnSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${providers.length} provider applications',
            style: TextStyle(color: textOnSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...providers.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isVerified = data['verified'] == true;
            final providerStatus = (data['status'] ?? 'pending').toString().toLowerCase();
            final statusColor = _providerStatusColor(
              isVerified: isVerified,
              providerStatus: providerStatus,
              error: error,
            );
            final selected = doc.id == selectedId;
            final fullName = (data['fullName'] ?? 'Unknown').toString();
            final specialty = (data['specialty'] ?? 'General').toString();
            final createdAt = data['createdAt'] as Timestamp?;
            final focused = doc.id == widget.focusProviderId;

            return InkWell(
              onTap: () {
                setState(() => _selectedProviderId = doc.id);
                if (isMobile) {
                  _showProviderDetailsSheet(doc);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected ? rowSelectedColor : rowBaseColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: focused
                        ? primary
                        : selected
                        ? primary
                        : (isDark ? Colors.white.withOpacity(0.06) : Colors.transparent),
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: primary.withOpacity(0.16),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(_getIcon(specialty), color: _getColor(specialty, primary), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textOnSurface,
                            ),
                          ),
                          Text(
                            '$specialty | ${_timeAgo(createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: textOnSurfaceVariant),
                          ),
                          if (focused)
                            const Text(
                              'Focused from notification',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _providerStatusLabel(
                          isVerified: isVerified,
                          providerStatus: providerStatus,
                        ),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _showProviderDetailsSheet(QueryDocumentSnapshot doc) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);
    final primary = AppColors.primary;
    final error = isDark ? AppColors.error : const Color(0xFFba1a1a);
    final screenWidth = MediaQuery.of(context).size.width;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.6,
          maxChildSize: 0.96,
          expand: false,
          builder: (ctx, controller) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                controller: controller,
                child: _buildProviderDetailPanel(
                  doc: doc,
                  textOnSurface: textOnSurface,
                  textOnSurfaceVariant: textOnSurfaceVariant,
                  surfaceContainerLow: surfaceContainerLow,
                  outlineVariant: outlineVariant,
                  primary: primary,
                  error: error,
                  screenWidth: screenWidth,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProviderDetailPanel({
    required QueryDocumentSnapshot doc,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
    required Color surfaceContainerLow,
    required Color outlineVariant,
    required Color primary,
    required Color error,
    required double screenWidth,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = doc.data() as Map<String, dynamic>;
    final providerId = doc.id;
    final fullName = (data['fullName'] ?? 'Unknown').toString();
    final companyName = (data['companyName'] ?? '$fullName Services').toString();
    final email = (data['email'] ?? '').toString();
    final notificationsEnabled = data['notificationsEnabled'] != false;
    final phone = (data['phone'] ?? '—').toString();
    final specialty = (data['specialty'] ?? 'General').toString();
    final isVerified = data['verified'] == true;
    final providerStatus = (data['status'] ?? 'pending').toString().toLowerCase();
    final verificationDecision = (data['verificationDecision'] ?? '').toString();
    final verificationNote = (data['verificationNote'] ?? '').toString().trim();
    final serviceAreas = (data['serviceAreas'] as List<dynamic>? ?? [])
        .map((area) => area.toString().trim())
        .where((area) => area.isNotEmpty)
        .toList();
    final documents = (data['documents'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final createdAt = data['createdAt'] as Timestamp?;
    final reviewedAt = data['reviewedAt'] as Timestamp?;
    final verifiedAt = data['verifiedAt'] as Timestamp?;
    final rejectedAt = data['rejectedAt'] as Timestamp?;
    final statusColor = _providerStatusColor(
      isVerified: isVerified,
      providerStatus: providerStatus,
      error: error,
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1d2128) : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_getIcon(specialty), color: _getColor(specialty, primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companyName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textOnSurface,
                        ),
                      ),
                      Text(
                        '$fullName | Registered ${_timeAgo(createdAt)}',
                        style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _providerStatusLabel(
                      isVerified: isVerified,
                      providerStatus: providerStatus,
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(Icons.mail_outline, email),
                const SizedBox(height: 10),
                _buildInfoRow(Icons.phone_outlined, phone),
                const SizedBox(height: 10),
                _buildInfoRow(
                  Icons.location_on_outlined,
                  serviceAreas.isNotEmpty
                      ? 'Service Areas: ${serviceAreas.join(', ')}'
                      : 'Service Areas: Not specified',
                ),
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('uploads')
                      .where('userId', isEqualTo: providerId)
                      .snapshots(),
                  builder: (context, uploadSnapshot) {
                    final effectiveDocuments = _providerDocumentRecords(
                      uploadSnapshot: uploadSnapshot.data,
                      legacyDocuments: documents,
                    );
                    return _buildInfoRow(
                      Icons.folder_outlined,
                      'Submitted documents: ${effectiveDocuments.length}',
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Review Summary',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textOnSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Decision: ${verificationDecision.isEmpty ? 'Pending' : verificationDecision[0].toUpperCase()}${verificationDecision.isEmpty ? '' : verificationDecision.substring(1)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: textOnSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Reviewed at: ${_formatExactDate(reviewedAt)}',
                        style: TextStyle(color: textOnSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Approved at: ${_formatExactDate(verifiedAt)}',
                        style: TextStyle(color: textOnSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Rejected at: ${_formatExactDate(rejectedAt)}',
                        style: TextStyle(color: textOnSurfaceVariant),
                      ),
                      if (verificationNote.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Admin note: $verificationNote',
                          style: TextStyle(
                            color: providerStatus == 'rejected'
                                ? error
                                : textOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildVerificationEmailActivitySection(
                  providerId: providerId,
                  textOnSurface: textOnSurface,
                  textOnSurfaceVariant: textOnSurfaceVariant,
                  surfaceContainerLow: surfaceContainerLow,
                  primary: primary,
                  error: error,
                ),
                if (verificationDecision == 'approved' || verificationDecision == 'rejected') ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _resendVerificationDecisionEmail(
                        providerId: providerId,
                        providerName: fullName,
                        providerEmail: email,
                        verificationDecision: verificationDecision,
                        verificationNote: verificationNote,
                        notificationsEnabled: notificationsEnabled,
                      ),
                      icon: const Icon(Icons.outgoing_mail),
                      label: Text(
                        verificationDecision == 'approved'
                            ? 'Resend Approval Email'
                            : 'Resend Rejection Email',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'Verification Documents',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textOnSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('uploads')
                      .where('userId', isEqualTo: providerId)
                      .snapshots(),
                  builder: (context, uploadSnapshot) {
                    final effectiveDocuments = _providerDocumentRecords(
                      uploadSnapshot: uploadSnapshot.data,
                      legacyDocuments: documents,
                    );
                    if (effectiveDocuments.isEmpty) {
                      return Text(
                        'No documents attached.',
                        style: TextStyle(color: textOnSurfaceVariant),
                      );
                    }

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: effectiveDocuments.map((docItem) {
                        final docName = (docItem['name'] ?? 'document').toString();
                        final size = (docItem['size'] ?? 'Unknown').toString();
                        final expired = docItem['expired'] == true;
                        return InkWell(
                          onTap: () => _openDocument(docItem),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: screenWidth < 520 ? double.infinity : 220,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: expired
                                    ? AppColors.error.withOpacity(0.4)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  expired ? Icons.warning_amber : Icons.description_outlined,
                                  color: expired ? AppColors.error : primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        docName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: textOnSurface,
                                        ),
                                      ),
                                      Text(
                                        '$size | ${expired ? 'Expired' : 'Valid'}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: textOnSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      GestureDetector(
                                        onTap: () => _downloadDocument(docItem),
                                        child: Text(
                                          'Download',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Text(
                  'Uploaded Records',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textOnSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                _buildUploadsSection(
                  providerId: providerId,
                  textOnSurface: textOnSurface,
                  textOnSurfaceVariant: textOnSurfaceVariant,
                  surfaceContainerLow: surfaceContainerLow,
                  primary: primary,
                  error: error,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: outlineVariant.withOpacity(0.2))),
            ),
            child: isVerified
                ? Text(
                    'This provider has already been verified.',
                    style: TextStyle(color: AppColors.successStrong, fontWeight: FontWeight.w600),
                  )
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton(
                        onPressed: () => _rejectProvider(
                          providerId: providerId,
                          providerName: fullName,
                          providerEmail: email,
                          notificationsEnabled: notificationsEnabled,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: error,
                          side: BorderSide(color: error),
                        ),
                        child: const Text('Reject Application'),
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('uploads')
                            .where('userId', isEqualTo: providerId)
                            .snapshots(),
                        builder: (context, uploadSnapshot) {
                          final effectiveDocuments = _providerDocumentRecords(
                            uploadSnapshot: uploadSnapshot.data,
                            legacyDocuments: documents,
                          );
                          return ElevatedButton.icon(
                            onPressed: () => _approveProvider(
                              providerId: providerId,
                              providerName: fullName,
                              providerEmail: email,
                              notificationsEnabled: notificationsEnabled,
                              documentCount: effectiveDocuments.length,
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Approve Provider'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(Color fillColor) {
    return Container(
      height: 48,
      decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Search by name, email, or company...',
          prefixIcon: Icon(Icons.search),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildVerificationEmailActivitySection({
    required String providerId,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
    required Color surfaceContainerLow,
    required Color primary,
    required Color error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email History',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textOnSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('activities')
              .where('type', isEqualTo: 'provider_verification_email')
              .where('providerId', isEqualTo: providerId)
              .orderBy('createdAt', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Email activity could not be loaded right now.',
                  style: TextStyle(color: textOnSurfaceVariant),
                ),
              );
            }

            if (!snapshot.hasData) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Loading email activity...',
                      style: TextStyle(color: textOnSurfaceVariant),
                    ),
                  ],
                ),
              );
            }

            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'No verification email activity yet.',
                  style: TextStyle(color: textOnSurfaceVariant),
                ),
              );
            }

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: docs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final activityDoc = entry.value;
                  final data = activityDoc.data() as Map<String, dynamic>;
                  final success = data['success'] == true;
                  final decision = (data['decision'] ?? '').toString();
                  final trigger = (data['trigger'] ?? '').toString();
                  final recipientEmail = (data['providerEmail'] ?? '').toString().trim();
                  final createdAt = data['createdAt'] as Timestamp?;
                  final statusColor = success ? AppColors.success : error;
                  final decisionLabel = decision.isEmpty
                      ? 'Decision email'
                      : '${decision[0].toUpperCase()}${decision.substring(1)} email';

                  return Padding(
                    padding: EdgeInsets.only(bottom: index == docs.length - 1 ? 0 : 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Icon(
                            success
                                ? Icons.mark_email_read_outlined
                                : Icons.mark_email_unread_outlined,
                            color: statusColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$decisionLabel • ${success ? 'Sent' : 'Unconfirmed'}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textOnSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _verificationEmailTriggerLabel(trigger),
                                style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                              ),
                              if (recipientEmail.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  recipientEmail,
                                  style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                _formatExactDate(createdAt),
                                style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(Color fillColor) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
          onChanged: (value) => setState(() => _selectedCategory = value!),
        ),
      ),
    );
  }

  Widget _buildPolicyCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColors.primary;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: isDark ? AppColors.surfaceDarkElevated : Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quality Assurance Policy', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textOnSurface)),
          const SizedBox(height: 12),
          Text('All providers must maintain a minimum 4.2-star rating. Verification checks are performed annually.', style: TextStyle(fontSize: 14, color: textOnSurfaceVariant)),
          const SizedBox(height: 24),
          Row(
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('98%', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primary)), Text('Success Rate', style: TextStyle(fontSize: 12, color: textOnSurfaceVariant))]),
              const SizedBox(width: 48),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('24h', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primary)), Text('Avg. Review Time', style: TextStyle(fontSize: 12, color: textOnSurfaceVariant))]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutomatedCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
          const SizedBox(height: 16),
          const Text('Automated Screening', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          const Text('Our system automatically flags expired licenses and missing certificates.', style: TextStyle(fontSize: 14, color: AppColors.primaryTintLight)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? AppColors.textSecondaryDark : AppColors.borderDark;
    final textColor = isDark ? Colors.white : const Color(0xFF1a1c1d);
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: textColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  IconData _getIcon(String spec) {
    switch (spec.toLowerCase()) {
      case 'plumbing': return Icons.plumbing;
      case 'electrical': return Icons.electrical_services;
      case 'landscaping': return Icons.nature_people;
      case 'security': return Icons.security;
      default: return Icons.handyman;
    }
  }

  Color _getColor(String spec, Color primary) {
    switch (spec.toLowerCase()) {
      case 'plumbing': return Colors.blue;
      case 'electrical': return AppColors.warning;
      case 'landscaping': return AppColors.success;
      case 'security': return AppColors.accent;
      default: return primary;
    }
  }
}
