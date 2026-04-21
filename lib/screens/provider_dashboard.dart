import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/app_home_action.dart';
import '../widgets/notification_bell_button.dart';
// import '../models/service_request_model.dart'; // Uncomment if needed

class ProviderDashboard extends StatefulWidget {
  const ProviderDashboard({
    super.key,
    this.initialWorkQueueTab = 0,
  });

  final int initialWorkQueueTab;

  @override
  State<ProviderDashboard> createState() => _ProviderDashboardState();
}

class _ProviderDashboardState extends State<ProviderDashboard> {
  final AuthService _auth = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _workQueueSectionKey = GlobalKey();
  final List<String> _arrivalWindowOptions = const [
    'In 15 minutes',
    'In 30 minutes',
    'In 45 minutes',
    'In 1 hour',
    'This afternoon',
    'Tomorrow morning',
  ];

  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int _selectedNavIndex = 0;
  int _selectedWorkQueueTab = 0;

  String get _providerStatus {
    final raw = (_userData?['status'] ?? '').toString().trim().toLowerCase();
    if (raw.isNotEmpty) return raw;
    return _userData?['verified'] == true ? 'active' : 'pending';
  }

  bool get _canOperateAsProvider {
    return _userData?['verified'] == true && _providerStatus == 'active';
  }

  String get _verificationNote {
    return (_userData?['verificationNote'] ?? '').toString();
  }

  String _normalizedRequestStatus(dynamic rawStatus) {
    final status = (rawStatus ?? '').toString().trim().toLowerCase();
    if (status == 'in progress') return 'inprogress';
    return status;
  }

