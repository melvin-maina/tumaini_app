import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({
    super.key,
    this.iconColor,
  });

  final Color? iconColor;

  Future<String> _currentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return (doc.data()?['role'] ?? '').toString().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      return IconButton(
        icon: const Icon(Icons.notifications_outlined),
        onPressed: () => context.push('/notifications'),
        color: iconColor,
      );
    }

    return FutureBuilder<String>(
      future: _currentUserRole(),
      builder: (context, roleSnapshot) {
        final role = roleSnapshot.data ?? '';
        final stream = role == 'admin'
            ? FirebaseFirestore.instance.collection('notifications').snapshots()
            : FirebaseFirestore.instance
                .collection('notifications')
                .where('userId', isEqualTo: userId)
                .snapshots();

        return StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            final unreadCount = snapshot.data?.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final target = (data['userId'] ?? '').toString();
                  final audience = (data['audience'] ?? '').toString().toLowerCase();
                  final isVisibleToAdmin =
                      role == 'admin' &&
                      (target == userId || target == 'admin' || audience == 'admin');
                  final isVisibleToUser = role != 'admin' && target == userId;
                  return data['isRead'] != true && (isVisibleToAdmin || isVisibleToUser);
                }).length ??
                0;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Notifications',
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => context.push('/notifications'),
                  color: iconColor,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
