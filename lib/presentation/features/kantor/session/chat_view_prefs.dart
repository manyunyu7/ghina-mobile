import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_markdown.dart';

const chatScaleMin = 0.8;
const chatScaleMax = 1.6;
const codeScaleMin = 0.8;
const codeScaleMax = 1.4;
const _scaleStep = 0.05;

/// The system text scale times ours never goes past this, so a large system
/// font plus a large chat font cannot blow the layout up.
const _totalScaleCap = 2.2;

enum ChatDensity {
  tight('Rapat', 0.6),
  normal('Normal', 1),
  loose('Lega', 1.5);

  const ChatDensity(this.label, this.factor);
  final String label;
  final double factor;
}

enum ChatToolMode {
  all('Semua'),
  compact('Ringkas'),
  hidden('Sembunyikan');

  const ChatToolMode(this.label);
  final String label;
}

enum ChatLineHeight {
  tight('Rapat', 1.25),
  normal('Normal', 1.45),
  loose('Lega', 1.7);

  const ChatLineHeight(this.label, this.value);
  final String label;
  final double value;
}

/// Share of the screen width a bubble may take.
enum ChatBubbleWidth {
  narrow('Sempit', 0.74),
  normal('Normal', 0.86),
  wide('Lebar', 0.96);

  const ChatBubbleWidth(this.label, this.fraction);
  final String label;
  final double fraction;
}

/// How the Kantor chat looks on this phone.
@immutable
class ChatViewPrefs {
  const ChatViewPrefs({
    this.scale = 1,
    this.density = ChatDensity.normal,
    this.tools = ChatToolMode.compact,
    this.bubbleWidth = ChatBubbleWidth.normal,
    this.flatClaude = false,
    this.codeScale = 1,
    this.lineHeight = ChatLineHeight.normal,
    this.showTime = true,
    this.wrapCode = false,
    this.bigImages = true,
  });

  final double scale;
  final ChatDensity density;

  /// [ChatToolMode.compact] folds long runs of tool calls (the original look),
  /// [ChatToolMode.all] never folds, [ChatToolMode.hidden] drops them.
  final ChatToolMode tools;
  final ChatBubbleWidth bubbleWidth;

  /// Claude's replies as full-width text, like a document, without a bubble.
  final bool flatClaude;

  /// Code size relative to the chat text (inline code, code blocks, tools).
  final double codeScale;
  final ChatLineHeight lineHeight;
  final bool showTime;

  /// Code blocks wrap instead of scrolling sideways.
  final bool wrapCode;

  /// Inline images (generated / sent) large, else small thumbnails.
  final bool bigImages;

  ChatViewPrefs copyWith({
    double? scale,
    ChatDensity? density,
    ChatToolMode? tools,
    ChatBubbleWidth? bubbleWidth,
    bool? flatClaude,
    double? codeScale,
    ChatLineHeight? lineHeight,
    bool? showTime,
    bool? wrapCode,
    bool? bigImages,
  }) => ChatViewPrefs(
    scale: scale ?? this.scale,
    density: density ?? this.density,
    tools: tools ?? this.tools,
    bubbleWidth: bubbleWidth ?? this.bubbleWidth,
    flatClaude: flatClaude ?? this.flatClaude,
    codeScale: codeScale ?? this.codeScale,
    lineHeight: lineHeight ?? this.lineHeight,
    showTime: showTime ?? this.showTime,
    wrapCode: wrapCode ?? this.wrapCode,
    bigImages: bigImages ?? this.bigImages,
  );

  Map<String, dynamic> toJson() => {
    'scale': scale,
    'density': density.name,
    'tools': tools.name,
    'bubbleWidth': bubbleWidth.name,
    'flatClaude': flatClaude,
    'codeScale': codeScale,
    'lineHeight': lineHeight.name,
    'showTime': showTime,
    'wrapCode': wrapCode,
    'bigImages': bigImages,
  };

