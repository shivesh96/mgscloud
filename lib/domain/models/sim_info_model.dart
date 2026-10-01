class SimInfoModel {
  final int subscriptionId;
  final int slotIndex;
  final String carrierName;
  final String defaultName;
  final String customName;
  final String detectedNumber;
  final String userPhoneNumber;
  final String numberSource;
  final bool enabled;
  final int updatedAt;

  SimInfoModel({
    required this.subscriptionId,
    required this.slotIndex,
    required this.carrierName,
    required this.defaultName,
    this.customName = '',
    this.detectedNumber = '',
    this.userPhoneNumber = '',
    this.numberSource = 'default',
    this.enabled = true,
    required this.updatedAt,
  });

  String get effectiveName {
    if (customName.trim().isNotEmpty) return customName.trim();
    if (defaultName.trim().isNotEmpty) return defaultName.trim();
    return 'SIM ${slotIndex + 1}';
  }

  String get effectiveNumber {
    if (numberSource == 'auto_detect') {
      if (detectedNumber.trim().isNotEmpty) return detectedNumber.trim();
      if (userPhoneNumber.trim().isNotEmpty) return userPhoneNumber.trim();
      return 'Not configured';
    }
    if (userPhoneNumber.trim().isNotEmpty) return userPhoneNumber.trim();
    if (detectedNumber.trim().isNotEmpty) return detectedNumber.trim();
    return 'Not configured';
  }

  Map<String, dynamic> toMap() {
    return {
      'subscription_id': subscriptionId,
      'slot_index': slotIndex,
      'carrier_name': carrierName,
      'default_name': defaultName,
      'custom_name': customName,
      'detected_number': detectedNumber,
      'user_phone_number': userPhoneNumber,
      'number_source': numberSource,
      'enabled': enabled ? 1 : 0,
      'updated_at': updatedAt,
    };
  }

  factory SimInfoModel.fromMap(Map<String, dynamic> map) {
    return SimInfoModel(
      subscriptionId: map['subscription_id'] as int? ?? 0,
      slotIndex: map['slot_index'] as int? ?? 0,
      carrierName: map['carrier_name'] as String? ?? 'Unknown',
      defaultName:
          map['default_name'] as String? ??
          'SIM ${((map['slot_index'] as int? ?? 0) + 1)}',
      customName: map['custom_name'] as String? ?? '',
      detectedNumber: map['detected_number'] as String? ?? '',
      userPhoneNumber: map['user_phone_number'] as String? ?? '',
      numberSource: map['number_source'] as String? ?? 'default',
      enabled: (map['enabled'] as int? ?? 1) == 1,
      updatedAt:
          map['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  SimInfoModel copyWith({
    String? customName,
    String? userPhoneNumber,
    String? numberSource,
    bool? enabled,
  }) {
    return SimInfoModel(
      subscriptionId: subscriptionId,
      slotIndex: slotIndex,
      carrierName: carrierName,
      defaultName: defaultName,
      customName: customName ?? this.customName,
      detectedNumber: detectedNumber,
      userPhoneNumber: userPhoneNumber ?? this.userPhoneNumber,
      numberSource: numberSource ?? this.numberSource,
      enabled: enabled ?? this.enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
