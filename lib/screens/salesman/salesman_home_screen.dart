import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/api_client.dart';
import '../../core/location_tracker.dart';
import '../../core/models.dart';
import '../../core/push_service.dart';
import '../../core/router.dart';
import '../../widgets/app_widgets.dart';
import '../notifications_screen.dart';
import 'address_card.dart';
import 'salesman_models.dart';
import 'salesman_service.dart';
import 'online_toggle.dart';
import 'salesman_merged_route_screen.dart';

/// Home screen for user_type = salesman.
/// Starts tracking, then lists the addresses (retailers) assigned by the
/// salesman leader from GET v1/salesman/addresses.
class SalesmanHomeScreen extends StatefulWidget {
  final Session session;
  const SalesmanHomeScreen({super.key, required this.session});

  @override
  State<SalesmanHomeScreen> createState() => _SalesmanHomeScreenState();
}

class _SalesmanHomeScreenState extends State<SalesmanHomeScreen>
    with WidgetsBindingObserver {
  static const int _pageSize = 20;

  final ScrollController _scroll = ScrollController();
  final List<SalesmanAddress> _items = [];

  int _page = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true; // first load
  bool _loadingMore = false;
  String? _error; // first-load error
  String? _moreError; // load-more error

  bool _merging = false;

  Session get session => widget.session;

  /// Merge Addresses: fetch ALL assigned addresses and open one combined
  /// route (current location -> every assigned shop).
  Future<void> _mergeAddresses() async {
    if (_merging) return;
    setState(() => _merging = true);
    try {
      final all = await SalesmanService.getAllAddresses();
      if (!mounted) return;
      final withPin = all.where((a) => a.hasLocation).toList();
      if (withPin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No assigned address has a map location.')));
        return;
      }
      if (withPin.length < all.length) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${all.length - withPin.length} address(es) skipped: no map location.')));
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SalesmanMergedRouteScreen(stops: withPin),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not merge addresses.')));
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  Widget _mergeButton() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: _merging ? null : _mergeAddresses,
            icon: _merging
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.alt_route),
            label: Text(_merging ? 'Merging...' : 'Merge Addresses'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green,
              textStyle:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      );

  /// Bottom nav "Logout": confirm -> LocationTracker.stop() (marks offline) -> login screen.
  Future<void> _confirmLogout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Do you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Logout')),
        ],
      ),
    );
    if (yes == true && mounted) await logoutAndGoToLogin(context);
  }

  /// Fixed bottom bar (outside the ListView => never scrolls).
  /// Only Logout for now; add more items to the Row later.
  Widget _bottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _confirmLogout,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, color: Color(0xFFDC3545), size: 24),
                      SizedBox(height: 2),
                      Text('Logout',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFDC3545))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.openPendingIfAny();
      _initTracking();
    });
    _load();
  }

  /// Permissions are asked up-front here. Tracking itself starts ONLY when
  /// the salesman turns the Online toggle on (or was already online earlier).
  Future<void> _initTracking() async {
    await LocationTracker.loadOnline();
    if (!mounted) return;
    await LocationTracker.requestPermissions(context);
    if (!mounted) return;
    await LocationTracker.resume(); // was online before -> keep service alive
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed) {
      LocationTracker.resume();
      // pick up new assignments silently when salesman comes back to the app
      if (!_loading && !_loadingMore) _load(silent: true);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  /// First page. [silent] keeps the old list on screen while refreshing.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = await SalesmanService.getAddresses(page: 1, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(p.addresses);
        _page = p.page;
        _total = p.total;
        _hasMore = p.hasMore;
        _loading = false;
        _error = null;
        _moreError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // silent refresh failing should not wipe a good list
      if (silent && _items.isNotEmpty) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      if (silent && _items.isNotEmpty) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final p =
          await SalesmanService.getAddresses(page: _page + 1, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(p.addresses);
        _page = p.page;
        _total = p.total;
        _hasMore = p.hasMore && p.addresses.isNotEmpty;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreError = e is ApiException ? e.message : 'Could not load more.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogoImage(size: 32, radius: 8),
            SizedBox(width: 10),
            Text('Ozie',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
          ],
        ),
        actions: [
          const OnlineToggle(),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Notifications',
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedNotification01,
              color: AppColors.text,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const NotificationsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _greeting(),
            const SizedBox(height: 20),
            _sectionTitle(),
            const SizedBox(height: 10),
            ..._body(),
          ],
        ),
      ),
    );
  }

  Widget _greeting() {
    final u = session.user;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [AppColors.green, AppColors.blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hello, ${u.displayName}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            _loading ? 'Loading your assigned addresses...' : '$_total address${_total == 1 ? '' : 'es'} assigned to you',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle() => const Text('Assigned Addresses',
      style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text));

  List<Widget> _body() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        _message(
          icon: Icons.cloud_off_outlined,
          text: _error!,
          actionLabel: 'Retry',
          onAction: _load,
        ),
      ];
    }
    if (_items.isEmpty) {
      return [
        _message(
          icon: Icons.inbox_outlined,
          text:
              'No address assigned yet.\nYour salesman leader will assign addresses to you.',
          actionLabel: 'Refresh',
          onAction: _load,
        ),
      ];
    }
    return [
      _mergeButton(),
      for (var i = 0; i < _items.length; i++)
        AddressCard(item: _items[i], index: i + 1),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        ),
      if (_moreError != null)
        _message(
          icon: Icons.error_outline,
          text: _moreError!,
          actionLabel: 'Try again',
          onAction: _loadMore,
        ),
    ];
  }

  Widget _message({
    required IconData icon,
    required String text,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 44, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, height: 1.4, color: AppColors.muted)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}