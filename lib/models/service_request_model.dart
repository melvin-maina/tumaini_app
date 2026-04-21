import 'package:cloud_firestore/cloud_firestore.dart';

enum RequestStatus {
  pending,
  assigned,
  inProgress,
  completed,
  cancelled,
}

class ServiceRequest {
  final String id;
  final String userId;
  final String serviceType; // 'plumbing' or 'electrical'
  final String urgency;
  final String description;
  final String preferredDate;
  final String preferredTimeSlot;
  final RequestStatus status;
  final String? assignedProviderId;
  final String? location;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ServiceRequest({
    required this.id,
    required this.userId,
    required this.serviceType,
    required this.urgency,
    required this.description,
    required this.preferredDate,
    required this.preferredTimeSlot,
    required this.status,
    this.assignedProviderId,
    this.location,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'serviceType': serviceType,
      'urgency': urgency,
      'description': description,
      'preferredDate': preferredDate,
      'preferredTimeSlot': preferredTimeSlot,
      'status': status.name,
      'assignedProviderId': assignedProviderId,
      'location': location,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  factory ServiceRequest.fromMap(Map<String, dynamic> map, String id) {
    return ServiceRequest(
      id: id,
      userId: map['userId'] ?? '',
      serviceType: map['serviceType'] ?? '',
      urgency: map['urgency'] ?? 'medium',
      description: map['description'] ?? '',
      preferredDate: map['preferredDate'] ?? '',
      preferredTimeSlot: map['preferredTimeSlot'] ?? '',
      status: _stringToStatus(map['status'] ?? 'pending'),
      assignedProviderId: map['assignedProviderId'],
      location: map['location'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  static RequestStatus _stringToStatus(String status) {
    switch (status) {
      case 'pending':
        return RequestStatus.pending;
      case 'assigned':
        return RequestStatus.assigned;
      case 'inProgress':
        return RequestStatus.inProgress;
      case 'completed':
        return RequestStatus.completed;
      case 'cancelled':
        return RequestStatus.cancelled;
      default:
        return RequestStatus.pending;
    }
  }
}
