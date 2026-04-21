import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../widgets/app_home_action.dart';
import '../widgets/notification_bell_button.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _selectedMobileIndex = 0;

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    context.go('/login');
  }

  void _openAdminProfile(BuildContext context) {
    context.push('/admin-profile');
  }

  static const List<String> _weekdayLabels = [
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
  ];

  Map<String, int> _buildLiveAggregates({
    required List<QueryDocumentSnapshot> requestDocs,
    required List<QueryDocumentSnapshot> userDocs,
    required List<QueryDocumentSnapshot> feedbackDocs,
  }) {
    final totalRequests = requestDocs.length;
    final completedJobs = requestDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['status'] ?? '').toString().toLowerCase() == 'completed';
    }).length;

    final providerDocs = userDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['role'] ?? '').toString().toLowerCase() == 'provider';
    }).toList();

    final activeProviders = providerDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      return data['verified'] == true && (status.isEmpty || status == 'active');
    }).length;
    final pendingVerifications = providerDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'pending').toString().trim().toLowerCase();
      return data['verified'] != true && status != 'rejected';
    }).length;

    double totalRating = 0;
    var ratingCount = 0;
    for (final doc in feedbackDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final rating = (data['rating'] as num?)?.toDouble();
      if (rating != null) {
        totalRating += rating;
        ratingCount++;
      }
    }

    final avgRating = ratingCount == 0 ? 0 : totalRating / ratingCount;
    final satisfaction = ((avgRating / 5) * 100).round().clamp(0, 100);

    return {
      'totalRequests': totalRequests,
      'completedJobs': completedJobs,
      'activeProviders': activeProviders,
      'pendingVerifications': pendingVerifications,
      'satisfaction': satisfaction,
    };
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'Just now';
    final date = timestamp.toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;

    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final secondary = isDark ? AppColors.textMutedDark : AppColors.primaryMuted;
    final tertiary = isDark ? AppColors.textMutedDark : const Color(0xFF7e2900);

    return Scaffold(
      backgroundColor: surface,
      drawer: isDesktop ? null : _buildDrawer(context),
      appBar: isDesktop
          ? null
          : AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text('Admin Dashboard'),
        actions: [
          const NotificationBellButton(),
          IconButton(
            tooltip: 'Admin Profile',
            onPressed: () => _openAdminProfile(context),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Log Out',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
          ),
          const AppHomeAction(),
        ],
      ),
      body: Row(
        children: [
          if (isDesktop)
            Container(
              width: 256,
              color: isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf8fafc),
              child: _buildSidebar(context),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_getResponsivePadding(screenWidth)),
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('requests').snapshots(),
                builder: (context, requestSnapshot) {
                  if (requestSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (requestSnapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading request data\n${requestSnapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    );
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('users').snapshots(),
                    builder: (context, usersSnapshot) {
                      if (usersSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (usersSnapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error loading users data\n${usersSnapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        );
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: _firestore.collection('feedback').snapshots(),
                        builder: (context, feedbackSnapshot) {
                          if (feedbackSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (feedbackSnapshot.hasError) {
                            return Center(
                              child: Text(
                                'Error loading feedback data\n${feedbackSnapshot.error}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            );
                          }

                          final aggregates = _buildLiveAggregates(
                            requestDocs: requestSnapshot.data?.docs ?? [],
                            userDocs: usersSnapshot.data?.docs ?? [],
                            feedbackDocs: feedbackSnapshot.data?.docs ?? [],
                          );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                      // Header (responsive)
                      _buildHeader(
                        context,
                        isDesktop,
                        textOnSurface,
                        textOnSurfaceVariant,
                        surfaceContainerLow,
                      ),
                      const SizedBox(height: 32),

                      // Stats row – scrollable horizontally
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: isDesktop
                            ? Row(
                          children: [
                            SizedBox(
                              width: 280,
                              child: _buildStatCard(
                                context,
                                icon: Icons.pending_actions,
                                iconBgColor: primary,
                                title: 'Total Requests',
                                value: aggregates['totalRequests'].toString(),
                                trend: '+12%',
                                trendUp: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 280,
                              child: _buildStatCard(
                                context,
                                icon: Icons.task_alt,
                                iconBgColor: secondary,
                                title: 'Completed Jobs',
                                value: aggregates['completedJobs'].toString(),
                                trend: aggregates['totalRequests']! > 0
                                    ? '${(aggregates['completedJobs']! / aggregates['totalRequests']! * 100).round()}%'
                                    : 'N/A',
                                trendUp: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 280,
                              child: _buildStatCard(
                                context,
                                icon: Icons.star,
                                iconBgColor: tertiary,
                                title: 'Satisfaction',
                                value: '${aggregates['satisfaction']}%',
                                trend: 'High',
                                trendUp: true,
                              ),
                            ),
                          ],
                        )
                            : Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            SizedBox(
                              width: 200,
                              child: _buildStatCard(
                                context,
                                icon: Icons.pending_actions,
                                iconBgColor: primary,
                                title: 'Total Requests',
                                value: aggregates['totalRequests'].toString(),
                                trend: '+12%',
                                trendUp: true,
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: _buildStatCard(
                                context,
                                icon: Icons.task_alt,
                                iconBgColor: secondary,
                                title: 'Completed Jobs',
                                value: aggregates['completedJobs'].toString(),
                                trend: aggregates['totalRequests']! > 0
                                    ? '${(aggregates['completedJobs']! / aggregates['totalRequests']! * 100).round()}%'
                                    : 'N/A',
                                trendUp: true,
                              ),
                            ),
                            SizedBox(
                              width: 200,
                              child: _buildStatCard(
                                context,
                                icon: Icons.star,
                                iconBgColor: tertiary,
                                title: 'Satisfaction',
                                value: '${aggregates['satisfaction']}%',
                                trend: 'High',
                                trendUp: true,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Two-column section
                      if (isDesktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 8,
                              child: _buildPerformanceMetrics(context),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 4,
                              child: _buildRightColumn(context),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _buildPerformanceMetrics(context),
                            const SizedBox(height: 24),
                            _buildRightColumn(context),
                          ],
                        ),

                      const SizedBox(height: 48),
                      _buildFooter(context, screenWidth),
                      const SizedBox(height: 80),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildBottomNavBar(context),
    );
  }

  // ------------------------------------------------------------------------
  // Header (responsive)
  // ------------------------------------------------------------------------
  Widget _buildHeader(
      BuildContext context,
      bool isDesktop,
      Color textOnSurface,
      Color textOnSurfaceVariant,
      Color surfaceContainerLow,
      ) {
    return isDesktop
        ? Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estate Dashboard',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: textOnSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Welcome back. Here is the operational overview for Tumaini Estate today.',
                style: TextStyle(
                  fontSize: 14,
                  color: textOnSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Last Update: ${_timeAgo(Timestamp.now())}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: textOnSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            const NotificationBellButton(),
            OutlinedButton.icon(
              onPressed: () => _openAdminProfile(context),
              icon: const Icon(Icons.account_circle_outlined, size: 18),
              label: const Text('Profile'),
            ),
            ElevatedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Log Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estate Dashboard',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: textOnSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Welcome back. Here is the operational overview for Tumaini Estate today.',
          style: TextStyle(
            fontSize: 14,
            color: textOnSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Last Update: ${_timeAgo(Timestamp.now())}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: textOnSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            const NotificationBellButton(),
            OutlinedButton.icon(
              onPressed: () => _openAdminProfile(context),
              icon: const Icon(Icons.account_circle_outlined, size: 18),
              label: const Text('Profile'),
            ),
            ElevatedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Log Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------------
  // Sidebar (desktop only)
  // ------------------------------------------------------------------------
  Widget _buildSidebar(BuildContext context) {
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
                'Admin Menu',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1a1c1d),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _buildSidebarItem(
                icon: Icons.dashboard,
                label: 'Dashboard',
                isSelected: true,
                onTap: () => context.go('/admin-dashboard'),
              ),
              _buildSidebarItem(
                icon: Icons.analytics_outlined,
                label: 'Reports',
                onTap: () => context.push('/reports'),
              ),
              _buildSidebarItem(
                icon: Icons.group_outlined,
                label: 'Users',
                onTap: () => context.push('/user-management'),
              ),
              _buildSidebarItem(
                icon: Icons.verified_user_outlined,
                label: 'Verifications',
                onTap: () => context.push('/provider-verification?returnTo=/admin-dashboard'),
              ),
              _buildSidebarItem(
                icon: Icons.assignment_ind_outlined,
                label: 'Assign Requests',
                onTap: () => context.push('/request-assignment?returnTo=/admin-dashboard'),
              ),
              _buildSidebarItem(
                icon: Icons.person,
                label: 'Profile',
                onTap: () => _openAdminProfile(context),
              ),
              _buildSidebarItem(
                icon: Icons.logout,
                label: 'Log Out',
                onTap: () => _logout(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    bool isSelected = false,
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

  // ------------------------------------------------------------------------
  // Stat Card – safe (no overflow)
  // ------------------------------------------------------------------------
  Widget _buildStatCard(
      BuildContext context, {
        required IconData icon,
        required Color iconBgColor,
        required String title,
        required String value,
        required String trend,
        required bool trendUp,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trendColor = trendUp ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.surfaceDarkElevated : AppColors.neutral200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Fixed‑size icon container
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBgColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconBgColor, size: 20),
              ),
              // Trend widget – flexible + ellipsis
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        trend,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: trendColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      trendUp ? Icons.trending_up : Icons.trending_down,
                      color: trendColor,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------------
  // Performance Metrics (Bar Chart)
  // ------------------------------------------------------------------------
  Widget _buildPerformanceMetrics(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final primaryContainer = AppColors.primary;
    final surfaceContainerHigh = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFe8e8ea);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('requests').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Text(
              'Could not load request volume right now.',
              style: TextStyle(color: AppColors.error),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        final avg = _calculateAvgResponseTime(docs);
        final dailyCounts = _requestCountsLast7Days(docs);
        final labels = _last7DayLabels();
        final maxCount = dailyCounts.isEmpty
            ? 0
            : dailyCounts.reduce((a, b) => a > b ? a : b);
        final hasRecentRequests = dailyCounts.any((count) => count > 0);
        final totalLast7Days = dailyCounts.fold<int>(0, (sum, count) => sum + count);
        final busiestCount = maxCount;
        final busiestIndex = hasRecentRequests ? dailyCounts.indexOf(busiestCount) : -1;
        final busiestLabel = busiestIndex >= 0 ? labels[busiestIndex] : null;
        final maxY = hasRecentRequests ? (maxCount + 1).toDouble() : 1.0;
        final statusCounts = _requestStatusCounts(docs);
        final responseTrend = _avgResponseTimeLast7Days(docs);

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Performance Metrics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textOnSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Live request volume over the last 7 days',
                        style: TextStyle(
                          fontSize: 12,
                          color: textOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildMetricPill(
                        label: 'Avg Response',
                        value: avg == 0 ? 'N/A' : '${avg.toStringAsFixed(0)} mins',
                        valueColor: primary,
                      ),
                      _buildMetricPill(
                        label: '7-Day Total',
                        value: totalLast7Days.toString(),
                        valueColor: textOnSurface,
                      ),
                      _buildMetricPill(
                        label: 'Busiest Day',
                        value: busiestLabel == null ? 'N/A' : '$busiestLabel ($busiestCount)',
                        valueColor: textOnSurface,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (hasRecentRequests)
                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      maxY: maxY,
                      minY: 0,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: surfaceContainerHigh.withOpacity(0.7),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
                            getTitlesWidget: (value, meta) {
                              if (value < 0 || value > maxY) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                value.toInt().toString(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textOnSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 38,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= labels.length) {
                                return const SizedBox.shrink();
                              }
                              final isToday = index == labels.length - 1;
                              final parts = labels[index].split(' ');
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  children: [
                                    Text(
                                      parts.first,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight:
                                            isToday ? FontWeight.w700 : FontWeight.w500,
                                        color:
                                            isToday ? AppColors.primary : textOnSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      parts.last,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            isToday ? AppColors.primary : textOnSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipRoundedRadius: 12,
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final count = dailyCounts[group.x.toInt()];
                            return BarTooltipItem(
                              '${labels[group.x.toInt()]}\n$count request${count == 1 ? '' : 's'}',
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ),
                      barGroups: List.generate(dailyCounts.length, (index) {
                        final isToday = index == dailyCounts.length - 1;
                        final count = dailyCounts[index].toDouble();
                        return BarChartGroupData(
                          x: index,
                          barsSpace: 0,
                          barRods: [
                            BarChartRodData(
                              toY: count,
                              width: 18,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                              color: isToday
                                  ? primary
                                  : count > 0
                                      ? primaryContainer.withOpacity(0.72)
                                      : surfaceContainerHigh.withOpacity(0.7),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: maxY,
                                color: surfaceContainerHigh.withOpacity(0.18),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                )
              else
                Container(
                  height: 220,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: surfaceContainerHigh.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'No requests recorded in the last 7 days.',
                    style: TextStyle(
                      fontSize: 12,
                      color: textOnSurfaceVariant,
                    ),
                  ),
                ),
              if (hasRecentRequests) ...[
                const SizedBox(height: 12),
                Text(
                  '$totalLast7Days requests in the last 7 days'
                  '${busiestLabel == null ? '' : ' • Busiest: $busiestLabel ($busiestCount)'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textOnSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final showSideBySide = constraints.maxWidth >= 860;
                  final statusCard = _buildStatusBreakdownCard(
                    context,
                    statusCounts: statusCounts,
                  );
                  final responseCard = _buildResponseTrendCard(
                    context,
                    labels: labels,
                    responseTrend: responseTrend,
                  );

                  if (showSideBySide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: statusCard),
                        const SizedBox(width: 16),
                        Expanded(child: responseCard),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      statusCard,
                      const SizedBox(height: 16),
                      responseCard,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: surfaceContainerHigh.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(dailyCounts.length, (index) {
                    final isToday = index == dailyCounts.length - 1;
                    return Expanded(
                      child: Column(
                        children: [
                          Text(
                            labels[index].split(' ').first,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: isToday ? primary : textOnSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dailyCounts[index].toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isToday ? primary : primaryContainer,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsSubcard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final surface = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFfbfbfc);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFE6E7EA),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.06 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: textOnSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: textOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildMetricPill({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdownCard(
    BuildContext context, {
    required Map<String, int> statusCounts,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final total = statusCounts.values.fold<int>(0, (sum, count) => sum + count);
    final orderedEntries = [
      ('Pending', statusCounts['pending'] ?? 0, const Color(0xFFF0A33B)),
      ('Assigned', statusCounts['assigned'] ?? 0, const Color(0xFF6AA6FF)),
      ('In Progress', statusCounts['inProgress'] ?? 0, const Color(0xFF4F7DF3)),
      ('Completed', statusCounts['completed'] ?? 0, AppColors.success),
      ('Cancelled', statusCounts['cancelled'] ?? 0, AppColors.error),
    ];
    final activeEntries = orderedEntries.where((entry) => entry.$2 > 0).toList();

    return _buildAnalyticsSubcard(
      context,
      title: 'Request Status Mix',
      subtitle: 'Where current workload is sitting right now',
      child: total == 0
          ? SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'No request status data available yet.',
                  style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                ),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 220,
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 52,
                      sectionsSpace: 3,
                      sections: activeEntries.map((entry) {
                        final ratio = entry.$2 / total;
                        return PieChartSectionData(
                          value: entry.$2.toDouble(),
                          color: entry.$3,
                          radius: 44,
                          title: '${(ratio * 100).round()}%',
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: orderedEntries.map((entry) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: entry.$3,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.$1}: ${entry.$2}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textOnSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }

  Widget _buildResponseTrendCard(
    BuildContext context, {
    required List<String> labels,
    required List<double> responseTrend,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurfaceVariant =
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final hasData = responseTrend.any((value) => value > 0);
    final maxY = hasData
        ? ((responseTrend.reduce((a, b) => a > b ? a : b) / 15).ceil() * 15)
            .toDouble()
            .clamp(15.0, 180.0)
            .toDouble()
        : 15.0;

    return _buildAnalyticsSubcard(
      context,
      title: 'Response Time Trend',
      subtitle: 'Average minutes to assignment over the last 7 days',
      child: hasData
          ? SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 6,
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY <= 30 ? 10 : (maxY / 3),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: (isDark ? AppColors.borderDark : const Color(0xFFE8E8EA))
                          .withOpacity(0.8),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: maxY <= 30 ? 10 : (maxY / 3),
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: TextStyle(fontSize: 10, color: textOnSurfaceVariant),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= labels.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              labels[index].split(' ').first,
                              style: TextStyle(fontSize: 10, color: textOnSurfaceVariant),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          final minutes = responseTrend[spot.x.toInt()].round();
                          return LineTooltipItem(
                            '${labels[spot.x.toInt()]}\n$minutes mins',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withOpacity(0.12),
                      ),
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          final isToday = index == responseTrend.length - 1;
                          return FlDotCirclePainter(
                            radius: isToday ? 4.5 : 3.5,
                            color: isToday
                                ? AppColors.primary
                                : AppColors.primary.withOpacity(0.8),
                            strokeWidth: 1.5,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      spots: List.generate(
                        responseTrend.length,
                        (index) => FlSpot(index.toDouble(), responseTrend[index]),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'No response-time data available yet.',
                  style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                ),
              ),
            ),
    );
  }

  DateTime? _coerceDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is Map<String, dynamic>) {
      final seconds = value['_seconds'];
      final nanoseconds = value['_nanoseconds'];
      if (seconds is int) {
        final millis = (seconds * 1000) + ((nanoseconds is int ? nanoseconds : 0) ~/ 1000000);
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }
    return null;
  }

  double _calculateAvgResponseTime(List<QueryDocumentSnapshot> requests) {
    int totalMinutes = 0;
    int count = 0;
    for (var doc in requests) {
      final data = doc.data() as Map<String, dynamic>;
      final created = _coerceDateTime(data['createdAt']);
      final assigned = _coerceDateTime(data['assignedAt']);
      if (created != null && assigned != null && !assigned.isBefore(created)) {
        totalMinutes += assigned.difference(created).inMinutes;
        count++;
      }
    }
    return count > 0 ? totalMinutes / count : 0;
  }

  List<int> _requestCountsLast7Days(List<QueryDocumentSnapshot> requests) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<int>.filled(7, 0);
    for (final doc in requests) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = _coerceDateTime(data['createdAt']);
      if (createdAt == null) continue;
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      final diff = today.difference(date).inDays;
      if (diff >= 0 && diff < 7) {
        counts[6 - diff] += 1;
      }
    }
    return counts;
  }

  Map<String, int> _requestStatusCounts(List<QueryDocumentSnapshot> requests) {
    final counts = <String, int>{
      'pending': 0,
      'assigned': 0,
      'inProgress': 0,
      'completed': 0,
      'cancelled': 0,
    };
    for (final doc in requests) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'pending').toString();
      counts.update(status, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  List<double> _avgResponseTimeLast7Days(List<QueryDocumentSnapshot> requests) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final totalMinutes = List<int>.filled(7, 0);
    final counts = List<int>.filled(7, 0);

    for (final doc in requests) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = _coerceDateTime(data['createdAt']);
      final assignedAt = _coerceDateTime(data['assignedAt']);
      if (createdAt == null || assignedAt == null || assignedAt.isBefore(createdAt)) {
        continue;
      }

      final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
      final diff = today.difference(day).inDays;
      if (diff >= 0 && diff < 7) {
        final index = 6 - diff;
        totalMinutes[index] += assignedAt.difference(createdAt).inMinutes;
        counts[index] += 1;
      }
    }

    return List<double>.generate(7, (index) {
      if (counts[index] == 0) return 0;
      return totalMinutes[index] / counts[index];
    });
  }

  List<String> _last7DayLabels() {
    final now = DateTime.now();
    return List<String>.generate(7, (index) {
      final day = now.subtract(Duration(days: 6 - index));
      final weekday = _weekdayLabels[day.weekday % 7];
      final dayLabel = '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
      return '$weekday $dayLabel';
    });
  }

  // Helper method for responsive padding
  double _getResponsivePadding(double screenWidth) {
    if (screenWidth < 300) return 8;
    if (screenWidth < 400) return 12;
    if (screenWidth < 600) return 16;
    if (screenWidth < 900) return 20;
    return 24;
  }

  // ------------------------------------------------------------------------
  // Right Column (Quick Navigation + Activity Feed)
  // ------------------------------------------------------------------------
  Widget _buildRightColumn(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuickNavigation(context),
          const SizedBox(height: 24),
          _buildActivityFeed(context),
        ],
      ),
    );
  }

  Widget _buildQuickNavigation(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Navigation',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: textOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Column(
            spacing: 12,
            children: [
              _buildQuickNavTile(
                icon: Icons.manage_accounts,
                label: 'User Management',
                onTap: () => context.push('/user-management'),
                wide: true,
              ),
              _buildQuickNavTile(
                icon: Icons.verified_user,
                label: 'Provider Verification',
                onTap: () => context.push('/provider-verification?returnTo=/admin-dashboard'),
                wide: true,
              ),
              _buildQuickNavTile(
                icon: Icons.summarize,
                label: 'Analytics Reports',
                onTap: () => context.push('/reports'),
                wide: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickNavTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool wide = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final primary = AppColors.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
            ),
          ],
        ),
        child: wide
            ? Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(icon, color: primary, size: 24),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textOnSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.neutral500),
          ],
        )
            : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: primary, size: 24),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textOnSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityFeed(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'System Activity',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textOnSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/request-assignment?returnTo=/admin-dashboard'),
                child: Text(
                  'Open Queue',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('requests').snapshots(),
            builder: (context, requestSnapshot) {
              if (requestSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (requestSnapshot.hasError) {
                return Text('Error loading activity: ${requestSnapshot.error}');
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('users').snapshots(),
                builder: (context, usersSnapshot) {
                  if (usersSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (usersSnapshot.hasError) {
                    return Text('Error loading activity: ${usersSnapshot.error}');
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('feedback').snapshots(),
                    builder: (context, feedbackSnapshot) {
                      if (feedbackSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (feedbackSnapshot.hasError) {
                        return Text('Error loading activity: ${feedbackSnapshot.error}');
                      }

                      final items = _buildDerivedActivities(
                        requestDocs: requestSnapshot.data?.docs ?? [],
                        userDocs: usersSnapshot.data?.docs ?? [],
                        feedbackDocs: feedbackSnapshot.data?.docs ?? [],
                      );

                      if (items.isEmpty) {
                        return const Center(child: Text('No recent activity'));
                      }

                      return Column(
                        children: items
                            .map((item) => _buildActivityItem(context, item))
                            .toList(),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(BuildContext context, Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;

    Color bgColor;
    String title;
    String description;
    final timestamp = data['timestamp'] as Timestamp?;
    final explicitTitle = (data['title'] ?? '').toString();
    final explicitDescription = (data['description'] ?? '').toString();

    if (explicitTitle.isNotEmpty) {
      title = explicitTitle;
      description = explicitDescription;
      switch ((data['type'] ?? '').toString()) {
        case 'request_created':
          bgColor = Colors.blue.withOpacity(0.1);
          break;
        case 'request_completed':
          bgColor = AppColors.success.withOpacity(0.1);
          break;
        case 'feedback_received':
          bgColor = AppColors.accent.withOpacity(0.1);
          break;
        case 'provider_registered':
          bgColor = Colors.purple.withOpacity(0.1);
          break;
        default:
          bgColor = AppColors.neutral500.withOpacity(0.1);
      }
    } else {
      switch (data['type']) {
        case 'user_registered':
          bgColor = Colors.blue.withOpacity(0.1);
          title = 'New Resident Registered';
          description = data['description'] ?? 'Apartment 4B, Phase II joined the portal.';
          break;
        case 'request_assigned':
          bgColor = AppColors.accent.withOpacity(0.1);
          title = 'Plumbing Request Assigned';
          description = data['description'] ?? 'Samuel O. assigned to Ticket #8921';
          break;
        case 'system_maintenance':
          bgColor = AppColors.neutral500.withOpacity(0.1);
          title = 'System Maintenance';
          description = data['description'] ?? 'Scheduled for Sunday, 2:00 AM';
          break;
        case 'provider_onboarded':
          bgColor = AppColors.success.withOpacity(0.1);
          title = 'Provider Onboarded';
          description = data['description'] ?? 'CleanTech Services verified as vendor.';
          break;
        default:
          bgColor = AppColors.neutral500.withOpacity(0.1);
          title = data['title'] ?? 'Activity';
          description = data['description'] ?? '';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(
              Icons.notifications_active,
              color: primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textOnSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: textOnSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _timeAgo(timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: textOnSurfaceVariant.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildDerivedActivities({
    required List<QueryDocumentSnapshot> requestDocs,
    required List<QueryDocumentSnapshot> userDocs,
    required List<QueryDocumentSnapshot> feedbackDocs,
  }) {
    final items = <Map<String, dynamic>>[];

    for (final doc in requestDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null) {
        items.add({
          'type': 'request_created',
          'title': 'New ${data['serviceType'] ?? 'service'} request',
          'description': (data['description'] ?? 'A new request was submitted.').toString(),
          'timestamp': createdAt,
        });
      }

      final status = (data['status'] ?? '').toString().toLowerCase();
      final updatedAt = data['updatedAt'] as Timestamp?;
      if (status == 'completed' && updatedAt != null) {
        final providerName =
            (data['assignedProviderName'] ?? 'Provider').toString();
        final residentName = (data['residentName'] ?? 'Resident').toString();
        final location =
            (data['location'] ?? data['unit'] ?? 'the resident location').toString();
        items.add({
          'type': 'request_completed',
          'title': 'Request completed',
          'description':
              '$providerName completed ${(data['serviceType'] ?? 'service').toString()} work for $residentName at $location.',
          'timestamp': updatedAt,
        });
      }
    }

    for (final doc in userDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null &&
          (data['role'] ?? '').toString().toLowerCase() == 'provider') {
        items.add({
          'type': 'provider_registered',
          'title': 'New provider registered',
          'description': (data['fullName'] ?? data['email'] ?? 'Provider').toString(),
          'timestamp': createdAt,
        });
      }
    }

    for (final doc in feedbackDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null) {
        final rating = ((data['rating'] as num?)?.toDouble() ?? 0).toStringAsFixed(1);
        final providerName = (data['providerName'] ?? data['providerId'] ?? 'Provider').toString();
        final residentName = (data['residentName'] ?? 'Resident').toString();
        items.add({
          'type': 'feedback_received',
          'title': 'New feedback received',
          'description': '$residentName rated $providerName $rating/5',
          'timestamp': createdAt,
        });
      }
    }

    items.sort((a, b) {
      final aTs = a['timestamp'] as Timestamp?;
      final bTs = b['timestamp'] as Timestamp?;
      final aMs = aTs?.millisecondsSinceEpoch ?? 0;
      final bMs = bTs?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });

    return items.take(6).toList();
  }

  // ------------------------------------------------------------------------
  // Footer – fully responsive with Wrap and higher breakpoint
  // ------------------------------------------------------------------------
  Widget _buildFooter(BuildContext context, double screenWidth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    final securityWidget = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.security, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Security & Compliance',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'System environment: Production • AES-256 Encrypted',
              style: TextStyle(
                fontSize: 10,
                color: textOnSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );

    final linksWrap = Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton(onPressed: () {}, child: const Text('Privacy Policy')),
        TextButton(onPressed: () {}, child: const Text('System Logs')),
        TextButton(onPressed: () {}, child: const Text('API Docs')),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: screenWidth > 900
          ? Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          securityWidget,
          linksWrap,
        ],
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          securityWidget,
          const SizedBox(height: 16),
          linksWrap,
        ],
      ),
    );
  }

  // ------------------------------------------------------------------------
  // Drawer (mobile)
  // ------------------------------------------------------------------------
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: _buildSidebar(context),
    );
  }

  // ------------------------------------------------------------------------
  // Bottom Navigation Bar (mobile)
  // ------------------------------------------------------------------------
  Widget _buildBottomNavBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: surface.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMobileNavItem(
                  context,
                  icon: Icons.dashboard,
                  label: 'Dashboard',
                  isSelected: _selectedMobileIndex == 0,
                  onTap: () {
                    setState(() => _selectedMobileIndex = 0);
                    context.go('/admin-dashboard');
                  },
                ),
                _buildMobileNavItem(
                  context,
                  icon: Icons.analytics_outlined,
                  label: 'Reports',
                  isSelected: _selectedMobileIndex == 1,
                  onTap: () {
                    setState(() => _selectedMobileIndex = 1);
                    context.push('/reports');
                  },
                ),
                _buildMobileNavItem(
                  context,
                  icon: Icons.group_outlined,
                  label: 'Users',
                  isSelected: _selectedMobileIndex == 2,
                  onTap: () {
                    setState(() => _selectedMobileIndex = 2);
                    context.push('/user-management');
                  },
                ),
                _buildMobileNavItem(
                  context,
                  icon: Icons.verified_user_outlined,
                  label: 'Verifications',
                  isSelected: _selectedMobileIndex == 3,
                  onTap: () {
                    setState(() => _selectedMobileIndex = 3);
                    context.push('/provider-verification?returnTo=/admin-dashboard');
                  },
                ),
                _buildMobileNavItem(
                  context,
                  icon: Icons.assignment_ind_outlined,
                  label: 'Assign',
                  isSelected: _selectedMobileIndex == 4,
                  onTap: () {
                    setState(() => _selectedMobileIndex = 4);
                    context.push('/request-assignment?returnTo=/admin-dashboard');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileNavItem(
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}



