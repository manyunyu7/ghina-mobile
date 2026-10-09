import 'package:dio/dio.dart';

import '../../core/failure.dart';
import '../../domain/entities/people.dart';
import '../../domain/repositories/people_notes_repository.dart';
import '../datasources/remote/api_client.dart';

/// [PeopleNotesRepository] over `/api/mobile/people/{id}[/notes[/append]]`
/// (`docs/people.md`). Nothing is cached or stored: the notes only live in
/// memory while a screen shows them.
final class ApiPeopleNotesRepository implements PeopleNotesRepository {
  ApiPeopleNotesRepository(this._client);
  final ApiClient _client;

  Dio get _dio => _client.dio;

  static String _path(String id) =>
      '/api/mobile/people/${Uri.encodeComponent(id)}';

  /// The stale-notes message of a 409 (the server answers a bare "conflict").
  static const conflictMessage =
      'Catatan ini sudah diubah di tempat lain. Muat ulang dulu, lalu coba lagi.';

  @override
  Future<PersonNotes> fetch(String personId) => apiCall(() async {
    final r = await _dio.get<Object?>(_path(personId));
    final d = r.data;
    final person = d is Map ? d['person'] : null;
    if (person is! Map) {
      throw const UnknownFailure('Respons catatan tidak valid');
    }
    final updated = DateTime.tryParse('${person['updatedAt']}');
    if (updated == null) {
      throw const UnknownFailure('Respons catatan tidak valid');
    }
    final notes = person['notes'];
    return PersonNotes(
      notes: notes is String ? notes : '',
      updatedAt: updated.toLocal(),
    );
  });

  @override
  Future<PersonNotesWrite> replace(
    String personId,
    String notes, {
    DateTime? expectedUpdatedAt,
  }) => _write(
    () => _dio.put<Object?>(
      '${_path(personId)}/notes',
      data: {
        'notes': notes,
        if (expectedUpdatedAt != null)
          'expectedUpdatedAt': expectedUpdatedAt.toUtc().toIso8601String(),
      },
    ),
  );

  @override
  Future<PersonNotesWrite> append(
    String personId,
    String text, {
    String? heading,
  }) => _write(
    () => _dio.post<Object?>(
      '${_path(personId)}/notes/append',
      data: {
        'text': text,
        if (heading != null && heading.trim().isNotEmpty)
          'heading': heading.trim(),
      },
    ),
  );

  Future<PersonNotesWrite> _write(
    Future<Response<Object?>> Function() call,
  ) async {
    try {
      final r = await call();
      final d = r.data;
      final updated = d is Map ? DateTime.tryParse('${d['updatedAt']}') : null;
      if (updated == null) {
        throw const UnknownFailure('Respons catatan tidak valid');
      }
      return PersonNotesWrite(
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
}
