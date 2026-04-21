import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../theme/app_colors.dart';
import '../utils/export_file_helper.dart';
import '../widgets/admin_navigation_shell.dart';
import '../widgets/app_home_action.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const List<String> _dateRangeOptions = <String>[
    'Last 7 Days',
    'Last 30 Days',
    'Last 90 Days',
    'Last 365 Days',
    'Custom Range',
  ];

  String _selectedDateRange = 'Last 30 Days';
  String _selectedReportType = 'Overview';
  String _selectedStatus = 'All Statuses';
  String _selectedProvider = 'All Providers';
  String _selectedAuditEventType = 'All Events';
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  static const List<String> _reportTypes = <String>[
    'Overview',
    'Admin Audit Report',
    'Request Submissions',
    'Pending Requests',
    'Completed Services',
    'Assignment Declines',
    'Provider Performance',
    'Feedback Summary',
  ];

  static const List<String> _statusOptions = <String>[
    'All Statuses',
    'Pending',
    'Assigned',
    'In Progress',
    'Completed',
  ];

  static const List<String> _auditEventOptions = <String>[
    'All Events',
    'Request Submitted',
    'Service Completed',
    'Assignment Declined',
    'Feedback Received',
  ];

  String _normalizedStatus(dynamic rawStatus) {
    final status = (rawStatus ?? 'pending').toString().trim().toLowerCase();
    if (status == 'in progress') return 'inprogress';
    return status;
  }

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_selectedDateRange) {
      case 'Custom Range':
        return _customStartDate ?? now.subtract(const Duration(days: 30));
      case 'Last 7 Days':
        return now.subtract(const Duration(days: 7));
      case 'Last 90 Days':
        return now.subtract(const Duration(days: 90));
      case 'Last 365 Days':
        return now.subtract(const Duration(days: 365));
      case 'Last 30 Days':
      default:
        return now.subtract(const Duration(days: 30));
    }
  }

  DateTime get _rangeEnd {
    final now = DateTime.now();
    switch (_selectedDateRange) {
      case 'Custom Range':
        final end = _customEndDate ?? now;
        return DateTime(end.year, end.month, end.day, 23, 59, 59);
      default:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
    }
  }

  String get _dateRangeLabel {
    if (_selectedDateRange != 'Custom Range') return _selectedDateRange;
    final start = _customStartDate;
    final end = _customEndDate;
    if (start == null || end == null) return 'Custom Range';
    return '${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}';
  }

  Future<void> _showDateRangePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _dateRangeOptions.map((option) {
            return ListTile(
              title: Text(option),
              trailing: option == _selectedDateRange
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(context, option),
            );
          }).toList(),
        ),
      ),
    );

    if (selected == null || !mounted) return;

    if (selected == 'Custom Range') {
      final now = DateTime.now();
      final initialRange = DateTimeRange(
        start: _customStartDate ?? now.subtract(const Duration(days: 30)),
        end: _customEndDate ?? now,
      );
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 1),
        initialDateRange: initialRange,
        saveText: 'Apply',
      );
      if (picked != null && mounted) {
        setState(() {
          _selectedDateRange = selected;
          _customStartDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
          _customEndDate = DateTime(picked.end.year, picked.end.month, picked.end.day);
        });
      }
      return;
    }

    setState(() => _selectedDateRange = selected);
  }

  bool _isInRange(Timestamp? timestamp) {
    if (timestamp == null) return false;
    final date = timestamp.toDate();
    return !date.isBefore(_rangeStart) && !date.isAfter(_rangeEnd);
  }

  List<QueryDocumentSnapshot> _filteredByCreatedAt(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _isInRange(data['createdAt'] as Timestamp?);
    }).toList();
  }

  List<QueryDocumentSnapshot> _filteredRequests(
    List<QueryDocumentSnapshot> docs, {
    required Map<String, String> providerNames,
  }) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _normalizedStatus(data['status']);
      final providerId = (data['assignedProviderId'] ?? '').toString();
      final providerName = providerNames[providerId] ?? '';

      final matchesStatus = switch (_selectedStatus) {
        'Pending' => status == 'pending',
        'Assigned' => status == 'assigned',
        'In Progress' => status == 'inprogress',
        'Completed' => status == 'completed',
        _ => true,
      };

      final matchesProvider = _selectedProvider == 'All Providers' ||
          providerId == _selectedProvider ||
          providerName == _selectedProvider;

      if (_selectedReportType == 'Pending Requests' && status != 'pending') {
        return false;
      }

      return matchesStatus && matchesProvider;
    }).toList();
  }

  List<QueryDocumentSnapshot> _filteredFeedback(
    List<QueryDocumentSnapshot> docs, {
    required Map<String, String> providerNames,
  }) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final providerId = (data['providerId'] ?? '').toString();
      final providerName = providerNames[providerId] ?? '';
      return _selectedProvider == 'All Providers' ||
          providerId == _selectedProvider ||
          providerName == _selectedProvider;
    }).toList();
  }

  double _averageRating(List<QueryDocumentSnapshot> feedbackDocs) {
    if (feedbackDocs.isEmpty) return 0;
    final total = feedbackDocs.fold<double>(0, (sum, doc) {
      final data = doc.data() as Map<String, dynamic>;
      return sum + ((data['rating'] as num?)?.toDouble() ?? 0);
    });
    return total / feedbackDocs.length;
  }

  double _averageResponseMinutes(List<QueryDocumentSnapshot> requestDocs) {
    var totalMinutes = 0.0;
    var count = 0;

    for (final doc in requestDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'] as Timestamp?;
      final assignedAt = data['assignedAt'] as Timestamp?;
      if (createdAt != null && assignedAt != null) {
        totalMinutes += assignedAt.toDate().difference(createdAt.toDate()).inMinutes;
        count++;
      }
    }

    return count == 0 ? 0 : totalMinutes / count;
  }

  int get _selectedRangeDays {
    final start = DateTime(_rangeStart.year, _rangeStart.month, _rangeStart.day);
    final end = DateTime(_rangeEnd.year, _rangeEnd.month, _rangeEnd.day);
    return end.difference(start).inDays + 1;
  }

  List<DateTime> _generateBucketStarts({
    required DateTime start,
    required DateTime end,
    required String granularity,
  }) {
    final buckets = <DateTime>[];
    var cursor = DateTime(start.year, start.month, start.day);

    while (!cursor.isAfter(end)) {
      buckets.add(cursor);
      if (granularity == 'day') {
        cursor = cursor.add(const Duration(days: 1));
      } else if (granularity == 'week') {
        cursor = cursor.add(const Duration(days: 7));
      } else {
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
    }

    return buckets;
  }

  String _satisfactionGranularity() {
    final days = _selectedRangeDays;
    if (days <= 14) return 'day';
    if (days <= 120) return 'week';
    return 'month';
  }

  String _bucketLabel(DateTime bucketStart, String granularity) {
    switch (granularity) {
      case 'day':
        return DateFormat('dd MMM').format(bucketStart);
      case 'week':
        return DateFormat('dd MMM').format(bucketStart);
      case 'month':
      default:
        return DateFormat('MMM').format(bucketStart);
    }
  }

  int _bucketIndexForDate({
    required DateTime date,
    required DateTime start,
    required String granularity,
  }) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedStart = DateTime(start.year, start.month, start.day);

    switch (granularity) {
      case 'day':
        return normalizedDate.difference(normalizedStart).inDays;
      case 'week':
        return normalizedDate.difference(normalizedStart).inDays ~/ 7;
      case 'month':
      default:
        return (normalizedDate.year - normalizedStart.year) * 12 +
            normalizedDate.month -
            normalizedStart.month;
    }
  }

  ({
    List<double> currentPoints,
    List<double> previousPoints,
    List<String> labels,
    String currentLegend,
    String previousLegend,
    String subtitle,
  }) _buildSatisfactionTrendData(List<QueryDocumentSnapshot> feedbackDocs) {
    final granularity = _satisfactionGranularity();
    final currentStart = DateTime(_rangeStart.year, _rangeStart.month, _rangeStart.day);
    final currentEnd = DateTime(_rangeEnd.year, _rangeEnd.month, _rangeEnd.day);
    final bucketStarts = _generateBucketStarts(
      start: currentStart,
      end: currentEnd,
      granularity: granularity,
    );

    final previousEnd = currentStart.subtract(const Duration(days: 1));
    final previousStart =
        previousEnd.subtract(Duration(days: currentEnd.difference(currentStart).inDays));

    final currentTotals = List<double>.filled(bucketStarts.length, 0);
    final currentCounts = List<int>.filled(bucketStarts.length, 0);
    final previousTotals = List<double>.filled(bucketStarts.length, 0);
    final previousCounts = List<int>.filled(bucketStarts.length, 0);

    for (final doc in feedbackDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'] as Timestamp?;
      final rating = (data['rating'] as num?)?.toDouble();
      if (createdAt == null || rating == null) continue;

      final date = createdAt.toDate();
      if (!date.isBefore(currentStart) && !date.isAfter(currentEnd)) {
        final index = _bucketIndexForDate(
          date: date,
          start: currentStart,
          granularity: granularity,
        );
        if (index >= 0 && index < currentTotals.length) {
          currentTotals[index] += rating;
          currentCounts[index] += 1;
        }
      } else if (!date.isBefore(previousStart) && !date.isAfter(previousEnd)) {
        final index = _bucketIndexForDate(
          date: date,
          start: previousStart,
          granularity: granularity,
        );
        if (index >= 0 && index < previousTotals.length) {
          previousTotals[index] += rating;
          previousCounts[index] += 1;
        }
      }
    }

    final currentPoints = List<double>.generate(
      bucketStarts.length,
      (index) => currentCounts[index] == 0 ? 0 : currentTotals[index] / currentCounts[index],
    );
    final previousPoints = List<double>.generate(
      bucketStarts.length,
      (index) => previousCounts[index] == 0 ? 0 : previousTotals[index] / previousCounts[index],
    );
    final labels = bucketStarts.map((date) => _bucketLabel(date, granularity)).toList();

    final currentLegend = _dateRangeLabel;
    final previousLegend = granularity == 'month'
        ? 'Previous matching period'
        : 'Previous ${_selectedRangeDays}-day period';
    final subtitle = switch (granularity) {
      'day' => 'Daily average feedback rating in the selected live range',
      'week' => 'Weekly average feedback rating in the selected live range',
      _ => 'Monthly average feedback rating in the selected live range',
    };

    return (
      currentPoints: currentPoints,
      previousPoints: previousPoints,
      labels: labels,
      currentLegend: currentLegend,
      previousLegend: previousLegend,
      subtitle: subtitle,
    );
  }

  List<int> _dailyRequestCounts(List<QueryDocumentSnapshot> requestDocs) {
    final now = DateTime.now();
    final counts = List<int>.filled(7, 0);

    for (final doc in requestDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) continue;
      final date = createdAt.toDate();
      final dayDiff = DateTime(now.year, now.month, now.day)
          .difference(DateTime(date.year, date.month, date.day))
          .inDays;
      if (dayDiff >= 0 && dayDiff < 7) {
        counts[6 - dayDiff]++;
      }
    }

    return counts;
  }

  List<String> _dailyLabels() {
    final now = DateTime.now();
    return List<String>.generate(7, (index) {
      final day = now.subtract(Duration(days: 6 - index));
      return DateFormat('EEE').format(day).toUpperCase();
    });
  }

  List<Map<String, dynamic>> _serviceDistribution(List<QueryDocumentSnapshot> requestDocs) {
    final counts = <String, int>{};
    for (final doc in requestDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = (data['serviceType'] ?? 'Other').toString().trim();
      counts[type] = (counts[type] ?? 0) + 1;
    }

    final total = counts.values.fold<int>(0, (sum, item) => sum + item);
    final palette = <Color>[
      AppColors.primary,
      AppColors.primaryMuted,
      const Color(0xFF7e2900),
      AppColors.success,
      AppColors.accent,
    ];

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(5).toList().asMap().entries.map((entry) {
      final item = entry.value;
      final percent = total == 0 ? 0 : ((item.value / total) * 100).round();
      return <String, dynamic>{
        'label': item.key,
        'count': item.value,
        'percent': percent,
        'color': palette[entry.key % palette.length],
      };
    }).toList();
  }

  List<double> _monthlyAverageRatings(
    List<QueryDocumentSnapshot> feedbackDocs, {
    required int year,
  }) {
    final totals = List<double>.filled(12, 0);
    final counts = List<int>.filled(12, 0);

    for (final doc in feedbackDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final createdAt = data['createdAt'] as Timestamp?;
      final rating = (data['rating'] as num?)?.toDouble();
      if (createdAt == null || rating == null) continue;

      final date = createdAt.toDate();
      if (date.year != year) continue;

      totals[date.month - 1] += rating;
      counts[date.month - 1] += 1;
    }

    return List<double>.generate(12, (index) {
      return counts[index] == 0 ? 0 : totals[index] / counts[index];
    });
  }

  List<Map<String, dynamic>> _providerPerformanceRows(
    List<QueryDocumentSnapshot> requestDocs,
    List<QueryDocumentSnapshot> feedbackDocs, {
    required Map<String, String> providerNames,
  }) {
    final stats = <String, Map<String, dynamic>>{};

    for (final doc in requestDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final providerId = (data['assignedProviderId'] ?? '').toString();
      if (providerId.isEmpty) continue;
      final entry = stats.putIfAbsent(providerId, () => <String, dynamic>{
            'providerName': providerNames[providerId] ??
                (data['assignedProviderName'] ?? 'Provider').toString(),
            'assigned': 0,
            'completed': 0,
            'responseMinutes': 0.0,
            'responseCount': 0,
            'ratingTotal': 0.0,
            'ratingCount': 0,
          });
      entry['assigned'] = (entry['assigned'] as int) + 1;
      if (_normalizedStatus(data['status']) == 'completed') {
        entry['completed'] = (entry['completed'] as int) + 1;
      }
      final createdAt = data['createdAt'] as Timestamp?;
      final assignedAt = data['assignedAt'] as Timestamp?;
      if (createdAt != null && assignedAt != null) {
        entry['responseMinutes'] = (entry['responseMinutes'] as double) +
            assignedAt.toDate().difference(createdAt.toDate()).inMinutes;
        entry['responseCount'] = (entry['responseCount'] as int) + 1;
      }
    }

    for (final doc in feedbackDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final providerId = (data['providerId'] ?? '').toString();
      if (providerId.isEmpty) continue;
      final entry = stats.putIfAbsent(providerId, () => <String, dynamic>{
            'providerName': providerNames[providerId] ?? 'Provider',
            'assigned': 0,
            'completed': 0,
            'responseMinutes': 0.0,
            'responseCount': 0,
            'ratingTotal': 0.0,
            'ratingCount': 0,
          });
      entry['ratingTotal'] =
          (entry['ratingTotal'] as double) + ((data['rating'] as num?)?.toDouble() ?? 0);
      entry['ratingCount'] = (entry['ratingCount'] as int) + 1;
    }

    final rows = stats.values.map((entry) {
      final responseCount = entry['responseCount'] as int;
      final ratingCount = entry['ratingCount'] as int;
      return <String, dynamic>{
        'providerName': entry['providerName'],
        'assigned': entry['assigned'],
        'completed': entry['completed'],
        'avgResponseMinutes':
            responseCount == 0 ? 0.0 : (entry['responseMinutes'] as double) / responseCount,
        'avgRating':
            ratingCount == 0 ? 0.0 : (entry['ratingTotal'] as double) / ratingCount,
        'reviews': ratingCount,
      };
    }).toList();

    rows.sort((a, b) {
      final completedCompare = (b['completed'] as int).compareTo(a['completed'] as int);
      if (completedCompare != 0) return completedCompare;
      return (b['avgRating'] as double).compareTo(a['avgRating'] as double);
    });
    return rows;
  }

  List<Map<String, dynamic>> _feedbackSummaryRows(
    List<QueryDocumentSnapshot> feedbackDocs, {
    required Map<String, String> providerNames,
  }) {
    final rows = feedbackDocs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final providerId = (data['providerId'] ?? '').toString();
      return <String, dynamic>{
        'providerName':
            (data['providerName'] ?? providerNames[providerId] ?? providerId).toString(),
        'residentName': (data['residentName'] ?? data['userName'] ?? 'Resident').toString(),
        'rating': ((data['rating'] as num?)?.toDouble() ?? 0).toStringAsFixed(1),
        'comment': (data['comment'] ?? 'No comment').toString(),
        'serviceType': (data['serviceType'] ?? 'Service').toString(),
        'unit': (data['unit'] ?? 'Unit not set').toString(),
        'createdAt': data['createdAt'] as Timestamp?,
      };
    }).toList();

    rows.sort((a, b) {
      final aTs = a['createdAt'] as Timestamp?;
      final bTs = b['createdAt'] as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(aTs?.millisecondsSinceEpoch ?? 0);
    });
    return rows;
  }

  List<Map<String, dynamic>> _completedServiceRows(
    List<QueryDocumentSnapshot> requestDocs, {
    required Map<String, String> providerNames,
  }) {
    final rows = requestDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _normalizedStatus(data['status']) == 'completed';
    }).map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final providerId = (data['assignedProviderId'] ?? '').toString();
      return <String, dynamic>{
        'residentName': (data['residentName'] ?? 'Resident').toString(),
        'providerName':
            (providerNames[providerId] ?? data['assignedProviderName'] ?? 'Provider').toString(),
        'serviceType': (data['serviceType'] ?? 'Service').toString(),
        'unit': (data['location'] ?? data['unit'] ?? 'Unit not set').toString(),
        'completedAt': data['completedAt'] as Timestamp?,
        'createdAt': data['createdAt'] as Timestamp?,
      };
    }).toList();

    rows.sort((a, b) {
      final aTs = a['completedAt'] as Timestamp?;
      final bTs = b['completedAt'] as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(aTs?.millisecondsSinceEpoch ?? 0);
    });
    return rows;
  }

  List<Map<String, dynamic>> _requestSubmissionRows(
    List<QueryDocumentSnapshot> requestDocs, {
    required Map<String, String> providerNames,
  }) {
    final rows = requestDocs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final providerId = (data['assignedProviderId'] ?? '').toString();
      return <String, dynamic>{
        'residentName': (data['residentName'] ?? 'Resident').toString(),
        'serviceType': (data['serviceType'] ?? 'Service').toString(),
        'urgency': (data['urgency'] ?? 'medium').toString(),
        'unit': (data['location'] ?? data['unit'] ?? 'Unit not set').toString(),
        'providerName':
            (providerNames[providerId] ?? data['assignedProviderName'] ?? 'Unassigned').toString(),
        'createdAt': data['createdAt'] as Timestamp?,
      };
    }).toList();

    rows.sort((a, b) {
      final aTs = a['createdAt'] as Timestamp?;
      final bTs = b['createdAt'] as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(aTs?.millisecondsSinceEpoch ?? 0);
    });
    return rows;
  }

  List<Map<String, dynamic>> _declineRows(
    List<QueryDocumentSnapshot> requestDocs, {
    required Map<String, String> providerNames,
  }) {
    final rows = requestDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['lastDeclinedAt'] != null;
    }).map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final providerId = (data['lastDeclinedByProviderId'] ?? '').toString();
      return <String, dynamic>{
        'residentName': (data['residentName'] ?? 'Resident').toString(),
        'providerName': (data['lastDeclinedByProviderName'] ??
                providerNames[providerId] ??
                'Provider')
            .toString(),
        'serviceType': (data['serviceType'] ?? 'Service').toString(),
        'unit': (data['location'] ?? data['unit'] ?? 'Unit not set').toString(),
        'reason': (data['lastDeclineReason'] ?? 'No reason recorded').toString(),
        'declinedAt': data['lastDeclinedAt'] as Timestamp?,
      };
    }).toList();

    rows.sort((a, b) {
      final aTs = a['declinedAt'] as Timestamp?;
      final bTs = b['declinedAt'] as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(aTs?.millisecondsSinceEpoch ?? 0);
    });
    return rows;
  }

  List<Map<String, dynamic>> _adminAuditRows(
    List<QueryDocumentSnapshot> requestDocs,
    List<QueryDocumentSnapshot> feedbackDocs, {
    required Map<String, String> providerNames,
  }) {
    final rows = <Map<String, dynamic>>[];

    for (final row in _requestSubmissionRows(requestDocs, providerNames: providerNames)) {
      rows.add(<String, dynamic>{
        'eventType': 'Request Submitted',
        'summary': '${row['residentName']} submitted ${row['serviceType']} for ${row['unit']}',
        'people': 'Resident: ${row['residentName']} | Provider: ${row['providerName']}',
        'outcome': 'Urgency: ${row['urgency']}',
        'timestamp': row['createdAt'] as Timestamp?,
      });
    }

    for (final row in _completedServiceRows(requestDocs, providerNames: providerNames)) {
      rows.add(<String, dynamic>{
        'eventType': 'Service Completed',
        'summary': '${row['providerName']} completed ${row['serviceType']} for ${row['residentName']}',
        'people': 'Provider: ${row['providerName']} | Resident: ${row['residentName']}',
        'outcome': 'Unit: ${row['unit']}',
        'timestamp': row['completedAt'] as Timestamp?,
      });
    }

    for (final row in _declineRows(requestDocs, providerNames: providerNames)) {
      rows.add(<String, dynamic>{
        'eventType': 'Assignment Declined',
        'summary': '${row['providerName']} declined ${row['serviceType']} for ${row['residentName']}',
        'people': 'Provider: ${row['providerName']} | Resident: ${row['residentName']}',
        'outcome': 'Reason: ${row['reason']} | Unit: ${row['unit']}',
        'timestamp': row['declinedAt'] as Timestamp?,
      });
    }

    for (final row in _feedbackSummaryRows(feedbackDocs, providerNames: providerNames)) {
      rows.add(<String, dynamic>{
        'eventType': 'Feedback Received',
        'summary': '${row['residentName']} rated ${row['providerName']} ${row['rating']}/5',
        'people': 'Resident: ${row['residentName']} | Provider: ${row['providerName']}',
        'outcome': '${row['serviceType']} | ${row['unit']} | ${row['comment']}',
        'timestamp': row['createdAt'] as Timestamp?,
      });
    }

    if (_selectedAuditEventType != 'All Events') {
      rows.removeWhere((row) => row['eventType'] != _selectedAuditEventType);
    }

    rows.sort((a, b) {
      final aTs = a['timestamp'] as Timestamp?;
      final bTs = b['timestamp'] as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(aTs?.millisecondsSinceEpoch ?? 0);
    });
    return rows;
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';
    return DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toDate());
  }

  String _escapeCsv(dynamic value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  String _reportFileSlug() {
    return _selectedReportType.toLowerCase().replaceAll(' ', '_');
  }

  String _pdfSafeText(dynamic value) {
    final text = value?.toString() ?? '';
    final normalized = text
        .replaceAll('•', '-')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"');
    return normalized.replaceAll(RegExp(r'[^\x00-\x7F]'), '?');
  }

  Future<pw.ThemeData?> _loadPdfTheme() async {
    try {
      final regularFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      );
      final boldFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
      );
      return pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportCurrentReportPdf({
    required List<QueryDocumentSnapshot> requestDocs,
    required List<QueryDocumentSnapshot> feedbackDocs,
    required Map<String, String> providerNames,
  }) async {
    final pdf = pw.Document();
    final pdfTheme = await _loadPdfTheme();
    final generatedAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final reportTitle = _selectedReportType == 'Overview'
        ? 'Overview Report'
        : _selectedReportType;
    final rows = <List<String>>[];
    var headers = <String>[];

    if (_selectedReportType == 'Provider Performance') {
      headers = ['Provider', 'Assigned', 'Completed', 'Avg Response', 'Avg Rating', 'Reviews'];
      for (final row in _providerPerformanceRows(
        requestDocs,
        feedbackDocs,
        providerNames: providerNames,
      )) {
        rows.add([
          _pdfSafeText(row['providerName']),
          _pdfSafeText(row['assigned']),
          _pdfSafeText(row['completed']),
          _pdfSafeText('${(row['avgResponseMinutes'] as double).toStringAsFixed(0)}m'),
          _pdfSafeText((row['avgRating'] as double).toStringAsFixed(1)),
          _pdfSafeText(row['reviews']),
        ]);
      }
    } else if (_selectedReportType == 'Feedback Summary') {
      headers = ['Provider', 'Resident', 'Service', 'Unit', 'Rating', 'Comment', 'Created At'];
      for (final row in _feedbackSummaryRows(feedbackDocs, providerNames: providerNames)) {
        rows.add([
          _pdfSafeText(row['providerName']),
          _pdfSafeText(row['residentName']),
          _pdfSafeText(row['serviceType']),
          _pdfSafeText(row['unit']),
          _pdfSafeText(row['rating']),
          _pdfSafeText(row['comment']),
          _pdfSafeText(_formatTimestamp(row['createdAt'] as Timestamp?)),
        ]);
      }
    } else if (_selectedReportType == 'Completed Services') {
      headers = ['Provider', 'Resident', 'Service', 'Unit', 'Completed At', 'Submitted At'];
      for (final row in _completedServiceRows(requestDocs, providerNames: providerNames)) {
        rows.add([
          _pdfSafeText(row['providerName']),
          _pdfSafeText(row['residentName']),
          _pdfSafeText(row['serviceType']),
          _pdfSafeText(row['unit']),
          _pdfSafeText(_formatTimestamp(row['completedAt'] as Timestamp?)),
          _pdfSafeText(_formatTimestamp(row['createdAt'] as Timestamp?)),
        ]);
      }
    } else if (_selectedReportType == 'Assignment Declines') {
      headers = ['Provider', 'Resident', 'Service', 'Unit', 'Reason', 'Declined At'];
      for (final row in _declineRows(requestDocs, providerNames: providerNames)) {
        rows.add([
          _pdfSafeText(row['providerName']),
          _pdfSafeText(row['residentName']),
          _pdfSafeText(row['serviceType']),
          _pdfSafeText(row['unit']),
          _pdfSafeText(row['reason']),
          _pdfSafeText(_formatTimestamp(row['declinedAt'] as Timestamp?)),
        ]);
      }
    } else if (_selectedReportType == 'Request Submissions') {
      headers = ['Resident', 'Service', 'Urgency', 'Unit', 'Provider', 'Submitted At'];
      for (final row in _requestSubmissionRows(requestDocs, providerNames: providerNames)) {
        rows.add([
          _pdfSafeText(row['residentName']),
          _pdfSafeText(row['serviceType']),
          _pdfSafeText(row['urgency']),
          _pdfSafeText(row['unit']),
          _pdfSafeText(row['providerName']),
          _pdfSafeText(_formatTimestamp(row['createdAt'] as Timestamp?)),
        ]);
      }
    } else if (_selectedReportType == 'Admin Audit Report') {
      headers = ['Event', 'Summary', 'People', 'Outcome', 'Recorded At'];
      for (final row in _adminAuditRows(
        requestDocs,
        feedbackDocs,
        providerNames: providerNames,
      )) {
        rows.add([
          _pdfSafeText(row['eventType']),
          _pdfSafeText(row['summary']),
          _pdfSafeText(row['people']),
          _pdfSafeText(row['outcome']),
          _pdfSafeText(_formatTimestamp(row['timestamp'] as Timestamp?)),
        ]);
      }
    } else {
      headers = ['Resident', 'Service Type', 'Status', 'Urgency', 'Provider', 'Unit', 'Created At'];
      for (final doc in requestDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final providerId = (data['assignedProviderId'] ?? '').toString();
        rows.add([
          _pdfSafeText(data['residentName'] ?? 'Resident'),
          _pdfSafeText(data['serviceType'] ?? 'Service'),
          _pdfSafeText(_normalizedStatus(data['status'])),
          _pdfSafeText(data['urgency'] ?? 'medium'),
          _pdfSafeText(providerNames[providerId] ?? data['assignedProviderName'] ?? 'Unassigned'),
          _pdfSafeText(data['location'] ?? data['unit'] ?? 'Unit not set'),
          _pdfSafeText(_formatTimestamp(data['createdAt'] as Timestamp?)),
        ]);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        build: (context) => [
          pw.Text(_pdfSafeText('Tumaini Estate'), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(_pdfSafeText(reportTitle), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(_pdfSafeText('Date range: $_dateRangeLabel')),
          pw.Text(_pdfSafeText('Generated: $generatedAt')),
          pw.SizedBox(height: 12),
          if (_selectedStatus != 'All Statuses' || _selectedProvider != 'All Providers')
            pw.Text(_pdfSafeText('Filters: status=$_selectedStatus, provider=${_selectedProvider == 'All Providers' ? 'All' : _selectedProvider}')),
          pw.SizedBox(height: 12),
          if (rows.isEmpty)
            pw.Text(_pdfSafeText('No records found for the selected filters.'))
          else
            pw.TableHelper.fromTextArray(
              headers: headers.map(_pdfSafeText).toList(),
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE6F2EF)),
              cellAlignment: pw.Alignment.centerLeft,
            ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await exportBytesAsFile(
      bytes: bytes,
      filename: '${_reportFileSlug()}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      mimeType: 'application/pdf',
      text: 'Tumaini Estate $reportTitle export',
      subject: 'Tumaini Estate $reportTitle PDF',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pdfTheme == null
              ? 'PDF export prepared for $reportTitle. Add NotoSans font files in assets/fonts to remove Unicode font warnings.'
              : 'PDF export prepared for $reportTitle',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _exportCurrentReportCsv({
    required List<QueryDocumentSnapshot> requestDocs,
    required List<QueryDocumentSnapshot> feedbackDocs,
    required Map<String, String> providerNames,
  }) async {
    final buffer = StringBuffer();

    if (_selectedReportType == 'Provider Performance') {
      buffer.writeln('Provider,Assigned,Completed,Average Response Minutes,Average Rating,Reviews');
      for (final row in _providerPerformanceRows(
        requestDocs,
        feedbackDocs,
        providerNames: providerNames,
      )) {
        buffer.writeln([
          _escapeCsv(row['providerName']),
          row['assigned'],
          row['completed'],
          (row['avgResponseMinutes'] as double).toStringAsFixed(0),
          (row['avgRating'] as double).toStringAsFixed(1),
          row['reviews'],
        ].join(','));
      }
    } else if (_selectedReportType == 'Feedback Summary') {
      buffer.writeln('Provider,Resident,Service,Unit,Rating,Comment,Created At');
      for (final row in _feedbackSummaryRows(feedbackDocs, providerNames: providerNames)) {
        buffer.writeln([
          _escapeCsv(row['providerName']),
          _escapeCsv(row['residentName']),
          _escapeCsv(row['serviceType']),
          _escapeCsv(row['unit']),
          row['rating'],
          _escapeCsv(row['comment']),
          _escapeCsv(_formatTimestamp(row['createdAt'] as Timestamp?)),
        ].join(','));
      }
    } else if (_selectedReportType == 'Completed Services') {
      buffer.writeln('Provider,Resident,Service,Unit,Completed At,Submitted At');
      for (final row in _completedServiceRows(requestDocs, providerNames: providerNames)) {
        buffer.writeln([
          _escapeCsv(row['providerName']),
          _escapeCsv(row['residentName']),
          _escapeCsv(row['serviceType']),
          _escapeCsv(row['unit']),
          _escapeCsv(_formatTimestamp(row['completedAt'] as Timestamp?)),
          _escapeCsv(_formatTimestamp(row['createdAt'] as Timestamp?)),
        ].join(','));
      }
    } else if (_selectedReportType == 'Assignment Declines') {
      buffer.writeln('Provider,Resident,Service,Unit,Reason,Declined At');
      for (final row in _declineRows(requestDocs, providerNames: providerNames)) {
        buffer.writeln([
          _escapeCsv(row['providerName']),
          _escapeCsv(row['residentName']),
          _escapeCsv(row['serviceType']),
          _escapeCsv(row['unit']),
          _escapeCsv(row['reason']),
          _escapeCsv(_formatTimestamp(row['declinedAt'] as Timestamp?)),
        ].join(','));
      }
    } else if (_selectedReportType == 'Request Submissions') {
      buffer.writeln('Resident,Service,Urgency,Unit,Provider,Submitted At');
      for (final row in _requestSubmissionRows(requestDocs, providerNames: providerNames)) {
        buffer.writeln([
          _escapeCsv(row['residentName']),
          _escapeCsv(row['serviceType']),
          _escapeCsv(row['urgency']),
          _escapeCsv(row['unit']),
          _escapeCsv(row['providerName']),
          _escapeCsv(_formatTimestamp(row['createdAt'] as Timestamp?)),
        ].join(','));
      }
    } else if (_selectedReportType == 'Admin Audit Report') {
      buffer.writeln('Event,Summary,People,Outcome,Recorded At');
      for (final row in _adminAuditRows(
        requestDocs,
        feedbackDocs,
        providerNames: providerNames,
      )) {
        buffer.writeln([
          _escapeCsv(row['eventType']),
          _escapeCsv(row['summary']),
          _escapeCsv(row['people']),
          _escapeCsv(row['outcome']),
          _escapeCsv(_formatTimestamp(row['timestamp'] as Timestamp?)),
        ].join(','));
      }
    } else {
      buffer.writeln('Resident,Service Type,Status,Urgency,Provider,Unit,Created At');
      for (final doc in requestDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final providerId = (data['assignedProviderId'] ?? '').toString();
        buffer.writeln([
          _escapeCsv(data['residentName'] ?? 'Resident'),
          _escapeCsv(data['serviceType'] ?? 'Service'),
          _escapeCsv(_normalizedStatus(data['status'])),
          _escapeCsv(data['urgency'] ?? 'medium'),
          _escapeCsv(providerNames[providerId] ?? data['assignedProviderName'] ?? 'Unassigned'),
          _escapeCsv(data['location'] ?? data['unit'] ?? 'Unit not set'),
          _escapeCsv(_formatTimestamp(data['createdAt'] as Timestamp?)),
        ].join(','));
      }
    }

    final csvBytes = utf8.encode(buffer.toString());
    await exportBytesAsFile(
      bytes: csvBytes,
      filename: '${_reportFileSlug()}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
      mimeType: 'text/csv',
      text: 'Tumaini Estate $_selectedReportType export',
      subject: 'Tumaini Estate $_selectedReportType CSV',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('CSV export prepared for $_selectedReportType'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 1024;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;
    final padding = isWide ? 32.0 : (isTablet ? 24.0 : 16.0);

    final surface = isDark ? AppColors.surfaceDark : const Color(0xFFf9f9fb);
    final surfaceContainer = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFedeef0);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return AdminNavigationShell(
      title: 'Reports & Analytics',
      selectedSection: AdminNavSection.reports,
      actions: const [AppHomeAction()],
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('requests').snapshots(),
        builder: (context, requestSnapshot) {
          if (requestSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (requestSnapshot.hasError) {
            return Center(child: Text('Failed to load requests: ${requestSnapshot.error}'));
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('feedback').snapshots(),
            builder: (context, feedbackSnapshot) {
              if (feedbackSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (feedbackSnapshot.hasError) {
                return Center(child: Text('Failed to load feedback: ${feedbackSnapshot.error}'));
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('users')
                    .where('role', isEqualTo: 'provider')
                    .snapshots(),
                builder: (context, providerSnapshot) {
                  if (providerSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (providerSnapshot.hasError) {
                    return Center(child: Text('Failed to load providers: ${providerSnapshot.error}'));
                  }

                  final providers = providerSnapshot.data?.docs ?? [];
                  final providerNames = <String, String>{
                    for (final doc in providers)
                      doc.id: ((doc.data() as Map<String, dynamic>)['fullName'] ?? 'Provider')
                          .toString(),
                  };

                  final requestDocs = _filteredRequests(
                    _filteredByCreatedAt(requestSnapshot.data?.docs ?? []),
                    providerNames: providerNames,
                  );
                  final feedbackDocs = _filteredFeedback(
                    _filteredByCreatedAt(feedbackSnapshot.data?.docs ?? []),
                    providerNames: providerNames,
                  );

                  return RefreshIndicator(
                    onRefresh: () async => setState(() {}),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            runSpacing: 16,
                            spacing: 16,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 540),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Reports & Analytics',
                                      style: TextStyle(
                                        fontSize: isWide ? 32 : 28,
                                        fontWeight: FontWeight.w800,
                                        color: textOnSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Live performance insights for Tumaini Estate based on real requests and feedback.',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: textOnSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _buildPickerChip(
                                    label: _dateRangeLabel,
                                    icon: Icons.date_range,
                                    onTap: _showDateRangePicker,
                                    surfaceContainer: surfaceContainer,
                                    textOnSurface: textOnSurface,
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => _exportCurrentReportPdf(
                                          requestDocs: requestDocs,
                                          feedbackDocs: feedbackDocs,
                                          providerNames: providerNames,
                                        ),
                                        icon: const Icon(Icons.picture_as_pdf_outlined),
                                        label: const Text('Export PDF'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => _exportCurrentReportCsv(
                                          requestDocs: requestDocs,
                                          feedbackDocs: feedbackDocs,
                                          providerNames: providerNames,
                                        ),
                                        icon: const Icon(Icons.table_view_outlined),
                                        label: const Text('Export CSV'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildFiltersRow(
                            context,
                            providers: providers,
                            surfaceContainer: surfaceContainer,
                            textOnSurface: textOnSurface,
                            textOnSurfaceVariant: textOnSurfaceVariant,
                          ),
                          const SizedBox(height: 32),
                          _buildMetricsRow(
                            context,
                            requestDocs: requestDocs,
                            feedbackDocs: feedbackDocs,
                          ),
                          const SizedBox(height: 32),
                          _buildReportTypeSection(
                            context,
                            requestDocs: requestDocs,
                            feedbackDocs: feedbackDocs,
                            providerNames: providerNames,
                          ),
                          if (_selectedReportType == 'Overview') ...[
                            const SizedBox(height: 32),
                            isWide
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 7,
                                        child: _buildDailyRequestsChart(
                                          context,
                                          requestDocs: requestDocs,
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        flex: 5,
                                        child: _buildServiceDistributionCard(
                                          context,
                                          requestDocs: requestDocs,
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      _buildDailyRequestsChart(
                                        context,
                                        requestDocs: requestDocs,
                                      ),
                                      const SizedBox(height: 32),
                                      _buildServiceDistributionCard(
                                        context,
                                        requestDocs: requestDocs,
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 32),
                            _buildSatisfactionTrendsChart(
                              context,
                              feedbackDocs: feedbackDocs,
                            ),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPickerChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required Color surfaceContainer,
    required Color textOnSurface,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textOnSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersRow(
    BuildContext context, {
    required List<QueryDocumentSnapshot> providers,
    required Color surfaceContainer,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
  }) {
    final providerOptions = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'All Providers', child: Text('All Providers')),
      ...providers.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return DropdownMenuItem(
          value: doc.id,
          child: Text((data['fullName'] ?? 'Provider').toString()),
        );
      }),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildDropdownFilter(
          label: 'Report Type',
          value: _selectedReportType,
          items: _reportTypes
              .map((type) => DropdownMenuItem(value: type, child: Text(type)))
              .toList(),
          onChanged: (value) => setState(() => _selectedReportType = value ?? _selectedReportType),
          surfaceContainer: surfaceContainer,
          textOnSurface: textOnSurface,
          textOnSurfaceVariant: textOnSurfaceVariant,
        ),
        _buildDropdownFilter(
          label: 'Status',
          value: _selectedStatus,
          items: _statusOptions
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: (value) => setState(() => _selectedStatus = value ?? _selectedStatus),
          surfaceContainer: surfaceContainer,
          textOnSurface: textOnSurface,
          textOnSurfaceVariant: textOnSurfaceVariant,
        ),
        _buildDropdownFilter(
          label: 'Provider',
          value: _selectedProvider,
          items: providerOptions,
          onChanged: (value) => setState(() => _selectedProvider = value ?? _selectedProvider),
          surfaceContainer: surfaceContainer,
          textOnSurface: textOnSurface,
          textOnSurfaceVariant: textOnSurfaceVariant,
        ),
        if (_selectedReportType == 'Admin Audit Report')
          _buildDropdownFilter(
            label: 'Audit Event',
            value: _selectedAuditEventType,
            items: _auditEventOptions
                .map((event) => DropdownMenuItem(value: event, child: Text(event)))
                .toList(),
            onChanged: (value) =>
                setState(() => _selectedAuditEventType = value ?? _selectedAuditEventType),
            surfaceContainer: surfaceContainer,
            textOnSurface: textOnSurface,
            textOnSurfaceVariant: textOnSurfaceVariant,
          ),
      ],
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required Color surfaceContainer,
    required Color textOnSurface,
    required Color textOnSurfaceVariant,
  }) {
    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textOnSurfaceVariant,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items,
              onChanged: onChanged,
              style: TextStyle(color: textOnSurface, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTypeSection(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
    required List<QueryDocumentSnapshot> feedbackDocs,
    required Map<String, String> providerNames,
  }) {
    switch (_selectedReportType) {
      case 'Admin Audit Report':
        return _buildAdminAuditReport(
          context,
          requestDocs: requestDocs,
          feedbackDocs: feedbackDocs,
          providerNames: providerNames,
        );
      case 'Pending Requests':
        return _buildPendingRequestsReport(
          context,
          requestDocs: requestDocs,
          providerNames: providerNames,
        );
      case 'Request Submissions':
        return _buildRequestSubmissionsReport(
          context,
          requestDocs: requestDocs,
          providerNames: providerNames,
        );
      case 'Completed Services':
        return _buildCompletedServicesReport(
          context,
          requestDocs: requestDocs,
          providerNames: providerNames,
        );
      case 'Assignment Declines':
        return _buildAssignmentDeclinesReport(
          context,
          requestDocs: requestDocs,
          providerNames: providerNames,
        );
      case 'Provider Performance':
        return _buildProviderPerformanceReport(
          context,
          requestDocs: requestDocs,
          feedbackDocs: feedbackDocs,
          providerNames: providerNames,
        );
      case 'Feedback Summary':
        return _buildFeedbackSummaryReport(
          context,
          feedbackDocs: feedbackDocs,
          providerNames: providerNames,
        );
      case 'Overview':
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMetricsRow(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
    required List<QueryDocumentSnapshot> feedbackDocs,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColors.primary;
    final secondary = isDark ? AppColors.textMutedDark : AppColors.primaryMuted;
    final tertiary = isDark ? AppColors.textMutedDark : const Color(0xFF7e2900);
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);

    final totalRequests = requestDocs.length;
    final completedCount = requestDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _normalizedStatus(data['status']) == 'completed';
    }).length;
    final completionRate = totalRequests > 0 ? (completedCount / totalRequests) : 0.0;
    final averageRating = _averageRating(feedbackDocs);
    final averageResponse = _averageResponseMinutes(requestDocs);

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildMetricCard(
          context,
          icon: Icons.assignment_late,
          iconBg: primary.withOpacity(0.05),
          iconColor: primary,
          title: 'Requests In Range',
          value: totalRequests.toString(),
          change: _dateRangeLabel,
          progress: completionRate,
          progressBg: surfaceContainerLow,
        ),
        _buildMetricCard(
          context,
          icon: Icons.task_alt,
          iconBg: secondary.withOpacity(0.05),
          iconColor: secondary,
          title: 'Completion Rate',
          value: '${(completionRate * 100).toStringAsFixed(1)}%',
          change: '$completedCount completed',
          secondary: true,
        ),
        _buildMetricCard(
          context,
          icon: Icons.schedule,
          iconBg: tertiary.withOpacity(0.05),
          iconColor: tertiary,
          title: 'Avg. Response Time',
          value: averageResponse == 0 ? 'N/A' : '${averageResponse.toStringAsFixed(0)}m',
          change:
              '${requestDocs.where((doc) => ((doc.data() as Map<String, dynamic>)['assignedAt'] != null)).length} assigned',
        ),
        _buildMetricCard(
          context,
          icon: Icons.star,
          iconBg: AppColors.accent.withOpacity(0.08),
          iconColor: AppColors.warningStrong,
          title: 'Avg. Satisfaction',
          value: averageRating.toStringAsFixed(1),
          subtitle: '/ 5',
          change: '${feedbackDocs.length} reviews',
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String value,
    String? subtitle,
    required String change,
    double? progress,
    Color? progressBg,
    bool secondary = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);

    return SizedBox(
      width: MediaQuery.of(context).size.width > 1200 ? 270 : 240,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                Flexible(
                  child: Text(
                    change,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: secondary ? textOnSurfaceVariant : iconColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: textOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textOnSurface,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 16, color: textOnSurfaceVariant),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: progressBg ?? surfaceContainerLow,
                  valueColor: AlwaysStoppedAnimation(iconColor),
                  minHeight: 6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDailyRequestsChart(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLow = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFf3f3f5);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;

    final labels = _dailyLabels();
    final values = _dailyRequestCounts(requestDocs);
    final maxValue = (values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b)).toDouble();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daily Service Requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textOnSurface,
                ),
              ),
              Text(
                DateFormat('dd MMM').format(DateTime.now().subtract(const Duration(days: 6))) +
                    ' - ' +
                    DateFormat('dd MMM').format(DateTime.now()),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: textOnSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(labels.length, (index) {
                final value = values[index].toDouble();
                // Keep bars slightly below the hard 200px chart height so
                // value/label text and spacing never overflow on web rendering.
                final height = maxValue == 0 ? 8.0 : (value / maxValue) * 150;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        values[index].toString(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textOnSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: height,
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: index == labels.length - 1
                              ? primary
                              : primary.withOpacity(0.22),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: index == labels.length - 1
                              ? primary
                              : textOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceDistributionCard(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerHighest = isDark ? AppColors.surfaceDarkElevated : const Color(0xFFe2e2e4);
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    final distribution = _serviceDistribution(requestDocs);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Service Distribution',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textOnSurface,
            ),
          ),
          const SizedBox(height: 24),
          if (distribution.isEmpty)
            Text(
              'No requests found in the selected period.',
              style: TextStyle(color: textOnSurfaceVariant),
            )
          else
            ...distribution.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: item['color'] as Color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item['label'] as String,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textOnSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${item['count']} • ${item['percent']}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textOnSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (item['percent'] as int) / 100,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation(item['color'] as Color),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildAdminAuditReport(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
    required List<QueryDocumentSnapshot> feedbackDocs,
    required Map<String, String> providerNames,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final rows = _adminAuditRows(
      requestDocs,
      feedbackDocs,
      providerNames: providerNames,
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admin Audit Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text),
          ),
          const SizedBox(height: 8),
          Text(
            '${rows.length} audit event(s) match the active filters.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Text(
              'No admin audit events found for the selected filters.',
              style: TextStyle(color: muted),
            )
          else
            ...rows.take(40).map((row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row['eventType']} • ${row['summary']}',
                    style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${row['people']}\n${row['outcome']}',
                    style: TextStyle(color: muted),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _formatTimestamp(row['timestamp'] as Timestamp?),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildPendingRequestsReport(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
    required Map<String, String> providerNames,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pending Requests Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text),
          ),
          const SizedBox(height: 8),
          Text(
            '${requestDocs.length} request(s) match the active filters.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          if (requestDocs.isEmpty)
            Text(
              'No pending requests found for the selected filters.',
              style: TextStyle(color: muted),
            )
          else
            ...requestDocs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final providerId = (data['assignedProviderId'] ?? '').toString();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${(data['residentName'] ?? 'Resident').toString()} • ${(data['serviceType'] ?? 'Service').toString()}',
                  style: TextStyle(color: text, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Status: ${_normalizedStatus(data['status'])} | Urgency: ${(data['urgency'] ?? 'medium')} | Provider: ${providerNames[providerId] ?? data['assignedProviderName'] ?? 'Unassigned'} | Unit: ${data['location'] ?? data['unit'] ?? 'Unit not set'}',
                  style: TextStyle(color: muted),
                ),
                trailing: Text(
                  _formatTimestamp(data['createdAt'] as Timestamp?),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRequestSubmissionsReport(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
    required Map<String, String> providerNames,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final rows = _requestSubmissionRows(requestDocs, providerNames: providerNames);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Request Submissions Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text),
          ),
          const SizedBox(height: 8),
          Text(
            '${rows.length} submission record(s) match the active filters.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Text(
              'No request submissions found for the selected filters.',
              style: TextStyle(color: muted),
            )
          else
            ...rows.map((row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row['residentName']} • ${row['serviceType']}',
                    style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Urgency: ${row['urgency']} | Unit: ${row['unit']} | Provider: ${row['providerName']}',
                    style: TextStyle(color: muted),
                  ),
                  trailing: Text(
                    _formatTimestamp(row['createdAt'] as Timestamp?),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildCompletedServicesReport(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
    required Map<String, String> providerNames,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final rows = _completedServiceRows(requestDocs, providerNames: providerNames);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Completed Services Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text),
          ),
          const SizedBox(height: 8),
          Text(
            '${rows.length} completed service record(s) match the active filters.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Text(
              'No completed services found for the selected filters.',
              style: TextStyle(color: muted),
            )
          else
            ...rows.map((row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row['providerName']} -> ${row['residentName']}',
                    style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${row['serviceType']} | ${row['unit']} | Completed ${_formatTimestamp(row['completedAt'] as Timestamp?)}',
                    style: TextStyle(color: muted),
                  ),
                  trailing: Text(
                    _formatTimestamp(row['createdAt'] as Timestamp?),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildAssignmentDeclinesReport(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
    required Map<String, String> providerNames,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final rows = _declineRows(requestDocs, providerNames: providerNames);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assignment Declines Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text),
          ),
          const SizedBox(height: 8),
          Text(
            '${rows.length} decline record(s) match the active filters.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Text(
              'No assignment declines found for the selected filters.',
              style: TextStyle(color: muted),
            )
          else
            ...rows.map((row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row['providerName']} declined ${row['residentName']}',
                    style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${row['serviceType']} | ${row['unit']} | Reason: ${row['reason']}',
                    style: TextStyle(color: muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _formatTimestamp(row['declinedAt'] as Timestamp?),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildProviderPerformanceReport(
    BuildContext context, {
    required List<QueryDocumentSnapshot> requestDocs,
    required List<QueryDocumentSnapshot> feedbackDocs,
    required Map<String, String> providerNames,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final rows = _providerPerformanceRows(
      requestDocs,
      feedbackDocs,
      providerNames: providerNames,
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Provider Performance Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Text(
              'No provider performance data found for the selected filters.',
              style: TextStyle(color: muted),
            )
          else
            ...rows.map((row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    row['providerName'].toString(),
                    style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Assigned: ${row['assigned']} | Completed: ${row['completed']} | Avg response: ${(row['avgResponseMinutes'] as double).toStringAsFixed(0)}m | Rating: ${(row['avgRating'] as double).toStringAsFixed(1)}',
                    style: TextStyle(color: muted),
                  ),
                  trailing: Text(
                    '${row['reviews']} reviews',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildFeedbackSummaryReport(
    BuildContext context, {
    required List<QueryDocumentSnapshot> feedbackDocs,
    required Map<String, String> providerNames,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final muted = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final rows = _feedbackSummaryRows(feedbackDocs, providerNames: providerNames);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Feedback Summary Report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Text(
              'No feedback data found for the selected filters.',
              style: TextStyle(color: muted),
            )
          else
            ...rows.take(20).map((row) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row['providerName']} • ${row['rating']}/5',
                    style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${row['residentName']} • ${row['serviceType']} • ${row['unit']}\n${row['comment']}',
                    style: TextStyle(color: muted),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _formatTimestamp(row['createdAt'] as Timestamp?),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildSatisfactionTrendsChart(
    BuildContext context, {
    required List<QueryDocumentSnapshot> feedbackDocs,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceContainerLowest = isDark ? AppColors.surfaceDark : Colors.white;
    final textOnSurface = isDark ? Colors.white : const Color(0xFF1a1c1d);
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);
    final primary = AppColors.primary;
    final outlineVariant = isDark ? AppColors.borderDark : const Color(0xFFc3c6d7);
    final trendData = _buildSatisfactionTrendData(feedbackDocs);
    final currentPoints = trendData.currentPoints;
    final previousPoints = trendData.previousPoints;
    final labels = trendData.labels;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Satisfaction Trends',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textOnSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trendData.subtitle,
                      style: TextStyle(fontSize: 12, color: textOnSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildTrendLegend(trendData.currentLegend, primary),
                    _buildTrendLegend(trendData.previousLegend, outlineVariant),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 220,
            child: CustomPaint(
              painter: LineChartPainter(
                currentPoints: currentPoints,
                previousPoints: previousPoints,
                labels: labels,
                currentColor: primary,
                previousColor: outlineVariant,
                maxY: 5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (labels.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: labels.length <= 6
                  ? labels
                      .map(
                        (label) => Text(
                          label,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                      .toList()
                  : List.generate(6, (index) {
                      final sampleIndex = ((labels.length - 1) * index / 5).round();
                      return Text(
                        labels[sampleIndex],
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      );
                    }),
            ),
        ],
      ),
    );
  }

  Widget _buildTrendLegend(String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textOnSurfaceVariant = isDark ? AppColors.textSecondaryDark : const Color(0xFF434654);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: textOnSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> currentPoints;
  final List<double> previousPoints;
  final List<String> labels;
  final Color currentColor;
  final Color previousColor;
  final double maxY;

  LineChartPainter({
    required this.currentPoints,
    required this.previousPoints,
    required this.labels,
    required this.currentColor,
    required this.previousColor,
    required this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintCurrent = Paint()
      ..color = currentColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintPrevious = Paint()
      ..color = previousColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final gridPaint = Paint()
      ..color = AppColors.neutral500.withOpacity(0.2)
      ..strokeWidth = 1;

    final width = size.width;
    final height = size.height;
    final pointCount = currentPoints.isEmpty ? 0 : currentPoints.length;
    if (pointCount == 0) {
      for (double y = 0; y <= height; y += height / 4) {
        canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
      }
      return;
    }

    final xStep = pointCount == 1 ? 0.0 : width / (pointCount - 1);

    for (double y = 0; y <= height; y += height / 4) {
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    final pathCurrent = Path();
    final pathPrevious = Path();

    for (int i = 0; i < currentPoints.length; i++) {
      final x = i * xStep;
      final y = height - ((currentPoints[i] / maxY).clamp(0.0, 1.0) * height);
      if (i == 0) {
        pathCurrent.moveTo(x, y);
      } else {
        pathCurrent.lineTo(x, y);
      }
    }
    canvas.drawPath(pathCurrent, paintCurrent);

    for (int i = 0; i < previousPoints.length; i++) {
      final x = i * xStep;
      final y = height - ((previousPoints[i] / maxY).clamp(0.0, 1.0) * height);
      if (i == 0) {
        pathPrevious.moveTo(x, y);
      } else {
        pathPrevious.lineTo(x, y);
      }
    }
    canvas.drawPath(pathPrevious, paintPrevious);

    final pointPaint = Paint()
      ..color = currentColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < currentPoints.length; i++) {
      final x = currentPoints.length == 1 ? width / 2 : i * xStep;
      final y = height - ((currentPoints[i] / maxY).clamp(0.0, 1.0) * height);
      canvas.drawCircle(Offset(x, y), 5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    return oldDelegate.currentPoints != currentPoints ||
        oldDelegate.previousPoints != previousPoints ||
        oldDelegate.labels != labels ||
        oldDelegate.currentColor != currentColor ||
        oldDelegate.previousColor != previousColor ||
        oldDelegate.maxY != maxY;
  }
}





