import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import 'chat_look.dart';
import 'chat_look_paint.dart';
import 'chat_view_prefs.dart';
import 'kantor_feed.dart';

/// Messenger palette is opt-in; the original widgets still render Default.
class ChatStyleColors {
  const ChatStyleColors(this.style, this.dark);
  final ChatStyle style;
  final bool dark;
  bool get wa => style == ChatStyle.whatsapp;
  Color get wall => dark
      ? const Color(0xFF111E24)
      : wa
      ? const Color(0xFFEFEAE2)
      : const Color(0xFFDCE8E4);
  Color get surface => dark ? const Color(0xFF203139) : Colors.white;
  Color get mine => dark
      ? const Color(0xFF174D43)
      : wa
      ? const Color(0xFFD9FDD3)
      : const Color(0xFFE1F5EF);
  Color get ink => dark ? const Color(0xFFE8F3EE) : const Color(0xFF0F1F1C);
  Color get muted => dark ? const Color(0xFFA7BDB7) : const Color(0xFF5B6E6A);
  Color get accent => dark ? const Color(0xFF7DD9C6) : const Color(0xFF0F766E);
  Color get header => wa ? const Color(0xFF0B5D52) : surface;
  Color get headerInk => wa ? Colors.white : ink;
  Color get send => wa ? const Color(0xFF1FA855) : const Color(0xFF0F766E);
  Color get tick => wa ? const Color(0xFF53BDEB) : accent;
  Color get tool => dark
      ? const Color(0xFF343D2C)
      : wa
      ? const Color(0xFFFFF5C4)
      : const Color(0xFFF4F8F7);
  static ChatStyleColors of(BuildContext context, ChatStyle style) =>
      ChatStyleColors(style, Theme.of(context).brightness == Brightness.dark);
}

class MessengerWallpaper extends StatelessWidget {
  const MessengerWallpaper({
    super.key,
    required this.view,
    required this.child,
  });
  final ChatViewPrefs view;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!view.useStyleWall) {
      return ChatWallpaper(
        wall: view.wall,
        photo: view.wallPhoto,
        child: child,
      );
    }
    final c = ChatStyleColors.of(context, view.style);
    return CustomPaint(
      painter: ChatWallPainter(
        wall: c.wa ? ChatWall.titik : ChatWall.polos,
        bg: c.wall,
        ink: c.muted,
        alt: c.wall,
        dark: c.dark,
      ),
      child: child,
    );
  }
}

/// Shared with chat and widget tests. Timestamp comes from the transcript;
/// checks mean present in the agent transcript, not a fabricated read receipt.
class MessengerBubble extends StatelessWidget {
  const MessengerBubble({
    super.key,
    required this.view,
    required this.mine,
    required this.child,
    this.time = '',
  });
  final ChatViewPrefs view;
  final bool mine;
  final Widget child;
  final String time;
  @override
  Widget build(BuildContext context) {
    final c = ChatStyleColors.of(context, view.style);
    final content = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      runSpacing: 2,
      children: [
        DefaultTextStyle.merge(
          style: TextStyle(color: c.ink),
          child: child,
        ),
        if (view.showTime && time.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                time,
                style: GhinaType.caption.copyWith(
                  color: mine && !view.useStyleMe
                      ? view.me.ink.withValues(alpha: .8)
                      : c.muted,
                  fontSize: 11,
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 3),
                Semantics(
                  label: 'Tercatat di percakapan agent',
                  child: Icon(Icons.done_all_rounded, size: 16, color: c.tick),
                ),
              ],
            ],
          ),
      ],
    );
    if (!view.useStyleBubble) {
      return ThemedBubble(
        fillColor: mine ? (view.useStyleMe ? c.mine : null) : c.surface,
        shape: view.bubble,
        mine: mine,
        me: view.me,
        peek: view.peek,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: content,
      );
    }
    final radius = c.wa
        ? BorderRadius.only(
            topLeft: Radius.circular(mine ? 8 : 0),
            topRight: Radius.circular(mine ? 0 : 8),
            bottomLeft: const Radius.circular(8),
            bottomRight: const Radius.circular(8),
          )
        : BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          key: ValueKey('messenger-bubble-${view.style.name}-$mine'),
          padding: const EdgeInsets.fromLTRB(11, 8, 11, 5),
          decoration: BoxDecoration(
            color: mine ? (view.useStyleMe ? c.mine : view.me.fill) : c.surface,
            gradient: mine && !view.useStyleMe ? view.me.gradient : null,
            borderRadius: radius,
          ),
          child: content,
        ),
        if (mine && view.peek != ChatPeek.none)
          Positioned(right: 10, top: -18, child: ChatPeekSprite(view.peek)),
      ],
    );
  }
}

class MessengerDay extends StatelessWidget {
  const MessengerDay({super.key, required this.at});
  final DateTime at;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = DateUtils.isSameDay(at, now)
        ? 'Hari ini'
        : DateUtils.isSameDay(at, now.subtract(const Duration(days: 1)))
        ? 'Kemarin'
        : '${at.day}/${at.month}/${at.year}';
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF526963).withValues(alpha: .65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: GhinaType.caption.copyWith(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class MessengerBoardCard extends StatelessWidget {
  const MessengerBoardCard({
    super.key,
    required this.card,
    required this.style,
    this.onTap,
  });
  final Json card;
  final ChatStyle style;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = ChatStyleColors.of(context, style);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.view_kanban_outlined, color: c.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KARTU AKTIF',
                      style: GhinaType.caption.copyWith(
                        color: c.muted,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${card['title']}',
                      style: GhinaType.body.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: c.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
