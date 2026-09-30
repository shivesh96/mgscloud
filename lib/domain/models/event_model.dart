class EventModel {
  final int? id;
  final String eventId;
  final String deviceId;
  final String eventType;
  final String source;
  final String timestamp;
  final int? simSlot;
  final String? simName;
  final String? simNumber;
  final String? sender;
  final String? message;
  final String? title;
  final String? packageName;
  final String? instanceName;
  final String? userPhoneNumber;
  final String? serviceCenter;
  final String? otp;
  final int? userId;
  final String? targetMobile;
  final String deliveryStatus;
  final int retryCount;
  final String? serverResponse;
  final String? userProfileId;
  final int createdAt;
  final bool? contentHidden;

  EventModel({
    this.id,
    required this.eventId,
    required this.deviceId,
    required this.eventType,
    required this.source,
    required this.timestamp,
    this.simSlot,
    this.simName,
    this.simNumber,
    this.sender,
    this.message,
    this.title,
    this.packageName,
    this.instanceName,
    this.userPhoneNumber,
    this.userProfileId,
    this.serviceCenter,
    this.otp,
    this.userId,
    this.targetMobile,
    this.deliveryStatus = 'pending',
    this.retryCount = 0,
    this.serverResponse,
    required this.createdAt,
    this.contentHidden,
  });

  Map<String, dynamic> toServerPayload() {
    final effectiveMobile = targetMobile ?? userPhoneNumber ?? simNumber ?? '';
    final effectiveSender = (sender != null && sender!.isNotEmpty && sender != 'Unknown')
        ? sender!
        : (title != null && title!.isNotEmpty ? title! : 'Unknown');

    return {
      'event_id': eventId,
      'device_id': deviceId,
      'user_id': userId,
      'mobile': effectiveMobile.isNotEmpty ? effectiveMobile : null,
      'type': source,
      'source': source,
      'event_type': eventType,
      'sender': effectiveSender,
      'title': title ?? effectiveSender,
      'service_center': serviceCenter,
      'body': message ?? '',
      'message': message ?? '',
      'otp': otp,
      'received_at': timestamp,
      'timestamp': timestamp,
      'sim_slot': simSlot,
      'sim_name': simName,
      'sim_number': simNumber,
      'instance_name': instanceName,
      'user_phone_number': userPhoneNumber,
      'user_profile_id': userProfileId,
      'package_name': packageName,
      if (simSlot != null || simName != null || simNumber != null)
        'sim': {
          if (simSlot != null) 'slot': simSlot,
          if (simName != null) 'name': simName,
          if (simNumber != null && simNumber!.isNotEmpty) 'number': simNumber,
        },
      if (contentHidden != null) 'content_hidden': contentHidden,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'uuid': eventId,
      'source': source,
      'event_type': eventType,
      'timestamp': DateTime.tryParse(timestamp)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
      'sim_slot': simSlot,
      'sim_name': simName,
      'sim_number': simNumber,
      'sender': sender,
      'title': title,
      'message': message ?? '',
      'package_name': packageName,
      'instance_name': instanceName,
      'user_phone_number': userPhoneNumber,
      'user_profile_id': userProfileId,
      'service_center': serviceCenter,
      'otp': otp,
      'user_id': userId,
      'target_mobile': targetMobile,
      'delivery_status': deliveryStatus,
      'retry_count': retryCount,
      'server_response': serverResponse,
      'created_at': createdAt,
      'content_hidden': contentHidden == true ? 1 : 0,
    };
  }

  factory EventModel.fromMap(Map<String, dynamic> map) {
    final tsEpoch = map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final tsIso = DateTime.fromMillisecondsSinceEpoch(tsEpoch).toIso8601String();

    return EventModel(
      id: map['id'] as int?,
      eventId: map['uuid'] as String? ?? map['event_id'] as String? ?? '',
      deviceId: map['device_id'] as String? ?? 'android-device',
      eventType: map['event_type'] as String? ?? 'event',
      source: map['source'] as String? ?? 'system',
      timestamp: tsIso,
      simSlot: map['sim_slot'] as int?,
      simName: map['sim_name'] as String?,
      simNumber: map['sim_number'] as String?,
      sender: map['sender'] as String?,
      title: map['title'] as String?,
      message: map['message'] as String?,
      packageName: map['package_name'] as String?,
      instanceName: map['instance_name'] as String?,
      userPhoneNumber: map['user_phone_number'] as String?,
      userProfileId: map['user_profile_id'] as String?,
      serviceCenter: map['service_center'] as String?,
      otp: map['otp'] as String?,
      userId: map['user_id'] as int?,
      targetMobile: map['target_mobile'] as String?,
      deliveryStatus: map['delivery_status'] as String? ?? 'pending',
      retryCount: map['retry_count'] as int? ?? 0,
      serverResponse: map['server_response'] as String?,
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      contentHidden: map['content_hidden'] == 1,
    );
  }

  EventModel copyWith({
    int? id,
    String? deviceId,
    String? deliveryStatus,
    int? retryCount,
    String? serverResponse,
    String? otp,
    int? userId,
    String? targetMobile,
    String? userProfileId,
    bool? contentHidden,
  }) {
    return EventModel(
      id: id ?? this.id,
      eventId: eventId,
      deviceId: deviceId ?? this.deviceId,
      eventType: eventType,
      source: source,
      timestamp: timestamp,
      simSlot: simSlot,
      simName: simName,
      simNumber: simNumber,
      sender: sender,
      message: message,
      title: title,
      packageName: packageName,
      instanceName: instanceName,
      userPhoneNumber: userPhoneNumber,
      userProfileId: userProfileId ?? this.userProfileId,
      serviceCenter: serviceCenter,
      otp: otp ?? this.otp,
      userId: userId ?? this.userId,
      targetMobile: targetMobile ?? this.targetMobile,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      retryCount: retryCount ?? this.retryCount,
      serverResponse: serverResponse ?? this.serverResponse,
      createdAt: createdAt,
      contentHidden: contentHidden ?? this.contentHidden,
    );
  }
}
