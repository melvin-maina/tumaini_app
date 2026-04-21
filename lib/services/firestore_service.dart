import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/service_request_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Users collection
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('users').doc(uid).update(data);
  }

  // Service Requests
  Future<void> createRequest(ServiceRequest request) async {
    await _firestore.collection('requests').doc(request.id).set(request.toMap());
  }

  Stream<List<ServiceRequest>> getRequestsForUser(String userId) {
    return _firestore
        .collection('requests')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => ServiceRequest.fromMap(doc.data(), doc.id))
        .toList());
  }

  Stream<List<ServiceRequest>> getNewRequestsForProviders() {
    return _firestore
        .collection('requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => ServiceRequest.fromMap(doc.data(), doc.id))
        .toList());
  }

  Stream<List<ServiceRequest>> getAssignedRequestsForProvider(String providerId) {
    return _firestore
        .collection('requests')
        .where('assignedProviderId', isEqualTo: providerId)
        .where('status', isNotEqualTo: 'completed')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => ServiceRequest.fromMap(doc.data(), doc.id))
        .toList());
  }

  Future<void> updateRequestStatus(String requestId, RequestStatus status,
      {String? assignedProviderId}) async {
    Map<String, dynamic> updateData = {
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (assignedProviderId != null) {
      updateData['assignedProviderId'] = assignedProviderId;
    }
    await _firestore.collection('requests').doc(requestId).update(updateData);
  }

  // Feedback
  Future<void> addFeedback(Map<String, dynamic> feedback) async {
    await _firestore.collection('feedback').add(feedback);
  }

  // Admin: Get users with limit (default 100 for better performance)
  Stream<List<Map<String, dynamic>>> getAllUsers({int limit = 100}) {
    return _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }
}