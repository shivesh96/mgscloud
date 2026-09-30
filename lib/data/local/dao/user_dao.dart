import '../database/app_database.dart';
import '../../../domain/models/user_model.dart';
import '../../../domain/models/user_binding_model.dart';

class UserDao {
  Future<UserModel?> getActiveUser() async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'users',
      where: 'is_active = 1',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (results.isNotEmpty) {
      return UserModel.fromMap(results.first);
    }
    return null;
  }

  Future<int> saveUser(UserModel user) async {
    final db = await AppDatabase.instance.database;
    // Set other users inactive
    await db.update('users', {'is_active': 0});
    return await db.insert('users', user.toMap());
  }

  Future<void> setGuestMode() async {
    final db = await AppDatabase.instance.database;
    await db.update('users', {'is_active': 0});
    await db.insert('users', {
      'server_user_id': null,
      'username': 'Guest User',
      'mobile': '',
      'email': '',
      'auth_token': '',
      'is_guest': 1,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Bindings
  Future<List<UserBindingModel>> getBindingsForUser(int userId) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'user_bindings',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
    );
    return results.map((r) => UserBindingModel.fromMap(r)).toList();
  }

  Future<List<UserBindingModel>> getAllBindings() async {
    final db = await AppDatabase.instance.database;
    final results = await db.query('user_bindings', orderBy: 'id DESC');
    return results.map((r) => UserBindingModel.fromMap(r)).toList();
  }

  Future<int> addBinding(UserBindingModel binding) async {
    final db = await AppDatabase.instance.database;
    return await db.insert('user_bindings', binding.toMap());
  }

  Future<void> deleteBinding(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('user_bindings', where: 'id = ?', whereArgs: [id]);
  }

  Future<UserBindingModel?> findBindingByValue(String value) async {
    final clean = value.replaceAll(RegExp(r'[^0-9a-zA-Z@._+-]'), '').toLowerCase();
    final db = await AppDatabase.instance.database;
    final results = await db.query('user_bindings');
    for (final row in results) {
      final bindingVal = (row['value'] as String? ?? '').replaceAll(RegExp(r'[^0-9a-zA-Z@._+-]'), '').toLowerCase();
      if (bindingVal.isNotEmpty && (clean.contains(bindingVal) || bindingVal.contains(clean))) {
        return UserBindingModel.fromMap(row);
      }
    }
    return null;
  }
}
