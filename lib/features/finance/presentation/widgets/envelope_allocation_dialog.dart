import 'package:flutter/material.dart';

import '../../../envelopes/application/providers/remote_envelopes_provider.dart';

class EnvelopeAllocationResult {
  const EnvelopeAllocationResult(this.allocations, {required this.noImpact});
  final List<Map<String, Object?>> allocations;
  final bool noImpact;
}

class EnvelopeAllocationDialog extends StatefulWidget {
  const EnvelopeAllocationDialog({
    super.key,
    required this.amountCents,
    required this.envelopes,
    this.allowNoImpact = false,
  });
  final int amountCents;
  final List<RemoteEnvelopeBalance> envelopes;
  final bool allowNoImpact;
  @override
  State<EnvelopeAllocationDialog> createState() =>
      _EnvelopeAllocationDialogState();
}

class _Line {
  _Line();
  String? envelopeId;
  final amount = TextEditingController();
  void dispose() => amount.dispose();
}

class _EnvelopeAllocationDialogState extends State<EnvelopeAllocationDialog> {
  final _lines = <_Line>[];
  bool _noImpact = false;
  @override
  void initState() {
    super.initState();
    _lines.add(_Line());
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int? _cents(String value) {
    final n = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(n)) return null;
    final p = n.split('.');
    return int.parse(p[0]) * 100 +
        (p.length == 1 ? 0 : int.parse(p[1].padRight(2, '0')));
  }

  int get _total => _lines.fold(0, (s, l) => s + (_cents(l.amount.text) ?? 0));
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Répartir sur les enveloppes'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Montant à affecter : ${(widget.amountCents / 100).toStringAsFixed(2)} MAD',
            ),
            if (widget.allowNoImpact)
              SwitchListTile(
                key: const Key('no-envelope-impact'),
                title: const Text(
                  'Aucun impact supplémentaire sur les enveloppes',
                ),
                value: _noImpact,
                onChanged: (v) => setState(() => _noImpact = v),
              ),
            if (!_noImpact) ...[
              for (var i = 0; i < _lines.length; i++)
                Row(
                  key: ValueKey('allocation-$i'),
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _lines[i].envelopeId,
                        decoration: const InputDecoration(
                          labelText: 'Enveloppe',
                        ),
                        items: widget.envelopes
                            .where((e) => !e.isArchived)
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(e.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _lines[i].envelopeId = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 145,
                      child: TextField(
                        controller: _lines[i].amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Montant (MAD)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      onPressed: _lines.length == 1
                          ? null
                          : () {
                              setState(() {
                                _lines.removeAt(i).dispose();
                              });
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _lines.add(_Line())),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une enveloppe'),
                ),
              ),
              Text('Total affecté : ${(_total / 100).toStringAsFixed(2)} MAD'),
              Text(
                'Reste à affecter : ${((widget.amountCents - _total) / 100).toStringAsFixed(2)} MAD',
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed:
            (_noImpact ||
                (_total == widget.amountCents &&
                    _lines.every(
                      (l) =>
                          l.envelopeId != null &&
                          (_cents(l.amount.text) ?? 0) > 0,
                    )))
            ? () {
                Navigator.pop(
                  context,
                  EnvelopeAllocationResult(
                    _noImpact
                        ? const []
                        : [
                            for (final l in _lines)
                              {
                                'envelope_id': l.envelopeId!,
                                'amount': ((_cents(l.amount.text)!) / 100)
                                    .toStringAsFixed(2),
                              },
                          ],
                    noImpact: _noImpact,
                  ),
                );
              }
            : null,
        child: const Text('Confirmer'),
      ),
    ],
  );
}
