class Thermostat {
  final String id;
  final double currentTemperature;
  final double targetTemperature;
  final String mode; // 'heat', 'cool', 'auto', 'off'
  final bool isConnected;
  final DateTime lastUpdated;
  final double humidity;

  Thermostat({
    required this.id,
    required this.currentTemperature,
    required this.targetTemperature,
    required this.mode,
    required this.isConnected,
    required this.lastUpdated,
    required this.humidity,
  });

  factory Thermostat.fromJson(Map<String, dynamic> json) {
    return Thermostat(
      id: json['id'] as String? ?? '',
      currentTemperature: (json['currentTemperature'] as num?)?.toDouble() ?? 0.0,
      targetTemperature: (json['targetTemperature'] as num?)?.toDouble() ?? 0.0,
      mode: json['mode'] as String? ?? 'off',
      isConnected: json['isConnected'] as bool? ?? false,
      lastUpdated: json['lastUpdated'] != null 
          ? DateTime.tryParse(json['lastUpdated'] as String) ?? DateTime.now()
          : DateTime.now(),
      humidity: (json['currentHumidity'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'currentTemperature': currentTemperature,
      'targetTemperature': targetTemperature,
      'mode': mode,
      'isConnected': isConnected,
      'lastUpdated': lastUpdated.toIso8601String(),
      'humidity': humidity,
    };
  }

  Thermostat copyWith({
    String? id,
    double? currentTemperature,
    double? targetTemperature,
    String? mode,
    bool? isConnected,
    DateTime? lastUpdated,
    double? humidity,
  }) {
    return Thermostat(
      id: id ?? this.id,
      currentTemperature: currentTemperature ?? this.currentTemperature,
      targetTemperature: targetTemperature ?? this.targetTemperature,
      mode: mode ?? this.mode,
      isConnected: isConnected ?? this.isConnected,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      humidity: humidity ?? this.humidity,
    );
  }
} 