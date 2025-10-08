import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'medication.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  void _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 0;
    setState(() {
      _themeMode = ThemeMode.values[themeIndex];
    });
  }

  void changeTheme(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medication Tracker',
      theme: ThemeData(
        // Light Theme
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB2D8B2)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        // Dark Theme
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFB2D8B2), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: MyHomePage(
        title: 'Medication Tracker',
        themeMode: _themeMode,
        onThemeChanged: changeTheme,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage(
      {super.key,
      required this.title,
      required this.themeMode,
      required this.onThemeChanged});

  final String title;
  // Add themeMode and onThemeChanged to pass down from MyApp
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeChanged;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  late List<Medication> _medications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _medications = [
      Medication(name: 'Morning Dose', icon: FontAwesomeIcons.cloudSun),
      Medication(name: 'Evening Dose', icon: FontAwesomeIcons.cloudMoon),
    ];
    _loadMedicationState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App has come to the foreground
      print("App resumed, reloading medication state.");
      _loadMedicationState();
    }
  }

  Future<void> _loadMedicationState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (int i = 0; i < _medications.length; i++) {
        final med = _medications[i];
        // Load 'isTaken' status
        med.isTaken = prefs.getBool(_getDailyKey(med.name)) ?? false;

        // Load reminder time
        final hour = prefs.getInt('${med.name}_reminder_hour');
        final minute = prefs.getInt('${med.name}_reminder_minute');

        if (hour != null && minute != null) {
          med.reminderTime = TimeOfDay(hour: hour, minute: minute);
          // Re-schedule the notification on app start
          final now = DateTime.now();
          final scheduledTime =
              DateTime(now.year, now.month, now.day, hour, minute);
          final notificationId = _medications.indexOf(med);

          // It's good practice to cancel any old notification before scheduling a new one
          NotificationService.instance.cancelNotification(notificationId);
          NotificationService.instance.scheduleDailyNotification(
              notificationId, // Pass the medication name in the payload
              "Time for your ${med.name}!",
              "Don't forget to take your medication.",
              scheduledTime);
        }
      }
    });
  }

  Future<void> _toggleMedication(Medication medication) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      medication.isTaken = !medication.isTaken;
      prefs.setBool(_getDailyKey(medication.name), medication.isTaken);
    });
  }

  Future<void> _selectTime(BuildContext context, Medication medication) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: medication.reminderTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != medication.reminderTime) {
      setState(() {
        medication.reminderTime = picked;
      });

      // Save the reminder time to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${medication.name}_reminder_hour', picked.hour);
      await prefs.setInt('${medication.name}_reminder_minute', picked.minute);
      final now = DateTime.now();
      final scheduledTime =
          DateTime(now.year, now.month, now.day, picked.hour, picked.minute);

      // Use a unique ID for each medication for the notification
      final notificationId = _medications.indexOf(medication);
      NotificationService.instance.scheduleDailyNotification(
          notificationId, // Pass the medication name in the payload
          "Time for your ${medication.name}!",
          "Don't forget to take your medication.",
          scheduledTime);
    }
  }

  String _getDailyKey(String medName) {
    final now = DateTime.now();
    // Creates a unique key for each day, e.g., "Morning Dose_2024-07-26"
    return '${medName}_${now.year}-${now.month}-${now.day}';
  }

  void _cycleTheme() async {
    final newThemeMode =
        widget.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    widget.onThemeChanged(newThemeMode);

    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('themeMode', newThemeMode.index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Transform.scale(
              scale: 1.2, // Increase the size by 20%
              child: Switch(
                value: widget.themeMode == ThemeMode.dark,
                onChanged: (isDark) => _cycleTheme(),
                thumbIcon: MaterialStateProperty.resolveWith<Icon?>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.selected)) {
                      return const Icon(Icons.nightlight_round);
                    }
                    return const Icon(Icons.wb_sunny_outlined);
                  },
                ),
              ),
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Today's Doses",
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._medications.map((med) => _buildMedicationCard(med)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          NotificationService.instance.showTestNotification();
        },
        child: const Icon(Icons.notification_add),
      ),
    );
  }

  Widget _buildMedicationCard(Medication medication) {
    final theme = Theme.of(context);
    final bool isTaken = medication.isTaken;

    return Card(
      elevation: 2.0,
      color: isTaken ? theme.colorScheme.primaryContainer : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: isTaken
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isTaken ? 2.0 : 1.0,
        ),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(15.0),
        onTap: () => _toggleMedication(medication),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(medication.icon, size: 30, color: theme.colorScheme.primary),
              const SizedBox(width: 20),
              Expanded(
                  // This will take up the space and push the switch to the end
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medication.name,
                    style: theme.textTheme.titleLarge,
                  ),
                  GestureDetector(
                    onTap: () => _selectTime(context, medication),
                    child: Text(
                      medication.reminderTime == null
                          ? 'Set reminder'
                          : 'Reminder at: ${medication.reminderTime!.format(context)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.secondary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              )),
              FaIcon(
                FontAwesomeIcons.pills,
                size: 40,
                color:
                    isTaken ? theme.colorScheme.primary : theme.disabledColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
