class Settings {
  final double hysteresis;
  final int overrideTimeout;
  final String theme;

  Settings({
    required this.hysteresis,
    required this.overrideTimeout,
    required this.theme,
  });

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      hysteresis: (json['hysteresis'] ?? 0.5).toDouble(),
      overrideTimeout: json['overrideTimeout'] ?? 60,
      theme: json['theme'] ?? 'system',
    );
  }

  Map<String, dynamic> toJson() => {
        'hysteresis': hysteresis,
        'overrideTimeout': overrideTimeout,
        'theme': theme,
      };

  Settings copyWith({
    double? hysteresis,
    int? overrideTimeout,
    String? theme,
  }) {
    return Settings(
      hysteresis: hysteresis ?? this.hysteresis,
      overrideTimeout: overrideTimeout ?? this.overrideTimeout,
      theme: theme ?? this.theme,
    );
  }
}
