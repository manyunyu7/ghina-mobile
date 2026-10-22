import '../../../design_system/design_system.dart';

/// Daemon note colors, in the order the web shows them.
const noteColors = ['kuning', 'hijau', 'biru', 'merah', 'ungu', 'abu'];

ChunkySwatch noteSwatch(String? color) => switch (color) {
  'hijau' => GhinaColors.green,
  'biru' => GhinaColors.blue,
  'merah' => GhinaColors.red,
  'ungu' => GhinaColors.purple,
  'abu' => GhinaColors.gray,
  _ => GhinaColors.yellow,
};
