import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_system_message/flyer_chat_system_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:uuid/uuid.dart';

import 'app/theme/ora_theme.dart';
import 'features/chat/presentation/ora_chat_theme.dart';

/// Dev-only entrypoint: previews the Ora-themed ride chat without Firebase.
/// Run with `flutter run -t lib/main_chat_preview.dart -d web-server`.
void main() => runApp(const OraChatPreviewApp());

class OraChatPreviewApp extends StatelessWidget {
  const OraChatPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ora chat preview',
        theme: OraTheme.dark(),
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: const _ChatPreview(),
      );
}

class _ChatPreview extends StatefulWidget {
  const _ChatPreview();

  @override
  State<_ChatPreview> createState() => _ChatPreviewState();
}

class _ChatPreviewState extends State<_ChatPreview> {
  final _controller = InMemoryChatController(
    messages: [
      TextMessage(
        id: 'm1',
        authorId: 'driver',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 4)),
        text: 'Assalam o alaikum, I am on my way. White Civic, 5 min.',
      ),
      TextMessage(
        id: 'm2',
        authorId: 'me',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
        text: 'Great, I am standing outside the gate.',
      ),
      TextMessage(
        id: 'm3',
        authorId: 'driver',
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        text: 'Almost there — I can see the gate.',
      ),
    ],
  );
  final _uuid = const Uuid();

  final _users = const {
    'me': User(id: 'me', name: 'Hamza'),
    'driver': User(id: 'driver', name: 'Ali (Driver)'),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat'),
            Text('Driver', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: mui.Material(
        child: Chat(
        chatController: _controller,
        currentUserId: 'me',
        theme: OraChatTheme.dark(),
        resolveUser: (id) async => _users[id] ?? User(id: id),
        onMessageSend: (text) {
          _controller.insertMessage(
            TextMessage(
              id: _uuid.v4(),
              authorId: 'me',
              createdAt: DateTime.now().toUtc(),
              text: text,
            ),
          );
        },
        builders: Builders(
          textMessageBuilder:
              (
                context,
                message,
                index, {
                required bool isSentByMe,
                MessageGroupStatus? groupStatus,
              }) =>
                  FlyerChatTextMessage(message: message, index: index),
          systemMessageBuilder:
              (
                context,
                message,
                index, {
                required bool isSentByMe,
                MessageGroupStatus? groupStatus,
              }) =>
                  FlyerChatSystemMessage(message: message, index: index),
        ),
        ),
      ),
    );
  }
}
