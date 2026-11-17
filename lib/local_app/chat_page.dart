// A single chat against the embedded Hermes engine. Uses the classic REST/SSE
// endpoint directly with the app's local API key — no gateway address, no
// dashboard sign-in and no interface mode.
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services/connection_manager.dart';
import '../core/utils/message_content.dart';

class _ChatMessage {
  _ChatMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class LocalChatPage extends StatefulWidget {
  const LocalChatPage({
    super.key,
    required this.api,
    required this.sessionId,
    required this.title,
    required this.models,
  });

  final ApiClient api;
  final String sessionId;
  final String title;
  final List<String> models;

  @override
  State<LocalChatPage> createState() => _LocalChatPageState();
}

class _LocalChatPageState extends State<LocalChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  late final GatewayChatClient _chat;
  String? _model;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _model = widget.models.isEmpty ? null : widget.models.first;
    _chat = GatewayChatClient(widget.api);
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await widget.api.getMessages(widget.sessionId, latest: true);
      final loaded = <_ChatMessage>[];
      for (final row in rows) {
        final role = (row['role']?.toString() ?? '').toLowerCase();
        if (role != 'user' && role != 'assistant') continue;
        loaded.add(
          _ChatMessage(
            role: role,
            content: messageContentToText(row['content']),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _messages.addAll(loaded);
        _loading = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Riwayat tidak dapat dimuat: $error';
          _loading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    final history = _messages
        .map((m) => <String, dynamic>{'role': m.role, 'content': m.content})
        .toList();
    setState(() {
      _sending = true;
      _error = null;
      _messages.add(_ChatMessage(role: 'user', content: text));
      _messages.add(_ChatMessage(role: 'assistant', content: ''));
      _input.clear();
    });
    _scrollToBottom();
    final answerIndex = _messages.length - 1;

    void append(String token) {
      if (!mounted) return;
      setState(() {
        final current = _messages[answerIndex];
        _messages[answerIndex] = _ChatMessage(
          role: 'assistant',
          content: current.content + token,
        );
      });
      _scrollToBottom();
    }

    void finish({String? error}) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (error != null) {
          _messages[answerIndex] = _ChatMessage(
            role: 'assistant',
            content: 'Error: $error',
          );
        }
      });
      _scrollToBottom();
    }

    try {
      await _chat.sendMessageStreaming(
        message: text,
        sessionId: widget.sessionId,
        model: _model,
        history: history,
        onToken: append,
        onDone: () => finish(),
        onError: (error) => finish(error: error),
      );
    } catch (error) {
      finish(error: '$error');
    }
  }

  @override
  void dispose() {
    _chat.abort();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.models.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButton<String>(
                value: _model,
                underline: const SizedBox(),
                items: [
                  for (final model in widget.models)
                    DropdownMenuItem<String>(value: model, child: Text(model)),
                ],
                onChanged: _sending
                    ? null
                    : (value) => setState(() => _model = value),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.all(10),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      'Tulis pesan pertama untuk mulai ngobrol.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final message = _messages[i];
                      final isUser = message.role == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                          ),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            message.content.isEmpty &&
                                    _sending &&
                                    i == _messages.length - 1
                                ? 'Hermes sedang menjawab…'
                                : message.content,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Tulis pesan…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => unawaited(_send()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => unawaited(_send()),
                    icon: const Icon(Icons.send),
                    tooltip: 'Kirim',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
