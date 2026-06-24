import 'package:flutter/material.dart';

import '../models/dose.dart';

/// Editor card for a single [dose]. Edits are pushed back immediately via
/// [onChanged]. Used both inline and inside the home long-press edit sheet.
class DoseEditor extends StatelessWidget {
  const DoseEditor({
    super.key,
    required this.dose,
    required this.onChanged,
    this.onRemove,
    this.embedded = false,
  });

  final Dose dose;
  final ValueChanged<Dose> onChanged;
  final VoidCallback? onRemove;

  /// When true, renders flat (no surrounding Card) for use inside a sheet.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
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
                const SizedBox(width: 12),
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
        );

    if (embedded) return body;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(16), child: body),
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
