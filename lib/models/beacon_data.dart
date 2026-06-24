class BeaconData {
  final String deviceId;
  final String? deviceName;
  final String uuid;
  final int major;
  final int minor;
  final int rssi;
  final int? measuredPower;
  final DateTime lastSeen;

  const BeaconData({
    required this.deviceId,
    this.deviceName,
    required this.uuid,
    required this.major,
    required this.minor,
    required this.rssi,
    this.measuredPower,
    required this.lastSeen,
  });

  BeaconData copyWith({
    String? deviceId,
    String? deviceName,
    String? uuid,
    int? major,
    int? minor,
    int? rssi,
    int? measuredPower,
    DateTime? lastSeen,
  }) {
    return BeaconData(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      uuid: uuid ?? this.uuid,
      major: major ?? this.major,
      minor: minor ?? this.minor,
      rssi: rssi ?? this.rssi,
      measuredPower: measuredPower ?? this.measuredPower,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
