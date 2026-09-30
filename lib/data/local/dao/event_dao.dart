import '../database/app_database.dart';
import '../../../domain/models/event_model.dart';

class EventDao {
  Future<EventModel?> getEventByUuid(String uuid) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query('events', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (results.isNotEmpty) {
      return EventModel.fromMap(results.first);
    }
    return null;
  }

  Future<int> insertEvent(EventModel event) async {
    final db = await AppDatabase.instance.database;
    return await db.insert('events', event.toMap());
  }

  Future<List<EventModel>> getRecentEvents({int limit = 10}) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'events',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return results.map((m) => EventModel.fromMap(m)).toList();
  }

  Future<List<EventModel>> getAllEvents({
    String? source,
    String? status,
    String? query,
    int limit = 100,
  }) async {
    final db = await AppDatabase.instance.database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (source != null && source.isNotEmpty && source != 'ALL') {
      whereClauses.add('source = ?');
      whereArgs.add(source);
    }

    if (status != null && status.isNotEmpty && status != 'ALL') {
      whereClauses.add('delivery_status = ?');
      whereArgs.add(status);
    }

    if (query != null && query.trim().isNotEmpty) {
      whereClauses.add('(sender LIKE ? OR message LIKE ? OR title LIKE ?)');
      final term = '%${query.trim()}%';
      whereArgs.addAll([term, term, term]);
    }

    final where = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final results = await db.query(
      'events',
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return results.map((m) => EventModel.fromMap(m)).toList();
  }

  Future<List<EventModel>> getPendingEvents({int limit = 50}) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'events',
      where: 'delivery_status = ? OR delivery_status = ?',
      whereArgs: ['pending', 'failed'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return results.map((m) => EventModel.fromMap(m)).toList();
  }

  Future<void> updateEventStatus(
    int id,
    String status, {
    String? response,
    int? retryCount,
  }) async {
    final db = await AppDatabase.instance.database;
    final values = <String, dynamic>{
      'delivery_status': status,
    };
    if (response != null) values['server_response'] = response;
    if (retryCount != null) values['retry_count'] = retryCount;

    await db.update('events', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getTodayEventCount() async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM events WHERE created_at >= ?',
      [startOfDay],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getPendingEventCount() async {
    final db = await AppDatabase.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM events WHERE delivery_status = ? OR delivery_status = ?',
      ['pending', 'failed'],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> deleteEvent(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteEventsByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete('events', where: 'id IN ($placeholders)', whereArgs: ids);
  }

  Future<int> deleteFilteredEvents() async {
    final db = await AppDatabase.instance.database;
    return await db.delete(
      'events',
      where: "delivery_status = 'filtered_out' OR otp IS NULL OR otp = ''",
    );
  }

  Future<void> clearAllLogs() async {
    final db = await AppDatabase.instance.database;
    await db.delete('events');
  }

  Future<void> pruneOldLogs(int retentionDays) async {
    if (retentionDays <= 0) return; // 0 means forever
    final db = await AppDatabase.instance.database;
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays)).millisecondsSinceEpoch;
    await db.delete('events', where: 'created_at < ?', whereArgs: [cutoff]);
  }
}