  factory ChatViewPrefs.fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> all, Object? v, T fallback) =>
        all.where((e) => e.name == v).firstOrNull ?? fallback;
    final s = j['scale'];
    final cs = j['codeScale'];
    return ChatViewPrefs(
      scale: s is num ? clampChatScale(s.toDouble()) : 1,
      density: pick(ChatDensity.values, j['density'], ChatDensity.normal),
      tools: pick(ChatToolMode.values, j['tools'], ChatToolMode.compact),
      bubbleWidth: pick(
        ChatBubbleWidth.values,
        j['bubbleWidth'],
        ChatBubbleWidth.normal,
      ),
      flatClaude: j['flatClaude'] == true,
      codeScale: cs is num
          ? cs.toDouble().clamp(codeScaleMin, codeScaleMax)
          : 1,
      lineHeight: pick(
        ChatLineHeight.values,
        j['lineHeight'],
        ChatLineHeight.normal,
      ),
      showTime: j['showTime'] != false,
      wrapCode: j['wrapCode'] == true,
      bigImages: j['bigImages'] != false,
    );
  }
}

double clampChatScale(double v) => v.clamp(chatScaleMin, chatScaleMax);

double _snap(double v) => (clampChatScale(v) / _scaleStep).round() * _scaleStep;

const _prefsKey = 'kantor.chat.view';

/// Chat look, remembered on this phone. Changes show up at once.
final chatViewPrefsProvider =
    NotifierProvider<ChatViewPrefsNotifier, ChatViewPrefs>(
      ChatViewPrefsNotifier.new,
    );

class ChatViewPrefsNotifier extends Notifier<ChatViewPrefs> {
  bool _touched = false;

  @override
  ChatViewPrefs build() {
    _load();
    return const ChatViewPrefs();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null || _touched) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) state = ChatViewPrefs.fromJson(j);
    } catch (_) {
      // defaults are fine
    }
  }

  void _save() {
    SharedPreferences.getInstance()
        .then((p) => p.setString(_prefsKey, jsonEncode(state.toJson())))
        .catchError((_) => false);
  }

  void update(ChatViewPrefs Function(ChatViewPrefs p) fn) {
    _touched = true;
    state = fn(state);
    _save();
  }

  /// [save] false while a pinch is still going: only the end writes to disk.
  void setScale(double v, {bool save = true}) {
    _touched = true;
    state = state.copyWith(scale: clampChatScale(v));
    if (save) _save();
  }

  void commit() => _save();

  void reset() => update((_) => const ChatViewPrefs());
}

/// Multiplies the surrounding text scale (system accessibility setting) by
/// [factor], capped so the product stays sane.
class ChatTextScaler extends TextScaler {
  const ChatTextScaler(this.inner, this.factor);

  final TextScaler inner;
  final double factor;

  @override
  double scale(double fontSize) {
    final v = inner.scale(fontSize) * factor;
    final cap = fontSize * _totalScaleCap;
    return v > cap ? cap : v;
  }

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is ChatTextScaler && other.inner == inner && other.factor == factor;

  @override
  int get hashCode => Object.hash(inner, factor);
}

/// Applies [ChatViewPrefs.scale] to everything below it.
class ChatScope extends StatelessWidget {
  const ChatScope({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: ChatTextScaler(mq.textScaler, scale)),
      child: child,
    );
  }
}

Future<void> showChatViewSheet(BuildContext context) =>
    showChunkyBottomSheet<void>(
      context,
      title: 'Tampilan chat',
      builder: (_) => const ChatViewSheet(),
    );

