class OtpRuleModel {
  final int? id;
  final int? serverId;
  final String ruleName;
  final String type;
  final String filterName;
  final String? sender;
  final String? serviceCenter;
  final String? bodyPattern;
  final String regex;
  final String attribute;
  final int regIndex;
  final bool enabled;
  final String? requestBodySample;
  final String? rawData;
  final int updatedAt;

  OtpRuleModel({
    this.id,
    this.serverId,
    required this.ruleName,
    this.type = 'sms',
    this.filterName = 'OTP',
    this.sender,
    this.serviceCenter,
    this.bodyPattern,
    required this.regex,
    this.attribute = 'gm',
    this.regIndex = 1,
    this.enabled = true,
    this.requestBodySample,
    this.rawData,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      'rule_name': ruleName,
      'type': type,
      'filter_name': filterName,
      'sender': sender,
      'service_center': serviceCenter,
      'body_pattern': bodyPattern,
      'regex': regex,
      'attribute': attribute,
      'reg_index': regIndex,
      'enabled': enabled ? 1 : 0,
      'request_body_sample': requestBodySample,
      'raw_data': rawData,
      'updated_at': updatedAt,
    };
  }

  Map<String, dynamic> toServerPayload() {
    return {
      'rule_name': ruleName,
      'type': type,
      'filter_name': filterName,
      'sender': sender ?? '',
      'service_center': serviceCenter ?? '',
      'body_pattern': bodyPattern ?? '',
      'regex': regex,
      'attribute': attribute,
      'reg_index': regIndex,
      'enabled': enabled ? 1 : 0,
      'request_body_sample': requestBodySample ?? '',
      'raw_data': rawData ?? '',
    };
  }

  factory OtpRuleModel.fromMap(Map<String, dynamic> map) {
    // If the map came from server API, 'id' is the server's rule ID
    final rawId = map['id'] as int?;
    final rawServerId = map['server_id'] as int?;

    return OtpRuleModel(
      id: rawServerId != null ? rawId : null,
      serverId: rawServerId ?? rawId,
      ruleName: map['rule_name'] as String? ?? map['Rule_Name'] as String? ?? 'Rule',
      type: map['type'] as String? ?? 'sms',
      filterName: map['filter_name'] as String? ?? 'OTP',
      sender: map['sender'] as String?,
      serviceCenter: map['service_center'] as String?,
      bodyPattern: map['body_pattern'] as String? ?? map['body'] as String?,
      regex: map['regex'] as String? ?? '',
      attribute: map['attribute'] as String? ?? 'gm',
      regIndex: map['reg_index'] as int? ?? 1,
      enabled: (map['enabled'] as int? ?? 1) == 1,
      requestBodySample: map['request_body_sample'] as String?,
      rawData: map['raw_data'] as String?,
      updatedAt: map['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  OtpRuleModel copyWith({
    int? id,
    int? serverId,
    String? ruleName,
    String? type,
    String? filterName,
    String? sender,
    String? serviceCenter,
    String? bodyPattern,
    String? regex,
    String? attribute,
    int? regIndex,
    bool? enabled,
    String? requestBodySample,
    String? rawData,
    int? updatedAt,
  }) {
    return OtpRuleModel(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      ruleName: ruleName ?? this.ruleName,
      type: type ?? this.type,
      filterName: filterName ?? this.filterName,
      sender: sender ?? this.sender,
      serviceCenter: serviceCenter ?? this.serviceCenter,
      bodyPattern: bodyPattern ?? this.bodyPattern,
      regex: regex ?? this.regex,
      attribute: attribute ?? this.attribute,
      regIndex: regIndex ?? this.regIndex,
      enabled: enabled ?? this.enabled,
      requestBodySample: requestBodySample ?? this.requestBodySample,
      rawData: rawData ?? this.rawData,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
