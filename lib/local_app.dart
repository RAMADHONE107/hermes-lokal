// Hermes Lokal: a minimal UI that talks straight to the embedded engine.
//
// There is deliberately no gateway address, sign-in, NextGen or Classic mode
// here. The engine runs in this app's private storage and listens on loopback;
// the API key comes from the native side. Everything else is chat.
import 'dart:async';

import 'package:flutter/material.dart';

import 'core/local_engine.dart';
import 'core/local_hermes.dart';
import 'core/services/connection_manager.dart';
import 'core/theme/hermes_theme.dart';
import 'local_app/chat_page.dart';

void runLocalHermesApp() => runApp(const LocalHermesApp());

class LocalHermesApp extends StatefulWidget {
  const LocalHermesApp({super.key});

  @override
  State<LocalHermesApp> createState() => _LocalHermesAppState();
}

class _LocalHermesAppState extends State<LocalHermesApp> {
  ApiClient? _api;
  String? _error;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final key = await LocalEngineClient.instance.apiKey();
      final api = ApiClient(
        baseUrl: 'http://${LocalHermes.host}:${LocalHermes.port}',
        apiKey: key,
      );
      if (!mounted) {
        api.close();
        return;
      }
      setState(() {
        _api = api;
        _booting = false;
      });
      // The first launch downloads and extracts the runtime. Keep that off the
      // UI path: chat simply reports "not ready" until the engine comes up.
      unawaited(
        LocalEngineClient.instance
            .prepare()
            .then((_) => LocalEngineClient.instance.start())
            .catchError((Object _) {}),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _booting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hermes Lokal',
      theme: hermesTheme(Brightness.light),
      darkTheme: hermesTheme(Brightness.dark),
      home: _booting
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _error != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Mesin lokal gagal disiapkan: $_error',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          : LocalHomePage(api: _api!),
    );
  }
}

class LocalHomePage extends StatefulWidget {
  const LocalHomePage({super.key, required this.api});

  final ApiClient api;

  @override
  State<LocalHomePage> createState() => _LocalHomePageState();
}

class _LocalHomePageState extends State<LocalHomePage> {
  List<Session> _sessions = const [];
  List<String> _models = const [];
  bool _loading = true;
  String? _error;
  StreamSubscription<LocalEngineStatus>? _engineStatus;
  LocalEngineState? _lastEngineState;

  @override
  void initState() {
    super.initState();
    // On a fresh install the runtime is still downloading/extracting. Retry
    // on the transition to running, not on every progress event.
    _engineStatus = LocalEngineClient.instance.status.listen((status) {
      final wasRunning = _lastEngineState == LocalEngineState.running;
      _lastEngineState = status.state;
      if (!wasRunning && status.state == LocalEngineState.running) {
        unawaited(_reload());
      }
    });
    unawaited(_reload());
  }

  @override
  void dispose() {
    _engineStatus?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await widget.api.getSessions();
      final models = await widget.api.getModels();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _models = models;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Mesin lokal belum siap. Sedang menunggu runtime…';
          _loading = false;
        });
      }
    }
  }

  void _openChat({String? sessionId, String title = 'Chat baru'}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalChatPage(
          api: widget.api,
          sessionId: sessionId ?? GatewayChatClient.generateSessionId(),
          title: title,
          models: _models,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hermes Lokal'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => unawaited(_reload()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          const EngineStatusCard(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Gagal memuat sesi: $_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Belum ada percakapan',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tekan + untuk mulai ngobrol dengan Hermes.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _sessions.length,
                    itemBuilder: (context, i) {
                      final session = _sessions[i];
                      return ListTile(
                        leading: const Icon(Icons.forum_outlined),
                        title: Text(
                          session.title.isEmpty ? 'Tanpa judul' : session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          session.preview.isEmpty
                              ? '${session.messageCount} pesan'
                              : session.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openChat(
                          sessionId: session.id,
                          title: session.title.isEmpty
                              ? 'Percakapan'
                              : session.title,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Chat baru',
        onPressed: () => _openChat(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class EngineStatusCard extends StatefulWidget {
  const EngineStatusCard({super.key, this.client});

  final LocalEngineClient? client;

  @override
  State<EngineStatusCard> createState() => _EngineStatusCardState();
}

class _EngineStatusCardState extends State<EngineStatusCard> {
  late final LocalEngineClient _client;
  StreamSubscription<LocalEngineStatus>? _subscription;
  LocalEngineStatus? _status;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? LocalEngineClient.instance;
    _subscription = _client.status.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final status = await _client.currentStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // The status card is informational; chat works as soon as the gateway
      // answers, regardless of what the native side reports here.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Buttons are a convenience; startup already auto-prepares and starts
      // the engine.
    }
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final theme = Theme.of(context);
    final state = status?.state ?? LocalEngineState.absent;
    final busy = state.isBusy;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state == LocalEngineState.running
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: state == LocalEngineState.running
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mesin lokal · ${state.label}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (status?.version != null)
                  Text(status!.version!, style: theme.textTheme.bodySmall),
              ],
            ),
            if (status?.message.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(status!.message, style: theme.textTheme.bodySmall),
            ],
            if (busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: (status?.progress ?? 0) / 100.0),
            ],
            const SizedBox(height: 8),
            Text(
              '${LocalHermes.host}:${LocalHermes.port} · berjalan di dalam aplikasi ini',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => unawaited(_run(_client.prepare)),
                  child: const Text('Siapkan'),
                ),
                TextButton(
                  onPressed: busy ? null : () => unawaited(_run(_client.start)),
                  child: const Text('Mulai'),
                ),
                TextButton(
                  onPressed: busy ? null : () => unawaited(_run(_client.stop)),
                  child: const Text('Setop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
