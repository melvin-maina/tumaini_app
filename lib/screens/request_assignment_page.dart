import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../widgets/admin_navigation_shell.dart';
import '../widgets/app_home_action.dart';

class RequestAssignmentPage extends StatefulWidget {
  const RequestAssignmentPage({
    super.key,
    this.focusRequestId,
    this.returnTo,
  });

  final String? focusRequestId;
  final String? returnTo;

  @override
  State<RequestAssignmentPage> createState() => _RequestAssignmentPageState();
}

class _RequestAssignmentPageState extends State<RequestAssignmentPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  bool _isAuthorizing = true;
  bool _isAssigning = false;
  String? _selectedRequestId;
  String _selectedEta = 'Today, 2:00 PM - 4:00 PM';
  String _adminName = 'Admin';

  final List<String> _etaOptions = const [
    'Today, 10:00 AM - 12:00 PM',
    'Today, 2:00 PM - 4:00 PM',
    'Today, 4:00 PM - 6:00 PM',
    'Tomorrow, 8:00 AM - 10:00 AM',
    'Tomorrow, 10:00 AM - 12:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    _selectedRequestId = widget.focusRequestId;
    _authorizeAdminAccess();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleBackNavigation() {
    final returnTo = widget.returnTo;
    if (returnTo != null && returnTo.isNotEmpty) {
      context.go(returnTo);
      return;
    }

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/admin-dashboard');
    }
  }

  Future<void> _authorizeAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      _adminName = (userData['fullName'] ?? user.displayName ?? 'Admin').toString();
      final role = (userData['role'] ?? '').toString().toLowerCase();
      if (!mounted) return;
      if (role == 'admin') {
        setState(() => _isAuthorizing = false);
      } else {
        context.go(role == 'provider' ? '/provider-dashboard' : '/resident-dashboard');
      }
    } catch (_) {
      if (mounted) context.go('/login');
    }
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'Just now';
    final diff = DateTime.now().difference(timestamp.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} d ago';
  }

  IconData _serviceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'plumbing':
        return Icons.plumbing;
      case 'electrical':
        return Icons.electrical_services;
      default:
        return Icons.build_circle_outlined;
    }
  }

  bool _isAssignableRequest(Map<String, dynamic> request) {
    final status = (request['status'] ?? 'pending').toString().toLowerCase();
    final assignedProviderId = (request['assignedProviderId'] ?? '').toString().trim();
    if (assignedProviderId.isNotEmpty) return false;
    return status.isEmpty ||
        status == 'pending' ||
        status == 'open' ||
        status == 'submitted';
  }

  List<QueryDocumentSnapshot> _sortRequests(List<QueryDocumentSnapshot> requests) {
    final sorted = [...requests];
    sorted.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aDeclinedAt = aData['lastDeclinedAt'] as Timestamp?;
      final bDeclinedAt = bData['lastDeclinedAt'] as Timestamp?;
      final aWasDeclined = aDeclinedAt != null;
      final bWasDeclined = bDeclinedAt != null;
      if (aWasDeclined != bWasDeclined) {
        return aWasDeclined ? -1 : 1;
      }
      if (aWasDeclined && bWasDeclined) {
        final aDeclineMs = aDeclinedAt?.millisecondsSinceEpoch ?? 0;
        final bDeclineMs = bDeclinedAt?.millisecondsSinceEpoch ?? 0;
        if (aDeclineMs != bDeclineMs) {
          return bDeclineMs.compareTo(aDeclineMs);
        }
      }
      final urgencyRank = {'high': 0, 'medium': 1, 'low': 2};
      final aUrgency = urgencyRank[(aData['urgency'] ?? 'medium').toString().toLowerCase()] ?? 1;
      final bUrgency = urgencyRank[(bData['urgency'] ?? 'medium').toString().toLowerCase()] ?? 1;
      if (aUrgency != bUrgency) {
        return aUrgency.compareTo(bUrgency);
      }
      final aDate = aData['createdAt'] as Timestamp?;
      final bDate = bData['createdAt'] as Timestamp?;
      final aMs = aDate?.millisecondsSinceEpoch ?? 0;
      final bMs = bDate?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    return sorted;
  }

  bool _providerSupportsService(Map<String, dynamic> provider, String serviceType) {
    final normalizedService = serviceType.trim().toLowerCase();
    if (normalizedService.isEmpty) return true;

    final specialtyRaw = provider['specialty'];
    if (specialtyRaw is String) {
      final specialty = specialtyRaw.trim().toLowerCase();
      if (specialty.isEmpty) return false;
      return specialty.contains(normalizedService);
    }

    if (specialtyRaw is Iterable) {
      return specialtyRaw
          .map((item) => item.toString().trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .any((item) => item.contains(normalizedService));
    }

    return false;
  }

  bool _matchesSpecialty(Map<String, dynamic> provider, Map<String, dynamic> request) {
    final serviceType = (request['serviceType'] ?? '').toString();
    return _providerSupportsService(provider, serviceType);
  }

  bool _isProviderEligible(Map<String, dynamic> provider) {
    final isAvailable = provider['isAvailable'] == true;
    final isVerified = provider['verified'] == true;
    final status = (provider['status'] ?? '').toString().trim().toLowerCase();
    return isAvailable && isVerified && (status.isEmpty || status == 'active');
  }

  int _providerScore(Map<String, dynamic> provider, Map<String, dynamic> request) {
    var score = _matchesSpecialty(provider, request) ? 100 : 0;
    score += (((provider['rating'] as num?)?.toDouble() ?? 4.0) * 10).round();
    score -= ((provider['currentTaskCount'] as num?)?.toInt() ?? 0) * 8;
    if (provider['verified'] == true) score += 20;
    return score;
  }

  Future<Map<String, dynamic>> _residentFor(String userId) async {
    if (userId.isEmpty) return {};
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.data() ?? {};
  }

  Future<void> _showProviderPicker({
    required String requestId,
    required Map<String, dynamic> request,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final card = isDark ? AppColors.surfaceDark : Colors.white;
        final chip = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
        final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
        final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('users')
                    .where('role', isEqualTo: 'provider')
                    .where('isAvailable', isEqualTo: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final serviceType = (request['serviceType'] ?? '').toString();
                  final docs = (snapshot.data?.docs ?? [])
                      .where(
                        (doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _isProviderEligible(data) &&
                              _providerSupportsService(data, serviceType);
                        },
                      )
                      .toList();
                  docs.sort((a, b) => _providerScore(
                                b.data() as Map<String, dynamic>,
                                request,
                              )
                              .compareTo(
                                _providerScore(a.data() as Map<String, dynamic>, request),
                              ));

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: muted.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Assign Provider',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose the best provider for ${(request['residentName'] ?? 'this resident')}\'s ${(request['serviceType'] ?? 'service')} request.',
                        style: TextStyle(color: muted),
                      ),
                      const SizedBox(height: 16),
                      if (docs.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: chip,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'No available providers found for this ${serviceType.isEmpty ? 'selected' : serviceType.toLowerCase()} service right now.',
                            style: TextStyle(color: muted),
                          ),
                        )
                      else
                        ...docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final name = (data['fullName'] ?? 'Provider').toString();
                          final specialty = (data['specialty'] ?? 'General').toString();
                          final rating =
                              ((data['rating'] as num?)?.toDouble() ?? 4.5).toStringAsFixed(1);
                          final tasks =
                              ((data['currentTaskCount'] as num?)?.toInt() ?? 0).toString();
                          final bestFit = _matchesSpecialty(data, request);
                          final status = (data['status'] ?? 'active').toString();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: chip,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: bestFit
                                    ? AppColors.primary.withOpacity(0.4)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: text,
                                            ),
                                          ),
                                          Text(
                                            specialty,
                                            style: const TextStyle(color: AppColors.primary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (bestFit)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          'Best fit',
                                          style: TextStyle(fontSize: 11, color: AppColors.primary),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _chip(Icons.phone_outlined,
                                        (data['phone'] ?? 'Phone not set').toString(), muted),
                                    _chip(Icons.star_outline, '$rating rating', muted),
                                    _chip(Icons.assignment_outlined, '$tasks active tasks', muted),
                                    _chip(Icons.verified_outlined, status, muted),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isAssigning
                                        ? null
                                        : () async {
                                            Navigator.pop(sheetContext);
                                            await _assignProvider(
                                              requestId: requestId,
                                              request: request,
                                              providerId: doc.id,
                                              provider: data,
                                            );
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: Text(
                                      _isAssigning ? 'Assigning...' : 'Assign this provider',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _assignProvider({
    required String requestId,
    required Map<String, dynamic> request,
    required String providerId,
    required Map<String, dynamic> provider,
  }) async {
    if (_isAssigning) return;

    final providerName = (provider['fullName'] ?? 'Provider').toString();
    final residentName = (request['residentName'] ?? 'Resident').toString();
    final residentUserId = (request['userId'] ?? '').toString();
    final serviceType = (request['serviceType'] ?? 'service').toString();
    final residentMessage =
        '$providerName has been assigned to your $serviceType request and is expected $_selectedEta.';
    final providerMessage =
        'You have been assigned a new $serviceType request for $residentName at ${(request['location'] ?? request['unit'] ?? 'the resident location').toString()}. Expected arrival: $_selectedEta.';

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm Assignment'),
            content: Text(
              'Assign $providerName to $residentName and notify them that arrival is expected $_selectedEta?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Assign')),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    setState(() => _isAssigning = true);

    try {
      await _firestore.runTransaction((transaction) async {
        final requestRef = _firestore.collection('requests').doc(requestId);
        final requestSnap = await transaction.get(requestRef);
        final latest = requestSnap.data() ?? <String, dynamic>{};

        if (!_isAssignableRequest(latest)) {
          throw Exception('This request has already been assigned or is no longer pending.');
        }

        transaction.update(requestRef, {
          'status': 'assigned',
          'assignedProviderId': providerId,
          'assignedProviderName': providerName,
          'assignedProviderPhone': provider['phone'] ?? '',
          'assignedProviderSpecialty': provider['specialty'] ?? '',
          'assignedAt': FieldValue.serverTimestamp(),
          'assignedByAdminId': FirebaseAuth.instance.currentUser?.uid ?? '',
          'assignedByAdminName': _adminName,
          'expectedArrivalWindow': _selectedEta,
          'residentNotificationMessage': residentMessage,
          'providerNotificationMessage': providerMessage,
          'lastDeclineReason': FieldValue.delete(),
          'lastDeclinedByProviderId': FieldValue.delete(),
          'lastDeclinedByProviderName': FieldValue.delete(),
          'lastDeclinedAt': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (residentUserId.isNotEmpty) {
        await _firestore.collection('notifications').add({
          'userId': residentUserId,
          'requestId': requestId,
          'type': 'provider_assigned',
          'title': 'Provider assigned',
          'message': residentMessage,
          'providerId': providerId,
          'providerName': providerName,
          'expectedArrivalWindow': _selectedEta,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _firestore.collection('notifications').add({
        'userId': providerId,
        'requestId': requestId,
        'type': 'request_assigned',
        'title': 'New service request assigned',
        'message': providerMessage,
        'residentName': residentName,
        'serviceType': serviceType,
        'expectedArrivalWindow': _selectedEta,
        'assignedByAdminName': _adminName,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assigned $providerName and notified both resident and provider'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assignment failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthorizing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final card = isDark ? AppColors.surfaceDark : Colors.white;
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final chip = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);

    return AdminNavigationShell(
      title: 'Request Assignment',
      selectedSection: AdminNavSection.assignRequests,
      actions: const [AppHomeAction()],
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('requests')
            .snapshots(),
        builder: (context, requestSnapshot) {
          if (requestSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final requestDocs = _sortRequests(
            (requestSnapshot.data?.docs ?? [])
                .where((doc) => _isAssignableRequest(doc.data() as Map<String, dynamic>))
                .toList(),
          );
          if (_selectedRequestId == null && requestDocs.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedRequestId = requestDocs.first.id);
            });
          }
          final query = _searchController.text.trim().toLowerCase();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Every new resident request appears here. The admin reviews the request, clicks assign, then chooses the right provider for that job.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search resident, request type, unit, or provider...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: chip,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedEta,
                      isExpanded: true,
                      items: _etaOptions.map((eta) => DropdownMenuItem(value: eta, child: Text(eta))).toList(),
                      onChanged: (value) => setState(() => _selectedEta = value ?? _selectedEta),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildRequestsPanel(requestDocs, query, card, chip, text, muted),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequestsPanel(
    List<QueryDocumentSnapshot> docs,
    String query,
    Color card,
    Color chip,
    Color text,
    Color muted,
  ) {
    final filteredDocs = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final serviceType = (data['serviceType'] ?? 'General').toString();
      final description = (data['description'] ?? 'No description provided').toString();
      final residentName = (data['residentName'] ?? '').toString().toLowerCase();
      final location = (data['location'] ?? data['unit'] ?? '').toString().toLowerCase();
      return query.isEmpty ||
          residentName.contains(query) ||
          serviceType.toLowerCase().contains(query) ||
          description.toLowerCase().contains(query) ||
          location.contains(query);
    }).toList();
    final containsSelected = _selectedRequestId != null &&
        filteredDocs.any((doc) => doc.id == _selectedRequestId);
    final selectedDoc = filteredDocs.isEmpty
        ? null
        : containsSelected
            ? filteredDocs.firstWhere((doc) => doc.id == _selectedRequestId)
            : filteredDocs.first;
    if (selectedDoc != null && !containsSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedRequestId = selectedDoc.id);
      });
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resident Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text)),
          const SizedBox(height: 4),
          Text('${docs.length} pending requests', style: TextStyle(color: muted)),
          const SizedBox(height: 16),
          if (filteredDocs.isEmpty)
            Text(
              'No resident requests are waiting for assignment right now.',
              style: TextStyle(color: muted),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 920;
                final listPanel = Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: chip,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Queue',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...filteredDocs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final serviceType = (data['serviceType'] ?? 'General').toString();
                        final residentName = (data['residentName'] ?? 'Resident').toString();
                        final selected = selectedDoc?.id == doc.id;
                        return InkWell(
                          onTap: () => setState(() => _selectedRequestId = doc.id),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary.withOpacity(0.1) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? AppColors.primary : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(_serviceIcon(serviceType), color: AppColors.primary, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        residentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: text,
                                        ),
                                      ),
                                      Text(
                                        '${serviceType.toUpperCase()} | ${_timeAgo(data['createdAt'] as Timestamp?)}',
                                        style: TextStyle(fontSize: 11, color: muted),
                                      ),
                                      if (data['lastDeclinedAt'] != null)
                                        Text(
                                          'Previously declined',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.warningStrong,
                                          ),
                                        ),
                                      if (doc.id == widget.focusRequestId)
                                        const Text(
                                          'Focused from notification',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
                final detailsPanel = selectedDoc == null
                    ? const SizedBox.shrink()
                    : _buildRequestDetailsPanel(
                        doc: selectedDoc,
                        text: text,
                        muted: muted,
                        chip: chip,
                      );

                if (compact) {
                  return Column(
                    children: [
                      listPanel,
                      const SizedBox(height: 12),
                      detailsPanel,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: listPanel),
                    const SizedBox(width: 12),
                    Expanded(flex: 8, child: detailsPanel),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRequestDetailsPanel({
    required QueryDocumentSnapshot doc,
    required Color text,
    required Color muted,
    required Color chip,
  }) {
    final data = doc.data() as Map<String, dynamic>;
    final serviceType = (data['serviceType'] ?? 'General').toString();
    final description = (data['description'] ?? 'No description provided').toString();

    return FutureBuilder<Map<String, dynamic>>(
      future: _residentFor((data['userId'] ?? '').toString()),
      builder: (context, snapshot) {
        final resident = snapshot.data ?? {};
        final displayName = (data['residentName'] ?? resident['fullName'] ?? 'Resident').toString();
        final unit = (data['unit'] ?? resident['unit'] ?? 'Unit not set').toString();
        final phone = (data['phone'] ?? resident['phone'] ?? 'Phone not set').toString();
        final phase = (resident['phase'] ?? '').toString();
        final urgency = (data['urgency'] ?? 'medium').toString();
        final lastDeclinedBy = (data['lastDeclinedByProviderName'] ?? '').toString();
        final lastDeclineReason = (data['lastDeclineReason'] ?? '').toString();
        final lastDeclinedAt = data['lastDeclinedAt'] as Timestamp?;
        final displayLocation =
            (data['location'] ?? (phase.isEmpty ? unit : '$phase, $unit')).toString();
        final isFocused = doc.id == widget.focusRequestId;
        return FutureBuilder<DocumentSnapshot>(
          future: _firestore.collection('feedback').doc(doc.id).get(),
          builder: (context, feedbackSnapshot) {
            final feedbackData = feedbackSnapshot.data?.data() as Map<String, dynamic>?;
            final assignedProviderName =
                (data['assignedProviderName'] ?? feedbackData?['providerName'] ?? 'Unassigned')
                    .toString();
            final completedAt = data['completedAt'] as Timestamp?;
            final feedbackRating =
                ((feedbackData?['rating'] as num?)?.toDouble() ?? 0).toStringAsFixed(1);
            final feedbackComment = (feedbackData?['comment'] ?? '').toString().trim();
            final feedbackCreatedAt = feedbackData?['createdAt'] as Timestamp?;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: chip,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFocused ? AppColors.primary.withOpacity(0.45) : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFocused) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Focused from notification',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Icon(_serviceIcon(serviceType), color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style:
                                  TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text),
                            ),
                            Text(
                              '${serviceType.toUpperCase()} | ${_timeAgo(data['createdAt'] as Timestamp?)}',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(description, style: TextStyle(color: text)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(Icons.home_outlined, displayLocation, muted),
                      _chip(Icons.phone_outlined, phone, muted),
                      _chip(
                        Icons.person_outline,
                        'Provider: $assignedProviderName',
                        muted,
                      ),
                      _chip(
                        Icons.schedule_outlined,
                        (data['preferredTimeSlot'] ?? 'No preferred time').toString(),
                        muted,
                      ),
                      _chip(
                        Icons.priority_high,
                        'Urgency: ${urgency[0].toUpperCase()}${urgency.substring(1)}',
                        muted,
                      ),
                    ],
                  ),
                  if (completedAt != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.success.withOpacity(0.22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Completion Record',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.successStrong,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$assignedProviderName completed this request for $displayName ${_timeAgo(completedAt)}.',
                            style: TextStyle(color: text),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Completed at: ${_timeAgo(completedAt)}',
                            style: TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (feedbackData != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.accent.withOpacity(0.22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Feedback Record',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDeep,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$displayName rated $assignedProviderName $feedbackRating/5.',
                            style: TextStyle(color: text),
                          ),
                          if (feedbackComment.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '"$feedbackComment"',
                              style: TextStyle(color: muted, fontStyle: FontStyle.italic),
                            ),
                          ],
                          if (feedbackCreatedAt != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Submitted ${_timeAgo(feedbackCreatedAt)}',
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (lastDeclinedAt != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.warning.withOpacity(0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Previous Decline',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.warningStrong,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${lastDeclinedBy.isEmpty ? 'A provider' : lastDeclinedBy} declined this request ${_timeAgo(lastDeclinedAt)}.',
                            style: TextStyle(color: text),
                          ),
                          if (lastDeclineReason.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Reason: $lastDeclineReason',
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showProviderPicker(
                        requestId: doc.id,
                        request: {
                          ...data,
                          'residentName': displayName,
                          'phone': phone,
                          'location': displayLocation,
                        },
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.assignment_ind_outlined),
                      label: const Text('Assign Provider'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}


