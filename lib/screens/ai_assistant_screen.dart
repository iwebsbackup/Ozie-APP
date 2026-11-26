import 'package:flutter/material.dart';

import '../core/ai_assistant_service.dart';
import '../core/api_client.dart';
import '../widgets/ai_assistant_fab.dart';
import '../widgets/app_widgets.dart';

/// "AI Business Assistant" chat. API: POST v1/retailer/ai-assistant.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _ChatMsg {
  final String text;
  final bool fromUser;
  final bool error;
  const _ChatMsg(this.text, {required this.fromUser, this.error = false});
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  static const String _greeting =
      "Hi! I'm your **AI Business Assistant**. Ask me how to use Ozie: "
      'orders, invoices, payments, returns, dispatch and more.';

  static const List<String> _suggestions = [
    'How do I place an order?',
    'How do I download an invoice?',
    'How do I raise a return claim?',
    'How do I apply for a finance facility?',
    'How do I raise a support ticket?',
    'Where can I see dispatch history?',
  ];

  /// Kept while the app is open, so the chat is still there on re-open.
  static final List<_ChatMsg> _history = [];

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _showChips = true;

  @override
  void initState() {
    super.initState();
    AiAssistantFab.setAssistantOpen(true);
    _showChips = _history.where((m) => m.fromUser).isEmpty;
  }

  @override
  void dispose() {
    AiAssistantFab.setAssistantOpen(false);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _ctrl.text).trim();
    if (q.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    _ctrl.clear();
    setState(() {
      _history.add(_ChatMsg(q, fromUser: true));
      _sending = true;
      _showChips = false;
    });
    _toBottom();
    try {
      final r = await AiAssistantService.ask(q);
      if (!mounted) return;
      setState(() {
        _history.add(_ChatMsg(r.text, fromUser: false));
        _showChips = r.showSuggestions;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _history.add(_ChatMsg(e.message, fromUser: false, error: true)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _history.add(const _ChatMsg(
          'Could not reach the assistant. Please try again.',
          fromUser: false,
          error: true)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    // greeting + history (+ typing bubble)
    final itemCount = 1 + _history.length + (_sending ? 1 : 0);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.text),
        titleSpacing: 0,
        title: const Row(
          children: [
            ClipOval(
              child: Image(
                image: AssetImage('assets/images/robot_logo.png'),
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'AI Business Assistant',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                itemCount: itemCount,
                itemBuilder: (_, i) {
                  if (i == 0) return _bubble(const _ChatMsg(_greeting, fromUser: false));
                  final idx = i - 1;
                  if (idx < _history.length) return _bubble(_history[idx]);
                  return _typing();
                },
              ),
            ),
            if (_showChips && !_sending) _chips(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _chips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in _suggestions)
            ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 12.5)),
              backgroundColor: AppColors.card,
              side: const BorderSide(color: AppColors.border),
              labelStyle: const TextStyle(
                  color: AppColors.blue, fontWeight: FontWeight.w600),
              onPressed: () => _send(s),
            ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: inputDecoration(hint: 'Ask about Ozie...')
                  .copyWith(counterText: ''),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _sending ? AppColors.muted : AppColors.blue,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sending ? null : _send,
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typing() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Thinking...',
                style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_ChatMsg m) {
    final maxW = MediaQuery.of(context).size.width * 0.82;
    final bg = m.fromUser
        ? AppColors.blue
        : (m.error ? AppColors.dangerBg : AppColors.card);
    final fg = m.fromUser
        ? Colors.white
        : (m.error ? AppColors.dangerText : AppColors.text);
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(m.fromUser ? 14 : 4),
            bottomRight: Radius.circular(m.fromUser ? 4 : 14),
          ),
          border: m.fromUser ? null : Border.all(color: AppColors.border),
        ),
        child: m.fromUser
            ? Text(m.text,
                style: TextStyle(fontSize: 14, height: 1.4, color: fg))
            : _MiniMarkdown(text: m.text, color: fg),
      ),
    );
  }
}

/// Small markdown view: # headings, 1. / - lists, **bold**.
class _MiniMarkdown extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniMarkdown({required this.text, required this.color});

  static final _bold = RegExp(r'\*\*(.+?)\*\*');
  static final _num = RegExp(r'^(\d+)[.)]\s+(.*)$');
  static final _bullet = RegExp(r'^[-*•]\s+(.*)$');
  static final _head = RegExp(r'^#{1,4}\s+(.*)$');

  TextSpan _inline(String s, TextStyle base) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _bold.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return TextSpan(style: base, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: 14, height: 1.45, color: color);
    final out = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        out.add(const SizedBox(height: 6));
        continue;
      }
      final h = _head.firstMatch(line.trim());
      if (h != null) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(_inline(
            h.group(1)!,
            base.copyWith(fontSize: 15.5, fontWeight: FontWeight.w800),
          )),
        ));
        continue;
      }
      final n = _num.firstMatch(line.trim());
      final b = _bullet.firstMatch(line.trim());
      if (n != null || b != null) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(n != null ? '${n.group(1)}.' : '•', style: base),
              ),
              Expanded(
                child: Text.rich(_inline(n != null ? n.group(2)! : b!.group(1)!, base)),
              ),
            ],
          ),
        ));
        continue;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text.rich(_inline(line.trim(), base)),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: out,
    );
  }
}