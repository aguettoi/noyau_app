import 'package:flutter/material.dart';

import '../../../../core/localization/envelopes_locale.dart';

import '../../../envelopes/application/providers/remote_envelopes_provider.dart';

String _envelopeText(BuildContext context, String key) =>
    EnvelopesWords.of(context).text(key);
String _envelopeFormat(
  BuildContext context,
  String key,
  Map<String, Object> values,
) => EnvelopesWords.of(context).format(key, values);

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
    title: Text(_envelopeText(context, 'envelopes.allocation_title')),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _envelopeFormat(context, 'envelopes.amount_to_allocate', {
                'value': '${(widget.amountCents / 100).toStringAsFixed(2)} MAD',
              }),
            ),
            if (widget.allowNoImpact)
              SwitchListTile(
                key: const Key('no-envelope-impact'),
                title: Text(
                  _envelopeText(context, 'envelopes.no_additional_impact'),
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
                        decoration: InputDecoration(
                          labelText: _envelopeText(
                            context,
                            'envelopes.envelope',
                          ),
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
                        decoration: InputDecoration(
                          labelText: _envelopeText(context, 'envelopes.amount'),
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
                  label: Text(_envelopeText(context, 'envelopes.add_envelope')),
                ),
              ),
              Text(
                _envelopeFormat(context, 'envelopes.allocated_total', {
                  'value': '${(_total / 100).toStringAsFixed(2)} MAD',
                }),
              ),
              Text(
                _envelopeFormat(context, 'envelopes.remaining_to_allocate', {
                  'value':
                      '${((widget.amountCents - _total) / 100).toStringAsFixed(2)} MAD',
                }),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_envelopeText(context, 'envelopes.cancel')),
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
        child: Text(_envelopeText(context, 'envelopes.confirm')),
      ),
    ],
  );
}
