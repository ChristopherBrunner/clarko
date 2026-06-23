import 'package:flutter/material.dart';

import '../models/dose.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final doses = state.doses;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            // Distinct from the branded "Clarko" home header: a lighter surface
            // bar with a primary-tinted title, reading clearly as a sub-screen.
            backgroundColor: theme.colorScheme.surface,
            foregroundColor: theme.colorScheme.primary,
            surfaceTintColor: theme.colorScheme.surfaceTint,
            elevation: 0,
            scrolledUnderElevation: 3,
            titleSpacing: 0,
            title: Row(
              children: [
                Icon(Icons.event_note_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Schedule',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.favorite_rounded),
                color: theme.colorScheme.error,
                tooltip: 'A little something',
                onPressed: () => _showEasterEgg(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final dose in doses)
                _DoseEditor(
                  dose: dose,
                  onChanged: state.updateDose,
                  onRemove: doses.length > 1
                      ? () => state.removeDose(dose)
                      : null,
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addDose(context),
            icon: const Icon(Icons.add),
            label: const Text('Add dose'),
          ),
        );
      },
    );
  }

  void _showEasterEgg(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Image.asset(
            'assets/minion.gif',
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }

  void _addDose(BuildContext context) {
    final id = 'dose_${DateTime.now().millisecondsSinceEpoch}';
    state.addDose(Dose(
      id: id,
      label: 'New dose',
      hour: 12,
      minute: 0,
      tablets: [500],
    ));
  }
}

class _DoseEditor extends StatelessWidget {
  const _DoseEditor({
    required this.dose,
    required this.onChanged,
    this.onRemove,
  });

  final Dose dose;
  final ValueChanged<Dose> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: dose.label,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        onChanged(dose.copyWith(label: value)),
                  ),
                ),
                const SizedBox(width: 16),
                Switch(
                  value: dose.enabled,
                  onChanged: (value) =>
                      onChanged(dose.copyWith(enabled: value)),
                ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove dose',
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.schedule, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Reminder', style: theme.textTheme.bodyLarge),
                const Spacer(),
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: dose.time,
                    );
                    if (picked != null) {
                      onChanged(dose.copyWith(
                          hour: picked.hour, minute: picked.minute));
                    }
                  },
                  child: Text(dose.time.format(context)),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.medication_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Tablets', style: theme.textTheme.bodyLarge),
                const Spacer(),
                Text(
                  '${dose.totalMg}mg total',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < dose.tablets.length; i++)
                  InputChip(
                    label: Text('${dose.tablets[i]}mg'),
                    onDeleted: () {
                      final tablets = List<int>.from(dose.tablets)..removeAt(i);
                      onChanged(dose.copyWith(tablets: tablets));
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add tablet'),
                  onPressed: () => _addTablet(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTablet(BuildContext context) async {
    final mg = await showDialog<int>(
      context: context,
      builder: (context) => const _TabletStrengthDialog(),
    );
    if (mg != null && mg > 0) {
      final tablets = List<int>.from(dose.tablets)..add(mg);
      onChanged(dose.copyWith(tablets: tablets));
    }
  }
}

/// Quick picker for a tablet strength, with common Levetiracetam presets.
class _TabletStrengthDialog extends StatefulWidget {
  const _TabletStrengthDialog();

  @override
  State<_TabletStrengthDialog> createState() => _TabletStrengthDialogState();
}

class _TabletStrengthDialogState extends State<_TabletStrengthDialog> {
  final _controller = TextEditingController();
  static const _presets = [250, 500, 750, 1000];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tablet strength'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final mg in _presets)
                ActionChip(
                  label: Text('${mg}mg'),
                  onPressed: () => Navigator.of(context).pop(mg),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Custom (mg)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = int.tryParse(_controller.text.trim());
            Navigator.of(context).pop(value);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
