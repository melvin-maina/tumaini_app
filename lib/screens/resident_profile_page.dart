import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/app_home_action.dart';
import '../widgets/notification_bell_button.dart';

class ResidentProfilePage extends StatefulWidget {
  const ResidentProfilePage({super.key});

  @override
  State<ResidentProfilePage> createState() => _ResidentProfilePageState();
}

class _ResidentProfilePageState extends State<ResidentProfilePage> {
  final AuthService _auth = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _unitController;

  String _selectedPhase = 'Phase II';
  bool _isOwner = true;
  bool _biometricEnabled = false;
  bool _notificationsEnabled = true;
  bool _serviceAlerts = true;
  bool _announcementAlerts = true;
  bool _isLoading = true;
  bool _isSaving = false;

  final List<String> _phases = ['Phase I', 'Phase II', 'Phase III', 'Phase IV'];

  String _normalizePhase(dynamic rawValue) {
    final value = (rawValue ?? '').toString().trim();
    if (value.isEmpty) return 'Phase II';

    if (_phases.contains(value)) return value;

    final lowercase = value.toLowerCase();
    const aliases = <String, String>{
      'phase 1': 'Phase I',
      'phase i': 'Phase I',
      '1': 'Phase I',
      'phase 2': 'Phase II',
      'phase ii': 'Phase II',
      '2': 'Phase II',
      'phase 3': 'Phase III',
      'phase iii': 'Phase III',
      '3': 'Phase III',
      'phase 4': 'Phase IV',
      'phase iv': 'Phase IV',
      '4': 'Phase IV',
    };

    return aliases[lowercase] ?? 'Phase II';
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _unitController = TextEditingController();
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
          _unitController.text = data['unit'] ?? '';
          _selectedPhase = _normalizePhase(data['phase']);
          _isOwner = data['isOwner'] ?? true;
          _biometricEnabled = data['biometricEnabled'] ?? false;
          _notificationsEnabled = data['notificationsEnabled'] ?? true;
          _serviceAlerts = data['serviceAlerts'] ?? true;
          _announcementAlerts = data['announcementAlerts'] ?? true;
          _isLoading = false;
        });
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
        'unit': _unitController.text.trim(),
        'phase': _selectedPhase,
        'isOwner': _isOwner,
        'biometricEnabled': _biometricEnabled,
        'notificationsEnabled': _notificationsEnabled,
        'serviceAlerts': _serviceAlerts,
        'announcementAlerts': _announcementAlerts,
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
          SnackBar(content: Text('Error saving profile: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _unitController.dispose();
    super.dispose();
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
    var serviceAlerts = _serviceAlerts;
    var announcementAlerts = _announcementAlerts;

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
                    onChanged: (value) {
                      setDialogState(() => notificationsEnabled = value);
                    },
                  ),
                  SwitchListTile(
                    value: serviceAlerts,
                    title: const Text('Service request updates'),
                    onChanged: notificationsEnabled
                        ? (value) => setDialogState(() => serviceAlerts = value)
                        : null,
                  ),
                  SwitchListTile(
                    value: announcementAlerts,
                    title: const Text('Estate announcements'),
                    onChanged: notificationsEnabled
                        ? (value) => setDialogState(() => announcementAlerts = value)
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
      'serviceAlerts': serviceAlerts,
      'announcementAlerts': announcementAlerts,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    setState(() {
      _notificationsEnabled = notificationsEnabled;
      _serviceAlerts = serviceAlerts;
      _announcementAlerts = announcementAlerts;
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
    try {
      await _auth.signOut();
      if (!mounted) return;
      context.go('/login');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to log out'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to log out'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = screenWidth < 768;
    final isWide = screenWidth >= 1024;
    final padding = isWide ? 32.0 : (screenWidth >= 768 ? 24.0 : 16.0);

    // All color variables used anywhere in the file
    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final surfaceContainer = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final surfaceContainerHigh = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFe8e8ea);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final primaryContainer = AppColors.primary;
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);
    final tertiaryFixed = const Color(0xFFffdbcf);
    final onTertiaryFixedVariant = const Color(0xFF802900);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text('Resident Profile'),
        actions: [
          const AppHomeAction(),
          NotificationBellButton(iconColor: textOnSurfaceVariant),
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
            _buildHeroSection(
              context,
              primaryContainer: primaryContainer,
              tertiaryFixed: tertiaryFixed,
              onTertiaryFixedVariant: onTertiaryFixedVariant,
              textOnSurface: textOnSurface,
            ),
            const SizedBox(height: 32),

            isMobile
                ? Column(
              children: [
                _buildPersonalDetailsCard(
                  context,
                  surfaceContainer,
                  surfaceContainerLowest,
                  textOnSurface,
                  textOnSurfaceVariant,
                  outlineVariant,
                ),
                const SizedBox(height: 24),
                _buildAccountSettingsCard(
                  context,
                  primary,
                  surfaceContainerLowest,
                  textOnSurface,
                  textOnSurfaceVariant,
                  outlineVariant,
                ),
                const SizedBox(height: 24),
                _buildEstateInfoCard(
                  context,
                  surfaceContainerLow,
                  primaryContainer,
                  textOnSurface,
                  textOnSurfaceVariant,
                  outlineVariant,
                ),
                const SizedBox(height: 24),
                _buildSecurityCard(
                  context,
                  surfaceContainerLowest,
                  textOnSurface,
                  textOnSurfaceVariant,
                  outlineVariant,
                ),
                const SizedBox(height: 32),
                _buildSaveButton(),
              ],
            )
                : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      _buildPersonalDetailsCard(
                        context,
                        surfaceContainer,
                        surfaceContainerLowest,
                        textOnSurface,
                        textOnSurfaceVariant,
                        outlineVariant,
                      ),
                      const SizedBox(height: 24),
                      _buildAccountSettingsCard(
                        context,
                        primary,
                        surfaceContainerLowest,
                        textOnSurface,
                        textOnSurfaceVariant,
                        outlineVariant,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _buildEstateInfoCard(
                        context,
                        surfaceContainerLow,
                        primaryContainer,
                        textOnSurface,
                        textOnSurfaceVariant,
                        outlineVariant,
                      ),
                      const SizedBox(height: 24),
                      _buildSecurityCard(
                        context,
                        surfaceContainerLowest,
                        textOnSurface,
                        textOnSurfaceVariant,
                        outlineVariant,
                      ),
                      const SizedBox(height: 32),
                      _buildSaveButton(),
                    ],
                  ),
                ),
              ],
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
                isSelected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(
      BuildContext context, {
        required Color primaryContainer,
        required Color tertiaryFixed,
        required Color onTertiaryFixedVariant,
        required Color textOnSurface,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerHigh = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFe8e8ea);
    final primary = AppColors.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surfaceContainerHigh,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  _auth.getCurrentUser()?.photoURL ??
                      'https://ui-avatars.com/api/?name=${_nameController.text.isNotEmpty ? _nameController.text : 'Resident'}&background=0D8ABC&color=fff',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 60),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Photo upload coming soon')),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryContainer,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 16),
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
              Text(
                _nameController.text.isEmpty ? 'Resident' : _nameController.text,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: textOnSurface,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _selectedPhase,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: primary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: tertiaryFixed,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _isOwner ? 'Owner' : 'Tenant',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: onTertiaryFixedVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalDetailsCard(
      BuildContext context,
      Color surfaceContainer,
      Color surfaceContainerLowest,
      Color textOnSurface,
      Color textOnSurfaceVariant,
      Color outlineVariant,
      ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Details',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: textOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildProfileField(
            label: 'Full Name',
            controller: _nameController,
            surfaceContainer: surfaceContainer,
            textColor: textOnSurface,
            hintColor: textOnSurfaceVariant,
          ),
          const SizedBox(height: 16),
          _buildProfileField(
            label: 'Email Address',
            controller: _emailController,
            surfaceContainer: surfaceContainer,
            textColor: textOnSurface,
            hintColor: textOnSurfaceVariant,
            readOnly: true,
          ),
          const SizedBox(height: 16),
          _buildProfileField(
            label: 'Phone Number',
            controller: _phoneController,
            surfaceContainer: surfaceContainer,
            textColor: textOnSurface,
            hintColor: textOnSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileField({
    required String label,
    required TextEditingController controller,
    required Color surfaceContainer,
    required Color textColor,
    required Color hintColor,
    bool readOnly = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.textSecondaryDark : const Color(0xFF434654),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: readOnly,
          style: TextStyle(
            color: textColor,
            fontWeight: readOnly ? FontWeight.w500 : FontWeight.w400,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: surfaceContainer,
            hintStyle: TextStyle(color: hintColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSettingsCard(
      BuildContext context,
      Color primary,
      Color surfaceContainerLowest,
      Color textOnSurface,
      Color textOnSurfaceVariant,
      Color outlineVariant,
      ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Settings',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: textOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _showChangePasswordDialog,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.lock_reset, color: primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Change Password',
                      style: TextStyle(fontWeight: FontWeight.w500, color: textOnSurface),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.neutral500),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _showNotificationSettingsDialog,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.notifications, color: primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Notification Settings',
                      style: TextStyle(fontWeight: FontWeight.w500, color: textOnSurface),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.neutral500),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _logout,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.logout, color: AppColors.error),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Log Out',
                      style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.error),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.neutral500),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstateInfoCard(
      BuildContext context,
      Color surfaceContainerLow,
      Color primaryContainer,
      Color textOnSurface,
      Color textOnSurfaceVariant,
      Color outlineVariant,
      ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estate Info',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: textOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            label: 'Unit Number',
            textColor: textOnSurface,
            child: TextField(
              controller: _unitController,
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                hintStyle: TextStyle(color: textOnSurfaceVariant),
              ),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: textOnSurface,
              ),
            ),
          ),
          const Divider(height: 24),
          _buildInfoRow(
            label: 'Phase',
            textColor: textOnSurface,
            child: DropdownButton<String>(
              value: _phases.contains(_selectedPhase) ? _selectedPhase : null,
              items: _phases.map((phase) {
                return DropdownMenuItem(value: phase, child: Text(phase));
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedPhase = value);
              },
              underline: const SizedBox(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textOnSurface,
              ),
            ),
          ),
          const Divider(height: 24),
          _buildInfoRow(
            label: 'Residency',
            textColor: textOnSurface,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(
                    'Owner',
                    style: TextStyle(
                      color: _isOwner ? Colors.white : textOnSurface,
                    ),
                  ),
                  selected: _isOwner,
                  onSelected: (selected) => setState(() => _isOwner = selected),
                  selectedColor: primaryContainer,
                  backgroundColor: Colors.transparent,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(
                    'Tenant',
                    style: TextStyle(
                      color: !_isOwner ? Colors.white : textOnSurface,
                    ),
                  ),
                  selected: !_isOwner,
                  onSelected: (selected) => setState(() => _isOwner = !selected),
                  selectedColor: primaryContainer,
                  backgroundColor: Colors.transparent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required Widget child,
    required Color textColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w500, color: textColor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Align(
            alignment: Alignment.centerRight,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityCard(
      BuildContext context,
      Color surfaceContainerLowest,
      Color textOnSurface,
      Color textOnSurfaceVariant,
      Color outlineVariant,
      ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: textOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.fingerprint),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Biometric Login',
                        style: TextStyle(color: textOnSurface),
                      ),
                      Text(
                        'FaceID or Fingerprint',
                        style: TextStyle(fontSize: 10, color: textOnSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: _biometricEnabled,
                onChanged: (value) async {
                  final user = _auth.getCurrentUser();
                  if (user == null) return;
                  setState(() => _biometricEnabled = value);
                  await _firestore.collection('users').doc(user.uid).update({
                    'biometricEnabled': value,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Biometric ${value ? "enabled" : "disabled"}'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                },
                activeColor: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveChanges,
        icon: _isSaving
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.save, size: 20),
        label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                isSelected: false,
                onTap: () => context.go('/request-tracking'),
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