  void _showVerificationBlockedMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your provider account is not active yet.'),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedWorkQueueTab = widget.initialWorkQueueTab == 1 ? 1 : 0;
    _selectedNavIndex = widget.initialWorkQueueTab == 1 ? 2 : 0;
    _loadUserData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.getCurrentUser();
      if (user != null) {
        final data = await _auth.getUserData(user.uid);
        if (mounted) {
          setState(() {
            _userData = data;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading provider data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';
    final date = timestamp.toDate();
    return '${date.month}/${date.day}/${date.year}';
  }

  int _calculateTotalEarned(List<QueryDocumentSnapshot> docs) {
    var total = 0.0;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final amount = (data['amount'] ??
              data['price'] ??
              data['cost'] ??
              data['fee'] ??
              data['total']) as num?;
      if (amount != null) {
        total += amount.toDouble();
      }
    }
    return total.round();
  }

  String _providerDisplayName() {
    return (_userData?['fullName'] ?? 'Your provider').toString();
  }

  String _providerFirstName() {
    final fullName = _providerDisplayName().trim();
    if (fullName.isEmpty) return 'Provider';
    return fullName.split(' ').first;
  }

  String _providerSpecialtyLabel() {
    final specialty = (_userData?['specialty'] ?? '').toString().trim();
    if (specialty.isEmpty) return 'Service Provider';
    return specialty[0].toUpperCase() + specialty.substring(1);
  }

  String _availabilityLabel() {
    return (_userData?['isAvailable'] ?? true) == true ? 'Available today' : 'Currently unavailable';
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollToWorkQueue() async {
    final context = _workQueueSectionKey.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  void _handleDashboardTap() {
    if (!mounted) return;
    setState(() => _selectedNavIndex = 0);
    _scrollToTop();
  }

  void _selectWorkQueueTab(int tabIndex) {
    if (!mounted) return;
    setState(() {
      _selectedWorkQueueTab = tabIndex == 1 ? 1 : 0;
      _selectedNavIndex = tabIndex == 1 ? 2 : 1;
    });
    _scrollToWorkQueue();
  }

  Widget _buildOverviewHero(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDeep.withOpacity(0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Provider Workspace',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Colors.white.withOpacity(0.78),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Jambo, ${_providerFirstName()}!',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              'Manage new assignments, keep residents updated, and stay on top of your verification and availability from one place.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Colors.white.withOpacity(0.88),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeroBadge(
                icon: Icons.handyman_outlined,
                label: _providerSpecialtyLabel(),
              ),
              _buildHeroBadge(
                icon: (_userData?['isAvailable'] ?? true) == true
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline,
                label: _availabilityLabel(),
              ),
              _buildHeroBadge(
                icon: _canOperateAsProvider ? Icons.verified : Icons.pending_actions,
                label: _canOperateAsProvider ? 'Verified account active' : 'Verification in review',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final surfaceCard = isDark ? AppColors.surfaceDarkElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFE2E2E4),
        ),
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
          _buildSectionHeader(
            overline: 'Shortcuts',
            title: 'Quick Actions',
            subtitle: 'Handle the most common provider tasks from one place.',
            textOnSurface: textOnSurface,
            textOnSurfaceVariant:
                isDark ? AppColors.textSecondaryDark : const Color(0xFF434654),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 760;
              final availabilityLabel = (_userData?['isAvailable'] ?? true) == true
                  ? 'Set Unavailable'
                  : 'Set Available';

              final actionButtons = <Widget>[
                OutlinedButton.icon(
                  onPressed: () => context.go('/provider-profile'),
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Open Profile'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/notifications'),
                  icon: const Icon(Icons.notifications_none_outlined),
                  label: const Text('Notifications'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final user = _auth.getCurrentUser();
                    if (user == null) return;
                    final nextValue = !((_userData?['isAvailable'] ?? true) == true);
                    await _firestore.collection('users').doc(user.uid).update({
                      'isAvailable': nextValue,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    if (mounted) {
                      setState(() {
                        _userData = {
                          ...?_userData,
                          'isAvailable': nextValue,
                        };
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            nextValue
                                ? 'You are now available for assignments.'
                                : 'You are now marked unavailable.',
                          ),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.toggle_on_outlined),
                  label: Text(availabilityLabel),
                ),
              ];

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actionButtons.length; i++) ...[
                      SizedBox(width: double.infinity, child: actionButtons[i]),
                      if (i != actionButtons.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  for (var i = 0; i < actionButtons.length; i++) ...[
                    Expanded(child: actionButtons[i]),
                    if (i != actionButtons.length - 1) const SizedBox(width: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: AppColors.primary),
      label: Text(label),
      onPressed: onTap,
      labelStyle: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: AppColors.primary.withOpacity(0.08),
      side: BorderSide(color: AppColors.primary.withOpacity(0.18)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _buildOperationalSnapshot(BuildContext context, String userId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 420;

    final cards = [
      _buildMetricCard(
        title: 'Availability',
        value: (_userData?['isAvailable'] ?? true) == true ? 'Open' : 'Paused',
        subtitle: _availabilityLabel(),
        icon: (_userData?['isAvailable'] ?? true) == true
            ? Icons.toggle_on_outlined
            : Icons.toggle_off_outlined,
        accent: (_userData?['isAvailable'] ?? true) == true
            ? AppColors.success
            : AppColors.warning,
      ),
      StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('requests')
            .where('assignedProviderId', isEqualTo: userId)
            .where('status', isEqualTo: 'assigned')
            .snapshots(),
        builder: (context, snapshot) {
          final count = snapshot.data?.docs.length ?? 0;
          return _buildMetricCard(
            title: 'New Assignments',
            value: '$count',
            subtitle: count == 1 ? 'needs your response' : 'need your response',
            icon: Icons.assignment_ind_outlined,
            accent: AppColors.primary,
          );
        },
      ),
      StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('requests')
            .where('assignedProviderId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final active = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _normalizedRequestStatus(data['status']) == 'inprogress';
          }).length;
          return _buildMetricCard(
            title: 'Active Jobs',
            value: '$active',
            subtitle: active == 1 ? 'job underway' : 'jobs underway',
            icon: Icons.build_circle_outlined,
            accent: AppColors.accent,
          );
        },
      ),
      StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('feedback')
            .where('providerId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          var total = 0.0;
          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            total += ((data['rating'] as num?)?.toDouble() ?? 0);
          }
          final average = docs.isEmpty ? 0.0 : total / docs.length;
          return _buildMetricCard(
            title: 'Average Rating',
            value: docs.isEmpty ? 'New' : average.toStringAsFixed(1),
            subtitle: docs.isEmpty ? 'no reviews yet' : '${docs.length} review${docs.length == 1 ? '' : 's'}',
            icon: Icons.star_rounded,
            accent: AppColors.warningStrong,
          );
        },
      ),
    ];

    if (isCompact) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i != cards.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return GridView.count(
      crossAxisCount: screenWidth < 1100 ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: screenWidth < 720 ? 1.2 : 1.55,
      children: cards,
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceCard = isDark ? AppColors.surfaceDarkElevated : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedHeight = constraints.maxHeight.isFinite;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              if (hasBoundedHeight)
                const Spacer()
              else
                const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: textOnSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: textOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader({
    required String overline,
    required String title,
    required String subtitle,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          overline,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textOnSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: textOnSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActionRequiredPanel(BuildContext context, String userId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceCard = isDark ? AppColors.surfaceDarkElevated : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('requests')
          .where('assignedProviderId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final newAssignments = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _normalizedRequestStatus(data['status']) == 'assigned';
        }).length;
        final activeJobs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _normalizedRequestStatus(data['status']) == 'inprogress';
        }).length;

        final headline = !_canOperateAsProvider
            ? 'Complete your verification and profile details to start taking jobs.'
            : newAssignments > 0
                ? 'You have $newAssignments new assignment${newAssignments == 1 ? '' : 's'} waiting for a response.'
                : activeJobs > 0
                    ? 'You currently have $activeJobs active job${activeJobs == 1 ? '' : 's'} to keep updated.'
                    : 'You are caught up for now. Stay available for the next assignment.';

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surfaceCard,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Action Required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textOnSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                headline,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: textOnSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 760;
                  final pills = <Widget>[
                    _buildActionPill('New assignments', '$newAssignments'),
                    _buildActionPill('Active jobs', '$activeJobs'),
                    _buildActionPill('Availability', (_userData?['isAvailable'] ?? true) == true ? 'Open' : 'Paused'),
                  ];

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < pills.length; i++) ...[
                          pills[i],
                          if (i != pills.length - 1) const SizedBox(height: 10),
                        ],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      for (var i = 0; i < pills.length; i++) ...[
                        Expanded(child: pills[i]),
                        if (i != pills.length - 1) const SizedBox(width: 10),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionPill(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.primary,
          ),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: label),
          ],
        ),
      ),
    );
  }

  Future<void> _adjustProviderTaskCount(String providerId, int delta) async {
    final providerRef = _firestore.collection('users').doc(providerId);
    final providerSnap = await providerRef.get();
    final providerData = providerSnap.data() ?? <String, dynamic>{};
    final current = ((providerData['currentTaskCount'] as num?)?.toInt() ?? 0);
    final next = (current + delta).clamp(0, 9999);
    await providerRef.update({
      'currentTaskCount': next,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _createWorkflowNotification({
    required String userId,
    required String requestId,
    required String type,
    required String title,
    required String message,
    Map<String, dynamic>? extras,
  }) async {
    if (userId.trim().isEmpty) return;

    await _firestore.collection('notifications').add({
      'userId': userId,
      'requestId': requestId,
      'type': type,
      'title': title,
      'message': message,
      'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...?extras,
    });
  }

  Future<void> _createAdminNotification({
    required String requestId,
    required String type,
    required String title,
    required String message,
    Map<String, dynamic>? extras,
  }) async {
    await _firestore.collection('notifications').add({
      'userId': 'admin',
      'audience': 'admin',
      'requestId': requestId,
      'type': type,
      'title': title,
      'message': message,
      'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...?extras,
    });
  }

  Future<void> _acceptRequest(String requestId) async {
    if (!_canOperateAsProvider) {
      _showVerificationBlockedMessage();
      return;
    }

    final user = _auth.getCurrentUser();
    if (user == null) return;

    try {
      final requestRef = _firestore.collection('requests').doc(requestId);
      final requestSnap = await requestRef.get();
      final requestData = requestSnap.data() ?? <String, dynamic>{};
      final residentName = (requestData['residentName'] ?? 'the resident').toString();
      final serviceType = (requestData['serviceType'] ?? 'service').toString();
      final location = (requestData['location'] ?? requestData['unit'] ?? 'the service location').toString();
      final providerName = _providerDisplayName();
      final expectedArrivalWindow = await _promptForArrivalWindow(
        initialValue: (requestData['expectedArrivalWindow'] ?? '').toString(),
      );
      if (expectedArrivalWindow == null) return;

      if ((requestData['assignedProviderId'] ?? '').toString() != user.uid) {
        throw Exception('This request is no longer assigned to you.');
      }

      await requestRef.update({
        'status': 'inProgress',
        'assignedProviderId': user.uid,
        'acceptedAt': FieldValue.serverTimestamp(),
        'inProgressAt': FieldValue.serverTimestamp(),
        'assignedAt': FieldValue.serverTimestamp(),
        'expectedArrivalWindow': expectedArrivalWindow,
        'residentNotificationMessage':
            '$providerName accepted your $serviceType request and plans to arrive $expectedArrivalWindow at $location.',
        'providerStatusMessage':
            'You accepted $residentName\'s $serviceType request and scheduled arrival for $expectedArrivalWindow.',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final residentUserId = (requestData['userId'] ?? '').toString();
      await _createWorkflowNotification(
        userId: residentUserId,
        requestId: requestId,
        type: 'request_accepted',
        title: 'Provider accepted your request',
        message:
            '$providerName accepted your $serviceType request and plans to arrive $expectedArrivalWindow at $location.',
        extras: {
          'providerId': user.uid,
          'providerName': providerName,
          'expectedArrivalWindow': expectedArrivalWindow,
        },
      );
      await _adjustProviderTaskCount(user.uid, 1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request accepted and arrival time shared'),
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

  Future<void> _updateRequestStatus(String requestId, String newStatus) async {
    if (!_canOperateAsProvider) {
      _showVerificationBlockedMessage();
      return;
    }

    try {
      final normalizedStatus = newStatus.toLowerCase() == 'in progress'
          ? 'inProgress'
          : newStatus;
      final user = _auth.getCurrentUser();
      if (user == null) return;

      final requestRef = _firestore.collection('requests').doc(requestId);
      final requestSnap = await requestRef.get();
      final requestData = requestSnap.data() ?? <String, dynamic>{};
      final providerName = _providerDisplayName();
      final serviceType = (requestData['serviceType'] ?? 'service').toString();
      final residentUserId = (requestData['userId'] ?? '').toString();
      final residentName = (requestData['residentName'] ?? 'Resident').toString();
      final location =
          (requestData['location'] ?? requestData['unit'] ?? 'the resident location')
              .toString();

      if ((requestData['assignedProviderId'] ?? '').toString() != user.uid) {
        throw Exception('This request is no longer assigned to you.');
      }

      final updateData = <String, dynamic>{
        'status': normalizedStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (normalizedStatus == 'inProgress') {
        updateData['inProgressAt'] = FieldValue.serverTimestamp();
        updateData['residentNotificationMessage'] =
            '$providerName is currently working on your $serviceType request.';
      } else if (normalizedStatus == 'completed') {
        updateData['completedAt'] = FieldValue.serverTimestamp();
        updateData['residentNotificationMessage'] =
            '$providerName marked your $serviceType request as completed. You can now review the job.';
      }

      await requestRef.update(updateData);

      if (normalizedStatus == 'inProgress') {
        await _createWorkflowNotification(
          userId: residentUserId,
          requestId: requestId,
          type: 'request_in_progress',
          title: 'Work is in progress',
          message: '$providerName is currently working on your $serviceType request.',
          extras: {
            'providerId': user.uid,
            'providerName': providerName,
          },
        );
      } else if (normalizedStatus == 'completed') {
        await _createWorkflowNotification(
          userId: residentUserId,
          requestId: requestId,
          type: 'request_completed',
          title: 'Request completed',
          message:
              '$providerName marked your $serviceType request as completed. You can now review the job.',
          extras: {
            'providerId': user.uid,
            'providerName': providerName,
          },
        );
        await _createAdminNotification(
          requestId: requestId,
          type: 'request_completed_admin',
          title: 'Service request completed',
          message:
              '$providerName completed $residentName\'s $serviceType request for $location.',
          extras: {
            'providerId': user.uid,
            'providerName': providerName,
            'residentId': residentUserId,
            'residentName': residentName,
            'serviceType': serviceType,
            'location': location,
          },
        );
      }

      if (normalizedStatus == 'completed') {
        await _adjustProviderTaskCount(user.uid, -1);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to $normalizedStatus and resident informed'),
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

  Future<String?> _promptForArrivalWindow({String initialValue = ''}) async {
    var selected = initialValue.trim();
    final customController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Set arrival time'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Let the resident know when you expect to arrive.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _arrivalWindowOptions.contains(selected) ? selected : null,
                  decoration: const InputDecoration(
                    labelText: 'Arrival window',
                    border: OutlineInputBorder(),
                  ),
                  items: _arrivalWindowOptions
                      .map((option) => DropdownMenuItem(value: option, child: Text(option)))
                      .toList(),
                  onChanged: (value) {
                    setModalState(() {
                      selected = value ?? '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customController,
                  decoration: const InputDecoration(
                    labelText: 'Or enter a custom time',
                    hintText: 'e.g. Today at 3:30 PM',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setModalState(() {}),
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
                  final manual = customController.text.trim();
                  final finalValue = manual.isNotEmpty ? manual : selected.trim();
                  if (finalValue.isEmpty) return;
                  Navigator.pop(ctx, finalValue);
                },
                child: const Text('Save time'),
              ),
            ],
          );
        },
      ),
    );
    customController.dispose();
    return result;
  }

  Future<void> _updateExpectedArrivalWindow(String requestId, String currentValue) async {
    if (!_canOperateAsProvider) {
      _showVerificationBlockedMessage();
      return;
    }

    final user = _auth.getCurrentUser();
    if (user == null) return;

    final newArrivalWindow = await _promptForArrivalWindow(initialValue: currentValue);
    if (newArrivalWindow == null) return;

    try {
      final requestRef = _firestore.collection('requests').doc(requestId);
      final requestSnap = await requestRef.get();
      final requestData = requestSnap.data() ?? <String, dynamic>{};
      final providerName = _providerDisplayName();
      final serviceType = (requestData['serviceType'] ?? 'service').toString();
      final residentUserId = (requestData['userId'] ?? '').toString();
      final location =
          (requestData['location'] ?? requestData['unit'] ?? 'the resident location').toString();

      if ((requestData['assignedProviderId'] ?? '').toString() != user.uid) {
        throw Exception('This request is no longer assigned to you.');
      }

      await requestRef.update({
        'expectedArrivalWindow': newArrivalWindow,
        'residentNotificationMessage':
            '$providerName updated the arrival time for your $serviceType request to $newArrivalWindow.',
        'providerStatusMessage': 'You updated your arrival time to $newArrivalWindow.',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _createWorkflowNotification(
        userId: residentUserId,
        requestId: requestId,
        type: 'request_arrival_updated',
        title: 'Arrival time updated',
        message:
            '$providerName updated the arrival time for your $serviceType request to $newArrivalWindow at $location.',
        extras: {
          'providerId': user.uid,
          'providerName': providerName,
          'expectedArrivalWindow': newArrivalWindow,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Arrival time updated'),
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

  Future<void> _declineRequest(String requestId) async {
    if (!_canOperateAsProvider) {
      _showVerificationBlockedMessage();
      return;
    }

    final user = _auth.getCurrentUser();
    if (user == null) return;

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Assignment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tell the admin why you cannot take this request right now.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. Outside my working area or unavailable today',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    try {
      final requestRef = _firestore.collection('requests').doc(requestId);
      final providerName = _providerDisplayName();
      final reason = reasonController.text.trim();

      await _firestore.runTransaction((transaction) async {
        final requestSnap = await transaction.get(requestRef);
        final requestData = requestSnap.data() ?? <String, dynamic>{};

        if ((requestData['assignedProviderId'] ?? '').toString() != user.uid) {
          throw Exception('This request is no longer assigned to you.');
        }

        if (_normalizedRequestStatus(requestData['status']) != 'assigned') {
          throw Exception('Only newly assigned requests can be declined.');
        }

        final declineCount = ((requestData['declineCount'] as num?)?.toInt() ?? 0) + 1;
        final serviceType = (requestData['serviceType'] ?? 'service').toString();

        transaction.update(requestRef, {
          'status': 'pending',
          'declineCount': declineCount,
          'lastDeclineReason': reason,
          'lastDeclinedByProviderId': user.uid,
          'lastDeclinedByProviderName': providerName,
          'lastDeclinedAt': FieldValue.serverTimestamp(),
          'residentNotificationMessage':
              '$providerName declined your $serviceType request. The admin will reassign it shortly.',
          'providerStatusMessage':
              'You declined this assignment. Admin reassignment is now required.',
          'assignedProviderId': FieldValue.delete(),
          'assignedProviderName': FieldValue.delete(),
          'assignedProviderPhone': FieldValue.delete(),
          'assignedProviderSpecialty': FieldValue.delete(),
          'assignedAt': FieldValue.delete(),
          'expectedArrivalWindow': FieldValue.delete(),
          'providerNotificationMessage': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      final refreshedSnap = await requestRef.get();
      final refreshedData = refreshedSnap.data() ?? <String, dynamic>{};
      final residentUserId = (refreshedData['userId'] ?? '').toString();
      final serviceType = (refreshedData['serviceType'] ?? 'service').toString();
      final residentName = (refreshedData['residentName'] ?? 'Resident').toString();
      final location =
          (refreshedData['location'] ?? refreshedData['unit'] ?? 'the resident location')
              .toString();
      final residentMessage =
          '$providerName declined your $serviceType request. The admin will reassign it shortly.';
      final adminMessage =
          '$providerName declined $residentName\'s $serviceType request for $location. Reason: $reason';

      await _createWorkflowNotification(
        userId: residentUserId,
        requestId: requestId,
        type: 'request_declined',
        title: 'Provider reassignment needed',
        message: residentMessage,
        extras: {
          'providerId': user.uid,
          'providerName': providerName,
        },
      );
      await _createAdminNotification(
        requestId: requestId,
        type: 'provider_declined_assignment',
        title: 'Provider declined assignment',
        message: adminMessage,
        extras: {
          'providerId': user.uid,
          'providerName': providerName,
          'residentId': residentUserId,
          'residentName': residentName,
          'serviceType': serviceType,
          'location': location,
          'reason': reason,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assignment declined. The request has been returned to admin for reassignment.'),
          backgroundColor: AppColors.warning,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 768;
    final padding = isWide ? 32.0 : 24.0;

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
    final secondary = isDark ? AppColors.textMutedDark : AppColors.primaryMuted;
    final secondaryContainer = isDark ? AppColors.borderDark : const Color(0xFFb1c2fd);
    final onSecondary = isDark ? Colors.white : const Color(0xFFffffff);

    final userId = _auth.getCurrentUser()?.uid ?? '';

    if (_isLoading) {
      return Scaffold(
        backgroundColor: surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surfaceContainerHigh,
              ),
              child: ClipOval(
                child: Image.network(
                  _userData?['avatarUrl'] ??
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuBhCkVqoO37yGLSSXidj8iW7LFOzq-sajt_Ks0XI1xfDHbc8RRGQE1G5rP-s_5tHrdEjGWecYHdCucLIhXlZ8raZYgETZJit-IAcRixB2oLLubZdYTJRPzVvZmHicEd3hGBJZazFhMgkISSQJim8TJaKLozLzIVHKv7TCfGo-mx3iPfLY-kmtCW3dH1ZnhW7nPTA9x24Mnnu_gB4yYVYa4runc8WzVQeh1xKYRHz14nRlXXCLlUiJ5xcIXY5lXcf4V6Sh-MNBxBFY4',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.person, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Tumaini Estate',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textOnSurface,
              ),
            ),
          ],
        ),
        actions: [
          const AppHomeAction(),
          NotificationBellButton(iconColor: textOnSurfaceVariant),
        ],
      ),
      body: Builder(
        builder: (context) {
          final content = RefreshIndicator(
            onRefresh: _loadUserData,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.all(padding),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverviewHero(context),
                  const SizedBox(height: 20),
                  _buildVerificationStatusBanner(),
                  const SizedBox(height: 24),
                  if (_selectedNavIndex == 0) ...[
                    _buildDashboardQueueSummary(context, userId),
                    const SizedBox(height: 24),
                    _buildActionRequiredPanel(context, userId),
                    const SizedBox(height: 24),
                    _buildOperationalSnapshot(context, userId),
                    const SizedBox(height: 20),
                    _buildQuickActions(context),
                    const SizedBox(height: 32),
                    _buildRecentFeedbackSection(context, userId),
                    const SizedBox(height: 80),
                  ] else ...[
                    KeyedSubtree(
                      key: _workQueueSectionKey,
                      child: _selectedNavIndex == 1
                          ? _buildNewAssignmentsSection(
                              context,
                              userId,
                              canOperate: _canOperateAsProvider,
                            )
                          : _buildActiveJobsSection(
                              context,
                              userId,
                              canOperate: _canOperateAsProvider,
                            ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ],
              ),
            ),
          );

          if (screenWidth < 768) {
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
      bottomNavigationBar:
          screenWidth < 768 ? _buildBottomNavBar(context) : null,
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
                isSelected: _selectedNavIndex == 0,
                onTap: _handleDashboardTap,
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.assignment_ind_outlined,
                label: 'New Assignments',
                isSelected: _selectedNavIndex == 1,
                onTap: () => _selectWorkQueueTab(0),
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.build_circle_outlined,
                label: 'Active Jobs',
                isSelected: _selectedNavIndex == 2,
                onTap: () => _selectWorkQueueTab(1),
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.person,
                label: 'Profile',
                isSelected: false,
                onTap: () => context.go('/provider-profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardQueueSummary(BuildContext context, String userId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final primary = AppColors.primary;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('requests')
          .where('assignedProviderId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Could not load your work queue right now.',
              style: TextStyle(color: textOnSurfaceVariant),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final newAssignments = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _normalizedRequestStatus(data['status']) == 'assigned';
        }).length;
        final activeJobs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _normalizedRequestStatus(data['status']) == 'inprogress';
        }).length;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.borderDark : const Color(0xFFE2E2E4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                overline: 'Queue Snapshot',
                title: 'Work Overview',
                subtitle: 'Keep the dashboard focused on the big picture, then jump into the right queue when you are ready to act.',
                textOnSurface: textOnSurface,
                textOnSurfaceVariant: textOnSurfaceVariant,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final spacing = constraints.maxWidth < 520 ? 8.0 : 12.0;
                  return Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'New Assignments',
                          value: '$newAssignments',
                          subtitle: 'waiting for your response',
                          icon: Icons.assignment_ind_outlined,
                          accent: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: spacing),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Active Jobs',
                          value: '$activeJobs',
                          subtitle: activeJobs == 1 ? 'job in progress' : 'jobs in progress',
                          icon: Icons.build_circle_outlined,
                          accent: AppColors.accent,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 680;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _selectWorkQueueTab(0),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.assignment_ind_outlined),
                            label: const Text('Open New Assignments'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _selectWorkQueueTab(1),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.build_circle_outlined),
                            label: const Text('Open Active Jobs'),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _selectWorkQueueTab(0),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.assignment_ind_outlined),
                          label: const Text('Open New Assignments'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _selectWorkQueueTab(1),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.build_circle_outlined),
                          label: const Text('Open Active Jobs'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNewAssignmentsSection(BuildContext context, String userId, {required bool canOperate}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final primary = AppColors.primary;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final outline = isDark ? AppColors.textMutedDark : const Color(0xFF737686);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('requests')
          .where('assignedProviderId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildWorkQueueErrorCard(context, textOnSurfaceVariant);
        }

        final docs = snapshot.data?.docs ?? [];
        final newAssignments = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _normalizedRequestStatus(data['status']) == 'assigned';
        }).toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs = aData['assignedAt'] as Timestamp? ?? aData['createdAt'] as Timestamp?;
            final bTs = bData['assignedAt'] as Timestamp? ?? bData['createdAt'] as Timestamp?;
            final aMs = aTs?.millisecondsSinceEpoch ?? 0;
            final bMs = bTs?.millisecondsSinceEpoch ?? 0;
            return bMs.compareTo(aMs);
          });

        return _buildFocusedQueueSection(
          context: context,
          title: 'New Assignments',
          subtitle: 'Review incoming jobs, accept the right work, or decline with a reason so admins can reassign quickly.',
          leadingIcon: Icons.assignment_ind_outlined,
          child: _buildNewAssignmentsContent(
            key: const ValueKey('newAssignmentsOnly'),
            context: context,
            requests: newAssignments,
            canOperate: canOperate,
            isDark: isDark,
            surfaceContainerLowest: surfaceContainerLowest,
            primary: primary,
            textOnSurface: textOnSurface,
            textOnSurfaceVariant: textOnSurfaceVariant,
            outline: outline,
          ),
        );
      },
    );
  }

  Widget _buildActiveJobsSection(BuildContext context, String userId, {required bool canOperate}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final primary = AppColors.primary;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('requests')
          .where('assignedProviderId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildWorkQueueErrorCard(context, textOnSurfaceVariant);
        }

        final docs = snapshot.data?.docs ?? [];
        final activeJobs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _normalizedRequestStatus(data['status']) == 'inprogress';
        }).toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs = aData['updatedAt'] as Timestamp? ?? aData['createdAt'] as Timestamp?;
            final bTs = bData['updatedAt'] as Timestamp? ?? bData['createdAt'] as Timestamp?;
            final aMs = aTs?.millisecondsSinceEpoch ?? 0;
            final bMs = bTs?.millisecondsSinceEpoch ?? 0;
            return bMs.compareTo(aMs);
          });

        return _buildFocusedQueueSection(
          context: context,
          title: 'Active Jobs',
          subtitle: 'Track the jobs already underway, update arrival windows, and close work only when it is completed.',
          leadingIcon: Icons.build_circle_outlined,
          child: _buildActiveJobsContent(
            key: const ValueKey('activeJobsOnly'),
            context: context,
            requests: activeJobs,
            canOperate: canOperate,
            isDark: isDark,
            surfaceContainerLowest: surfaceContainerLowest,
            surfaceContainerLow: surfaceContainerLow,
            primary: primary,
            textOnSurface: textOnSurface,
            textOnSurfaceVariant: textOnSurfaceVariant,
          ),
        );
      },
    );
  }

  Widget _buildFocusedQueueSection({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData leadingIcon,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFE2E2E4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(leadingIcon, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          _buildSectionHeader(
            overline: 'Work Queue',
            title: title,
            subtitle: subtitle,
            textOnSurface: textOnSurface,
            textOnSurfaceVariant: textOnSurfaceVariant,
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildWorkQueueErrorCard(BuildContext context, Color textOnSurfaceVariant) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Could not load your work queue right now.',
        style: TextStyle(color: textOnSurfaceVariant),
      ),
    );
  }

  Widget _buildWorkQueueTab({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    required Color primary,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
    required Color surfaceContainerLowest,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? surfaceContainerLowest : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? textOnSurface : textOnSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? primary.withOpacity(0.12) : Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewAssignmentsContent({
    Key? key,
    required BuildContext context,
    required List<QueryDocumentSnapshot> requests,
    required bool canOperate,
    required bool isDark,
    required Color surfaceContainerLowest,
    required Color primary,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
    required Color outline,
  }) {
    if (requests.isEmpty) {
      return Container(
        key: key,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          'No new assignments right now.',
          style: TextStyle(color: textOnSurfaceVariant),
        ),
      );
    }

    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final useSingleColumn = constraints.maxWidth < 760;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: useSingleColumn ? 1 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: useSingleColumn ? 1.55 : 0.9,
          children: requests.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final serviceType = data['serviceType'] ?? 'Unknown';
            final title = serviceType == 'plumbing' ? 'Plumbing Request' : serviceType == 'electrical' ? 'Electrical Request' : '$serviceType Request';
            final description = data['description'] ?? '';
            final location = data['location'] ?? data['unit'] ?? 'Location not provided';
            final preferredTimeSlot = data['preferredTimeSlot'];
            final residentName = (data['residentName'] ?? 'Resident').toString();
            final urgency = (data['urgency'] ?? 'medium').toString();

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : const Color(0xFFE2E2E4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textOnSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    residentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: AppColors.neutral500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: textOnSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 14, color: AppColors.neutral500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          (preferredTimeSlot ?? 'Flexible').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: textOnSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.priority_high, size: 14, color: AppColors.neutral500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Urgency: ${urgency[0].toUpperCase()}${urgency.substring(1)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: textOnSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Text(
                      description.toString(),
                      maxLines: useSingleColumn ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: textOnSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: canOperate ? () => _acceptRequest(doc.id) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Accept'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: canOperate ? () => _declineRequest(doc.id) : null,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: outline),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Decline'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildActiveJobsContent({
    Key? key,
    required BuildContext context,
    required List<QueryDocumentSnapshot> requests,
    required bool canOperate,
    required bool isDark,
    required Color surfaceContainerLowest,
    required Color surfaceContainerLow,
    required Color primary,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
  }) {
    if (requests.isEmpty) {
      return Container(
        key: key,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          'No active jobs right now.',
          style: TextStyle(color: textOnSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      key: key,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final doc = requests[index];
        final data = doc.data() as Map<String, dynamic>;
        final serviceType = data['serviceType'] ?? 'Unknown';
        final title = serviceType == 'plumbing' ? 'Plumbing Request' : serviceType == 'electrical' ? 'Electrical Request' : '$serviceType Request';
        final location = data['location'] ?? data['unit'] ?? 'Location not provided';
        final currentStatus = data['status'] ?? 'inProgress';
        final residentName = (data['residentName'] ?? 'Resident').toString();
        final description = (data['description'] ?? 'No description provided').toString();
        final expectedArrivalWindow = (data['expectedArrivalWindow'] ?? '').toString().trim();

        return Container(
          margin: EdgeInsets.only(bottom: index == requests.length - 1 ? 0 : 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.borderDark : const Color(0xFFE2E2E4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.08 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.build, size: 24, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textOnSurface,
                          ),
                        ),
                        Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: textOnSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          residentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: textOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.directions),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Navigation coming soon')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: textOnSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        expectedArrivalWindow.isEmpty
                            ? 'Arrival time not shared yet'
                            : 'Arrival: $expectedArrivalWindow',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textOnSurface,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _updateExpectedArrivalWindow(doc.id, expectedArrivalWindow),
                      child: const Text('Update time'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<String>(
                        value: currentStatus == 'inProgress' ? 'In Progress' : currentStatus,
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                          DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                        ],
                        onChanged: (value) async {
                          if (value != null) {
                            if (!canOperate) {
                              _showVerificationBlockedMessage();
                              return;
                            }
                            if (value == 'Completed') {
                              final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Mark job as completed'),
                                      content: const Text(
                                        'Confirm that the work is finished and the resident can now leave feedback.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Complete'),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (!confirmed) return;
                            }
                            await _updateRequestStatus(doc.id, value.toLowerCase());
                          }
                        },
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Navigation coming soon')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Navigate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentFeedbackSection(BuildContext context, String userId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('feedback')
          .where('providerId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final feedbackDocs = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Feedback',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textOnSurface,
              ),
            ),
            const SizedBox(height: 16),
            if (feedbackDocs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'No feedback yet.',
                  style: TextStyle(color: textOnSurfaceVariant),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: feedbackDocs.length,
                itemBuilder: (context, index) {
                  final data = feedbackDocs[index].data() as Map<String, dynamic>;
                  final rating = ((data['rating'] as num?)?.toInt() ?? 0).clamp(0, 5);
                  final comment = (data['comment'] ?? 'No comment provided').toString();
                  final residentName =
                      (data['residentName'] ?? data['userName'] ?? data['userId'] ?? 'Resident')
                          .toString();
                  final createdAt = data['createdAt'] as Timestamp?;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: List.generate(5, (i) {
                                return Icon(
                                  i < rating ? Icons.star : Icons.star_border,
                                  size: 14,
                                  color: AppColors.accent,
                                );
                              }),
                            ),
                            Text(
                              createdAt == null ? 'Just now' : _formatDate(createdAt),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: textOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          comment,
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: textOnSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '- $residentName',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: textOnSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildVerificationStatusBanner() {
    final status = _providerStatus;
    if (_canOperateAsProvider) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.successStrong.withOpacity(0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, size: 18, color: AppColors.successStrong),
            const SizedBox(width: 8),
            Text(
              'Verified account active',
              style: TextStyle(
                color: AppColors.successStrong,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final isRejected = status == 'rejected';
    final bannerColor = isRejected ? AppColors.error : AppColors.warning;
    final bannerTextColor = isRejected ? AppColors.errorStrong : AppColors.warningStrong;
    final title = isRejected ? 'Verification rejected' : 'Verification pending';
    final note = _verificationNote.trim();
    final message = isRejected
        ? (note.isEmpty
              ? 'Please update your details and re-apply from your profile page.'
              : 'Reason: $note')
        : 'Your account is under review. You cannot accept jobs until approved.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bannerColor.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bannerTextColor.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRejected ? Icons.gpp_bad : Icons.pending_actions,
                size: 18,
                color: bannerTextColor,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: bannerTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(color: bannerTextColor),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => context.go('/provider-profile'),
            child: const Text('Open profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: surface.withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                context,
                icon: Icons.dashboard,
                label: 'Dashboard',
                isSelected: _selectedNavIndex == 0,
                onTap: _handleDashboardTap,
              ),
              _buildNavItem(
                context,
                icon: Icons.assignment_ind_outlined,
                label: 'New',
                isSelected: _selectedNavIndex == 1,
                onTap: () => _selectWorkQueueTab(0),
              ),
              _buildNavItem(
                context,
                icon: Icons.build_circle_outlined,
                label: 'Active',
                isSelected: _selectedNavIndex == 2,
                onTap: () => _selectWorkQueueTab(1),
              ),
              _buildNavItem(
                context,
                icon: Icons.person,
                label: 'Profile',
                isSelected: false,
                onTap: () => context.go('/provider-profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context,
      {required IconData icon,
        required String label,
        required bool isSelected,
        required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isSelected
        ? AppColors.primary
        : (isDark ? AppColors.textMutedDark : AppColors.textSecondaryDark);
    final bgColor = isSelected
        ? (isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.shade50)
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
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





