import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';
import 'admin_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final AuthService _authService = AuthService();
  int _unreadChats = 0;
  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _screens.addAll([
      const HomeScreen(),
      const SearchScreen(),
      const ChatListScreen(),
      const ProfileScreen(),
    ]);
    if (_isAdmin) {
      _screens.add(const AdminScreen());
    }
    _listenToUnreadChats();
  }

  void _listenToUnreadChats() {
    final user = _authService.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        int unread = 0;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final lastSenderId = data['lastMessageSenderId'] as String?;
          final readBy = List<String>.from(data['readBy'] ?? []);
          // Count as unread if last message was not sent by current user
          // and current user hasn't read it
          if (lastSenderId != null &&
              lastSenderId != user.uid &&
              !readBy.contains(user.uid)) {
            unread++;
          }
        }
        setState(() => _unreadChats = unread);
      }
    });
  }

  bool get _isAdmin {
    return _authService.currentUser?.email == 'theprimestarventures@gmail.com';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? Colors.white : AppTheme.backgroundDark;

    final tabs = [
      _TabItem(icon: Icons.home_outlined, activeIcon: Icons.home, index: 0),
      _TabItem(icon: Icons.search_outlined, activeIcon: Icons.search, index: 1),
      _TabItem(icon: Icons.chat_bubble_outlined, activeIcon: Icons.chat_bubble, index: 2, badge: _unreadChats),
      _TabItem(icon: Icons.person_outlined, activeIcon: Icons.person, index: 3),
      if (_isAdmin)
        _TabItem(icon: Icons.shield_outlined, activeIcon: Icons.shield, index: 4),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withAlpha(13)
                  : Colors.black.withAlpha(13),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: tabs.map((tab) {
                final isActive = _currentIndex == tab.index;
                return GestureDetector(
                  onTap: () {
                    if (_currentIndex != tab.index) {
                      HapticFeedback.selectionClick();
                      setState(() => _currentIndex = tab.index);
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: _buildTabIcon(tab, isActive, activeColor),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabIcon(_TabItem tab, bool isActive, Color activeColor) {
    return Stack(
      children: [
        Icon(
          isActive ? tab.activeIcon : tab.icon,
          size: 26,
          color: isActive ? activeColor : const Color(0xFF6B7280),
        ),
        if (tab.badge != null && tab.badge! > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.royalBlue,
              ),
              child: Text(
                tab.badge! > 99 ? '99+' : '${tab.badge}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final int index;
  final int? badge;

  _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.index,
    this.badge,
  });
}
