class UserBindingModel {
  final int? id;
  final int userId;
  final String type; // 'mobile' or 'email'
  final String value;
  final int createdAt;

  UserBindingModel({
    this.id,
    required this.userId,
    required this.type,
    required this.value,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'type': type,
      'value': value,
      'created_at': createdAt,
    };
  }

  factory UserBindingModel.fromMap(Map<String, dynamic> map) {
    return UserBindingModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int? ?? 1,
      type: map['type'] as String? ?? 'mobile',
      value: map['value'] as String? ?? '',
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
