class Location {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius; // in meters
  bool isEnabled;
  final String action; // 'away', 'home'
  final double awayTemperature;
  final double homeTemperature;

  Location({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.isEnabled = true,
    required this.action,
    required this.awayTemperature,
    required this.homeTemperature,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radius: (json['radius'] as num).toDouble(),
      isEnabled: json['isEnabled'] as bool,
      action: json['action'] as String,
      awayTemperature: (json['awayTemperature'] as num).toDouble(),
      homeTemperature: (json['homeTemperature'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'isEnabled': isEnabled,
      'action': action,
      'awayTemperature': awayTemperature,
      'homeTemperature': homeTemperature,
    };
  }

  Location copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radius,
    bool? isEnabled,
    String? action,
    double? awayTemperature,
    double? homeTemperature,
  }) {
    return Location(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      isEnabled: isEnabled ?? this.isEnabled,
      action: action ?? this.action,
      awayTemperature: awayTemperature ?? this.awayTemperature,
      homeTemperature: homeTemperature ?? this.homeTemperature,
    );
  }
}
