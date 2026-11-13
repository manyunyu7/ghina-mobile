import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/design_system.dart';
import '../widgets/kantor_markdown.dart';
import 'chat_look.dart';
import 'chat_look_paint.dart';
import 'terminal_prefs.dart';
import 'terminal_themes.dart';

const chatScaleMin = 0.8;
const chatScaleMax = 1.6;
const codeScaleMin = 0.8;
const codeScaleMax = 1.4;
const _scaleStep = 0.05;

/// The system text scale times ours never goes past this, so a large system
/// font plus a large chat font cannot blow the layout up.
const _totalScaleCap = 2.2;

enum ChatStyle {
  bawaan('Default'),
  telegram('Telegram'),
  whatsapp('WhatsApp');

  const ChatStyle(this.label);
  final String label;
}

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
    this.style = ChatStyle.bawaan,
    this.customWall = false,
    this.customBubble = false,
    this.customMe = false,
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
    this.wall = ChatWall.polos,
    this.wallPhoto,
    this.bubble = ChatBubbleShape.kantor,
    this.me = ChatMeColor.biru,
    this.peek = ChatPeek.none,
  });

  final double scale;
  final ChatStyle style;
  final bool customWall, customBubble, customMe;
  bool get messenger => style != ChatStyle.bawaan;
  bool get useStyleWall => messenger && !customWall && wall == ChatWall.polos;
  bool get useStyleBubble =>
      messenger && !customBubble && bubble == ChatBubbleShape.kantor;
  bool get useStyleMe => messenger && !customMe && me == ChatMeColor.biru;
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

  final ChatWall wall;

  /// Path of the owner's own wallpaper picture (used when [wall] is
  /// [ChatWall.foto]); null until one was chosen.
  final String? wallPhoto;
  final ChatBubbleShape bubble;
  final ChatMeColor me;
  final ChatPeek peek;

  /// True when something is painted behind the chat, so loose text and the
  /// bottom bar need a light backing to stay readable.
  bool get hasWall => useStyleWall || wall != ChatWall.polos;

  ChatViewPrefs copyWith({
    ChatStyle? style,
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
    ChatWall? wall,
    String? wallPhoto,
    ChatBubbleShape? bubble,
    ChatMeColor? me,
    ChatPeek? peek,
  }) => ChatViewPrefs(
    style: style ?? this.style,
    customWall: customWall || wall != null,
    customBubble: customBubble || bubble != null,
    customMe: customMe || me != null,
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
    wall: wall ?? this.wall,
    wallPhoto: wallPhoto ?? this.wallPhoto,
    bubble: bubble ?? this.bubble,
    me: me ?? this.me,
    peek: peek ?? this.peek,
  );

  Map<String, dynamic> toJson() => {
    'style': style.name,
    'customWall': customWall,
    'customBubble': customBubble,
    'customMe': customMe,
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
    'wall': wall.name,
    'wallPhoto': wallPhoto,
    'bubble': bubble.name,
    'me': me.name,
    'peek': peek.name,
  };

  factory ChatViewPrefs.fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> all, Object? v, T fallback) =>
        all.where((e) => e.name == v).firstOrNull ?? fallback;
    final s = j['scale'];
    final cs = j['codeScale'];
    return ChatViewPrefs(
      style: pick(ChatStyle.values, j['style'], ChatStyle.bawaan),
      customWall: j['customWall'] == true,
      customBubble: j['customBubble'] == true,
      customMe: j['customMe'] == true,
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
      wall: pick(ChatWall.values, j['wall'], ChatWall.polos),
      wallPhoto: j['wallPhoto'] is String ? j['wallPhoto'] as String : null,
      bubble: pick(ChatBubbleShape.values, j['bubble'], ChatBubbleShape.kantor),
      me: pick(ChatMeColor.values, j['me'], ChatMeColor.biru),
      peek: pick(ChatPeek.values, j['peek'], ChatPeek.none),
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

  /// Back to the defaults; the saved wallpaper picture is deleted too.
  void reset() {
    final old = state.wallPhoto;
    update((_) => const ChatViewPrefs());
    if (old != null) {
      File(old).delete().then((_) {}, onError: (_) {});
    }
  }

  /// Makes [picked] the wallpaper: a shrunk copy (long side 1600 px) is kept
  /// in the app's own folder, on this phone only. Returns false when the
  /// picture could not be read.
  Future<bool> setWallPhoto(File picked) async {
    try {
      final dir = await ref.read(chatWallDirProvider);
      final target = p.join(
        dir.path,
        'wall_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      File? saved;
      try {
        final res = await FlutterImageCompress.compressAndGetFile(
          picked.path,
          target,
          minWidth: 1600,
          minHeight: 1600,
          quality: 82,
        );
        if (res != null) saved = File(res.path);
      } catch (_) {
        // no compressor here (tests, desktop): plain copy below
      }
      saved ??= await picked.copy(target);
      final old = state.wallPhoto;
      update((x) => x.copyWith(wall: ChatWall.foto, wallPhoto: saved!.path));
      if (old != null && old != saved.path) {
        File(old).delete().then((_) {}, onError: (_) {});
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Where the wallpaper picture is kept. Tests override.
final chatWallDirProvider = Provider<Future<Directory>>((ref) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'kantor_wall'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
});

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

/// Which part of the look a settings sheet shows: the open tab decides
/// (Chat -> chat only, Terminal -> terminal only); both from Settings.
enum ViewSheetScope {
  chat('Tampilan chat'),
  terminal('Tampilan terminal'),
  both('Tampilan');

  const ViewSheetScope(this.title);
  final String title;
}

Future<void> showChatViewSheet(
  BuildContext context, {
  ViewSheetScope scope = ViewSheetScope.chat,
}) => showChunkyBottomSheet<void>(
  context,
  title: scope.title,
  builder: (_) => ChatViewSheet(scope: scope),
);

class ChatViewSheet extends ConsumerWidget {
  const ChatViewSheet({super.key, this.scope = ViewSheetScope.chat});

  final ViewSheetScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final p = ref.watch(chatViewPrefsProvider);
    final n = ref.read(chatViewPrefsProvider.notifier);
    final showChat = scope != ViewSheetScope.terminal;
    final showTerm = scope != ViewSheetScope.chat;

    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.xs),
      child: Text(
        t,
        style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
      ),
    );

    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.sm),
      child: Text(t, style: GhinaType.h3.copyWith(color: g.textPrimary)),
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

    final chat = _ChatSections(
      prefs: p,
      notifier: n,
      label: label,
      seg: seg,
      toggle: toggle,
    );

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scope == ViewSheetScope.both) heading('Chat'),
          if (showChat) ...chat.build(context),
          if (scope == ViewSheetScope.both) ...[
            GhinaSpace.gapMd,
            heading('Terminal'),
          ],
          if (showTerm) const TerminalViewSection(),
          if (showChat) ...[
            GhinaSpace.gapMd,
            ChunkyButton(
              key: const ValueKey('chat-reset'),
              label: 'Kembalikan bawaan',
              variant: ChunkyButtonVariant.outline,
              onPressed: n.reset,
            ),
          ],
        ],
      ),
    );
  }
}

