import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/scoreboard_provider.dart';

class ScoreboardEditor extends ConsumerStatefulWidget {
  const ScoreboardEditor({super.key, this.onSave});
  final Future<void> Function(Map<String, dynamic>)? onSave;
  @override
  ConsumerState<ScoreboardEditor> createState() => _ScoreboardEditorState();
}

class _ScoreboardEditorState extends ConsumerState<ScoreboardEditor> {
  final _form = GlobalKey<FormState>();
  late Map<String, TextEditingController> _fields;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _fields = ref
        .read(scoreboardProvider)
        .map((k, v) => MapEntry(k, TextEditingController(text: v.toString())));
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final score = <String, dynamic>{
      for (final entry in _fields.entries) entry.key: entry.value.text.trim(),
    };
    score['runs'] = int.parse(score['runs']);
    score['wickets'] = int.parse(score['wickets']);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave?.call(score);
      ref.read(scoreboardProvider.notifier).state = score;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Scoreboard saved')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _form,
        child: Column(
          children: [
            const Text('Scoreboard'),
            for (final key in _fields.keys)
              TextFormField(
                controller: _fields[key],
                decoration: InputDecoration(
                  labelText: const {
                    'teamA': 'Batting team',
                    'teamB': 'Opponent',
                    'runs': 'Runs',
                    'wickets': 'Wickets',
                    'overs': 'Overs (e.g. 12.3)',
                    'caption': 'Caption',
                  }[key],
                ),
                validator: (value) {
                  final s = (value ?? '').trim();
                  if (key == 'runs' || key == 'wickets') {
                    final n = int.tryParse(s);
                    if (n == null ||
                        n < 0 ||
                        n > (key == 'wickets' ? 10 : 9999)) {
                      return 'Enter a valid $key value';
                    }
                  } else if (key == 'overs') {
                    if (!RegExp(r'^\d{1,3}\.[0-5]$').hasMatch(s)) {
                      return 'Use completed overs and balls 0–5';
                    }
                  } else if ((key != 'caption' && s.isEmpty) ||
                      s.length > (key == 'caption' ? 60 : 24) ||
                      RegExp(r'[\x00-\x1f\x7f]').hasMatch(s)) {
                    return 'Enter a shorter single-line value';
                  }
                  return null;
                },
              ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save scoreboard'),
            ),
          ],
        ),
      ),
    ),
  );
}
