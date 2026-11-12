import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'terminal_themes.dart';

/// How the Kantor terminal looks on this phone: color preset, font and size.
@immutable
class TerminalPrefs {
  const TerminalPrefs({
    this.theme = defaultTermThemeId,
    this.face = TermFace.jetbrains,
    this.fontSize = termFontDefault,
  });

  /// Id of a [termThemes] preset.
  final String theme;
  final TermFace face;
  final double fontSize;

  TermThemeDef get themeDef => termThemeById(theme);

  TerminalPrefs copyWith({String? theme, TermFace? face, double? fontSize}) =>
      TerminalPrefs(
        theme: theme ?? this.theme,
        face: face ?? this.face,
        fontSize: fontSize == null
            ? this.fontSize
            : fontSize.clamp(termFontMin, termFontMax),
      );

  Map<String, dynamic> toJson() => {
    'theme': theme,
    'face': face.name,
    'fontSize': fontSize,
  };

  /// Unknown or out-of-range content goes back to the default.
  factory TerminalPrefs.fromJson(Map<String, dynamic> j) {
    final size = j['fontSize'];
    return TerminalPrefs(
      theme: termThemes.any((t) => t.id == j['theme'])
          ? '${j['theme']}'
          : defaultTermThemeId,
      face:
          TermFace.values.where((f) => f.name == j['face']).firstOrNull ??
          TermFace.jetbrains,
      fontSize: size is num
          ? size.toDouble().clamp(termFontMin, termFontMax)
          : termFontDefault,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TerminalPrefs &&
      other.theme == theme &&
      other.face == face &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(theme, face, fontSize);
}

const _termPrefsKey = 'kantor.terminal.view';

/// Terminal look, remembered on this phone. Changes show up at once.
final terminalPrefsProvider =
    NotifierProvider<TerminalPrefsNotifier, TerminalPrefs>(
      TerminalPrefsNotifier.new,
    );

class TerminalPrefsNotifier extends Notifier<TerminalPrefs> {
  bool _touched = false;

  @override
  TerminalPrefs build() {
    _load();
    return const TerminalPrefs();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_termPrefsKey);
      if (raw == null || _touched) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) state = TerminalPrefs.fromJson(j);
    } catch (_) {
      // defaults are fine
    }
  }

  void update(TerminalPrefs Function(TerminalPrefs p) fn) {
    _touched = true;
    state = fn(state);
    SharedPreferences.getInstance()
        .then((p) => p.setString(_termPrefsKey, jsonEncode(state.toJson())))
        .catchError((_) => false);
  }

  void reset() => update((_) => const TerminalPrefs());
}
