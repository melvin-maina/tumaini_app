import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/app_home_action.dart';
import '../widgets/notification_bell_button.dart';

class RequestTrackingPage extends StatefulWidget {
  const RequestTrackingPage({
    super.key,
    this.focusRequestId,
    this.returnTo,
  });

  final String? focusRequestId;
  final String? returnTo;

  @override
  State<RequestTrackingPage> createState() => _RequestTrackingPageState();
}

class _RequestTrackingPageState extends State<RequestTrackingPage> {
  final AuthService _auth = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Pending', 'Assigned', 'In Progress', 'Completed'];
  String? _lastAutoOpenedRequestId;

  String _normalizedStatus(dynamic rawStatus) {
    final status = (rawStatus ?? 'pending').toString().trim().toLowerCase();
    if (status == 'in progress') return 'inprogress';
    return status;
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
      context.go('/resident-dashboard');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';
    final date = timestamp.toDate();
    return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
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

  (String label, Color bgColor, Color textColor) _getStatusStyle(String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status.toLowerCase()) {
      case 'pending':
        return (
        'Pending',
        isDark ? AppColors.surfaceDarkElevated : const Color(0xFFe2e2e4),
        isDark ? AppColors.textSecondaryDark : const Color(0xFF434654)
        );
      case 'assigned':
        return (
        'Assigned',
        const Color(0xFFb1c2fd).withOpacity(0.3),
        const Color(0xFF344477)
        );
      case 'inprogress':
        return (
        'In Progress',
        const Color(0xFFffdbcf).withOpacity(0.3),
        const Color(0xFF802900)
        );
      case 'completed':
        return (
        'Completed',
        AppColors.success.withOpacity(0.1),
        AppColors.success
        );
      default:
        return ('Pending', AppColors.neutral200, AppColors.neutral500);
    }
  }

