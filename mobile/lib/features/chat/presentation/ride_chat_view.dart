import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flyer_chat_system_message/flyer_chat_system_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:material_ui/material_ui.dart' as mui;

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../auth/presentation/view_models/session_user_profile.dart';
import 'ora_chat_theme.dart';
import 'ride_chat_controller.dart';

/// Ride-scoped chat between passenger and driver, themed to match Ora.
///
/// Backed by RTDB `rideChats/{rideId}` — see [RtdbChatController].
class RideChatView extends ConsumerStatefulWidget {
  const RideChatView({
    required this.rideId,
    required this.otherPartyLabel,
    super.key,
  });

  final String rideId;

  /// Who the current user is talking to — shown in the app bar
  /// ('Driver' on the passenger side, 'Passenger' on the driver side).
  final String otherPartyLabel;

  @override
  ConsumerState<RideChatView> createState() => _RideChatViewState();
}

class _RideChatViewState extends ConsumerState<RideChatView> {
  late final RtdbChatController _controller;
  final _names = <String, String>{};
  var _sending = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(rideChatControllerProvider(widget.rideId));
    _controller.start();
  }

  String _displayName(String? raw) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isNotEmpty ? trimmed : 'You';
  }

  Future<void> _onMessageSend(String text) async {
    final profile = ref.read(sessionUserProfileProvider);
    if (profile == null || _sending) return;
    setState(() => _sending = true);
    try {
      await _controller.sendText(
        authorId: profile.uid,
        authorName: _displayName(profile.displayName),
        text: text,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message not sent — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<User?> _resolveUser(UserID id) async {
    final profile = ref.read(sessionUserProfileProvider);
    if (id == profile?.uid) {
      return User(
        id: id,
        name: _displayName(profile?.displayName),
      );
    }
    // Names are snapshotted onto each message — recover them from the
    // controller's current list rather than another backend lookup.
    for (final m in _controller.messages) {
      if (m.authorId == id) {
        final name = m.metadata?['authorName'];
        if (name is String && name.isNotEmpty) {
          return User(id: id, name: _names[id] = name);
        }
      }
    }
    return User(id: id, name: _names[id] ?? widget.otherPartyLabel);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(sessionUserProfileProvider)?.uid ?? '';

    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat',
              style: OraTypography.title(OraColors.textPrimary),
            ),
            Text(
              widget.otherPartyLabel,
              style: OraTypography.caption(OraColors.textSecondary),
            ),
          ],
        ),
      ),
      // flutter_chat_ui's composer resolves package:material_ui's Material
      // and localizations — provide them here scoped to this screen.
      body: Localizations.override(
        context: context,
        delegates: const [
          mui.DefaultMaterialLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: SafeArea(
          child: mui.Material(
            color: OraColors.canvas,
            child: Chat(
              chatController: _controller,
              currentUserId: uid,
              theme: OraChatTheme.dark(),
              resolveUser: _resolveUser,
              onMessageSend: _onMessageSend,
              builders: const Builders(
                textMessageBuilder: _textMessage,
                systemMessageBuilder: _systemMessage,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _textMessage(
    BuildContext context,
    TextMessage message,
    int index, {
    required bool isSentByMe,
    MessageGroupStatus? groupStatus,
  }) =>
      FlyerChatTextMessage(message: message, index: index);

  static Widget _systemMessage(
    BuildContext context,
    SystemMessage message,
    int index, {
    required bool isSentByMe,
    MessageGroupStatus? groupStatus,
  }) =>
      FlyerChatSystemMessage(message: message, index: index);
}
