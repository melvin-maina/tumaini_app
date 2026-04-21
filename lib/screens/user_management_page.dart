import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_navigation_shell.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _selectedRole = 'All Roles';
  String _selectedStatus = 'All Status';
  int _currentPage = 1;
  int _itemsPerPage = 10;
  List<DocumentSnapshot> _allUsers = [];
  bool _isLoading = true;

  int _newRegistrations = 0;
  int _pendingVerifications = 0;
  double _identityVerified = 0.0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() => _currentPage = 1);
    });
  }

  void _updateDerivedStatsFromUsers(List<DocumentSnapshot> users) {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final providerDocs = users.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['role'] ?? '').toString().toLowerCase() == 'provider';
    }).toList();

    _newRegistrations = users.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'] as Timestamp?;
      return createdAt != null && createdAt.toDate().isAfter(thirtyDaysAgo);
    }).length;
    _pendingVerifications = providerDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['verified'] != true;
    }).length;
    _identityVerified = users.isEmpty
        ? 0
        : (providerDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['verified'] == true;
              }).length /
              users.length) *
            100;
  }

  List<DocumentSnapshot> _sortedUsers(List<DocumentSnapshot> users) {
    final sorted = [...users];
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

  List<DocumentSnapshot> _filteredUsers() {
    var filtered = _allUsers.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final role = (data['role'] ?? '').toString().toLowerCase();
      final status = (data['status'] ?? 'active').toString().toLowerCase();
      final name = (data['fullName'] ?? '').toLowerCase();
      final email = (data['email'] ?? '').toLowerCase();

      if (_selectedRole != 'All Roles' && role != _selectedRole.toLowerCase()) return false;
      if (_selectedStatus != 'All Status') {
        if (_selectedStatus == 'Active' && status != 'active') return false;
        if (_selectedStatus == 'Pending' && status != 'pending') return false;
        if (_selectedStatus == 'Suspended' && status != 'suspended') return false;
      }
      if (_searchController.text.isNotEmpty) {
        final query = _searchController.text.toLowerCase();
        if (!name.contains(query) && !email.contains(query)) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final aDate = (a.data() as Map)['createdAt'] as Timestamp?;
      final bDate = (b.data() as Map)['createdAt'] as Timestamp?;
      if (aDate == null || bDate == null) return 0;
      return bDate.compareTo(aDate);
    });
    return filtered;
  }

  List<DocumentSnapshot> _paginatedUsers() {
    final filtered = _filteredUsers();
    final start = (_currentPage - 1) * _itemsPerPage;
    final end = start + _itemsPerPage;
    if (start >= filtered.length) return [];
    return filtered.sublist(start, end > filtered.length ? filtered.length : end);
  }

  int _totalPages() {
    final count = _filteredUsers().length;
    return (count / _itemsPerPage).ceil();
  }

  void _changePage(int page) {
    if (page < 1 || page > _totalPages()) return;
    setState(() => _currentPage = page);
  }

  Future<void> _updateUserStatus(String userId, String newStatus) async {
    try {
      await _firestore.collection('users').doc(userId).update({'status': newStatus, 'updatedAt': FieldValue.serverTimestamp()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User status updated to $newStatus')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
    }
  }

  void _openProviderVerification(String providerId) {
    context.push('/provider-verification?providerId=$providerId&returnTo=/user-management');
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> userData, String userId) async {
    final nameController = TextEditingController(text: userData['fullName'] ?? '');
    final emailController = TextEditingController(text: userData['email'] ?? '');
    final phoneController = TextEditingController(text: userData['phone'] ?? '');
    final unitController = TextEditingController(text: userData['unit'] ?? '');
    final phaseController = TextEditingController(text: userData['phase'] ?? '');
    final role = (userData['role'] ?? 'resident').toString().toLowerCase();
    final isProvider = role == 'provider';
    final isResident = role == 'resident';
    bool isVerified = userData['verified'] ?? false;
    bool isSuspended = userData['status'] == 'suspended';
    String selectedSpecialty = (userData['specialty'] ?? '').toString().toLowerCase();
    if (selectedSpecialty != 'plumbing' && selectedSpecialty != 'electrical') {
      selectedSpecialty = '';
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name')),
                TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email'), enabled: false),
                TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
                if (isResident) ...[
                  TextField(controller: phaseController, decoration: const InputDecoration(labelText: 'Phase')),
                  TextField(controller: unitController, decoration: const InputDecoration(labelText: 'Unit')),
                ],
                if (isProvider) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedSpecialty.isEmpty ? null : selectedSpecialty,
                    decoration: const InputDecoration(labelText: 'Specialty'),
                    items: const [
                      DropdownMenuItem(value: 'plumbing', child: Text('Plumbing')),
                      DropdownMenuItem(value: 'electrical', child: Text('Electrical')),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedSpecialty = value ?? '');
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Verified:'),
                      const SizedBox(width: 8),
                      Switch(
                        value: isVerified,
                        onChanged: (value) => setDialogState(() => isVerified = value),
                        activeColor: AppColors.primary,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Suspended:'),
                    const SizedBox(width: 8),
                    Switch(
                      value: isSuspended,
                      onChanged: (value) => setDialogState(() => isSuspended = value),
                      activeColor: AppColors.error,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (isProvider && selectedSpecialty.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select provider specialty')),
                    );
                  }
                  return;
                }

                final updates = {
                  'fullName': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'status': isSuspended ? 'suspended' : 'active',
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                if (isProvider) {
                  updates['verified'] = isVerified;
                  updates['specialty'] = selectedSpecialty;
                }
                if (isResident) {
                  updates['phase'] = phaseController.text.trim();
                  updates['unit'] = unitController.text.trim();
                }

                try {
                  await _firestore.collection('users').doc(userId).update(updates);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User updated successfully')));
                    Navigator.pop(ctx);
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    unitController.dispose();
    phaseController.dispose();
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
    return 32;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final secondary = isDark ? AppColors.textMutedDark : AppColors.primaryMuted;
    final tertiary = isDark ? AppColors.textMutedDark : const Color(0xFF7e2900);
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);
    final error = isDark ? AppColors.error : const Color(0xFFba1a1a);

    return AdminNavigationShell(
      title: 'User Management',
      selectedSection: AdminNavSection.users,
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _allUsers.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading users\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error),
              ),
            );
          }

          final liveUsers = _sortedUsers(snapshot.data?.docs ?? <DocumentSnapshot>[]);
          _allUsers = liveUsers;
          _updateDerivedStatsFromUsers(liveUsers);
          _isLoading = false;

          return SingleChildScrollView(
            padding: EdgeInsets.all(_getResponsivePadding(screenWidth)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Header
            isMobile
                ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('User Management', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: textOnSurface)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text('Global Directory', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primary)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('${_allUsers.length} total active users', style: TextStyle(fontSize: 12, color: textOnSurfaceVariant), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/register'),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add New User'),
                    style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('User Management', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: textOnSurface)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text('Global Directory', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primary)),
                        ),
                        const SizedBox(width: 8),
                        Text('${_allUsers.length} total active users', style: TextStyle(fontSize: 12, color: textOnSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => context.push('/register'),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add New User'),
                  style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Filter bar
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
              child: isMobile
                  ? Column(
                children: [
                  _buildSearchField(),
                  const SizedBox(height: 12),
                  _buildRoleDropdown(),
                  const SizedBox(height: 12),
                  _buildStatusDropdown(),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {}))),
                ],
              )
                  : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 2, child: _buildSearchField()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildRoleDropdown()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatusDropdown()),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {})),
                ],
              ),
            ),
            const SizedBox(height: 32),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  decoration: BoxDecoration(color: surfaceContainerLowest, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Table header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(color: surfaceContainerLow.withOpacity(0.5), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                        child: Row(
                          children: [
                            SizedBox(width: 250, child: Text('User Information', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: textOnSurfaceVariant))),
                            const SizedBox(width: 16),
                            SizedBox(width: 120, child: Text('Role', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: textOnSurfaceVariant))),
                            const SizedBox(width: 16),
                            SizedBox(width: 120, child: Text('Joined Date', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: textOnSurfaceVariant))),
                            const SizedBox(width: 16),
                            SizedBox(width: 120, child: Text('Status', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: textOnSurfaceVariant))),
                            const SizedBox(width: 16),
                            SizedBox(width: 160, child: Text('Actions', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: textOnSurfaceVariant))),
                          ],
                        ),
                      ),

                      // Table rows
                      ..._paginatedUsers().map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final userId = doc.id;
                        final name = data['fullName'] ?? 'Unknown';
                        final email = data['email'] ?? '';
                        final role = data['role'] ?? '';
                        final joinedDate = data['createdAt'] as Timestamp?;
                        final status = data['status'] ?? 'active';
                        final isVerified = data['verified'] ?? false;
                        final isPendingProvider = role == 'provider' && !isVerified;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: outlineVariant.withOpacity(0.2)))),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 250,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(color: primary.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.network(
                                          data['avatarUrl'] ?? 'https://ui-avatars.com/api/?name=$name&background=0D8ABC&color=fff',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 24),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text(email, style: TextStyle(fontSize: 12, color: textOnSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(width: 120, child: _buildRoleChip(role)),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 120,
                                child: Text(
                                  joinedDate != null ? '${joinedDate.toDate().month}/${joinedDate.toDate().day}/${joinedDate.toDate().year}' : 'Unknown',
                                  style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(width: 120, child: _buildStatusChip(status, isPendingProvider)),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 160,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (isPendingProvider)
                                      IconButton(
                                        icon: const Icon(Icons.verified),
                                        onPressed: () => _openProviderVerification(userId),
                                        tooltip: 'Review Provider',
                                        color: primary,
                                      ),
                                    IconButton(icon: const Icon(Icons.edit_note), onPressed: () => _showEditUserDialog(data, userId), tooltip: 'Edit'),
                                    if (status != 'suspended')
                                      IconButton(icon: const Icon(Icons.block), onPressed: () => _updateUserStatus(userId, 'suspended'), tooltip: 'Suspend', color: error)
                                    else
                                      IconButton(icon: const Icon(Icons.check_circle), onPressed: () => _updateUserStatus(userId, 'active'), tooltip: 'Activate', color: AppColors.success),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      // Pagination
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: outlineVariant.withOpacity(0.2)))),
                        child: isMobile
                            ? Column(
                          children: [
                            Text(
                              'Showing ${((_currentPage - 1) * _itemsPerPage) + 1}-${(_currentPage * _itemsPerPage) > _filteredUsers().length ? _filteredUsers().length : _currentPage * _itemsPerPage} of ${_filteredUsers().length} users',
                              style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                            ),
                            const SizedBox(height: 12),
                            Wrap(alignment: WrapAlignment.center, spacing: 4, children: _buildPaginationButtons()),
                          ],
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Showing ${((_currentPage - 1) * _itemsPerPage) + 1}-${(_currentPage * _itemsPerPage) > _filteredUsers().length ? _filteredUsers().length : _currentPage * _itemsPerPage} of ${_filteredUsers().length} users',
                              style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                            ),
                            Row(children: _buildPaginationButtons()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // Stats cards
            Wrap(
              spacing: 24,
              runSpacing: 24,
              children: [
                _buildStatCard(icon: Icons.trending_up, title: 'New Registrations', value: _newRegistrations.toString(), change: '+12% Month', color: primary, bgColor: primary.withOpacity(0.05)),
                _buildStatCard(icon: Icons.pending_actions, title: 'Pending Verifications', value: _pendingVerifications.toString(), change: 'Awaiting Action', color: secondary, bgColor: surfaceContainerLow),
                _buildStatCard(icon: Icons.security, title: 'Identity Verified', value: '${_identityVerified.toStringAsFixed(1)}%', change: 'Audit Secure', color: tertiary, bgColor: surfaceContainerLowest, border: true),
              ],
            ),
            const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  // Helper methods – now compute their own colors
  Widget _buildSearchField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? AppColors.surfaceDark : Colors.white;
    final textColor = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Search Directory', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: textColor)),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Filter by name, email, or ID...',
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: fillColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? AppColors.surfaceDark : Colors.white;
    final textColor = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('System Role', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: textColor)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedRole,
          items: const [
            DropdownMenuItem(value: 'All Roles', child: Text('All Roles')),
            DropdownMenuItem(value: 'Resident', child: Text('Resident')),
            DropdownMenuItem(value: 'Provider', child: Text('Provider')),
            DropdownMenuItem(value: 'Admin', child: Text('Admin')),
          ],
          onChanged: (value) => setState(() {
            _selectedRole = value!;
            _currentPage = 1;
          }),
          decoration: InputDecoration(
            filled: true,
            fillColor: fillColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? AppColors.surfaceDark : Colors.white;
    final textColor = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Status', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: textColor)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedStatus,
          items: const [
            DropdownMenuItem(value: 'All Status', child: Text('All Status')),
            DropdownMenuItem(value: 'Active', child: Text('Active')),
            DropdownMenuItem(value: 'Pending', child: Text('Pending')),
            DropdownMenuItem(value: 'Suspended', child: Text('Suspended')),
          ],
          onChanged: (value) => setState(() {
            _selectedStatus = value!;
            _currentPage = 1;
          }),
          decoration: InputDecoration(
            filled: true,
            fillColor: fillColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPaginationButtons() {
    final total = _totalPages();
    final current = _currentPage;
    final List<Widget> buttons = [];

    buttons.add(IconButton(icon: const Icon(Icons.chevron_left), onPressed: current > 1 ? () => _changePage(current - 1) : null));

    for (int i = 1; i <= total; i++) {
      if (i == 1 || i == total || (i >= current - 2 && i <= current + 2)) {
        buttons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: () => _changePage(i),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: i == current ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(i.toString(), style: TextStyle(color: i == current ? Colors.white : null, fontWeight: FontWeight.bold))),
            ),
          ),
        ));
      } else if (i == 2 && current > 3) {
        buttons.add(const Text('...'));
      } else if (i == total - 1 && current < total - 2) {
        buttons.add(const Text('...'));
      }
    }

    buttons.add(IconButton(icon: const Icon(Icons.chevron_right), onPressed: current < total ? () => _changePage(current + 1) : null));
    return buttons;
  }

  Widget _buildRoleChip(String role) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor, textColor;
    String label;
    switch (role.toLowerCase()) {
      case 'resident':
        bgColor = const Color(0xFFb1c2fd).withOpacity(0.3);
        textColor = const Color(0xFF344477);
        label = 'Resident';
        break;
      case 'provider':
        bgColor = const Color(0xFFffdbcf).withOpacity(0.3);
        textColor = const Color(0xFF802900);
        label = 'Provider';
        break;
      case 'admin':
        bgColor = AppColors.primaryTintLight;
        textColor = const Color(0xFF003da9);
        label = 'Admin';
        break;
      default:
        bgColor = AppColors.neutral200;
        textColor = AppColors.borderDark;
        label = 'Unknown';
    }
    if (isDark) {
      bgColor = bgColor.withOpacity(0.2);
      textColor = textColor.withOpacity(0.8);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 0.5)),
    );
  }

  Widget _buildStatusChip(String status, bool isPendingProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color dotColor, textColor;
    String label;
    if (isPendingProvider) {
      dotColor = AppColors.accent;
      textColor = AppColors.warningStrong;
      label = 'Pending';
    } else {
      switch (status.toLowerCase()) {
        case 'active':
          dotColor = AppColors.success;
          textColor = AppColors.successStrong;
          label = 'Active';
          break;
        case 'suspended':
          dotColor = AppColors.error;
          textColor = AppColors.errorStrong;
          label = 'Suspended';
          break;
        default:
          dotColor = AppColors.neutral500;
          textColor = AppColors.borderDark;
          label = status;
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textColor)),
      ],
    );
  }

  Widget _buildStatCard({required IconData icon, required String title, required String value, required String change, required Color color, required Color bgColor, bool border = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return SizedBox(
      width: MediaQuery.of(context).size.width > 800 ? 280 : double.infinity,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(24), border: border ? Border.all(color: isDark ? AppColors.surfaceDarkElevated : AppColors.neutral200) : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)]), child: Icon(icon, color: color, size: 20)),
                Text(change, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 16),
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textOnSurface)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 12, color: textOnSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}