/// The Chat part of the sheet: the original text/layout options, then the
/// wallpaper, bubble shape, own color and mascot.
class _ChatSections {
  _ChatSections({
    required this.prefs,
    required this.notifier,
    required this.label,
    required this.seg,
    required this.toggle,
  });

  final ChatViewPrefs prefs;
  final ChatViewPrefsNotifier notifier;
  final Widget Function(String) label;
  final Widget Function<T>(String, List<(T, String)>, T, ValueChanged<T>) seg;
  final Widget Function(String, String, String, bool, ValueChanged<bool>)
  toggle;

  List<Widget> build(BuildContext context) {
    final g = context.ghina;
    final p = prefs;
    final n = notifier;
    return [
      seg<ChatStyle>(
        'Gaya',
        [for (final style in ChatStyle.values) (style, style.label)],
        p.style,
        (style) => n.update((p) => p.copyWith(style: style)),
      ),
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
        onChanged: (v) =>
            n.update((x) => x.copyWith(codeScale: (v * 20).round() / 20)),
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
      label('Wallpaper'),
      _WallPicker(prefs: p, notifier: n),
      GhinaSpace.gapMd,
      label('Gelembung'),
      _BubblePicker(prefs: p, notifier: n),
      GhinaSpace.gapMd,
      label('Warna pesanmu'),
      _ColorPicker(prefs: p, notifier: n),
      GhinaSpace.gapMd,
      label('Maskot di pesanmu'),
      _PeekPicker(prefs: p, notifier: n),
    ];
  }
}

