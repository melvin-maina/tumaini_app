import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

enum AdminNavSection {
  dashboard,
  reports,
  users,
  verifications,
  assignRequests,
  profile,
}

class AdminNavigationShell extends StatelessWidget {
  const AdminNavigationShell({
    super.key,
    required this.selectedSection,
    required this.body,
    required this.title,
    this.actions = const <Widget>[],
  });

  final AdminNavSection selectedSection;
  final Widget body;
  final String title;
  final List<Widget> actions;

  void _goToSection(BuildContext context, AdminNavSection section) {
    switch (section) {
      case AdminNavSection.dashboard:
        context.go('/admin-dashboard');
        break;
      case AdminNavSection.reports:
        context.go('/reports');
        break;
      case AdminNavSection.users:
        context.go('/user-management');
        break;
      case AdminNavSection.verifications:
        context.go('/provider-verification');
        break;
      case AdminNavSection.assignRequests:
        context.go('/request-assignment');
        break;
      case AdminNavSection.profile:
        context.go('/admin-profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;
    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final sidebarSurface = isDark ? AppColors.surfaceDarkElevated : Colors.white;
    final borderColor =
        isDark ? AppColors.borderDark : const Color(0xFFe2e2e4);

    return Scaffold(
      backgroundColor: surface,
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: surface,
              elevation: 0,
              title: Text(title),
              actions: actions,
            ),
      body: Row(
        children: [
          if (isDesktop)
            Container(
              width: 240,
              decoration: BoxDecoration(
                color: sidebarSurface,
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
                      _AdminSidebarItem(
                        icon: Icons.dashboard,
                        label: 'Dashboard',
                        isSelected: selectedSection == AdminNavSection.dashboard,
                        onTap: () => _goToSection(context, AdminNavSection.dashboard),
                      ),
                      _AdminSidebarItem(
                        icon: Icons.analytics_outlined,
                        label: 'Reports',
                        isSelected: selectedSection == AdminNavSection.reports,
                        onTap: () => _goToSection(context, AdminNavSection.reports),
                      ),
                      _AdminSidebarItem(
                        icon: Icons.group_outlined,
                        label: 'Users',
                        isSelected: selectedSection == AdminNavSection.users,
                        onTap: () => _goToSection(context, AdminNavSection.users),
                      ),
                      _AdminSidebarItem(
                        icon: Icons.verified_user_outlined,
                        label: 'Verifications',
                        isSelected: selectedSection == AdminNavSection.verifications,
                        onTap: () => _goToSection(context, AdminNavSection.verifications),
                      ),
                      _AdminSidebarItem(
                        icon: Icons.assignment_ind_outlined,
                        label: 'Assign Requests',
                        isSelected: selectedSection == AdminNavSection.assignRequests,
                        onTap: () => _goToSection(context, AdminNavSection.assignRequests),
                      ),
                      _AdminSidebarItem(
                        icon: Icons.person,
                        label: 'Profile',
                        isSelected: selectedSection == AdminNavSection.profile,
                        onTap: () => _goToSection(context, AdminNavSection.profile),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : Container(
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
                      _AdminBottomNavItem(
                        icon: Icons.dashboard,
                        label: 'Dash',
                        isSelected: selectedSection == AdminNavSection.dashboard,
                        onTap: () => _goToSection(context, AdminNavSection.dashboard),
                      ),
                      _AdminBottomNavItem(
                        icon: Icons.analytics_outlined,
                        label: 'Reports',
                        isSelected: selectedSection == AdminNavSection.reports,
                        onTap: () => _goToSection(context, AdminNavSection.reports),
                      ),
                      _AdminBottomNavItem(
                        icon: Icons.group_outlined,
                        label: 'Users',
                        isSelected: selectedSection == AdminNavSection.users,
                        onTap: () => _goToSection(context, AdminNavSection.users),
                      ),
                      _AdminBottomNavItem(
                        icon: Icons.verified_user_outlined,
                        label: 'Verify',
                        isSelected: selectedSection == AdminNavSection.verifications,
                        onTap: () => _goToSection(context, AdminNavSection.verifications),
                      ),
                      _AdminBottomNavItem(
                        icon: Icons.assignment_ind_outlined,
                        label: 'Assign',
                        isSelected: selectedSection == AdminNavSection.assignRequests,
                        onTap: () => _goToSection(context, AdminNavSection.assignRequests),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _AdminSidebarItem extends StatelessWidget {
  const _AdminSidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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

class _AdminBottomNavItem extends StatelessWidget {
  const _AdminBottomNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isSelected
        ? AppColors.primary
        : (isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark);

    return GestureDetector(
      onTap: onTap,
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
    );
  }
}
