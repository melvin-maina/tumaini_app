import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/app_home_action.dart';
import '../widgets/notification_bell_button.dart';

class ServiceRequestPage extends StatefulWidget {
  const ServiceRequestPage({super.key});

  @override
  State<ServiceRequestPage> createState() => _ServiceRequestPageState();
}

class _ServiceRequestPageState extends State<ServiceRequestPage> {
  final _formKey = GlobalKey<FormState>();
  String _selectedServiceType = 'plumbing'; // 'plumbing' or 'electrical'
  String _selectedUrgency = 'medium';
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedTimeSlot;
  bool _isSubmitting = false;

  final List<String> _timeSlots = [
    'Morning (08:00 - 12:00)',
    'Afternoon (13:00 - 17:00)',
    'Evening (18:00 - 20:00)',
  ];

  final AuthService _auth = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _createAdminNotification({
    required String requestId,
    required String title,
    required String message,
    Map<String, dynamic>? extras,
  }) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _firestore.collection('notifications').add({
      'userId': 'admin',
      'audience': 'admin',
      'requestId': requestId,
      'type': 'request_submitted',
      'title': title,
      'message': message,
      'createdBy': currentUserId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...?extras,
    });
  }

  String _formatPreferredDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your preferred date'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (_selectedTimeSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your preferred time slot'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = _auth.getCurrentUser();
      if (user == null) throw Exception('Not logged in');
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final unit = (userData['unit'] ?? '').toString();
      final phase = (userData['phase'] ?? '').toString();
      final location = [
        if (phase.isNotEmpty) phase,
        if (unit.isNotEmpty) unit,
      ].join(', ');
      final residentName =
          (userData['fullName'] ?? user.displayName ?? 'Resident').toString();

      if (unit.isEmpty) {
        throw Exception(
          'Your apartment number is missing. Please update your resident profile before submitting a request.',
        );
      }

      final requestData = {
        'userId': user.uid,
        'residentId': user.uid,
        'residentName': residentName,
        'phone': userData['phone'] ?? '',
        'unit': unit,
        'location': location,
        'serviceType': _selectedServiceType,
        'urgency': _selectedUrgency,
        'description': _descriptionController.text.trim(),
        'preferredDate': Timestamp.fromDate(_selectedDate!),
        'preferredDateLabel': _formatPreferredDate(_selectedDate!),
        'preferredTimeSlot': _selectedTimeSlot,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final requestRef = _firestore.collection('requests').doc();
      await requestRef.set(requestData);
      await _createAdminNotification(
        requestId: requestRef.id,
        title: 'New service request submitted',
        message:
            '$residentName submitted a ${_selectedServiceType.toLowerCase()} request for ${location.isEmpty ? unit : location}.',
        extras: {
          'residentId': user.uid,
          'residentName': residentName,
          'serviceType': _selectedServiceType,
          'urgency': _selectedUrgency,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request submitted successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/request-tracking');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
      confirmText: 'OK',
      cancelText: 'CANCEL',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
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
                    : screenWidth < 1024
                        ? 24.0
                        : 32.0;

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // ALL color variables used in the file are defined here
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final surfaceContainer = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final primaryContainer = AppColors.primary;
    final outline = isDark ? AppColors.textMutedDark : const Color(0xFF737686);
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);
    final primaryFixed = isDark ? AppColors.surfaceDarkElevated : AppColors.primaryTintLight;
    final tertiaryFixed = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFffdbcf);
    final tertiary = isDark ? AppColors.textMutedDark : const Color(0xFF7e2900);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: const Text('New Service Request'),
        actions: [
          const AppHomeAction(),
          NotificationBellButton(iconColor: textOnSurfaceVariant),
        ],
      ),
      body: Builder(
        builder: (context) {
          final content = SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Hero title
              Text(
                'New Service Request',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: textOnSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Describe the maintenance issue or installation service you require within your unit.',
                style: TextStyle(
                  fontSize: 16,
                  color: textOnSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // Service Type Selector
              Text(
                'Select Service Category',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                  color: textOnSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildServiceTypeCard(
                      context,
                      type: 'plumbing',
                      icon: Icons.plumbing,
                      title: 'Plumbing',
                      description: 'Leaks, blockages, or fixture repairs.',
                      isSelected: _selectedServiceType == 'plumbing',
                      onTap: () => setState(() => _selectedServiceType = 'plumbing'),
                      selectedBgColor: primary,
                      iconBgColor: primaryFixed,
                      iconColor: primary,
                      textOnSurface: textOnSurface,
                      textOnSurfaceVariant: textOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildServiceTypeCard(
                      context,
                      type: 'electrical',
                      icon: Icons.electrical_services,
                      title: 'Electrical',
                      description: 'Wiring, lighting, or socket issues.',
                      isSelected: _selectedServiceType == 'electrical',
                      onTap: () => setState(() => _selectedServiceType = 'electrical'),
                      selectedBgColor: tertiary,
                      iconBgColor: tertiaryFixed,
                      iconColor: tertiary,
                      textOnSurface: textOnSurface,
                      textOnSurfaceVariant: textOnSurfaceVariant,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              Text(
                'Urgency Level',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                  color: textOnSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildUrgencyChip(
                    label: 'Low',
                    value: 'low',
                    selectedColor: AppColors.neutral500,
                  ),
                  _buildUrgencyChip(
                    label: 'Medium',
                    value: 'medium',
                    selectedColor: AppColors.primary,
                  ),
                  _buildUrgencyChip(
                    label: 'High',
                    value: 'high',
                    selectedColor: AppColors.warning,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Issue Description
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: _inputDecoration(
                  isDark: isDark,
                  surfaceContainer: surfaceContainer,
                  primary: primary,
                  labelText: 'Issue Description',
                  labelColor: textOnSurfaceVariant,
                  hintText:
                      'Please provide details about the location and severity of the problem...',
                  helperText: 'MIN. 20 CHARS',
                ).copyWith(contentPadding: const EdgeInsets.all(16)),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please describe the issue';
                  }
                  if (value.trim().length < 20) {
                    return 'Please provide at least 20 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Preferred Schedule
              Text(
                'Preferred Schedule',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                  color: textOnSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              isMobile
                  ? Column(
                children: [
                  InkWell(
                    onTap: _selectDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 20, color: AppColors.neutral500),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedDate == null
                                  ? 'Select date'
                                  : _formatPreferredDate(_selectedDate!),
                              style: TextStyle(
                                color: _selectedDate == null ? textOnSurfaceVariant : textOnSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedTimeSlot,
                    decoration: _inputDecoration(
                      isDark: isDark,
                      surfaceContainer: surfaceContainer,
                      primary: primary,
                      prefixIcon: const Icon(
                        Icons.schedule,
                        size: 20,
                        color: AppColors.neutral500,
                      ),
                    ).copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: _timeSlots.map((slot) {
                      return DropdownMenuItem(value: slot, child: Text(slot));
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedTimeSlot = value);
                    },
                    validator: (value) => value == null ? 'Please select a time slot' : null,
                  ),
                ],
              )
                  : Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _selectDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 20, color: AppColors.neutral500),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedDate == null
                                    ? 'Select date'
                                    : _formatPreferredDate(_selectedDate!),
                                style: TextStyle(
                                  color: _selectedDate == null ? textOnSurfaceVariant : textOnSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedTimeSlot,
                      decoration: _inputDecoration(
                        isDark: isDark,
                        surfaceContainer: surfaceContainer,
                        primary: primary,
                        prefixIcon: const Icon(
                          Icons.schedule,
                          size: 20,
                          color: AppColors.neutral500,
                        ),
                      ).copyWith(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: _timeSlots.map((slot) {
                        return DropdownMenuItem(value: slot, child: Text(slot));
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedTimeSlot = value);
                      },
                      validator: (value) => value == null ? 'Please select a time slot' : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Photo Upload (placeholder)
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Photo upload will be available soon')),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: outlineVariant,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: surfaceContainerLow,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: surfaceContainerLowest,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4),
                          ],
                        ),
                        child: const Icon(
                          Icons.cloud_upload,
                          size: 32,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tap to upload',
                        style: TextStyle(fontWeight: FontWeight.w600, color: textOnSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'JPEG or PNG, Max 10MB each',
                        style: TextStyle(fontSize: 10, color: textOnSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text(
                    'Submit Request',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 80),
                ],
              ),
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
      bottomNavigationBar: isMobile ? _buildBottomNavBar(context, isDark, surface) : null,
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
                isSelected: true,
                onTap: () {},
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
                isSelected: false,
                onTap: () => context.go('/resident-profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceTypeCard(
      BuildContext context, {
        required String type,
        required IconData icon,
        required String title,
        required String description,
        required bool isSelected,
        required VoidCallback onTap,
        required Color selectedBgColor,
        required Color iconBgColor,
        required Color iconColor,
        required Color textOnSurface,
        required Color textOnSurfaceVariant,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? selectedBgColor.withOpacity(0.05) : surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? selectedBgColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? iconColor : textOnSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgencyChip({
    required String label,
    required String value,
    required Color selectedColor,
  }) {
    final isSelected = _selectedUrgency == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedUrgency = value),
      selectedColor: selectedColor.withOpacity(0.14),
      labelStyle: TextStyle(
        color: isSelected ? selectedColor : AppColors.neutral600,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      side: BorderSide(
        color: isSelected ? selectedColor : AppColors.neutral200,
      ),
      backgroundColor: Colors.transparent,
    );
  }

  InputDecoration _inputDecoration({
    required bool isDark,
    required Color surfaceContainer,
    required Color primary,
    String? labelText,
    String? hintText,
    String? helperText,
    Color? labelColor,
    Widget? prefixIcon,
  }) {
    final borderColor =
        isDark ? AppColors.borderDark : const Color(0xFFE2E2E4);

    return InputDecoration(
      labelText: labelText,
      labelStyle: labelText == null
          ? null
          : TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
              color: labelColor,
            ),
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: 14,
        color: isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark,
      ),
      helperText: helperText,
      helperStyle: const TextStyle(fontSize: 10),
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.8),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context, bool isDark, Color surface) {
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
                isSelected: true,
                onTap: () {}, // already here
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



