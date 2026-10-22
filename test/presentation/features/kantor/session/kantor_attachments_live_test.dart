import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_model.dart';
import 'package:ghina/presentation/features/kantor/session/attachment_uploader.dart';

/// Against a real (demo) daemon; skipped unless `KANTOR_LIVE_URL` and
/// `KANTOR_LIVE_SID` are set (token from `KANTOR_LIVE_TOKEN`, default `demotoken`):
/// `KANTOR_LIVE_URL=http://127.0.0.1:4373 KANTOR_LIVE_SID=… flutter test <this file>`
void main() {
  final url = Platform.environment['KANTOR_LIVE_URL'];
  final sid = Platform.environment['KANTOR_LIVE_SID'];
  final token = Platform.environment['KANTOR_LIVE_TOKEN'] ?? 'demotoken';
  final skip = url == null || sid == null
      ? 'KANTOR_LIVE_URL / KANTOR_LIVE_SID not set'
      : null;

  test(
    'uploads 9 MB in 4 MB pieces, survives a dropped piece, lands as an attachment',
    () async {
      final tmp = await Directory.systemTemp.createTemp('kantor_live_');
      addTearDown(() => tmp.delete(recursive: true));
      final rnd = Random(7);
      final data = List<int>.generate(
        9 * 1024 * 1024 + 123,
        (_) => rnd.nextInt(256),
      );
      final src = File('${tmp.path}/video-uji.mp4')..writeAsBytesSync(data);

      final dio = Dio(
        BaseOptions(baseUrl: url!, headers: {'Authorization': 'Bearer $token'}),
      );
      var puts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'PUT' && ++puts == 2) {
              return h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.connectionError,
                ),
                true,
              );
            }
            h.next(o);
          },
        ),
      );
      final up = KantorUploader(dio, backoff: (_) => Duration.zero);
      final job = UploadJob(
        id: 'l1',
        sid: sid!,
        agent: 'Rara',
        path: src.path,
        name: 'video-uji.mp4',
        size: data.length,
        mime: 'video/mp4',
        caption: 'uji dari Ghina',
      );
      final seen = <int>[];
      final id = await up.upload(job, onProgress: (s, _) => seen.add(s));
      expect(seen.last, data.length);
      expect(puts, greaterThanOrEqualTo(4), reason: '3 pieces + 1 retried');

      final plain = Dio(
        BaseOptions(baseUrl: url, headers: {'Authorization': 'Bearer $token'}),
      );
      final st = (await plain.get<Map<String, dynamic>>(
        '/api/uploads/$id',
      )).data!;
      expect(st['done'], isTrue);
      final list = parseAttachments(
        (await plain.get<dynamic>('/api/sessions/$sid/attachments')).data,
      );
      final mine = list.firstWhere((a) => a.name.endsWith('video-uji.mp4'));
      expect(mine.mine, isTrue);
      expect(mine.kind, AttachmentKind.video);
      expect(mine.caption, 'uji dari Ghina');
      final back = await plain.get<List<int>>(
        mine.rawPath,
        options: Options(responseType: ResponseType.bytes),
      );
      expect(back.data, data);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
