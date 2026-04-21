import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../theme/app_colors.dart';
import '../widgets/app_home_action.dart';

class FeedbackPage extends StatefulWidget {
  final String? requestId;

  const FeedbackPage({super.key, this.requestId});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _rating = 0;
  final TextEditingController _commentController = TextEditingController();
  final Set<String> _selectedTags = <String>{};
  bool _isSubmitting = false;

  final List<String> _availableTags = [
    'Punctual',
    'Professional',
    'Clean workspace',
    'Great value',
    'Friendly',
    'High quality',
    'Quick response',
  ];

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _providerName;
  String? _providerPhotoUrl;
  String? _providerRole;
  bool _feedbackAlreadySubmitted = false;

  String? get _requestId => widget.requestId;

  Future<void> _createAdminNotification({
    required String requestId,
    required String title,
    required String message,
    Map<String, dynamic>? extras,
  }) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _db.collection('notifications').add({
      'userId': 'admin',
      'audience': 'admin',
      'requestId': requestId,
      'type': 'feedback_received',
      'title': title,
      'message': message,
      'createdBy': currentUserId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...?extras,
    });
  }

  Future<bool> _hasExistingFeedback(String requestId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return false;

    final snapshot = await _db
        .collection('feedback')
        .where('requestId', isEqualTo: requestId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _loadProviderInfo();
  }

  Future<void> _loadProviderInfo() async {
    try {
      final requestId = _requestId;
      if (requestId == null) return;

      final requestDoc = await _db.collection('requests').doc(requestId).get();
      final hasFeedback = await _hasExistingFeedback(requestId);

      if (requestDoc.exists) {
        final data = requestDoc.data();
        setState(() {
          _providerName = (data?['assignedProviderName'] ?? 'Unknown Provider').toString();
          _providerPhotoUrl = null;
          _providerRole =
              (data?['assignedProviderSpecialty'] ?? 'Service Provider').toString();
          _feedbackAlreadySubmitted = hasFeedback;
        });
      }
    } catch (e) {
      debugPrint('Error loading provider info: $e');
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

      try {
        final requestId = _requestId;
        if (requestId == null) {
          throw Exception('No request ID provided');
        }
        final requestDoc = await _db.collection('requests').doc(requestId).get();
        final requestData = requestDoc.data() ?? <String, dynamic>{};
        final hasExistingFeedback = await _hasExistingFeedback(requestId);
        final providerId = (requestData['assignedProviderId'] ?? '').toString();
        var providerName = (requestData['assignedProviderName'] ?? '').toString();
        if (providerName.isEmpty) {
          providerName = _providerName ?? 'the provider';
        }
        final residentName = (requestData['residentName'] ?? 'Resident').toString();
        final serviceType = (requestData['serviceType'] ?? 'service').toString();
        final unit = (requestData['unit'] ?? requestData['location'] ?? 'the resident location')
            .toString();

        if ((requestData['status'] ?? '').toString().toLowerCase() != 'completed') {
          throw Exception('Feedback is only available after the job is completed.');
        }
        if (hasExistingFeedback) {
          throw Exception('Feedback has already been submitted for this request.');
        }

      await _db.collection('feedback').doc(requestId).set({
        'requestId': requestId,
        'providerId': requestData['assignedProviderId'],
        'rating': _rating,
        'comment': _commentController.text.trim(),
        'tags': _selectedTags.toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'residentName': residentName,
        'serviceType': serviceType,
        'providerName': providerName,
        'unit': unit,
      });

      await _db.collection('requests').doc(requestId).update({
        'feedbackSubmitted': true,
        'feedbackAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _createAdminNotification(
        requestId: requestId,
        title: 'New feedback received',
        message:
            '$residentName rated $providerName $_rating/5 after $serviceType service at $unit.',
        extras: {
          'providerId': providerId,
          'providerName': providerName,
          'residentName': residentName,
          'serviceType': serviceType,
          'unit': unit,
          'rating': _rating,
          'comment': _commentController.text.trim(),
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you for your feedback!'),
          backgroundColor: AppColors.success,
        ),
      );

      context.go('/resident-dashboard');
    } catch (e) {
      if (!mounted) return;
      final message = e is FirebaseException
          ? (e.message ?? 'Unable to submit feedback right now.')
          : 'Unable to submit feedback right now.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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
    final showBottomNav = screenWidth < 768;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb),
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (GoRouter.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/resident-dashboard');
            }
          },
        ),
        title: const Text(
          'Service Feedback',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: const [AppHomeAction()],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(screenWidth < 600 ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rate your service',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Request ID: ${_requestId ?? '—'}',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textMutedDark,
              ),
            ),
            const SizedBox(height: 24),

            if (_feedbackAlreadySubmitted)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                ),
                child: const Text(
                  'Feedback has already been submitted for this completed request.',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            // Provider info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDarkElevated.withOpacity(0.5) : AppColors.neutral50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.neutral200,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: _providerPhotoUrl != null && _providerPhotoUrl!.isNotEmpty
                          ? Image.network(
                        _providerPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 36),
                      )
                          : const Icon(Icons.person, size: 36),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _providerName ?? 'Loading provider...',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _providerRole ?? 'Service Provider',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.borderDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Rating
            Center(
              child: Column(
                children: [
                  Text(
                    'How was your experience?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.borderLight : AppColors.borderDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _buildStars(),
                  ),
                  const SizedBox(height: 12),
                  if (_rating > 0)
                    Text(
                      '$_rating / 5',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _rating >= 4
                            ? AppColors.success
                            : _rating >= 3
                            ? AppColors.warning
                            : AppColors.error,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Comment
            Text(
              'Detailed Comments (Optional)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.borderLight : AppColors.surfaceDarkElevated,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Tell us what you liked or how we can improve...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDark ? AppColors.surfaceDarkElevated : Colors.white,
                counterStyle: TextStyle(
                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedDark,
                ),
              ),
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            ),

            const SizedBox(height: 32),

            // Tags
            Text(
              'Quick compliments',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textSecondaryDark : AppColors.borderDark,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _availableTags.map((tag) {
                final selected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text(tag),
                  selected: selected,
                  onSelected: (sel) => setState(() {
                    if (sel) _selectedTags.add(tag);
                    else _selectedTags.remove(tag);
                  }),
                  backgroundColor: isDark ? AppColors.surfaceDarkElevated : Colors.white,
                  selectedColor: AppColors.primary.withOpacity(0.15),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.primary : null,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.textSecondaryDark,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                );
              }).toList(),
            ),

            const SizedBox(height: 40),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting || _feedbackAlreadySubmitted ? null : _submitFeedback,
                icon: _isSubmitting
                    ? const SizedBox.shrink()
                    : const Icon(Icons.send, size: 20),
                label: _isSubmitting
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
                    : const Text(
                  'Submit Feedback',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 3,
                ),
              ),
            ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                'Your feedback helps us maintain high standards at Tumaini Estate.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedDark,
                ),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
      bottomNavigationBar: showBottomNav ? _buildBottomNavBar(context) : null,
    );
  }

  // ──────────────────────────────────────────────
  // The rest remains the same (_buildStars, _buildBottomNavBar, _buildNavItem)
  // ──────────────────────────────────────────────

  List<Widget> _buildStars() {
    final starSize = MediaQuery.of(context).size.width < 360 ? 36.0 : 44.0;

    return List.generate(5, (index) {
      final filled = index < _rating;
      return Semantics(
        label: 'Rate ${index + 1} out of 5 stars',
        child: GestureDetector(
          onTap: () {
            setState(() => _rating = index + 1);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedScale(
              scale: filled ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                color: filled ? AppColors.accent : AppColors.textSecondaryDark,
                size: starSize,
                shadows: filled ? [const Shadow(color: AppColors.accent, blurRadius: 8)] : null,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceDark : Colors.white).withOpacity(0.97),
        border: Border(
          top: BorderSide(color: isDark ? AppColors.surfaceDarkElevated : AppColors.neutral200),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(context, Icons.home_outlined, 'Home', false),
              _buildNavItem(context, Icons.assignment, 'Requests', true),
              _buildNavItem(context, Icons.person_outline, 'Profile', false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, bool isSelected) {
    final color = isSelected ? AppColors.primary : AppColors.textMutedDark;
    return GestureDetector(
      onTap: () {
        if (label == 'Home') context.go('/resident-dashboard');
        if (label == 'Requests') context.go('/request-tracking');
        if (label == 'Profile') context.go('/profile');
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 3),
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
}

