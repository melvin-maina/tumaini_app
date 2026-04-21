import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/app_home_action.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _apartmentNumberController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _selectedRole = 'resident';
  String? _selectedProviderSpecialty;
  bool _termsAccepted = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  final AuthService _auth = AuthService();

  String _normalizeKenyanPhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('254') && digits.length >= 12) {
      return '+${digits.substring(0, 12)}';
    }
    if (digits.startsWith('0') && digits.length >= 10) {
      return '+254${digits.substring(1, 10)}';
    }
    if (digits.length >= 9) {
      return '+254${digits.substring(0, 9)}';
    }
    return '+254$digits';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _apartmentNumberController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildUserData() {
    final userData = <String, dynamic>{
      'fullName': _nameController.text.trim(),
      'phone': _normalizeKenyanPhone(_phoneController.text.trim()),
      'email': _emailController.text.trim(),
      'role': _selectedRole,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (_selectedRole == 'provider') {
      userData.addAll({
        'isAvailable': true,
        'serviceAreas': [],
        'verified': false,
        'status': 'pending',
        'specialty': _selectedProviderSpecialty,
      });
    } else {
      userData.addAll({
        'isOwner': true,
        'unit': _apartmentNumberController.text.trim(),
        'phase': '',
      });
    }

    return userData;
  }

  Future<bool> _recoverDeletedProfileIfPossible() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final existingUser = await _auth.signInWithEmailAndPassword(email, password);
    if (existingUser == null) return false;

    final existingData = await _auth.getUserData(existingUser.uid);
    if (existingData != null) {
      await _auth.signOut();
      return false;
    }

    await _auth.createUserDocument(existingUser.uid, _buildUserData());
    await _auth.signOut();
    return true;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms and conditions')),
      );
      return;
    }
    if (_selectedRole == 'provider' && _selectedProviderSpecialty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select provider specialty')),
      );
      return;
    }

    setState(() => _isLoading = true);
    var shouldRedirectToLogin = false;

    try {
      User? user = await _auth.signUpWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (user != null) {
        await _auth.createUserDocument(user.uid, _buildUserData());
        await _auth.signOut();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration successful! Please login.')),
          );
          context.go('/login');
        }
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'The password is too weak. Use at least 6 characters.';
          break;
        case 'email-already-in-use':
          try {
            final recovered = await _recoverDeletedProfileIfPossible();
            if (recovered) {
              message =
                  'This email already existed in authentication, but the missing profile was restored. Please login.';
              shouldRedirectToLogin = true;
              break;
            }
          } on FirebaseAuthException catch (_) {
            // Fall through to the standard message below if the password is wrong
            // or the existing account should not be auto-recovered.
          }
          message = 'An account already exists with that email.';
          break;
        case 'invalid-email':
          message = 'The email address is badly formatted.';
          break;
        default:
          message = e.message ?? 'Registration failed.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (shouldRedirectToLogin) {
          context.go('/login');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ------------------------------------------------------------
  // Responsive helper for the Terms text (avoids overflow)
  // ------------------------------------------------------------
  String _buildResponsiveText(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 400) {
      return ' of Tumaini.';
    }
    return ' of Tumaini Estate.';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    // Define all color variables used in the file
    final primary = AppColors.primary;
    final primaryContainer = AppColors.primary;
    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainer = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final outline = isDark ? AppColors.textMutedDark : const Color(0xFF737686);
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final onPrimaryContainer = AppColors.primaryTintLight;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text('Tumaini Estate'),
        actions: [
          const AppHomeAction(),
          TextButton(
            onPressed: () => context.push('/login'),
            child: const Text('Sign In'),
            style: TextButton.styleFrom(foregroundColor: primary),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: isMobile
                    ? _buildMobileLayout(
                  context,
                  primary,
                  primaryContainer,
                  surface,
                  surfaceContainer,
                  surfaceContainerLowest,
                  outline,
                  outlineVariant,
                  textOnSurface,
                  textOnSurfaceVariant,
                  onPrimaryContainer,
                )
                    : _buildDesktopLayout(
                  context,
                  primary,
                  primaryContainer,
                  surface,
                  surfaceContainer,
                  surfaceContainerLowest,
                  outline,
                  outlineVariant,
                  textOnSurface,
                  textOnSurfaceVariant,
                  onPrimaryContainer,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopLayout(
      BuildContext context,
      Color primary,
      Color primaryContainer,
      Color surface,
      Color surfaceContainer,
      Color surfaceContainerLowest,
      Color outline,
      Color outlineVariant,
      Color textOnSurface,
      Color textOnSurfaceVariant,
      Color onPrimaryContainer,
      ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: _buildHeroSection(context, primary, primaryContainer, onPrimaryContainer),
        ),
        Expanded(
          flex: 7,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            child: _buildFormSection(
              context,
              primary,
              surface,
              surfaceContainer,
              surfaceContainerLowest,
              outline,
              outlineVariant,
              textOnSurface,
              textOnSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
      BuildContext context,
      Color primary,
      Color primaryContainer,
      Color surface,
      Color surfaceContainer,
      Color surfaceContainerLowest,
      Color outline,
      Color outlineVariant,
      Color textOnSurface,
      Color textOnSurfaceVariant,
      Color onPrimaryContainer,
      ) {
    return Column(
      children: [
        // Compressed hero for mobile
        Container(
          height: 380,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryDeep, primaryContainer],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Text(
                    'JOIN THE COMMUNITY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'A Smarter Way\nto Manage Your\nEstate Life.',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Seamless communication, verified providers, efficient estate management.',
                  style: TextStyle(fontSize: 14, color: onPrimaryContainer),
                ),
              ],
            ),
          ),
        ),
        // Form
        Padding(
          padding: const EdgeInsets.all(24),
          child: _buildFormSection(
            context,
            primary,
            surface,
            surfaceContainer,
            surfaceContainerLowest,
            outline,
            outlineVariant,
            textOnSurface,
            textOnSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSection(
      BuildContext context,
      Color primary,
      Color primaryContainer,
      Color onPrimaryContainer,
      ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDeep, primaryContainer],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.2), width: 60),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -120,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Text(
                    'JOIN THE COMMUNITY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'A Smarter Way\nto Manage Your\nEstate Life.',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 380,
                  child: Text(
                    'Experience seamless communication, verified service providers, and efficient estate management all in one secure portal.',
                    style: TextStyle(
                      fontSize: 17,
                      color: onPrimaryContainer,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Row(
                  children: [
                    _buildFeatureItem(Icons.verified_user, 'Verified Security', 'Tier-1 protocols'),
                    const SizedBox(width: 48),
                    _buildFeatureItem(Icons.bolt, 'Instant Access', 'Quick processing'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFormSection(
      BuildContext context,
      Color primary,
      Color surface,
      Color surfaceContainer,
      Color surfaceContainerLowest,
      Color outline,
      Color outlineVariant,
      Color textOnSurface,
      Color textOnSurfaceVariant,
      ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Account',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: textOnSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome to Tumaini Estate. Please fill in your details.',
            style: TextStyle(fontSize: 14, color: textOnSurfaceVariant),
          ),
          const SizedBox(height: 32),

          // Role selector
          _buildRoleSelector(
            context,
            primary,
            surfaceContainer,
            surfaceContainerLowest,
            textOnSurfaceVariant,
          ),
          if (_selectedRole == 'provider') ...[
            const SizedBox(height: 16),
            _buildProviderSpecialtySelector(
              primary,
              surfaceContainer,
              surfaceContainerLowest,
              textOnSurfaceVariant,
            ),
          ],
          const SizedBox(height: 32),

          // Name + Email
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'John Doe',
                  validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'john@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
                      return 'Invalid email';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Phone
          _buildTextField(
            controller: _phoneController,
            label: 'Phone Number',
            hint: '712 345 678',
            prefixText: '+254 ',
            keyboardType: TextInputType.phone,
            validator: (v) {
              final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
              if (digits.isEmpty) return 'Required';
              if (digits.length != 9) return 'Enter 9 digits (e.g. 712345678)';
              return null;
            },
          ),
          const SizedBox(height: 24),

          if (_selectedRole == 'resident') ...[
            _buildTextField(
              controller: _apartmentNumberController,
              label: 'Apartment Number',
              hint: 'e.g. A-12 or 4B',
              validator: (v) {
                if (_selectedRole != 'resident') return null;
                if (v == null || v.trim().isEmpty) {
                  return 'Apartment number is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
          ],

          // Passwords
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildPasswordField(
                  controller: _passwordController,
                  label: 'Password',
                  obscureText: _obscurePassword,
                  onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 6) return 'At least 6 characters';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPasswordField(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  obscureText: _obscureConfirmPassword,
                  onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // --------------------------------------------------------
          // TERMS SECTION – RESPONSIVE (FIXED OVERFLOW)
          // --------------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _termsAccepted,
                  onChanged: (v) => setState(() => _termsAccepted = v ?? false),
                  side: BorderSide(color: outlineVariant),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width < 400 ? 12 : 13,
                      color: textOnSurfaceVariant,
                    ),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Terms & Conditions',
                        style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: _buildResponsiveText(context)), // Dynamic text
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Submit
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
              child: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text(
                'Create Account',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: TextStyle(fontSize: 14, color: textOnSurfaceVariant),
                ),
                TextButton(
                  onPressed: () => context.push('/login'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(
                    'Sign in here',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector(
      BuildContext context,
      Color primary,
      Color surfaceContainer,
      Color surfaceContainerLowest,
      Color textOnSurfaceVariant,
      ) {
    final isResident = _selectedRole == 'resident';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Your Role',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textOnSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedRole = 'resident';
                    _selectedProviderSpecialty = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isResident ? surfaceContainerLowest : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.home, color: isResident ? primary : AppColors.neutral500, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Resident',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isResident ? FontWeight.bold : FontWeight.normal,
                            color: isResident ? primary : textOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedRole = 'provider'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: !isResident ? surfaceContainerLowest : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.engineering, color: !isResident ? primary : AppColors.neutral500, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Provider',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: !isResident ? FontWeight.bold : FontWeight.normal,
                            color: !isResident ? primary : textOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProviderSpecialtySelector(
      Color primary,
      Color surfaceContainer,
      Color surfaceContainerLowest,
      Color textOnSurfaceVariant,
      ) {
    Widget option({
      required String value,
      required String label,
      required IconData icon,
    }) {
      final isSelected = _selectedProviderSpecialty == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _selectedProviderSpecialty = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: isSelected ? surfaceContainerLowest : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: isSelected ? primary : textOnSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? primary : textOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Provider Specialty',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textOnSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              option(
                value: 'plumbing',
                label: 'Plumbing',
                icon: Icons.plumbing,
              ),
              const SizedBox(width: 8),
              option(
                value: 'electrical',
                label: 'Electrical',
                icon: Icons.electrical_services,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? prefixText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final fieldFill = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final inputTextColor = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final hintColor = isDark ? AppColors.textMutedDark : AppColors.textMutedDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: inputTextColor),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            prefixText: prefixText,
            prefixStyle: TextStyle(
              color: inputTextColor,
              fontWeight: FontWeight.w600,
            ),
            hintText: hint,
            hintStyle: TextStyle(color: hintColor),
            filled: true,
            fillColor: fieldFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
    required String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final fieldFill = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final inputTextColor = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final hintColor = isDark ? AppColors.textMutedDark : AppColors.textMutedDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          style: TextStyle(color: inputTextColor),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: '********',
            hintStyle: TextStyle(color: hintColor),
            filled: true,
            fillColor: fieldFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                size: 20,
                color: isDark ? AppColors.textSecondaryDark : AppColors.borderDark,
              ),
              onPressed: onToggle,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}




