import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class GroupDetailsScreen extends StatelessWidget {
  final String groupId;
  const GroupDetailsScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الجروب')),
        body: FutureBuilder<DataSnapshot>(
          future: FirebaseDatabase.instance.ref('groups/$groupId').get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final value = snapshot.data?.value;
            final group = value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
            final members = group['memberNames'];
            final names = members is Map ? members.values.map((e) => e.toString()).toList() : <String>[];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CircleAvatar(radius: 42, child: Text((group['name']?.toString() ?? 'ج').characters.first)),
                const SizedBox(height: 12),
                Center(child: Text(group['name']?.toString() ?? 'جروب', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                const SizedBox(height: 24),
                Text('الأعضاء (${names.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ...names.map((name) => ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(name))),
              ],
            );
          },
        ),
      );
}
