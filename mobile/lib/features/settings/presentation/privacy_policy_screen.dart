import 'package:flutter/material.dart';

/// Static privacy summary highlighting Zexo's location-fuzzing guarantees.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Text(
            'Your location, blurred by design',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Text(
            'Zexo never stores your exact GPS position. Before any coordinate is '
            'saved, it is offset by roughly 150 metres in a random direction. '
            'Only this blurred location is used for discovery, and only blurred '
            'positions are ever shown to other people.',
          ),
          SizedBox(height: 20),
          Text(
            'Ephemeral by default',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Messages disappear after 24 hours, or sooner if you move out of '
            'range of the person you are chatting with.',
          ),
          SizedBox(height: 20),
          Text(
            'Your data, your control',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'You can go invisible at any time without losing your account, and '
            'deleting your account erases your profile, location history, chats, '
            'and RSVPs within 24 hours.',
          ),
        ],
      ),
    );
  }
}
