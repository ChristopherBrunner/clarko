import 'package:flutter/material.dart';

/// A single scheduled dose (e.g. "Morning" or "Night").
///
/// A dose is made up of one or more [tablets] (each a strength in mg), has a
/// reminder [time], and can be individually [enabled] / disabled.
class Dose {
  Dose({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    required this.tablets,
    this.enabled = true,
  });

  /// Stable identifier, also used as the notification id seed and widget key.
  final String id;
  String label;
  int hour;
  int minute;

  /// Tablet strengths in milligrams, e.g. `[500, 250]` for a 750mg dose.
  List<int> tablets;
  bool enabled;

  TimeOfDay get time => TimeOfDay(hour: hour, minute: minute);
  set time(TimeOfDay value) {
    hour = value.hour;
    minute = value.minute;
  }

  /// Total dose strength in mg across all tablets.
  int get totalMg => tablets.fold(0, (sum, mg) => sum + mg);

  /// Human-readable dosage, e.g. "500mg + 250mg (750mg)".
  String get dosageLabel {
    if (tablets.isEmpty) return 'No tablets';
    final parts = tablets.map((mg) => '${mg}mg').join(' + ');
    if (tablets.length == 1) return parts;
    return '$parts ($totalMg' 'mg)';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'tablets': tablets,
        'enabled': enabled,
      };

  factory Dose.fromJson(Map<String, dynamic> json) => Dose(
        id: json['id'] as String,
        label: json['label'] as String,
        hour: json['hour'] as int,
        minute: json['minute'] as int,
        tablets: (json['tablets'] as List).map((e) => e as int).toList(),
        enabled: json['enabled'] as bool? ?? true,
      );

  Dose copyWith({
    String? label,
    int? hour,
    int? minute,
    List<int>? tablets,
    bool? enabled,
  }) =>
      Dose(
        id: id,
        label: label ?? this.label,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        tablets: tablets ?? List<int>.from(this.tablets),
        enabled: enabled ?? this.enabled,
      );

  /// The two default Levetiracetam doses for first run.
  static List<Dose> defaults() => [
        Dose(
          id: 'morning',
          label: 'Morning',
          hour: 8,
          minute: 0,
          tablets: [500, 250],
        ),
        Dose(
          id: 'night',
          label: 'Night',
          hour: 20,
          minute: 0,
          tablets: [500, 250],
        ),
      ];
}