class ChatViewSheet extends ConsumerWidget {
  const ChatViewSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final p = ref.watch(chatViewPrefsProvider);
    final n = ref.read(chatViewPrefsProvider.notifier);

    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.xs),
      child: Text(
        t,
        style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
      ),
    );

    Widget seg<T>(
      String title,
      List<(T, String)> items,
      T value,
      ValueChanged<T> on,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(title),
          ChunkySegmented<T>(
            height: 44,
            segments: [
              for (final i in items) ChunkySegment(value: i.$1, label: i.$2),
            ],
            value: value,
            onChanged: on,
          ),
        ],
      ),
    );

    Widget toggle(
      String key,
      String title,
      String sub,
      bool value,
      ValueChanged<bool> on,
    ) => ChunkyTile(
      key: ValueKey(key),
      title: title,
      subtitle: sub,
      showChevron: false,
      trailing: Switch(value: value, onChanged: on),
      onTap: () => on(!value),
    );

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('Ukuran teks (${(p.scale * 100).round()}%)'),
          Row(
            children: [
              Text('A', style: GhinaType.bodyS.copyWith(color: g.textMuted)),
              Expanded(
                child: Slider(
                  key: const ValueKey('chat-scale'),
                  value: p.scale,
                  min: chatScaleMin,
                  max: chatScaleMax,
                  divisions: 16,
                  onChanged: (v) => n.setScale(_snap(v)),
                ),
              ),
              Text('A', style: GhinaType.h3.copyWith(color: g.textMuted)),
            ],
          ),
          // preview: same scaler the chat gets
          ChatScope(
            scale: p.scale,
            child: Container(
              key: const ValueKey('chat-preview'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: GhinaSpace.md),
              padding: EdgeInsets.symmetric(
                horizontal: GhinaSpace.md,
                vertical: GhinaSpace.sm * p.density.factor,
              ),
              decoration: BoxDecoration(
                color: g.surface,
                borderRadius: GhinaRadii.rLg,
                border: Border.all(color: g.border, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KantorMarkdown(
                    'Contoh balasan Claude. Teks ini mengikuti ukuran dan '
                    'jarak baris yang kamu pilih, termasuk `kode`.\n\n'
                    '```\nflutter analyze lib/presentation/features/kantor/session --no-fatal-infos\n```',
                    lineHeight: p.lineHeight.value,
                    codeScale: p.codeScale,
                    wrapCode: p.wrapCode,
                  ),
                  if (p.showTime)
                    Text(
                      '09:41',
                      style: GhinaType.caption.copyWith(color: g.textMuted),
                    ),
                ],
              ),
            ),
          ),
          label('Ukuran kode (${(p.codeScale * 100).round()}%)'),
          Slider(
            key: const ValueKey('chat-code-scale'),
            value: p.codeScale,
            min: codeScaleMin,
            max: codeScaleMax,
            divisions: 12,
            onChanged: (v) => n.update(
              (x) => x.copyWith(codeScale: (v * 20).round() / 20),
            ),
          ),
          seg<ChatLineHeight>(
            'Jarak baris',
            [for (final d in ChatLineHeight.values) (d, d.label)],
            p.lineHeight,
            (v) => n.update((x) => x.copyWith(lineHeight: v)),
          ),
          seg<ChatDensity>(
            'Kerapatan',
            [for (final d in ChatDensity.values) (d, d.label)],
            p.density,
            (v) => n.update((x) => x.copyWith(density: v)),
          ),
          seg<ChatToolMode>(
            'Kartu tool',
            [for (final d in ChatToolMode.values) (d, d.label)],
            p.tools,
            (v) => n.update((x) => x.copyWith(tools: v)),
          ),
          seg<ChatBubbleWidth>(
            'Lebar gelembung',
            [for (final d in ChatBubbleWidth.values) (d, d.label)],
            p.bubbleWidth,
            (v) => n.update((x) => x.copyWith(bubbleWidth: v)),
          ),
          ChunkyTile(
            key: const ValueKey('chat-flat'),
            title: 'Balasan Claude tanpa gelembung',
            subtitle: 'Penuh lebar, seperti dokumen',
            showChevron: false,
            trailing: Switch(
              value: p.flatClaude,
              onChanged: (v) => n.update((x) => x.copyWith(flatClaude: v)),
            ),
            onTap: () => n.update((x) => x.copyWith(flatClaude: !x.flatClaude)),
          ),
          toggle(
            'chat-time',
            'Tampilkan waktu',
            'Jam di bawah tiap pesan',
            p.showTime,
            (v) => n.update((x) => x.copyWith(showTime: v)),
          ),
          toggle(
            'chat-wrap',
            'Bungkus baris kode',
            'Mati: blok kode digeser ke samping',
            p.wrapCode,
            (v) => n.update((x) => x.copyWith(wrapCode: v)),
          ),
          toggle(
            'chat-big-img',
            'Gambar besar',
            'Mati: gambar tampil sebagai thumbnail kecil',
            p.bigImages,
            (v) => n.update((x) => x.copyWith(bigImages: v)),
          ),
          GhinaSpace.gapSm,
          Text(
            'Cubit dua jari di daftar chat juga mengubah ukuran teks. '
            'Blok kode ikut membesar.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
          GhinaSpace.gapMd,
          ChunkyButton(
            label: 'Kembalikan bawaan',
            variant: ChunkyButtonVariant.outline,
            onPressed: n.reset,
          ),
        ],
      ),
    );
  }
}
