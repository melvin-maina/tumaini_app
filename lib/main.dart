import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

// Screens
import 'home_page.dart';
import 'screens/login_page.dart';
import 'screens/registration_page.dart';
import 'screens/splash_page.dart';
import 'screens/resident_dashboard.dart';
import 'screens/provider_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'screens/request_tracking_page.dart';
import 'screens/service_request_page.dart';
import 'screens/feedback_page.dart';
import 'screens/reports_page.dart';
import 'screens/user_management_page.dart';
import 'screens/provider_profile_page.dart';
import 'screens/resident_profile_page.dart';
import 'screens/admin_profile_page.dart';
import 'screens/help_support_page.dart';
import 'screens/request_assignment_page.dart';
import 'screens/provider_verification_page.dart';
import 'screens/notifications_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class ProfileRedirectPage extends StatefulWidget {
  const ProfileRedirectPage({super.key});

  @override
  State<ProfileRedirectPage> createState() => _ProfileRedirectPageState();
}

class _ProfileRedirectPageState extends State<ProfileRedirectPage> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        if (mounted) context.go('/login');
        return;
      }

      final role = doc.data()?['role'] as String?;
      switch (role?.toLowerCase()) {
        case 'resident':
          if (mounted) context.go('/resident-profile');
          break;
        case 'provider':
          if (mounted) context.go('/provider-profile');
          break;
        case 'admin':
          if (mounted) context.go('/admin-profile');
          break;
        default:
          if (mounted) context.go('/login');
      }
    } catch (e) {
      debugPrint('Profile redirect failed: $e');
      if (mounted) context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter _router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;
        final path = state.uri.toString();

        // If not logged in, redirect to login except for public routes
        if (user == null) {
          if (path != '/' &&
              path != '/home' &&
              path != '/login' &&
              path != '/register') {
            return '/login';
          }
        }

        if (user != null && (path == '/login' || path == '/register')) {
          return '/home';
        }

        return null; // continue to requested route
      },
      routes: [
        GoRoute(
          path: '/',
          name: 'splash',
          builder: (context, state) => const SplashPage(),
        ),
        GoRoute(
          path: '/home',
          name: 'home',
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/register',
          name: 'register',
          builder: (context, state) => const RegistrationPage(),
        ),
        // Authenticated routes
        GoRoute(
          path: '/resident-dashboard',
          name: 'residentDashboard',
          builder: (context, state) => const ResidentDashboard(),
        ),
        GoRoute(
          path: '/provider-dashboard',
          name: 'providerDashboard',
          builder: (context, state) => ProviderDashboard(
            initialWorkQueueTab:
                int.tryParse(state.uri.queryParameters['tab'] ?? '0') == 1 ? 1 : 0,
          ),
        ),
        GoRoute(
          path: '/admin-dashboard',
          name: 'adminDashboard',
          builder: (context, state) => const AdminDashboard(),
        ),
        GoRoute(
          path: '/admin-profile',
          name: 'adminProfile',
          builder: (context, state) => const AdminProfilePage(),
        ),
        GoRoute(
          path: '/request-tracking',
          name: 'requestTracking',
          builder: (context, state) => RequestTrackingPage(
            focusRequestId: state.uri.queryParameters['requestId'],
            returnTo: state.uri.queryParameters['returnTo'],
          ),
        ),
        GoRoute(
          path: '/service-request',
          name: 'serviceRequest',
          builder: (context, state) => const ServiceRequestPage(),
        ),
        GoRoute(
          path: '/feedback',
          name: 'feedback',
          builder: (context, state) => FeedbackPage(requestId: state.extra as String?),
        ),
        GoRoute(
          path: '/reports',
          name: 'reports',
          builder: (context, state) => const ReportsPage(),
        ),
        GoRoute(
          path: '/user-management',
          name: 'userManagement',
          builder: (context, state) => const UserManagementPage(),
        ),
        GoRoute(
          path: '/provider-profile',
          name: 'providerProfile',
          builder: (context, state) => const ProviderProfilePage(),
        ),
        GoRoute(
          path: '/resident-profile',
          name: 'residentProfile',
          builder: (context, state) => const ResidentProfilePage(),
        ),
        GoRoute(
          path: '/request-assignment',
          name: 'requestAssignment',
          builder: (context, state) => RequestAssignmentPage(
            focusRequestId: state.uri.queryParameters['requestId'],
            returnTo: state.uri.queryParameters['returnTo'],
          ),
        ),
        GoRoute(
          path: '/provider-verification',
          name: 'providerVerification',
          builder: (context, state) => ProviderVerificationPage(
            focusProviderId: state.uri.queryParameters['providerId'],
            returnTo: state.uri.queryParameters['returnTo'],
          ),
        ),
        GoRoute(
          path: '/help-support',
          name: 'helpSupport',
          builder: (context, state) => const HelpSupportPage(),
        ),
        GoRoute(
          path: '/notifications',
          name: 'notifications',
          builder: (context, state) => const NotificationsPage(),
        ),
        // Profile redirect page
        GoRoute(
          path: '/profile',
          name: 'profile',
          builder: (context, state) => const ProfileRedirectPage(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Text('Page not found: ${state.uri}'),
        ),
      ),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeMode,
      builder: (context, selectedThemeMode, _) {
        return MaterialApp.router(
          title: 'Tumaini Estate',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: selectedThemeMode,
          routerConfig: _router,
          builder: (context, child) {
            return child ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}
