import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_home_action.dart';
import '../widgets/notification_bell_button.dart';

class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  final AuthService _auth = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  String _normalizedStatus(dynamic rawStatus) {
    final status = (rawStatus ?? 'pending').toString().trim().toLowerCase();
    if (status == 'in progress') return 'inprogress';
    return status;
  }

  bool _isLoading = true;
  String _userName = 'Resident';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    try {
      final user = _auth.getCurrentUser();
      if (user == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userName = userDoc.data()?['fullName'] ?? 'Resident';

      if (mounted) {
        setState(() {
          _userName = userName;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isCompact = screenWidth < 360;

    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final cardBackground = isDark ? AppColors.surfaceDark : Colors.white;
    final borderColor =
        isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final secondary = isDark ? AppColors.textMutedDark : AppColors.primaryMuted;
    final tertiary = isDark ? AppColors.textMutedDark : const Color(0xFF7e2900);

    final padding = screenWidth < 300
        ? 8.0
        : screenWidth < 400
            ? 12.0
            : screenWidth < 600
                ? 16.0
                : screenWidth < 768
                    ? 20.0
                    : 24.0;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: Text(
          isCompact ? 'Dashboard' : 'Estate Services Dashboard',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          const AppHomeAction(),
          const NotificationBellButton(),
        ],
      ),
      body: Builder(
        builder: (context) {
          final content = _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isCompact ? 16 : 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [primary, primary.withOpacity(0.7)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome Back, $_userName!',
                          style: TextStyle(
                            fontSize: isCompact ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Manage your service requests and track their progress',
                          style: TextStyle(
                            fontSize: isCompact ? 13 : 14,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Your Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textOnSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildActivityStats(
                    isMobile: isMobile,
                    primary: primary,
                    secondary: secondary,
                    tertiary: tertiary,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textOnSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  isMobile
                      ? Column(
                          children: [
                            _buildActionButton(
                              context,
                              'Submit New Request',
                              'Create a new service request',
                              Icons.add_circle_outline,
                              primary,
                              () => context.push('/service-request'),
                            ),
                            const SizedBox(height: 12),
                            _buildActionButton(
                              context,
                              'View My Requests',
                              'Track all your submitted requests',
                              Icons.list_alt,
                              secondary,
                              () => context.push('/request-tracking'),
                            ),
                            const SizedBox(height: 12),
                            _buildActionButton(
                              context,
                              'View Profile',
                              'Edit your profile information',
                              Icons.person,
                              tertiary,
                              () => context.push('/resident-profile'),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _buildActionButton(
                                context,
                                'Submit New Request',
                                'Create a new service request',
                                Icons.add_circle_outline,
                                primary,
                                () => context.push('/service-request'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildActionButton(
                                context,
                                'View My Requests',
                                'Track all your submitted requests',
                                Icons.list_alt,
                                secondary,
                                () => context.push('/request-tracking'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildActionButton(
                                context,
                                'View Profile',
                                'Edit your profile information',
                                Icons.person,
                                tertiary,
                                () => context.push('/resident-profile'),
                              ),
                            ),
                          ],
                        ),
                  const SizedBox(height: 32),
                  Text(
                    'Recent Requests',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textOnSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRecentRequestsList(
                    textOnSurface: textOnSurface,
                    textOnSurfaceVariant: textOnSurfaceVariant,
                    cardBackground: cardBackground,
                    borderColor: borderColor,
                  ),
                  const SizedBox(height: 40),
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
                'Resident Menu',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1a1c1d),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _buildDesktopNavTile(
                context,
                icon: Icons.home,
                label: 'Home',
                isSelected: true,
                onTap: _scrollToTop,
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.add_task,
                label: 'New Request',
                isSelected: false,
                onTap: () => context.go('/service-request'),
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.assignment,
                label: 'Requests',
                isSelected: false,
                onTap: () => context.go('/request-tracking'),
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.support_agent,
                label: 'Support',
                isSelected: false,
                onTap: () => context.go('/help-support'),
              ),
              _buildDesktopNavTile(
                context,
                icon: Icons.person,
                label: 'Profile',
                isSelected: false,
                onTap: () => context.go('/resident-profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: surface.withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                icon: Icons.home,
                label: 'Home',
                isSelected: true,
                onTap: _scrollToTop,
              ),
              _buildNavItem(
                context,
                icon: Icons.add_task,
                label: 'New Request',
                isSelected: false,
                onTap: () => context.go('/service-request'),
              ),
              _buildNavItem(
                context,
                icon: Icons.assignment,
                label: 'Requests',
                isSelected: false,
                onTap: () => context.go('/request-tracking'),
              ),
              _buildNavItem(
                context,
                icon: Icons.person,
                label: 'Profile',
                isSelected: false,
                onTap: () => context.go('/resident-profile'),
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
    final color = isSelected
        ? AppColors.primary
        : (isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark);

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

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 240;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(isCompact ? 14 : 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: color, size: 28),
                    const SizedBox(height: 12),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(icon, color: color, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildActivityStats({
    required bool isMobile,
    required Color primary,
    required Color secondary,
    required Color tertiary,
  }) {
    final userId = _auth.getCurrentUser()?.uid ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('requests')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var pending = 0;
        var assigned = 0;
        var inProgress = 0;
        var completed = 0;
        for (final doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = _normalizedStatus(data['status']);
          if (status == 'pending') pending++;
          if (status == 'assigned') assigned++;
          if (status == 'inprogress') inProgress++;
          if (status == 'completed') completed++;
        }

        if (isMobile) {
          return Column(
            children: [
              _buildStatCard('Pending', pending.toString(), primary, Icons.pending_actions),
              const SizedBox(height: 12),
              _buildStatCard('Assigned', assigned.toString(), secondary, Icons.assignment_ind),
              const SizedBox(height: 12),
              _buildStatCard('In Progress', inProgress.toString(), secondary, Icons.handyman),
              const SizedBox(height: 12),
              _buildStatCard('Completed', completed.toString(), tertiary, Icons.task_alt),
            ],
          );
        }

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(width: 220, child: _buildStatCard('Pending', pending.toString(), primary, Icons.pending_actions)),
            SizedBox(width: 220, child: _buildStatCard('Assigned', assigned.toString(), secondary, Icons.assignment_ind)),
            SizedBox(width: 220, child: _buildStatCard('In Progress', inProgress.toString(), secondary, Icons.handyman)),
            SizedBox(width: 220, child: _buildStatCard('Completed', completed.toString(), tertiary, Icons.task_alt)),
          ],
        );
      },
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withOpacity(0.7),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentRequestsList({
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
    required Color cardBackground,
    required Color borderColor,
  }) {
    final userId = _auth.getCurrentUser()?.uid ?? '';

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('requests')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = (snapshot.data?.docs ?? []).toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTs = aData['createdAt'] as Timestamp?;
            final bTs = bData['createdAt'] as Timestamp?;
            final aMs = aTs?.millisecondsSinceEpoch ?? 0;
            final bMs = bTs?.millisecondsSinceEpoch ?? 0;
            return bMs.compareTo(aMs);
          });
        final latestDocs = docs.take(5).toList();

        if (latestDocs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Text(
                'No requests yet. Create one to get started!',
                style: TextStyle(color: textOnSurfaceVariant),
              ),
            ),
          );
        }

        return Column(
          children: latestDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final serviceType = (data['serviceType'] ?? '').toString();
            final title = (data['title'] ?? '').toString().trim().isNotEmpty
                ? data['title'].toString()
                : serviceType == 'plumbing'
                    ? 'Plumbing Request'
                    : serviceType == 'electrical'
                        ? 'Electrical Request'
                        : 'Service Request';
            final status = _normalizedStatus(data['status']);
            final createdAt = data['createdAt'] as Timestamp?;
            final statusColor = _getStatusColor(status);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 320;

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getStatusIcon(status),
                            color: statusColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: textOnSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          createdAt != null
                              ? _formatDate(createdAt)
                              : 'Date unknown',
                          style: TextStyle(
                            fontSize: 12,
                            color: textOnSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status[0].toUpperCase() + status.substring(1),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getStatusIcon(status),
                          color: statusColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textOnSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              createdAt != null
                                  ? _formatDate(createdAt)
                                  : 'Date unknown',
                              style: TextStyle(
                                fontSize: 12,
                                color: textOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status[0].toUpperCase() + status.substring(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.month}/${date.day}/${date.year}';
  }

  Color _getStatusColor(String status) {
    switch (_normalizedStatus(status)) {
      case 'pending':
        return AppColors.warning;
      case 'assigned':
        return Colors.blue;
      case 'inprogress':
        return Colors.deepPurple;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.neutral500;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (_normalizedStatus(status)) {
      case 'pending':
        return Icons.schedule;
      case 'assigned':
        return Icons.assignment_ind;
      case 'inprogress':
        return Icons.handyman;
      case 'completed':
        return Icons.task_alt;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
}



