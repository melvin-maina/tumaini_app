import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _initialsFromName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'U';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<Map<String, dynamic>?> _loadUserProfile(String userId) async {
    if (userId.isEmpty) return null;
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.data();
  }

  String _dashboardRouteForRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return '/admin-dashboard';
      case 'provider':
        return '/provider-dashboard';
      case 'resident':
      default:
        return '/resident-dashboard';
    }
  }

  bool _canCreateServiceRequest(String role) {
    return role.toLowerCase() == 'resident';
  }

  String _heroSubtitleForRole(String role) {
    switch (role.toLowerCase()) {
      case 'provider':
        return 'Welcome back to Tumaini Estate. Open your dashboard, review assignments, and keep your work queue moving smoothly.';
      case 'admin':
        return 'Welcome back to Tumaini Estate. Open your dashboard, review operations, and keep the platform running smoothly.';
      case 'resident':
      default:
        return 'Welcome back to Tumaini Estate. Review updates, open your dashboard, and handle service requests without leaving home.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;

    // ──────────────────────────────────────────────
    // ALL color variables used anywhere in the file
    // ──────────────────────────────────────────────
    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final surfaceContainerHigh = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFe8e8ea);
    final primary = colorScheme.primary;
    final accent = colorScheme.secondary;
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);
    final textSecondary = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    // Button widths calculation (only for desktop)
    final horizontalPadding = 24.0 * 2;
    final buttonGap = 16.0;
    final availableWidth = screenWidth - horizontalPadding;
    final buttonWidth = (availableWidth - buttonGap) / 2;

    // Responsive font sizes
    final heroTitleFontSize = isMobile ? 32.0 : (isTablet ? 40.0 : 48.0);
    final heroSubtitleFontSize = isMobile ? 16.0 : 18.0;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text(
          'Tumaini Estate',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
                PopupMenuButton<ThemeMode>(
                  tooltip: 'Theme',
                  icon: const Icon(Icons.color_lens_outlined),
                  onSelected: ThemeController.setThemeMode,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light mode'),
                    ),
                    PopupMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark mode'),
                    ),
                    PopupMenuItem(
                      value: ThemeMode.system,
                      child: Text('Use system'),
                    ),
                  ],
                ),
                if (isLoggedIn) ...[
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {},
                  color: textSecondary,
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {},
                  color: textSecondary,
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    onTap: () => context.go('/profile'),
                    borderRadius: BorderRadius.circular(999),
                    child: FutureBuilder<Map<String, dynamic>?>(
                      future: _loadUserProfile(user.uid),
                      builder: (context, snapshot) {
                        final data = snapshot.data ?? const <String, dynamic>{};
                        final fullName = (data['fullName'] ?? user.displayName ?? '').toString();
                        final photoUrl = (data['photoUrl'] ?? user.photoURL ?? '').toString();
                        final initials = _initialsFromName(fullName);

                        return Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: surfaceContainerHigh,
                            border: Border.all(
                              color: primary.withOpacity(0.24),
                            ),
                          ),
                          child: ClipOval(
                            child: photoUrl.isNotEmpty
                                ? Image.network(
                                    photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Center(
                                      child: Text(
                                        initials,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      initials,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                ],
              ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Section
            SizedBox(
              height: 700,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuBJD2Jd9rk732K79daAF3teVLcQUwdspVPCQyON8hfUuLkaOVMal4MoQ5TC8d0unw4JqmWJXKhlGvxiQN42LJXy28exAJVFWK9sCDHCUs1wznYzMPIG4XdB92vRQDXzvUJJ5v1cci3pTq0WRYgr2hVxT4wPQFxHK_VCTaCuPfP59N8POwrlTy_Tm2IpRhO8zSMUIg54IOvzkslYzHblkB4v44m5kwh0mgj8ZOUAaIxE1l28H3cxGsnQ_sXON-1vsr3f-eQs_0k7gNk',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: AppColors.borderLight),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            isDark
                                ? AppColors.primaryDeep.withOpacity(0.78)
                                : AppColors.primaryDeep.withOpacity(0.92),
                            primary.withOpacity(isDark ? 0.84 : 0.74),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withOpacity(0.08),
                            primary.withOpacity(isDark ? 0.42 : 0.30),
                            Colors.black.withOpacity(isDark ? 0.22 : 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: const Text(
                            'The Architectural Curator',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Tumaini Estate Service Platform',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: heroTitleFontSize,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: isMobile ? double.infinity : 400,
                          child: isLoggedIn
                              ? FutureBuilder<Map<String, dynamic>?>(
                                  future: _loadUserProfile(user.uid),
                                  builder: (context, snapshot) {
                                    final userData = snapshot.data ?? <String, dynamic>{};
                                    final role =
                                        (userData['role'] ?? 'resident').toString();

                                    return Text(
                                      _heroSubtitleForRole(role),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: heroSubtitleFontSize,
                                        height: 1.4,
                                      ),
                                    );
                                  },
                                )
                              : Text(
                                  'Experience a premium digital ecosystem designed for modern living. Manage your residency with architectural precision and ease.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: heroSubtitleFontSize,
                                    height: 1.4,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 32),
                        // Button Row - Responsive (stacked on mobile, side-by-side on tablet/desktop)
                        if (isLoggedIn)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _loadUserProfile(user.uid),
                            builder: (context, snapshot) {
                              final userData = snapshot.data ?? <String, dynamic>{};
                              final role = (userData['role'] ?? 'resident').toString();

                              return _buildLoggedInHeroActions(
                                context,
                                isMobile: isMobile,
                                primary: primary,
                                buttonWidth: buttonWidth,
                                role: role,
                                dashboardRoute: _dashboardRouteForRole(role),
                              );
                            },
                          )
                        else if (isMobile)
                          Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => context.replace('/register'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: primary,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 8,
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Register', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 18),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => context.replace('/login'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white, width: 1.5),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Login',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              SizedBox(
                                width: buttonWidth,
                                child: ElevatedButton(
                                  onPressed: () => context.replace('/register'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: primary,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 8,
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Register', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 18),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: buttonWidth,
                                child: OutlinedButton(
                                  onPressed: () => context.replace('/login'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white, width: 1.5),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Login',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 24),
                        Text(
                          isLoggedIn ? 'Resident access active' : 'Available for Members Only',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bento Grid Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                children: [
                  // Support + Highlight Cards (stack on mobile, side-by-side on tablet/desktop)
                  if (isMobile)
                    Column(
                      children: [
                        _buildSupportCard(context),
                        const SizedBox(height: 24),
                        _buildHighlightCard(context),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: _buildSupportCard(context),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 8,
                          child: _buildHighlightCard(context),
                        ),
                      ],
                    ),
                  const SizedBox(height: 40),

                  // Feature Cards – Wrap for tablet/desktop, Column for mobile
                  isMobile
                      ? Column(
                    children: [
                      _buildFeatureItemMobile(
                        icon: Icons.security,
                        title: 'Secure Access',
                        description: 'Military-grade encryption for all your personal data and estate transactions.',
                        iconColor: primary.withOpacity(isDark ? 0.90 : 0.78),
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItemMobile(
                        icon: Icons.analytics,
                        title: 'Real-time Tracking',
                        description: 'Monitor your utility consumption and service requests in real-time.',
                        iconColor: primary.withOpacity(isDark ? 0.90 : 0.78),
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItemMobile(
                        icon: Icons.group,
                        title: 'Community First',
                        description: 'Connect with your neighbors and stay informed about local events.',
                        iconColor: primary.withOpacity(isDark ? 0.90 : 0.78),
                        textSecondary: textSecondary,
                      ),
                    ],
                  )
                      : Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: [
                      SizedBox(
                        width: (screenWidth - 48 - 48) / 3, // Responsive width for each card
                        child: _buildFeatureItem(
                          icon: Icons.security,
                          title: 'Secure Access',
                          description: 'Military-grade encryption for all your personal data and estate transactions.',
                          iconColor: primary.withOpacity(isDark ? 0.90 : 0.78),
                          bgColor: surfaceContainerLowest,
                          borderColor: outlineVariant.withOpacity(0.1),
                          textSecondary: textSecondary,
                        ),
                      ),
                      SizedBox(
                        width: (screenWidth - 48 - 48) / 3,
                        child: _buildFeatureItem(
                          icon: Icons.analytics,
                          title: 'Real-time Tracking',
                          description: 'Monitor your utility consumption and service requests in real-time.',
                          iconColor: primary.withOpacity(isDark ? 0.90 : 0.78),
                          bgColor: surfaceContainerLowest,
                          borderColor: outlineVariant.withOpacity(0.1),
                          textSecondary: textSecondary,
                        ),
                      ),
                      SizedBox(
                        width: (screenWidth - 48 - 48) / 3,
                        child: _buildFeatureItem(
                          icon: Icons.group,
                          title: 'Community First',
                          description: 'Connect with your neighbors and stay informed about local events.',
                          iconColor: primary.withOpacity(isDark ? 0.90 : 0.78),
                          bgColor: surfaceContainerLowest,
                          borderColor: outlineVariant.withOpacity(0.1),
                          textSecondary: textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: outlineVariant.withOpacity(0.15)),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Tumaini Estate',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {},
                        child: const Text('Privacy Policy'),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Terms of Service'),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Support'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '© 2024 Tumaini Estate Platform',
                    style: TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // Widgets
  // ----------------------------------------------------------------------

  Widget _buildLoggedInHeroActions(
    BuildContext context, {
    required bool isMobile,
    required Color primary,
    required double buttonWidth,
    required String role,
    required String dashboardRoute,
  }) {
    final canCreateServiceRequest = _canCreateServiceRequest(role);

    if (isMobile) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go(dashboardRoute),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 8,
              ),
              child: const Text(
                'Open Dashboard',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (canCreateServiceRequest) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/service-request'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'New Service Request',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: buttonWidth,
          child: ElevatedButton(
            onPressed: () => context.go(dashboardRoute),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
            ),
            child: const Text(
              'Open Dashboard',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (canCreateServiceRequest) ...[
          const SizedBox(width: 16),
          SizedBox(
            width: buttonWidth,
            child: OutlinedButton(
              onPressed: () => context.go('/service-request'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'New Service Request',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSupportCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final textColor = isDark ? AppColors.textDark : const Color(0xFF1a1c1d);
    final textSecondary = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = Theme.of(context).colorScheme.primary;
    final secondaryFixed = isDark ? AppColors.surfaceDarkElevated : AppColors.primaryTintLight;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: secondaryFixed.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: secondaryFixed,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.help_center,
              color: primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Need Support?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: textColor,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Our dedicated management office is here to assist you with any inquiries or estate-related issues.',
            style: TextStyle(
              fontSize: 14,
              color: textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contact office (demo)')),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: primary.withOpacity(0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Contact Office',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final textColor = isDark ? AppColors.textDark : const Color(0xFF1a1c1d);
    final textSecondary = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        image: const DecorationImage(
          image: NetworkImage(
            'https://lh3.googleusercontent.com/aida-public/AB6AXuDvg-NJaOvyuJQjqg4jJ7rgsbH0gdXseieTzwebD-499Ce7Hd26_TPXLI8C9r0yUoDRt8V04YiuOf-dMzvVFVnwg9ge9-IUlQiV8-OXVWHbVvAIKVvFF7aqmVdwqRWYxElN3Ll7F5_fzc1Lt_B83yKeZlpsNdV-x6o7QLVeLmat_a3-Kp6RodroixkY8KnIS_4r3vbGlt7YwYddik4qURlvt-SYK8kmrG9ZudO2MI2d6TTaeZC4Cxly41tmbJYPltf-fQdEyqv9QRc',
          ),
          fit: BoxFit.cover,
          opacity: 0.1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Estate Highlights',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Seamless Integration',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Discover a suite of tools designed to simplify your daily life. From maintenance requests to amenity bookings, everything is just a tap away within the Tumaini ecosystem.',
              style: TextStyle(
                fontSize: 14,
                color: textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required Color textSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItemMobile({
    required IconData icon,
    required String title,
    required String description,
    required Color iconColor,
    required Color textSecondary,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  style: TextStyle(
                    fontSize: 14,
                    color: textSecondary,
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
}





