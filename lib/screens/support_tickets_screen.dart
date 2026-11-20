import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/retailer_service.dart';
import '../core/support_models.dart';
import '../widgets/app_widgets.dart';
import 'support_ticket_form_screen.dart';

/// Retailer support tickets. List + filter + detail sheet + rating.
/// API: GET/POST v1/retailer/support-tickets.
/// Header / body layout follows Invoices screen (blue bar, pills, rounded sheet).
/// Status colors are screen-local on purpose.

// ---- screen-local palette ----
const Color _tIndigo = Color(0xFF4F46E5); // accent / ticket no. / FAB
const Color _tOrange = Color(0xFFF97316); // open
const Color _tSky = Color(0xFF0EA5E9); // in progress
const Color _tMint = Color(0xFF10B981); // solved
const Color _tRed = Color(0xFFEF4444); // negative feedback
const Color _tHeader = Color(0xFF4F46E5); // top header + pills (change here)

Color _statusColor(SupportTicket t) {
  if (t.isSolved) return _tMint;
  if (t.isOpen) return _tOrange;
  return _tSky;
}

String _statusText(SupportTicket t) =>
    t.status.isEmpty ? 'Open' : t.status;

IconData _typeIcon(String type) {
  final s = type.toLowerCase();
  if (s.contains('order')) return Icons.shopping_bag_outlined;
  if (s.contains('payment')) return Icons.payments_outlined;
  if (s.contains('delivery')) return Icons.local_shipping_outlined;
  if (s.contains('product')) return Icons.inventory_2_outlined;
  if (s.contains('return') || s.contains('refund')) {
    return Icons.assignment_return_outlined;
  }
  if (s.contains('account') || s.contains('profile')) {
    return Icons.person_outline_rounded;
  }
  if (s.contains('app')) return Icons.phone_android_rounded;
  return Icons.support_agent_outlined;
}

class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  static const List<String> _filters = ['All', 'Open', 'In Progress', 'Solved'];

  final List<SupportTicket> _items = [];
  String _filter = 'All';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await RetailerService.getSupportTickets();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.tickets);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  List<SupportTicket> get _visible {
    switch (_filter) {
      case 'Open':
        return _items.where((t) => t.isOpen).toList();
      case 'In Progress':
        return _items.where((t) => t.isInProgress).toList();
      case 'Solved':
        return _items.where((t) => t.isSolved).toList();
      default:
        return _items;
    }
  }

  int _count(String f) {
    switch (f) {
      case 'Open':
        return _items.where((t) => t.isOpen).length;
      case 'In Progress':
        return _items.where((t) => t.isInProgress).length;
      case 'Solved':
        return _items.where((t) => t.isSolved).length;
      default:
        return _items.length;
    }
  }

  Future<void> _newTicket() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const SupportTicketFormScreen()),
    );
    if (created == true && mounted) _load();
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showStatus(context, 'Could not open file.', error: true);
    }
  }

  Future<void> _rate(SupportTicket t, String rating) async {
    try {
      await RetailerService.rateSupportTicket(ticketId: t.id, rating: rating);
      if (!mounted) return;
      final i = _items.indexWhere((x) => x.id == t.id);
      if (i >= 0) setState(() => _items[i] = t.copyWithRating(rating));
      showStatus(context, 'Thanks for your feedback.');
    } on ApiException catch (e) {
      if (!mounted) return;
      showStatus(context, e.message, error: true);
    }
  }

  void _openDetail(SupportTicket t) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TicketDetailSheet(
        ticket: t,
        onOpenUrl: _openUrl,
        onRate: (r) async {
          Navigator.of(ctx).pop();
          await _rate(t, r);
        },
      ),
    );
  }

  // ---------- shell ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _tHeader,
      appBar: AppBar(
        title: const Text('My Tickets'),
        backgroundColor: _tHeader,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: Colors.white,
            strokeWidth: 1.5,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTicket,
        backgroundColor: _tIndigo,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Ticket',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _filterStrip(),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  /// Blue strip, same pill style as Invoices (selected = white).
  Widget _filterStrip() {
    return Container(
      color: _tHeader,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final f = _filters[i];
            return _pill(
              '$f (${_count(f)})',
              _filter == f,
              onTap: () {
                if (_filter == f) return;
                setState(() => _filter = f);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.dangerText),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final list = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: list.isEmpty
          ? _emptyState()
          : ListView.separated(
              key: PageStorageKey<String>('tickets-$_filter'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              itemCount: list.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, idx) {
                if (idx == 0) return _countHeader(list.length);
                final i = idx - 1;
                final t = list[i];
                return _AppearIn(
                  key: ValueKey('${_filter}_${t.id}'),
                  delay: Duration(milliseconds: math.min(i, 6) * 45),
                  child: _card(t),
                );
              },
            ),
    );
  }

  Widget _countHeader(int n) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _filter == 'All' ? 'Tickets' : _filter,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.text,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: _tIndigo.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$n',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _tIndigo,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        const SizedBox(height: 90),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: _tIndigo.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded,
                size: 42, color: _tIndigo),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            _filter == 'All' ? 'No tickets yet' : 'No $_filter tickets',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Need help? Raise a ticket and our team will get back to you.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
          ),
        ),
        if (_filter == 'All') ...[
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: _newTicket,
              style: FilledButton.styleFrom(
                backgroundColor: _tIndigo,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create ticket'),
            ),
          ),
        ],
      ],
    );
  }

  // ---------- card ----------

  Widget _card(SupportTicket t) {
    final c = _statusColor(t);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border.withOpacity(0.8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDetail(t),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: c),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _tIndigo.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(_typeIcon(t.ticketType),
                                  size: 18, color: _tIndigo),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.ticketNumber,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.1,
                                      color: _tIndigo,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    t.ticketType,
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.muted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(ticket: t),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.subject,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (t.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            t.description,
                            style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: AppColors.muted),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.event_outlined,
                                size: 14, color: AppColors.muted),
                            const SizedBox(width: 6),
                            Text(
                              formatDate(t.createdAt),
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted),
                            ),
                            const Spacer(),
                            if (t.hasRating)
                              Icon(
                                t.satisfactionRating == 'satisfied'
                                    ? Icons.thumb_up_alt_rounded
                                    : Icons.thumb_down_alt_rounded,
                                size: 15,
                                color: t.satisfactionRating == 'satisfied'
                                    ? _tMint
                                    : _tRed,
                              )
                            else
                              const Icon(Icons.chevron_right_rounded,
                                  size: 20, color: AppColors.muted),
                          ],
                        ),
                        if (t.canRate) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _tMint.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.rate_review_outlined,
                                    size: 15, color: _tMint),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Solved · tap to give feedback',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF047857),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill chip, same look as Invoices (on blue: selected fills white).
