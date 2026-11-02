import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'The assistant is not available yet. Agent 1 will be connected '
        'after the forecast backend is implemented.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
