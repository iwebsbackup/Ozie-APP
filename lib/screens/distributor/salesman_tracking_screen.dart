import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../widgets/app_widgets.dart';
import 'distributor_models.dart';
import 'distributor_service.dart';
import 'salesman_track_map_screen.dart';

Color statusColor(String s) => switch (s) {
      'moving' => AppColors.successText,
      'stop' => const Color(0xFFB45309),
      _ => AppColors.muted,
    };

String statusLabel(String s) => switch (s) {
      'moving' => 'Moving',
      'stop' => 'Stopped',
      _ => 'Offline',
    };

/// Distributor -> View Reports: ONLINE salesmen only (moving / stopped).
/// Tap a salesman -> map with his tracking (day-wise).
class SalesmanTrackingScreen extends StatefulWidget {
  const SalesmanTrackingScreen({super.key});

  @override
  State<SalesmanTrackingScreen> createState() => _SalesmanTrackingScreenState();
}

class _SalesmanTrackingScreenState extends State<SalesmanTrackingScreen> {
  SalesmanListResult? _data;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final r = await DistributorService.getSalesmen();
      if (!mounted) return;
      setState(() {
        _data = r;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!silent || _data == null) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Widget _count(String label, int n, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: c.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: c)),
            Text(label, style: TextStyle(fontSize: 12, color: c)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Salesman Tracking'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(children: [
                        _count('Moving', d!.moving, AppColors.successText),
                        const SizedBox(width: 8),
                        _count('Stopped', d.stop, const Color(0xFFB45309)),
                      ]),
                      const SizedBox(height: 16),
                      if (d.salesmen.where((x) => x.isOnline).isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                              child: Text('No salesman online right now.',
                                  style: TextStyle(color: AppColors.muted))),
                        ),
                      for (final s in d.salesmen.where((x) => x.isOnline)) _tile(s),
                    ],
                  ),
                ),
    );
  }

  Widget _tile(SalesmanLive s) {
    final c = statusColor(s.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => SalesmanTrackMapScreen(salesman: s)),
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.blue.withOpacity(0.1),
          child: Text(
            s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
            style: const TextStyle(
                color: AppColors.blue, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(s.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.text)),
        subtitle: Text('Last active: ${s.lastActive}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(statusLabel(s.status),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ]),
      ),
    );
  }
}
