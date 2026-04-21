class UserModel {
  final String uid;
  final String fullName;
  final String phone;
  final String email;
  final String role; // 'resident', 'provider', 'admin'
  final String? unit; // only for residents
  final String? phase; // only for residents
  final bool isAvailable; // only for providers
  final List<String>? serviceAreas; // only for providers

  UserModel({
    required this.uid,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.role,
    this.unit,
    this.phase,
    this.isAvailable = false,
    this.serviceAreas,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'role': role,
      'unit': unit,
      'phase': phase,
      'isAvailable': isAvailable,
      'serviceAreas': serviceAreas,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      fullName: map['fullName'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'resident',
      unit: map['unit'],
      phase: map['phase'],
      isAvailable: map['isAvailable'] ?? false,
      serviceAreas: map['serviceAreas'] != null
          ? List<String>.from(map['serviceAreas'])
          : null,
    );
  }
}