  void _showRequestDetails(BuildContext context, Map<String, dynamic> request, String requestId) {
    final status = _normalizedStatus(request['status']);
    final isCompleted = status == 'completed';
    final canLeaveFeedback = isCompleted;
    final urgency = (request['urgency'] ?? 'medium').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          request['serviceType'] == 'plumbing' ? 'Plumbing Issue' : 'Electrical Issue',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Description: ${request['description'] ?? 'No description'}'),
              const SizedBox(height: 12),
              Text('Status: ${status.toUpperCase()}'),
              const SizedBox(height: 8),
              Text('Urgency: ${urgency.toUpperCase()}'),
              const SizedBox(height: 8),
              Text('Created: ${_formatDate(request['createdAt'] as Timestamp?)}'),
              if (request['acceptedAt'] != null) ...[
                const SizedBox(height: 8),
                Text('Accepted: ${_formatDate(request['acceptedAt'] as Timestamp?)}'),
              ],
              if (request['inProgressAt'] != null) ...[
                const SizedBox(height: 8),
                Text('Work started: ${_formatDate(request['inProgressAt'] as Timestamp?)}'),
              ],
              if (request['completedAt'] != null) ...[
                const SizedBox(height: 8),
                Text('Completed: ${_formatDate(request['completedAt'] as Timestamp?)}'),
              ],
              if (request['assignedProviderId'] != null) ...[
                const SizedBox(height: 8),
                Text('Assigned to: ${request['assignedProviderName'] ?? request['assignedProviderId']}'),
              ],
              if (request['expectedArrivalWindow'] != null) ...[
                const SizedBox(height: 8),
                Text('Expected arrival: ${request['expectedArrivalWindow']}'),
              ],
              if (request['residentNotificationMessage'] != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(request['residentNotificationMessage']),
              ],
              if (isCompleted) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('How was your experience?', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ],
          ),
        ),
        actions: [
          if (canLeaveFeedback)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/feedback', extra: requestId);
              },
              child: const Text('Leave Feedback'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isWide = screenWidth >= 1024;
    // Responsive padding: scales down on very small screens
    final padding = screenWidth < 300
        ? 8.0
        : screenWidth < 400
            ? 12.0
            : screenWidth < 600
                ? 16.0
                : screenWidth < 768
                    ? 20.0
                    : isWide
                        ? 32.0
                        : 24.0;

    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final surfaceContainer = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final surfaceContainerHigh = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFe8e8ea);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final primaryContainer = AppColors.primary;
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);

    final userId = _auth.getCurrentUser()?.uid ?? '';

    if (userId.isEmpty) {
      return Scaffold(
        backgroundColor: surface,
        appBar: AppBar(
          backgroundColor: surface,
          elevation: 0,
          title: const Text('Service Requests'),
          actions: [
            const AppHomeAction(),
            NotificationBellButton(iconColor: textOnSurfaceVariant),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: surface,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/service-request'),
        backgroundColor: primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text('Service Requests'),
        actions: [
          const AppHomeAction(),
          NotificationBellButton(iconColor: textOnSurfaceVariant),
        ],
      ),
      body: Builder(
        builder: (context) {
          final content = SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _buildHeaderCard(
              textOnSurface: textOnSurface,
              textOnSurfaceVariant: textOnSurfaceVariant,
              surfaceContainer: surfaceContainer,
              primary: primary,
            ),
            const SizedBox(height: 24),

            // Search field
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: AppColors.neutral500),
                  hintText: 'Search requests...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Filter chips
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isSelected = filter == _selectedFilter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _selectedFilter = filter);
                      },
                      backgroundColor: surfaceContainerHigh,
                      selectedColor: primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isSelected ? primary : outlineVariant,
                        ),
                      ),
                      side: BorderSide(
                        color: isSelected ? primary : outlineVariant,
                      ),
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : textOnSurfaceVariant,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),

            // Requests list
            StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('requests')
                  .where('userId', isEqualTo: userId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Could not load requests: ${snapshot.error}',
                        style: TextStyle(fontSize: 14, color: textOnSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No requests found',
                        style: TextStyle(fontSize: 16, color: textOnSurfaceVariant),
                      ),
                    ),
                  );
                }

                var docs = snapshot.data!.docs.toList();
                docs.sort((a, b) {
                  final aTs = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                  final bTs = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                  final aMs = aTs?.millisecondsSinceEpoch ?? 0;
                  final bMs = bTs?.millisecondsSinceEpoch ?? 0;
                  return bMs.compareTo(aMs);
                });

                // Apply filter
                if (_selectedFilter != 'All') {
                  final statusMap = {
                    'Pending': 'pending',
                    'Assigned': 'assigned',
                    'In Progress': 'inprogress',
                    'Completed': 'completed',
                  };
                  final targetStatus = statusMap[_selectedFilter];
                  if (targetStatus != null) {
                    docs = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final status = _normalizedStatus(data['status']);
                      return status == targetStatus;
                    }).toList();
                  }
                }

                // Apply search
                if (_searchController.text.isNotEmpty) {
                  final query = _searchController.text.toLowerCase();
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['serviceType'] == 'plumbing' ? 'Plumbing Issue' : 'Electrical Issue';
                    final description = (data['description'] ?? '').toLowerCase();
                    return title.toLowerCase().contains(query) || description.contains(query);
                  }).toList();
                }

                if (widget.focusRequestId != null) {
                  QueryDocumentSnapshot? focusedDoc;
                  for (final doc in docs) {
                    if (doc.id == widget.focusRequestId) {
                      focusedDoc = doc;
                      break;
                    }
                  }
                  final matchedDoc = focusedDoc;
                  if (matchedDoc != null && _lastAutoOpenedRequestId != matchedDoc.id) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _lastAutoOpenedRequestId = matchedDoc.id;
                      _showRequestDetails(
                        context,
                        matchedDoc.data() as Map<String, dynamic>,
                        matchedDoc.id,
                      );
                    });
                  }
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No matching requests',
                        style: TextStyle(fontSize: 16, color: textOnSurfaceVariant),
                      ),
                    ),
                  );
                }

                if (isMobile) {
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildRequestCard(
                          context,
                          doc.id,
                          data,
                          isFocused: doc.id == widget.focusRequestId,
                        ),
                      );
                    },
                  );
                } else {
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 3 : 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return _buildRequestCard(
                        context,
                        doc.id,
                        data,
                        isFocused: doc.id == widget.focusRequestId,
                      );
                    },
                  );
                }
              },
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
                isSelected: false,
                onTap: () => context.go('/resident-dashboard'),
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
                isSelected: true,
                onTap: () {},
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

  Widget _buildRequestCard(
    BuildContext context,
    String requestId,
    Map<String, dynamic> data, {
    bool isFocused = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.borderDark : const Color(0xFFE2E2E4);
    final status = _normalizedStatus(data['status']);
    final serviceType = data['serviceType'] ?? 'Unknown';
    final title = serviceType == 'plumbing'
        ? 'Plumbing Request'
        : serviceType == 'electrical'
            ? 'Electrical Request'
            : '$serviceType Request';
    final description = data['description'] ?? 'No description provided';
    final createdAt = data['createdAt'] as Timestamp?;
    final (statusLabel, statusBg, statusTextColor) = _getStatusStyle(status);
    final canLeaveFeedback = status == 'completed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: status == 'completed' ? (isDark ? AppColors.surfaceDarkElevated : AppColors.neutral50) : (isDark ? AppColors.surfaceDark : Colors.white),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: status == 'completed'
              ? (isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.neutral50)
              : (isDark ? AppColors.surfaceDark : Colors.white),
          border: Border.all(
            color: isFocused ? AppColors.primary : borderColor,
            width: isFocused ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isFocused
                  ? AppColors.primary.withOpacity(0.14)
                  : Colors.black.withOpacity(isDark ? 0.08 : 0.04),
              blurRadius: isFocused ? 16 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      child: InkWell(
        onTap: () => _showRequestDetails(context, data, requestId),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusTextColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (isFocused)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Focused',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  Text(
                    _timeAgo(createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? AppColors.textMutedDark : AppColors.textMutedDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.borderDark,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (status == 'assigned' || status == 'inprogress')
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: AppColors.neutral500),
                        const SizedBox(width: 4),
                        Text(
                          'Provider assigned',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.textMutedDark : AppColors.textMutedDark,
                          ),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canLeaveFeedback)
                        TextButton(
                          onPressed: () => context.push('/feedback', extra: requestId),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Leave Feedback',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: () => _showRequestDetails(context, data, requestId),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildHeaderCard({
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
    required Color surfaceContainer,
    required Color primary,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.assignment, color: primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Service Requests',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: textOnSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Track every maintenance request, follow status updates, and open completed jobs when you need to leave feedback.',
                  style: TextStyle(
                    fontSize: 14,
                    color: textOnSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
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
                isSelected: false,
                onTap: () => context.go('/resident-dashboard'),
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
                isSelected: true,
                onTap: () {}, // already here
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



