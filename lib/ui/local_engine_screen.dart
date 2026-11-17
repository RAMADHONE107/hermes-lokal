import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/local_engine.dart';
import '../core/local_hermes.dart';

/// Control panel for the Hermes engine embedded inside this APK.
class LocalEngineScreen extends StatefulWidget {
  const LocalEngineScreen({super.key, this.client});

  final LocalEngineClient? client;

  @override
  State<LocalEngineScreen> createState() => _LocalEngineScreenState();
}

class _LocalEngineScreenState extends State<LocalEngineScreen> {
  late final LocalEngineClient _client =
      widget.client ?? LocalEngineClient.instance;
  StreamSubscription<LocalEngineStatus>? _subscription;

  LocalEngineStatus _status = const LocalEngineStatus(
    state: LocalEngineState.absent,
    progress: 0,
    message: 'Memeriksa mesin…',
  );
  String _apiKey = '';
  String _log = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subscription = _client.status.listen(
      (status) {
        if (!mounted) return;
        setState(() => _status = status);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = error.toString());
      },
    );
    _refresh();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        _client.currentStatus(),
        _client.apiKey(),
        _client.logTail(),
      ]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as LocalEngineStatus;
        _apiKey = results[1] as String;
        _log = results[2] as String;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _status.state == LocalEngineState.running;
    final busy = _busy || _status.isBusy;
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Mesin Lokal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          running ? Icons.cloud_done : Icons.cloud_off,
                          color: running ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _status.state.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_status.message),
                    if (_status.version != null)
                      Text('Versi runtime: ${_status.version}'),
                    Text('${LocalHermes.host}:${LocalHermes.port}'),
                    if (busy) const LinearProgressIndicator(),
                    if (_status.progress > 0 && !running)
                      LinearProgressIndicator(value: _status.progress / 100),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(_client.prepare),
                  icon: const Icon(Icons.download),
                  label: const Text('Siapkan'),
                ),
                FilledButton.icon(
                  onPressed: busy || running
                      ? null
                      : () => _run(_client.start),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Mulai'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || !running
                      ? null
                      : () => _run(_client.stop),
                  icon: const Icon(Icons.stop),
                  label: const Text('Setop'),
                ),
                IconButton(
                  tooltip: 'Muat ulang',
                  onPressed: busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            ListTile(
              title: const Text('Kunci API lokal'),
              subtitle: Text(
                _apiKey.isEmpty
                    ? 'Belum dibuat'
                    : '${_apiKey.substring(0, 8)}… (disalin utuh saat ditekan)',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: _apiKey.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _apiKey));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kunci API disalin')),
                          );
                        }
                      },
              ),
            ),
            const SizedBox(height: 12),
            Text('Log mesin', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(_log.isEmpty ? 'Belum ada log.' : _log),
            ),
          ],
        ),
      ),
    );
  }
}
