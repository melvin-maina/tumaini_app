import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../widgets/app_home_action.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _selectedFilter = 'all';

  bool _isAdminNotification(Map<String, dynamic> data, String userId) {
    final target = (data['userId'] ?? '').toString();
    final audience = (data['audience'] ?? '').toString().toLowerCase();
    return target == userId || target == 'admin' || audience == 'admin';
  }

  bool _matchesFilter(Map<String, dynamic> data, String role) {
    if (_selectedFilter == 'all') return true;

    final type = (data['type'] ?? '').toString();
    final unreadOnly = _selectedFilter == 'unread';
    if (unreadOnly) {
      return data['isRead'] != true;
    }

    const requestTypes = {
      'request_submitted',
      'request_assigned',
      'request_accepted',
      'request_arrival_updated',
      'request_in_progress',
      'request_completed',
      'request_completed_admin',
      'request_declined',
      'provider_declined_assignment',
    };
    const providerTypes = {
      'provider_application_submitted',
      'provider_verified',
      'provider_rejected',
      'provider_assigned',
    };
    const feedbackTypes = {'feedback_received'};

    if (_selectedFilter == 'requests') {
      return requestTypes.contains(type);
    }
    if (_selectedFilter == 'providers') {
      return providerTypes.contains(type);
    }
    if (_selectedFilter == 'feedback') {
      return feedbackTypes.contains(type);
    }

    if (role == 'admin') return true;
    return true;
  }

  List<Map<String, String>> _filtersForRole(String role) {
    if (role == 'admin') {
      return const [
        {'id': 'all', 'label': 'All'},
        {'id': 'unread', 'label': 'Unread'},
        {'id': 'requests', 'label': 'Requests'},
        {'id': 'providers', 'label': 'Providers'},
        {'id': 'feedback', 'label': 'Feedback'},
      ];
    }

    return const [
      {'id': 'all', 'label': 'All'},
      {'id': 'unread', 'label': 'Unread'},
      {'id': 'requests', 'label': 'Requests'},
    ];
  }

  Widget _buildFilterChips(String role, bool isDark) {
    final filters = _filtersForRole(role);
    final selectedColor = AppColors.primary;
    final unselectedBackground =
        isDark ? AppColors.surfaceDarkElevated : const Color(0xFFeceff3);
    final unselectedText =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final id = filter['id']!;
          final selected = _selectedFilter == id;
          return ChoiceChip(
            label: Text(filter['label']!),
            selected: selected,
            onSelected: (_) => setState(() => _selectedFilter = id),
            selectedColor: selectedColor.withOpacity(0.14),
            backgroundColor: unselectedBackground,
            side: BorderSide(
              color: selected ? selectedColor.withOpacity(0.35) : Colors.transparent,
            ),
            labelStyle: TextStyle(
              color: selected ? selectedColor : unselectedText,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          );
        },
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Just now';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  List<MapEntry<String, String>> _detailFieldsForNotification(
    String type,
    Map<String, dynamic> data,
  ) {
    final fields = <MapEntry<String, String>>[];

    void addField(String label, dynamic value) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) {
        fields.add(MapEntry(label, text));
      }
    }

    switch (type) {
      case 'feedback_received':
        addField('From Resident', data['residentName']);
        addField('To Provider', data['providerName']);
        addField('Service', data['serviceType']);
        addField('Unit', data['unit']);
        addField('Rating', data['rating'] != null ? '${data['rating']}/5' : '');
        addField('Comment', data['comment']);
        break;
      case 'request_assigned':
        addField('Resident', data['residentName']);
        addField('Service', data['serviceType']);
        addField('Expected Arrival', data['expectedArrivalWindow']);
        addField('Assigned By', data['assignedByAdminName']);
        break;
      case 'provider_assigned':
        addField('Provider', data['providerName']);
        addField('Service', data['serviceType']);
        addField('Expected Arrival', data['expectedArrivalWindow']);
        break;
      case 'request_accepted':
        addField('Provider', data['providerName']);
        addField('Service', data['serviceType']);
        addField('Unit', data['location'] ?? data['unit']);
        break;
      case 'request_in_progress':
        addField('Provider', data['providerName']);
        addField('Service', data['serviceType']);
        addField('Unit', data['location'] ?? data['unit']);
        break;
      case 'request_completed':
        addField('Provider', data['providerName']);
        addField('Service', data['serviceType']);
        addField('Unit', data['location'] ?? data['unit']);
        break;
      case 'request_completed_admin':
        addField('Provider', data['providerName']);
        addField('Resident', data['residentName']);
        addField('Service', data['serviceType']);
        addField('Unit', data['location'] ?? data['unit']);
        break;
      case 'request_declined':
        addField('Provider', data['providerName']);
        addField('Service', data['serviceType']);
        addField('Unit', data['location'] ?? data['unit']);
        addField('Reason', data['reason']);
        break;
      case 'provider_verified':
        addField('Status', 'Approved');
        addField('Provider', data['providerName']);
        addField('Email', data['providerEmail']);
        break;
      case 'provider_rejected':
        addField('Status', 'Rejected');
        addField('Provider', data['providerName']);
        addField('Email', data['providerEmail']);
        addField('Reason', data['reason'] ?? data['verificationNote']);
        break;
      case 'provider_declined_assignment':
        addField('Provider', data['providerName']);
        addField('Resident', data['residentName']);
        addField('Service', data['serviceType']);
        addField('Unit', data['location'] ?? data['unit']);
        addField('Reason', data['reason']);
        break;
      case 'request_submitted':
        addField('Resident', data['residentName']);
        addField('Service', data['serviceType']);
        addField('Urgency', data['urgency']);
        addField('Unit', data['unit'] ?? data['location']);
        break;
      case 'support_ticket_submitted':
        addField('Category', data['category']);
        addField('Subject', data['subject']);
        addField('Unit', data['unit']);
        addField('Phone', data['phone']);
        addField('Description', data['description']);
        addField('Submitted By', data['createdByEmail']);
        break;
      case 'provider_application_submitted':
        addField('Provider', data['providerName']);
        addField('Email', data['providerEmail']);
        addField('Specialty', data['specialty']);
        addField('Status', data['status']);
        break;
      default:
        addField('Details', data['message']);
        break;
    }

    addField('Recorded', _formatTimestamp(data['createdAt'] as Timestamp?));
    return fields;
  }

  IconData _detailIconForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'from resident':
      case 'resident':
        return Icons.person_outline;
      case 'to provider':
      case 'provider':
        return Icons.engineering_outlined;
      case 'service':
        return Icons.build_circle_outlined;
      case 'unit':
        return Icons.home_work_outlined;
      case 'rating':
        return Icons.star_outline;
      case 'comment':
      case 'reason':
      case 'details':
        return Icons.notes_outlined;
      case 'urgency':
        return Icons.priority_high;
      case 'category':
        return Icons.category_outlined;
      case 'subject':
        return Icons.subject_outlined;
      case 'phone':
        return Icons.phone_outlined;
      case 'description':
        return Icons.notes_outlined;
      case 'submitted by':
        return Icons.alternate_email_outlined;
      case 'email':
        return Icons.mail_outline;
      case 'specialty':
        return Icons.handyman_outlined;
      case 'status':
        return Icons.info_outline;
      case 'recorded':
        return Icons.schedule_outlined;
      default:
        return Icons.label_outline;
    }
  }

  Color _detailValueColor(String label) {
    switch (label.toLowerCase()) {
      case 'rating':
        return AppColors.accent;
      case 'urgency':
        return AppColors.warningStrong;
      case 'status':
        return AppColors.info;
      case 'recorded':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  bool _shouldHighlightValue(String label) {
    switch (label.toLowerCase()) {
      case 'rating':
      case 'urgency':
      case 'status':
        return true;
      default:
        return false;
    }
  }

  String _adminPreviewMessage(String type, Map<String, dynamic> data, String fallback) {
    switch (type) {
      case 'feedback_received':
        final resident = (data['residentName'] ?? 'Resident').toString();
        final provider = (data['providerName'] ?? 'Provider').toString();
        final rating = data['rating'] != null ? '${data['rating']}/5' : 'feedback';
        final service = (data['serviceType'] ?? 'service').toString();
        return '$resident rated $provider $rating for $service';
      case 'request_completed_admin':
        final provider = (data['providerName'] ?? 'Provider').toString();
        final resident = (data['residentName'] ?? 'Resident').toString();
        final service = (data['serviceType'] ?? 'service').toString();
        return '$provider completed $service for $resident';
      case 'provider_declined_assignment':
        final provider = (data['providerName'] ?? 'Provider').toString();
        final resident = (data['residentName'] ?? 'Resident').toString();
        final service = (data['serviceType'] ?? 'service').toString();
        return '$provider declined $service for $resident';
      case 'request_submitted':
        final resident = (data['residentName'] ?? 'Resident').toString();
        final service = (data['serviceType'] ?? 'service').toString();
        final urgency = (data['urgency'] ?? '').toString().trim();
        return urgency.isEmpty
            ? '$resident submitted a $service request'
            : '$resident submitted a $service request ($urgency)';
      case 'provider_application_submitted':
        final provider = (data['providerName'] ?? 'Provider').toString();
        final specialty = (data['specialty'] ?? '').toString().trim();
        return specialty.isEmpty
            ? '$provider submitted a provider application'
            : '$provider submitted a $specialty application';
      case 'support_ticket_submitted':
        final category = (data['category'] ?? 'Support').toString();
        final subject = (data['subject'] ?? data['message'] ?? 'New support ticket').toString();
        return '$category ticket: $subject';
      default:
        return fallback;
    }
  }

  Future<void> _showAdminNotificationDetails(
    BuildContext context, {
    required Map<String, dynamic> data,
    required String type,
    required String title,
    required String message,
    required String role,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final fields = _detailFieldsForNotification(type, data);
    final iconColor = _iconColorForType(type);
    final icon = _iconForType(type);
    final badgeBackground =
        isDark ? iconColor.withOpacity(0.18) : iconColor.withOpacity(0.12);
    final useDialog = MediaQuery.of(context).size.width >= 900;
    final requestId = (data['requestId'] ?? '').toString();
    final canLeaveFeedback = role == 'resident' && type == 'request_completed' && requestId.isNotEmpty;

    Widget detailContent(BuildContext modalContext, {bool showHandle = false}) {
      return SafeArea(
        child: Container(
          width: useDialog ? 620 : null,
          margin: EdgeInsets.all(useDialog ? 0 : 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHandle)
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: muted.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                if (showHandle) const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: iconColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: badgeBackground,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  type.replaceAll('_', ' ').toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: iconColor,
                                  ),
                                ),
                              ),
                              if (type == 'request_completed_admin' ||
                                  type == 'feedback_received' ||
                                  type == 'provider_declined_assignment')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: badgeBackground,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    type == 'request_completed_admin'
                                        ? 'COMPLETED'
                                        : type == 'feedback_received'
                                            ? 'FEEDBACK'
                                            : 'DECLINED',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: iconColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (message.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDarkElevated
                          : const Color(0xFFF7F8FB),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(color: muted, height: 1.4),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ...fields.map((field) {
                  final detailIcon = _detailIconForLabel(field.key);
                  final highlightValue = _shouldHighlightValue(field.key);
                  final valueColor = _detailValueColor(field.key);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDarkElevated
                          : const Color(0xFFF7F8FB),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: iconColor.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(detailIcon, size: 18, color: iconColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                field.key,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (highlightValue)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: valueColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    field.value.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: valueColor,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  field.value,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (canLeaveFeedback) ...[
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(modalContext);
                            if (context.mounted) {
                              context.push('/feedback', extra: requestId);
                            }
                          },
                          child: const Text('Leave Feedback'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.pop(modalContext),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (useDialog) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: detailContent(dialogContext),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => detailContent(sheetContext, showHandle: true),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'provider_verified':
        return Icons.verified_outlined;
      case 'provider_rejected':
        return Icons.rule_folder_outlined;
      case 'request_submitted':
        return Icons.receipt_long_outlined;
      case 'provider_application_submitted':
        return Icons.verified_user_outlined;
      case 'request_accepted':
        return Icons.handshake_outlined;
      case 'request_in_progress':
        return Icons.build_circle_outlined;
      case 'request_assigned':
      case 'provider_assigned':
        return Icons.assignment_ind_outlined;
      case 'request_completed':
      case 'request_completed_admin':
        return Icons.task_alt_outlined;
      case 'feedback_received':
        return Icons.reviews_outlined;
      case 'support_ticket_submitted':
        return Icons.support_agent_outlined;
      case 'request_declined':
      case 'provider_declined_assignment':
        return Icons.assignment_late_outlined;
      default:
        return Icons.notifications_none_outlined;
    }
  }

  Color _iconColorForType(String type) {
    switch (type) {
      case 'provider_verified':
      case 'request_accepted':
      case 'request_in_progress':
      case 'request_completed':
      case 'request_completed_admin':
        return AppColors.success;
      case 'feedback_received':
      case 'provider_application_submitted':
        return AppColors.accent;
      case 'support_ticket_submitted':
        return AppColors.primary;
      case 'provider_rejected':
      case 'request_declined':
      case 'provider_declined_assignment':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _markAllAsRead(String userId, String role) async {
    final firestore = FirebaseFirestore.instance;
    final snapshot = role == 'admin'
        ? await firestore.collection('notifications').where('isRead', isEqualTo: false).get()
        : await firestore
            .collection('notifications')
            .where('userId', isEqualTo: userId)
            .where('isRead', isEqualTo: false)
            .get();

    final unread = role == 'admin'
        ? snapshot.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _isAdminNotification(data, userId);
          }).toList()
        : snapshot.docs;

    if (unread.isEmpty) return;

    final batch = firestore.batch();
    for (final doc in unread) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _markOneAsRead(DocumentReference reference) async {
    await reference.update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> _currentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return (doc.data()?['role'] ?? '').toString().toLowerCase();
  }

  String? _routeForNotification({
    required String type,
    required String role,
    required Map<String, dynamic> data,
  }) {
    final requestId = (data['requestId'] ?? '').toString();
    final providerId =
        (data['providerId'] ?? data['targetProviderId'] ?? data['subjectProviderId'] ?? '')
            .toString();

    switch (type) {
      case 'provider_verified':
      case 'provider_rejected':
        return role == 'provider'
            ? '/provider-dashboard'
            : providerId.isNotEmpty
                ? '/provider-verification?providerId=$providerId&returnTo=/notifications'
                : '/provider-verification?returnTo=/notifications';
      case 'request_submitted':
        return role == 'admin'
            ? requestId.isNotEmpty
                ? '/request-assignment?requestId=$requestId&returnTo=/notifications'
                : '/request-assignment?returnTo=/notifications'
            : requestId.isNotEmpty
                ? '/request-tracking?requestId=$requestId&returnTo=/notifications'
                : '/request-tracking?returnTo=/notifications';
      case 'provider_application_submitted':
        return role == 'admin'
            ? providerId.isNotEmpty
                ? '/provider-verification?providerId=$providerId&returnTo=/notifications'
                : '/provider-verification?returnTo=/notifications'
            : '/notifications';
      case 'request_assigned':
        return role == 'provider'
            ? '/provider-dashboard'
            : requestId.isNotEmpty
                ? '/request-assignment?requestId=$requestId&returnTo=/notifications'
                : '/request-assignment?returnTo=/notifications';
      case 'provider_assigned':
      case 'request_accepted':
      case 'request_in_progress':
      case 'request_completed':
      case 'request_declined':
        return role == 'resident'
            ? requestId.isNotEmpty
                ? '/request-tracking?requestId=$requestId&returnTo=/notifications'
                : '/request-tracking?returnTo=/notifications'
            : '/notifications';
      case 'provider_declined_assignment':
        return role == 'admin'
            ? requestId.isNotEmpty
                ? '/request-assignment?requestId=$requestId&returnTo=/notifications'
                : '/request-assignment?returnTo=/notifications'
            : '/notifications';
      case 'request_completed_admin':
      case 'feedback_received':
        return role == 'admin' ? '/reports' : '/notifications';
      case 'support_ticket_submitted':
        return role == 'admin' ? '/help-support' : '/notifications';
      default:
        return null;
    }
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    QueryDocumentSnapshot doc,
    bool isRead,
  ) async {
    if (!isRead) {
      await _markOneAsRead(doc.reference);
    }

    final data = doc.data() as Map<String, dynamic>;
    final type = (data['type'] ?? '').toString();
    final title = (data['title'] ?? 'Notification').toString();
    final message = (data['message'] ?? '').toString();

    if (context.mounted) {
      await _showAdminNotificationDetails(
        context,
        data: data,
        type: type,
        title: title,
        message: message,
        role: await _currentUserRole(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceCard = isDark ? AppColors.surfaceDarkElevated : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text('Notifications'),
        actions: [
          const AppHomeAction(),
          if (userId.isNotEmpty)
            FutureBuilder<String>(
              future: _currentUserRole(),
              builder: (context, snapshot) {
                final role = snapshot.data ?? '';
                return TextButton(
                  onPressed: () async {
                    await _markAllAsRead(userId, role);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('All notifications marked as read.'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  },
                  child: const Text('Mark All Read'),
                );
              },
            ),
        ],
      ),
      body: userId.isEmpty
          ? const Center(child: Text('Please log in to view notifications.'))
          : FutureBuilder<String>(
              future: _currentUserRole(),
              builder: (context, snapshot) {
                final role = snapshot.data ?? '';
                final stream = role == 'admin'
                    ? FirebaseFirestore.instance.collection('notifications').snapshots()
                    : FirebaseFirestore.instance
                        .collection('notifications')
                        .where('userId', isEqualTo: userId)
                        .snapshots();

                return StreamBuilder<QuerySnapshot>(
                  stream: stream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Could not load notifications right now.',
                          style: TextStyle(color: textOnSurfaceVariant),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final visible =
                          role == 'admin' ? _isAdminNotification(data, userId) : true;
                      return visible && _matchesFilter(data, role);
                    }).toList();
                    docs.sort((a, b) {
                      final aData = a.data() as Map<String, dynamic>;
                      final bData = b.data() as Map<String, dynamic>;
                      final aCreatedAt = aData['createdAt'] as Timestamp?;
                      final bCreatedAt = bData['createdAt'] as Timestamp?;
                      final aMs = aCreatedAt?.millisecondsSinceEpoch ?? 0;
                      final bMs = bCreatedAt?.millisecondsSinceEpoch ?? 0;
                      return bMs.compareTo(aMs);
                    });
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'No notifications yet.',
                          style: TextStyle(color: textOnSurfaceVariant),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        const SizedBox(height: 12),
                        _buildFilterChips(role, isDark),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final type = (data['type'] ?? '').toString();
                              final title = (data['title'] ?? 'Notification').toString();
                              final message = (data['message'] ?? '').toString();
                              final previewMessage = role == 'admin'
                                  ? _adminPreviewMessage(type, data, message)
                                  : message;
                              final isRead = data['isRead'] == true;
                              final createdAt = data['createdAt'] as Timestamp?;
                              final iconColor = _iconColorForType(type);

                              return Material(
                                color: surfaceCard,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () async {
                                    await _handleNotificationTap(context, doc, isRead);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isRead
                                            ? Colors.transparent
                                            : AppColors.primary.withOpacity(0.18),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: iconColor.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(_iconForType(type), color: iconColor),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w700,
                                                        color: textOnSurface,
                                                      ),
                                                    ),
                                                  ),
                                                  if (!isRead)
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: const BoxDecoration(
                                                        color: AppColors.primary,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              if (previewMessage.isNotEmpty)
                                                Text(
                                                  previewMessage,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: textOnSurfaceVariant,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _formatTimestamp(createdAt),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: textOnSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}