/// Picks the wallpaper picture from the gallery. Tests override.
final chatWallPickerProvider = Provider<Future<File?> Function()>(
  (ref) => () async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    return x == null ? null : File(x.path);
  },
);

const _tileGap = 8.0;

/// A tappable option tile with a selected ring, used by every picker below.
class _PickTile extends StatelessWidget {
  const _PickTile({
    super.key,
    required this.selected,
    required this.onTap,
    required this.width,
    required this.child,
    required this.label,
  });

  final bool selected;
  final VoidCallback onTap;
  final double width;
  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Material(
          color: g.surface,
          shape: RoundedRectangleBorder(
            borderRadius: GhinaRadii.rMd,
            side: BorderSide(
              color: selected ? g.highlight.base : g.border,
              width: 2,
            ),
          ),
          child: InkWell(
            borderRadius: GhinaRadii.rMd,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  child,
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.caption.copyWith(
                      color: selected ? g.textPrimary : g.textSecondary,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WallPicker extends ConsumerWidget {
  const _WallPicker({required this.prefs, required this.notifier});
  final ChatViewPrefs prefs;
  final ChatViewPrefsNotifier notifier;

  Future<void> _photo(BuildContext context, WidgetRef ref) async {
    final picked = await ref.read(chatWallPickerProvider)();
    if (picked == null) return;
    final ok = await notifier.setWallPhoto(picked);
    if (!ok && context.mounted) {
      showToastBadge(
        context,
        message: 'Foto tidak bisa dibuka.',
        icon: Icons.error_outline_rounded,
        color: GhinaColors.red,
        tag: 'kantor-wall',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    return Wrap(
      spacing: _tileGap,
      runSpacing: _tileGap,
      children: [
        for (final w in ChatWall.values)
          _PickTile(
            key: ValueKey('wall-${w.name}'),
            width: 92,
            selected: prefs.wall == w,
            label: w.label,
            onTap: w == ChatWall.foto
                ? () => _photo(context, ref)
                : () => notifier.update((x) => x.copyWith(wall: w)),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ChatWallSwatch(
                  wall: w,
                  photo: prefs.wallPhoto,
                  width: 80,
                  height: 40,
                ),
                if (w == ChatWall.foto && prefs.wallPhoto == null)
                  Icon(Icons.add_photo_alternate_rounded, color: g.textMuted),
              ],
            ),
          ),
      ],
    );
  }
}

class _BubblePicker extends StatelessWidget {
  const _BubblePicker({required this.prefs, required this.notifier});
  final ChatViewPrefs prefs;
  final ChatViewPrefsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    Widget mini(ChatBubbleShape s, bool mine) => ThemedBubble(
      shape: s,
      mine: mine,
      me: prefs.me,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: const SizedBox(width: 26, height: 6),
    );
    return Wrap(
      spacing: _tileGap,
      runSpacing: _tileGap,
      children: [
        for (final s in ChatBubbleShape.values)
          _PickTile(
            key: ValueKey('bubble-${s.name}'),
            width: 92,
            selected: prefs.bubble == s,
            label: s.label,
            onTap: () => notifier.update((x) => x.copyWith(bubble: s)),
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: mini(s, false),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: mini(s, true),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.prefs, required this.notifier});
  final ChatViewPrefs prefs;
  final ChatViewPrefsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Wrap(
      spacing: _tileGap,
      runSpacing: _tileGap,
      children: [
        for (final c in ChatMeColor.values)
          Semantics(
            button: true,
            selected: prefs.me == c,
            label: c.label,
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('me-${c.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => notifier.update((x) => x.copyWith(me: c)),
              child: Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: prefs.me == c ? g.textPrimary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.fill,
                    gradient: c.gradient,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PeekPicker extends StatelessWidget {
  const _PeekPicker({required this.prefs, required this.notifier});
  final ChatViewPrefs prefs;
  final ChatViewPrefsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Wrap(
      spacing: _tileGap,
      runSpacing: _tileGap,
      children: [
        for (final k in ChatPeek.values)
          _PickTile(
            key: ValueKey('peek-${k.name}'),
            width: 58,
            selected: prefs.peek == k,
            label: k.label,
            onTap: () => notifier.update((x) => x.copyWith(peek: k)),
            child: SizedBox(
              height: 24,
              child: k == ChatPeek.none
                  ? Icon(Icons.close_rounded, size: 18, color: g.textMuted)
                  : ChatPeekSprite(k),
            ),
          ),
      ],
    );
  }
}

/// The Terminal part of the sheet: size, font and color preset.
class TerminalViewSection extends ConsumerWidget {
  const TerminalViewSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final p = ref.watch(terminalPrefsProvider);
    final n = ref.read(terminalPrefsProvider.notifier);

    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: GhinaSpace.xs),
      child: Text(
        t,
        style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Ukuran huruf (${p.fontSize.round()})'),
        Row(
          children: [
            Text('A', style: GhinaType.bodyS.copyWith(color: g.textMuted)),
            Expanded(
              child: Slider(
                key: const ValueKey('term-font-size'),
                value: p.fontSize,
                min: termFontMin,
                max: termFontMax,
                divisions: (termFontMax - termFontMin).round(),
                onChanged: (v) =>
                    n.update((x) => x.copyWith(fontSize: v.roundToDouble())),
              ),
            ),
            Text('A', style: GhinaType.h3.copyWith(color: g.textMuted)),
          ],
        ),
        GhinaSpace.gapSm,
        label('Font'),
        Wrap(
          spacing: _tileGap,
          runSpacing: _tileGap,
          children: [
            for (final f in TermFace.values)
              _PickTile(
                key: ValueKey('face-${f.name}'),
                width: 148,
                selected: p.face == f,
                label: f.label,
                onTap: () => n.update((x) => x.copyWith(face: f)),
                child: Text(
                  'Aa 0O il1 {}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: f.family,
                    fontFamilyFallback: TermFace.fallback,
                    fontSize: 14,
                    color: g.textPrimary,
                  ),
                ),
              ),
          ],
        ),
        GhinaSpace.gapMd,
        label('Warna'),
        Wrap(
          spacing: _tileGap,
          runSpacing: _tileGap,
          children: [
            for (final t in termThemes)
              _PickTile(
                key: ValueKey('theme-${t.id}'),
                width: 96,
                selected: p.theme == t.id,
                label: t.label,
                onTap: () => n.update((x) => x.copyWith(theme: t.id)),
                child: _ThemeSwatch(theme: t),
              ),
          ],
        ),
        if (p.themeDef.light) ...[
          GhinaSpace.gapSm,
          Text(
            'Tema terang: ketik /theme di sesi Claude lalu pilih tema light '
            'supaya teks Claude Code tetap terbaca.',
            style: GhinaType.caption.copyWith(color: g.textMuted),
          ),
        ],
        GhinaSpace.gapMd,
        ChunkyButton(
          key: const ValueKey('term-reset'),
          label: 'Kembalikan bawaan',
          variant: ChunkyButtonVariant.outline,
          onPressed: n.reset,
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});
  final TermThemeDef theme;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    return Container(
      width: double.infinity,
      height: 40,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: GhinaRadii.rSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              dot(theme.ansi[2]),
              dot(theme.ansi[1]),
              dot(theme.ansi[3]),
              dot(theme.ansi[4]),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            r'$ ok',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              height: 1,
              color: theme.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
