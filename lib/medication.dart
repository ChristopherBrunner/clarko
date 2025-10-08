import 'package:flutter/material.dart';

class Medication {
  final String name;
  final IconData icon;
  bool isTaken;
  TimeOfDay? reminderTime;

  Medication(
      {required this.name,
      required this.icon,
      this.isTaken = false,
      this.reminderTime});
}
