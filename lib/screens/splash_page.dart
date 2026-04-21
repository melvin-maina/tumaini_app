import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  bool _isChecking = true;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _progressAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndNavigate();
    });

    // Fallback timeout (in case of network/auth delay)
    Future.delayed(const Duration(seconds: 6), () {
      if (_isChecking && mounted) {
        context.go('/home');
      }
    });
  }

  Future<void> _checkAuthAndNavigate() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (mounted) context.go('/home');
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists || !mounted) {
        context.go('/login');
        return;
      }

      final role = doc.data()?['role'] as String?;
      final userData = doc.data() ?? <String, dynamic>{};

      switch (role?.toLowerCase()) {
        case 'resident':
          if (mounted) context.go('/resident-dashboard');
          break;
        case 'provider':
          final verified = userData['verified'] == true;
          final status = (userData['status'] ?? '').toString().toLowerCase();
          final isActive = verified && (status.isEmpty || status == 'active');
          if (mounted) context.go(isActive ? '/provider-dashboard' : '/provider-profile');
          break;
        case 'admin':
          if (mounted) context.go('/admin-dashboard');
          break;
        default:
          if (mounted) context.go('/login');
      }
    } catch (e) {
      debugPrint('Splash auth check error: $e');
      if (mounted) context.go('/home');
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
        _progressController.stop();
      }
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // All color variables used in the splash screen
    final bgColor = isDark ? AppColors.backgroundDark : const Color(0xFFf9f9fb);
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final mutedColor = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final outlineColor = isDark ? AppColors.textMutedDark : const Color(0xFF737686);
    final primary = AppColors.primary;

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated logo with rotation + verification badge
            Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: 0.2, // ~11.5 degrees
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primaryDeep, primary],
                      ),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withOpacity(0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Transform.rotate(
                      angle: -0.2,
                      child: const Icon(
                        Icons.apartment,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -8,
                  right: -8,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.verified,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            Text(
              'Tumaini Estate',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Premium Resident Services',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
                color: mutedColor,
              ),
            ),
            const SizedBox(height: 48),

            // Animated progress bar
            SizedBox(
              width: 140,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progressAnimation.value,
                  backgroundColor: isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0),
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primary.withOpacity(0.6),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Authenticating...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2,
                    color: outlineColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomSheet: Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: Center(
          child: Text(
            'SECURE ARCHITECTURAL PLATFORM',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: outlineColor,
            ),
          ),
        ),
      ),
    );
  }
}