Widget _pill(String label, bool selected, {required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
            color: selected ? Colors.white : Colors.white.withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? _tHeader : Colors.white,
        ),
      ),
    ),
  );
}

/// Fade + slide-up entrance, plays once per item.
class _AppearIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _AppearIn({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<_AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<_AppearIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _a.value) * 16),
          child: child,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SupportTicket ticket;
  const _StatusBadge({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(ticket);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _statusText(ticket),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ticket.isSolved
                  ? const Color(0xFF047857)
                  : (ticket.isOpen
                      ? const Color(0xFFC2410C)
                      : const Color(0xFF0369A1)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketDetailSheet extends StatelessWidget {
  final SupportTicket ticket;
  final Future<void> Function(String url) onOpenUrl;
  final void Function(String rating) onRate;

  const _TicketDetailSheet({
    required this.ticket,
    required this.onOpenUrl,
    required this.onRate,
  });

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          s.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _block(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withOpacity(0.7)),
        ),
        child: child,
      );

  Widget _fileLink(String label, String url, Color c) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton.icon(
          onPressed: () => onOpenUrl(url),
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: c,
            side: BorderSide(color: c.withOpacity(0.5)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final sc = _statusColor(t);
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _tIndigo.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_typeIcon(t.ticketType),
                    size: 22, color: _tIndigo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.ticketNumber,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: _tIndigo,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.ticketType}  •  ${formatDate(t.createdAt)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              _StatusBadge(ticket: t),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 3,
            margin: const EdgeInsets.only(top: 14, bottom: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [sc, sc.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          _label('Subject'),
          Text(t.subject,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text)),
          const SizedBox(height: 16),
          _label('Description'),
          _block(Text(t.description,
              style: const TextStyle(
                  fontSize: 14, height: 1.45, color: AppColors.text))),
          if (t.attachmentUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            _label('Your attachment'),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                t.attachmentUrl,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            _fileLink('Open attachment', t.attachmentUrl, _tIndigo),
          ],
          if (t.solutionComment.isNotEmpty || t.solutionDocUrl.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _tMint.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _tMint.withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 18, color: _tMint),
                      SizedBox(width: 8),
                      Text(
                        'Solution',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                  if (t.solutionComment.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(t.solutionComment,
                        style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: AppColors.text)),
                  ],
                  if (t.solvedBy.isNotEmpty || t.solvedAt.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (t.solvedBy.isNotEmpty) 'By ${t.solvedBy}',
                        if (t.solvedAt.isNotEmpty) formatDate(t.solvedAt),
                      ].join('  •  '),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF047857)),
                    ),
                  ],
                  if (t.solutionDocUrl.isNotEmpty)
                    _fileLink('Open solution document', t.solutionDocUrl,
                        const Color(0xFF047857)),
                ],
              ),
            ),
          ],
          if (t.hasRating) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (t.satisfactionRating == 'satisfied' ? _tMint : _tRed)
                    .withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    t.satisfactionRating == 'satisfied'
                        ? Icons.thumb_up_alt_rounded
                        : Icons.thumb_down_alt_rounded,
                    size: 18,
                    color: t.satisfactionRating == 'satisfied'
                        ? _tMint
                        : _tRed,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    t.satisfactionRating == 'satisfied'
                        ? 'You marked: Satisfied'
                        : 'You marked: Not satisfied',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text),
                  ),
                ],
              ),
            ),
          ],
          if (t.canRate) ...[
            const SizedBox(height: 22),
            const Text(
              'Was your issue solved?',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onRate('unsatisfied'),
                    icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                    label: const Text('Not satisfied'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _tRed,
                      side: BorderSide(color: _tRed.withOpacity(0.5)),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onRate('satisfied'),
                    icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                    label: const Text('Satisfied'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _tMint,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}