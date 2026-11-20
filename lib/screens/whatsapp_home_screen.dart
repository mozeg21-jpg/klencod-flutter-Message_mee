import 'package:flutter/material.dart';
import 'chats_list_screen.dart';
import 'community_features_screen.dart';
import 'contacts_screen.dart';
import 'calls_list_screen.dart';

/// الواجهة الرئيسية للمراسلة: لا تعرض شاشة مجتمع، بل أقسام واتساب الأساسية.
class WhatsappHomeScreen extends StatefulWidget {
  const WhatsappHomeScreen({super.key});

  @override
  State<WhatsappHomeScreen> createState() => _WhatsappHomeScreenState();
}

class _WhatsappHomeScreenState extends State<WhatsappHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ChatsListScreen(),
      const MessengerFeaturesScreen(),
      const ContactsScreen(),
      const CallsListScreen(),
    ];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(.08, 0), end: Offset.zero).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat), label: 'الدردشات'),
          NavigationDestination(icon: Icon(Icons.camera_alt_outlined), selectedIcon: Icon(Icons.camera_alt), label: 'الحالة'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'جهات الاتصال'),
          NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: 'المكالمات'),
        ],
      ),
    );
  }
}
