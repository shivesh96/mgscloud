class WhatsAppConfigModel {
  final int? id;
  final String packageName;
  final String instanceName;
  final String phoneNumber;
  final bool isClone;
  final bool enabled;
  final int updatedAt;

  WhatsAppConfigModel({
    this.id,
    required this.packageName,
    required this.instanceName,
    this.phoneNumber = '',
    this.isClone = false,
    this.enabled = true,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'package_name': packageName,
      'instance_name': instanceName,
      'phone_number': phoneNumber,
      'is_clone': isClone ? 1 : 0,
      'enabled': enabled ? 1 : 0,
      'updated_at': updatedAt,
    };
  }

  factory WhatsAppConfigModel.fromMap(Map<String, dynamic> map) {
    return WhatsAppConfigModel(
      id: map['id'] as int?,
      packageName: map['package_name'] as String? ?? '',
      instanceName: map['instance_name'] as String? ?? 'WhatsApp',
      phoneNumber: map['phone_number'] as String? ?? '',
      isClone: (map['is_clone'] as int? ?? 0) == 1,
      enabled: (map['enabled'] as int? ?? 1) == 1,
      updatedAt: map['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  WhatsAppConfigModel copyWith({
    int? id,
    String? instanceName,
    String? phoneNumber,
    bool? enabled,
  }) {
    return WhatsAppConfigModel(
      id: id ?? this.id,
      packageName: packageName,
      instanceName: instanceName ?? this.instanceName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isClone: isClone,
      enabled: enabled ?? this.enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
