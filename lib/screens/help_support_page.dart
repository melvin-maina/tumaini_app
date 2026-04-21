import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/app_home_action.dart';
import '../widgets/notification_bell_button.dart';

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _selectedCategory = 'Billing';
  bool _isSubmitting = false;

  final List<String> _categories = [
    'Billing',
    'Maintenance',
    'Security',
    'App Technical Issue',
    'Other',
  ];

  Future<void> _createAdminNotification({
    required String ticketId,
    required String category,
    required String subject,
    required String description,
    required String unit,
    required String phone,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': 'admin',
      'audience': 'admin',
      'supportTicketId': ticketId,
      'type': 'support_ticket_submitted',
      'title': 'New support ticket submitted',
      'message': subject,
      'category': category,
      'subject': subject,
      'description': description,
      'unit': unit,
      'phone': phone,
      'createdBy': currentUser?.uid ?? '',
      'createdByEmail': currentUser?.email ?? '',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _subjectController.dispose();
    _unitController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitTicket() async {
    if (_subjectController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a subject')),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the issue')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final ticketData = {
        'category': _selectedCategory,
        'subject': _subjectController.text.trim(),
        'unit': _unitController.text.trim(),
        'description': _descriptionController.text.trim(),
        'phone': _phoneController.text.trim(),
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
      };

      final ticketRef =
          await FirebaseFirestore.instance.collection('support_tickets').add(ticketData);

      var adminNotificationCreated = true;
      try {
        await _createAdminNotification(
          ticketId: ticketRef.id,
          category: ticketData['category']! as String,
          subject: ticketData['subject']! as String,
          description: ticketData['description']! as String,
          unit: ticketData['unit']! as String,
          phone: ticketData['phone']! as String,
        );
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          adminNotificationCreated = false;
        } else {
          rethrow;
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            adminNotificationCreated
                ? 'Support ticket submitted successfully!'
                : 'Support ticket submitted, but admin notification is blocked by Firestore rules.',
          ),
          backgroundColor: AppColors.success,
        ),
      );

      // Clear form
      _subjectController.clear();
      _unitController.clear();
      _descriptionController.clear();
      _phoneController.clear();
      setState(() {
        _selectedCategory = 'Billing';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting ticket: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 768;
    // Responsive padding: scales down on very small screens
    final padding = screenWidth < 300
        ? 8.0
        : screenWidth < 400
            ? 12.0
            : screenWidth < 600
                ? 16.0
                : isWide
                    ? 32.0
                    : 24.0;

    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final surfaceContainer = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text(
          'Help & Support',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
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
              isWide: isWide,
              textOnSurface: textOnSurface,
              textOnSurfaceVariant: textOnSurfaceVariant,
              surfaceContainer: surfaceContainer,
              primary: primary,
            ),
            const SizedBox(height: 20),

            // Search (currently decorative – can add filtering later)
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: surfaceContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search help topics, FAQs...',
                  prefixIcon: const Icon(Icons.search),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 32),

            Text(
              'Common Topics',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: textOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: isWide ? 4 : 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: isWide ? 1.6 : 1.35,
              children: [
                _buildCategoryCard(
                  icon: Icons.account_balance_wallet,
                  iconBg: primary.withOpacity(0.12),
                  iconColor: primary,
                  title: 'Billing',
                  subtitle: 'Payments & Invoices',
                ),
                _buildCategoryCard(
                  icon: Icons.engineering,
                  iconBg: const Color(0xFFFFDBCF),
                  iconColor: const Color(0xFF7E2900),
                  title: 'Maintenance',
                  subtitle: 'Repairs & Requests',
                ),
                _buildCategoryCard(
                  icon: Icons.security,
                  iconBg: AppColors.primaryTintLight,
                  iconColor: AppColors.primaryMuted,
                  title: 'Security',
                  subtitle: 'Access & Safety',
                ),
                _buildCategoryCard(
                  icon: Icons.phone_android,
                  iconBg: AppColors.accent.withOpacity(0.12),
                  iconColor: AppColors.warningStrong,
                  title: 'App Issues',
                  subtitle: 'Technical Support',
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Contact & Ticket form
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? AppColors.borderDark
                      : const Color(0xFFE2E2E4),
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
                    'Contact Support or Submit Ticket',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: textOnSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We usually respond within 24 hours (Mon–Fri 9 AM – 6 PM)',
                    style: TextStyle(
                      fontSize: 14,
                      color: textOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Category
                  _buildFormField(
                    label: 'Category',
                    child: DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      items: _categories.map((cat) {
                        return DropdownMenuItem(value: cat, child: Text(cat));
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedCategory = v!),
                      decoration: _inputDecoration(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Subject
                  _buildFormField(
                    label: 'Subject',
                    child: TextField(
                      controller: _subjectController,
                      decoration: _inputDecoration(hint: 'Brief summary of your issue'),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Unit
                  _buildFormField(
                    label: 'Unit Number',
                    child: TextField(
                      controller: _unitController,
                      decoration: _inputDecoration(hint: 'e.g. Apt 402, Block A'),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Description
                  _buildFormField(
                    label: 'Description',
                    child: TextField(
                      controller: _descriptionController,
                      maxLines: 5,
                      decoration: _inputDecoration(hint: 'Please describe the issue in detail...'),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Phone (optional)
                  _buildFormField(
                    label: 'Phone Number (optional)',
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration(hint: 'For faster follow-up'),
                    ),
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submitTicket,
                      icon: _isSubmitting
                          ? const SizedBox.shrink()
                          : const Icon(Icons.send),
                      label: _isSubmitting
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        'Submit Ticket',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 60),
              ],
            ),
          );

          if (!isWide) {
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
      bottomNavigationBar: isWide ? null : _buildBottomNavBar(context),
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
                isSelected: true,
                onTap: () {},
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

  InputDecoration _inputDecoration({String? hint}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.borderDark : const Color(0xFFE2E2E4);
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: isDark ? AppColors.surfaceDarkElevated : Colors.white,
      hintStyle: TextStyle(
        color: isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildFormField({required String label, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.borderLight : AppColors.surfaceDarkElevated,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildCategoryCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final borderColor =
        isDark ? AppColors.borderDark : const Color(0xFFE2E2E4);

    return InkWell(
      onTap: () {
        // Can navigate to category-specific help later
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening $title help articles...')),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1a1c1d),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.textSecondaryDark : AppColors.borderDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: surface.withOpacity(0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                icon: Icons.support_agent,
                label: 'Support',
                isSelected: true,
                onTap: () {}, // already here
              ),
              _buildNavItem(
                context,
                icon: Icons.person_outline,
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
    final color = isSelected ? AppColors.primary : (isDark ? AppColors.textSecondaryDark : AppColors.borderDark);

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

  Widget _buildHeaderCard({
    required bool isWide,
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
            child: Icon(Icons.support_agent, color: primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support Center',
                  style: TextStyle(
                    fontSize: isWide ? 30 : 24,
                    fontWeight: FontWeight.w700,
                    color: textOnSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Search common topics or send a support ticket when you need help with billing, maintenance, security, or the app itself.',
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
        : (isDark ? AppColors.textSecondaryDark : AppColors.borderDark);

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




