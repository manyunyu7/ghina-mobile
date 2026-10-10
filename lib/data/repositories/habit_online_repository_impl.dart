import 'package:dio/dio.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../core/failure.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/habit_online_repository.dart';
import '../datasources/remote/api_client.dart';
import '../models/habit_analysis_wire.dart';

/// [HabitOnlineRepository] over `/api/mobile/habits/{id}[/notes[/append]]`
/// and `/insights` (`docs/habits-food-enrichment.md`). Nothing is cached or
/// stored: notes and analysis only live in memory while a screen shows them.
final class ApiHabitOnlineRepository implements HabitOnlineRepository {
  ApiHabitOnlineRepository(this._client, {Future<String?> Function()? timeZone})
    : _timeZone = timeZone ?? _deviceTimeZone;
  final ApiClient _client;
  final Future<String?> Function() _timeZone;

  Dio get _dio => _client.dio;

  static String _path(String id) =>
      '/api/mobile/habits/${Uri.encodeComponent(id)}';

  /// The stale-notes message of a 409 (the server answers a bare "conflict").
  static const conflictMessage =
      'Catatan ini sudah diubah di tempat lain. Muat ulang dulu, lalu coba lagi.';

  static Future<String?> _deviceTimeZone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return null; // the server falls back to Asia/Jakarta
    }
  }

  @override
  Future<HabitNotes> fetchNotes(String habitId) => apiCall(() async {
    final r = await _dio.get<Object?>(_path(habitId));
    final d = r.data;
    final habit = d is Map ? d['habit'] : null;
    if (habit is! Map) {
      throw const UnknownFailure('Respons catatan tidak valid');
    }
    final updated = DateTime.tryParse('${habit['updatedAt']}');
    if (updated == null) {
      throw const UnknownFailure('Respons catatan tidak valid');
    }
    final notes = habit['notes'];
    return HabitNotes(
      notes: notes is String ? notes : '',
      updatedAt: updated.toLocal(),
    );
  });

  @override
  Future<HabitNotesWrite> replaceNotes(
    String habitId,
    String notes, {
    DateTime? expectedUpdatedAt,
  }) => _write(
    () => _dio.put<Object?>(
      '${_path(habitId)}/notes',
      data: {
        'notes': notes,
        if (expectedUpdatedAt != null)
          'expectedUpdatedAt': expectedUpdatedAt.toUtc().toIso8601String(),
      },
    ),
  );

  @override
  Future<HabitNotesWrite> appendNotes(
    String habitId,
    String text, {
    String? heading,
  }) => _write(
    () => _dio.post<Object?>(
      '${_path(habitId)}/notes/append',
      data: {
        'text': text,
        if (heading != null && heading.trim().isNotEmpty)
          'heading': heading.trim(),
      },
    ),
  );

  Future<HabitNotesWrite> _write(
    Future<Response<Object?>> Function() call,
  ) async {
    try {
      final r = await call();
      final d = r.data;
      final updated = d is Map ? DateTime.tryParse('${d['updatedAt']}') : null;
      if (updated == null) {
        throw const UnknownFailure('Respons catatan tidak valid');
      }
      return HabitNotesWrite(
        updatedAt: updated.toLocal(),
        notesLength: d is Map && d['notesLength'] is num
            ? (d['notesLength'] as num).toInt()
            : 0,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const ConflictFailure(conflictMessage);
      }
      throw mapDioError(e);
    }
  }

  @override
  Future<HabitAnalysis> fetchAnalysis(
    String habitId, {
    int days = 90,
    required String today,
  }) => apiCall(() async {
    final tz = await _timeZone();
    final r = await _dio.get<Object?>(
      '${_path(habitId)}/insights',
      queryParameters: {'days': days, 'today': today, 'tz': ?tz},
    );
    final a = habitAnalysisFromWire(habitId, r.data);
    if (a == null) throw const UnknownFailure('Respons analisis tidak valid');
    return a;
  });
}
