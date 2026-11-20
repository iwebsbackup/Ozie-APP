import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_widgets.dart';
import 'delivery_nav_screen.dart';
import 'test_models.dart';
import 'test_service.dart';
import 'test_widgets.dart';

/// Delivery boy flow: login (name + mobile) -> assigned orders -> map -> delivered.
/// Token lives only in memory, separate from the main app login.
class DeliveryBoyTestView extends StatefulWidget {
  /// Already logged in from the main login page (test mode).
  final DeliveryLoginResult? initialLogin;

  /// Called after Logout (standalone screen uses it to go back).
  final VoidCallback? onLoggedOut;
  const DeliveryBoyTestView({super.key, this.initialLogin, this.onLoggedOut});

  @override
  State<DeliveryBoyTestView> createState() => _DeliveryBoyTestViewState();
}

class _DeliveryBoyTestViewState extends State<DeliveryBoyTestView>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  DeliveryLoginResult? _login;
  bool _loggingIn = false;

  String _status = 'Assigned';
  bool _loading = false;
  String? _error;
  List<DeliveryOrder> _orders = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.initialLogin != null) {
      _login = widget.initialLogin;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _doLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loggingIn = true);
    try {
      final r = await TestService.deliveryLogin(
          _nameCtrl.text.trim(), _mobileCtrl.text.trim());
      if (!mounted) return;
      setState(() => _login = r);
      await _load();
    } catch (e) {
      if (mounted) testToast(context, testErr(e), error: true);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _logout() {
    setState(() {
      _login = null;
      _orders = [];
      _error = null;
      _status = 'Assigned';
    });
    widget.onLoggedOut?.call();
  }

  Future<void> _load() async {
    final l = _login;
    if (l == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await TestService.deliveryOrders(l.token, status: _status);
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = testErr(e);
      // Token expired -> back to login screen.
      if (e is Exception && msg.toLowerCase().contains('login')) {
        _logout();
        testToast(context, msg, error: true);
        return;
      }
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
  }

  bool _starting = false;

  /// Start Delivery -> GPS check -> tell server -> open live navigation screen.
  /// Already-started trips just reopen the screen ("Continue Delivery").
  Future<void> _startDelivery(DeliveryOrder o) async {
    final l = _login;
    if (l == null || _starting) return;
    setState(() => _starting = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Please enable Location Services (GPS).';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Location permission denied. Allow it in app settings.';
      }

      var order = o;
      if (!o.isStarted) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        await TestService.startDelivery(
            l.token, o.assignmentId, p.latitude, p.longitude);
        order = o.copyWithStatus('Started');
      }
      if (!mounted) return;
      final delivered = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
            builder: (_) => DeliveryNavScreen(token: l.token, order: order)),
      );
      if (!mounted) return;
      if (delivered == true) {
        testToast(context, 'Order #${o.orderNumber} delivered.');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        testToast(context, e is String ? e : testErr(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) testToast(context, 'Could not open.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _login == null ? _loginForm() : _ordersView();
  }

  Widget _loginForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TestCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivery boy login',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 4),
                const Text('Use the name & mobile the distributor created.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 14),
                LabeledField(
                  label: 'Name',
                  controller: _nameCtrl,
                  validator: requiredValidator,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Mobile number',
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10
                          ? 'Enter 10 digit mobile'
                          : null,
                  onSubmitted: (_) => _doLogin(),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Login',
                  loading: _loggingIn,
                  onPressed: _loggingIn ? null : _doLogin,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ordersView() {
    final l = _login!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Hi, ${l.name}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ),
              TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Logout'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: ['Assigned', 'Delivered']
                .map((s) => ChoiceChip(
                      label: Text(s),
                      selected: _status == s,
                      onSelected: (_) {
                        setState(() => _status = s);
                        _load();
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          if (_loading && _orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            TestError(_error!, onRetry: _load)
          else if (_orders.isEmpty)
            TestEmpty(_status == 'Assigned'
                ? 'No assigned orders.'
                : 'No delivered orders yet.')
          else
            ..._orders.map(_orderCard),
        ],
      ),
    );
  }

  Widget _orderCard(DeliveryOrder o) {
    final hasGps = o.lat != null && o.lng != null;
    return TestCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#${o.orderNumber}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ),
              TestStatusChip(o.deliveryStatus),
            ],
          ),
          const SizedBox(height: 6),
          const Text('RETAILER',
              style: TextStyle(
                  fontSize: 10, letterSpacing: 0.8, color: AppColors.muted)),
          TestLine(Icons.storefront_outlined, o.retailerName),
          TestLine(Icons.phone_outlined, o.retailerMobile),
          const SizedBox(height: 10),
          const Text('DELIVERY ADDRESS',
              style: TextStyle(
                  fontSize: 10, letterSpacing: 0.8, color: AppColors.muted)),
          TestLine(Icons.place_outlined, o.address),
          if (hasGps)
            TestLine(Icons.my_location,
                '${o.lat!.toStringAsFixed(6)}, ${o.lng!.toStringAsFixed(6)}'),
          const SizedBox(height: 10),
          const Text('PRODUCT',
              style: TextStyle(
                  fontSize: 10, letterSpacing: 0.8, color: AppColors.muted)),
          TestLine(Icons.inventory_2_outlined, o.productName),
          TestLine(Icons.sell_outlined,
              'Price ${formatInr(o.price)}  ×  Qty ${o.quantity}'),
          TestLine(Icons.currency_rupee, 'Total ${formatInr(o.total)}'),
          const SizedBox(height: 12),
          Row(
            children: [
              TestBtn('Open Map',
                  outlined: true, onPressed: () => _open(o.mapUrl)),
              TestBtn('Call',
                  outlined: true,
                  onPressed: o.retailerMobile.isEmpty
                      ? null
                      : () => _open('tel:${o.retailerMobile}')),
            ],
          ),
          if (o.deliveryStatus != 'Delivered') ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _starting ? null : () => _startDelivery(o),
                icon: Icon(o.isStarted ? Icons.navigation : Icons.play_arrow),
                label: Text(o.isStarted ? 'Continue Delivery' : 'Start Delivery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            if ((o.deliveredAt ?? '').isNotEmpty)
              TestLine(Icons.event_available_outlined,
                  'Delivered on ${o.deliveredAt}'),
            TestLine(Icons.route_outlined,
                'Distance travelled: ${fmtDistanceM(o.distanceM)}'),
            TestLine(Icons.timer_outlined,
                'Time taken: ${fmtDurationS(o.durationS)}'),
          ],
        ],
      ),
    );
  }
}

/// Standalone page (opened from the login screen) so a delivery boy can
/// log in without a main-app account.
class DeliveryBoyTestScreen extends StatelessWidget {
  final DeliveryLoginResult? initialLogin;
  const DeliveryBoyTestScreen({super.key, this.initialLogin});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          title: const Text('Delivery Boy (Test)',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: DeliveryBoyTestView(
          initialLogin: initialLogin,
          onLoggedOut: () => Navigator.of(context).pop(),
        ),
      );
}
