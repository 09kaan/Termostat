class Settings {
  final double hysteresis;
  final int overrideTimeout;
  final String theme;
  final bool enableDynamicBackground;
  final bool enableHaptics;
  final double hourlyEnergyCost;
  final bool optimumStartEnabled;
  final bool frostProtectionEnabled;
  final double frostProtectionTemp;
  final bool warmWeatherAutoOff;

  Settings({
    required this.hysteresis,
    required this.overrideTimeout,
    required this.theme,
    this.enableDynamicBackground = true,
    this.enableHaptics = true,
    this.hourlyEnergyCost = 12.5,
    this.optimumStartEnabled = false,
    this.frostProtectionEnabled = true,
    this.frostProtectionTemp = 12.0,
    this.warmWeatherAutoOff = false,
  });

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      hysteresis: (json['hysteresis'] ?? 0.5).toDouble(),
      overrideTimeout: json['overrideTimeout'] ?? 60,
      theme: json['theme'] ?? 'system',
      enableDynamicBackground: json['enableDynamicBackground'] ?? true,
      enableHaptics: json['enableHaptics'] ?? true,
      hourlyEnergyCost: (json['hourlyEnergyCost'] ?? 12.5).toDouble(),
      optimumStartEnabled: json['optimumStartEnabled'] ?? false,
      frostProtectionEnabled: json['frostProtectionEnabled'] ?? true,
      frostProtectionTemp: (json['frostProtectionTemp'] ?? 12.0).toDouble(),
      warmWeatherAutoOff: json['warmWeatherAutoOff'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'hysteresis': hysteresis,
        'overrideTimeout': overrideTimeout,
        'theme': theme,
        'enableDynamicBackground': enableDynamicBackground,
        'enableHaptics': enableHaptics,
        'hourlyEnergyCost': hourlyEnergyCost,
        'optimumStartEnabled': optimumStartEnabled,
        'frostProtectionEnabled': frostProtectionEnabled,
        'frostProtectionTemp': frostProtectionTemp,
        'warmWeatherAutoOff': warmWeatherAutoOff,
      };

  Settings copyWith({
    double? hysteresis,
    int? overrideTimeout,
    String? theme,
    bool? enableDynamicBackground,
    bool? enableHaptics,
    double? hourlyEnergyCost,
    bool? optimumStartEnabled,
    bool? frostProtectionEnabled,
    double? frostProtectionTemp,
    bool? warmWeatherAutoOff,
  }) {
    return Settings(
      hysteresis: hysteresis ?? this.hysteresis,
      overrideTimeout: overrideTimeout ?? this.overrideTimeout,
      theme: theme ?? this.theme,
      enableDynamicBackground:
          enableDynamicBackground ?? this.enableDynamicBackground,
      enableHaptics: enableHaptics ?? this.enableHaptics,
      hourlyEnergyCost: hourlyEnergyCost ?? this.hourlyEnergyCost,
      optimumStartEnabled: optimumStartEnabled ?? this.optimumStartEnabled,
      frostProtectionEnabled:
          frostProtectionEnabled ?? this.frostProtectionEnabled,
      frostProtectionTemp: frostProtectionTemp ?? this.frostProtectionTemp,
      warmWeatherAutoOff: warmWeatherAutoOff ?? this.warmWeatherAutoOff,
    );
  }
}
