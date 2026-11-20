import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mappls_gl/mappls_gl.dart' show LatLng;

import '../../core/models.dart';
import '../../core/router.dart';
import '../../widgets/app_widgets.dart';
import 'location_picker_screen.dart';
import 'retailer_track_screen.dart';
import 'test_models.dart';
import 'test_service.dart';
import 'test_widgets.dart';

/// Retailer home in TEST MODE: no bottom menu, no old dashboard data.
/// Only Quick Actions: Create Order, Where is my order.
class RetailerTestHome extends StatelessWidget {
  final Session session;
  const RetailerTestHome({super.key, required this.session});

  Future<void> _create(BuildContext context) async {
    final no = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const RetailerCreateOrderScreen()),
    );
    if (no != null && context.mounted) {
      testToast(context, 'Order #$no placed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (session.user.name ?? '').trim();
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
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: AppColors.text),
            onPressed: () => logoutAndGoToLogin(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name.isEmpty ? 'Hello' : 'Hi, $name',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ),
              const TestStatusChip('TEST MODE'),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Retailer',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 24),
          const Text('Quick Actions',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: [
              TestActionTile(
                icon: Icons.add_shopping_cart,
                label: 'Create Order',
                subtitle: 'Product, price, qty & location',
                onTap: () => _create(context),
              ),
              TestActionTile(
                icon: Icons.local_shipping_outlined,
                label: 'Where is my order',
                subtitle: 'Track status & delivery boy',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RetailerOrdersScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Create Order ─────────────────────────

class RetailerCreateOrderScreen extends StatefulWidget {
  const RetailerCreateOrderScreen({super.key});

  @override
  State<RetailerCreateOrderScreen> createState() =>
      _RetailerCreateOrderScreenState();
}

class _RetailerCreateOrderScreenState extends State<RetailerCreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _productCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');

  // saved = retailer's saved address, current = GPS now, map = picked on map
  String _addrMode = 'current';
  PickedLocation? _picked;
  bool _submitting = false;

  @override
  void dispose() {
    _productCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _addressFor(Position p) async {
    try {
      // geocoding 5.x: methods live on a Geocoding instance.
      final list =
          await Geocoding().placemarkFromCoordinates(p.latitude, p.longitude);
      if (list.isEmpty) return null;
      final m = list.first;
      final parts = <String?>[
        m.street,
        m.subLocality,
        m.locality,
        m.administrativeArea,
        m.postalCode,
      ].where((s) => s != null && s.trim().isNotEmpty).cast<String>().toList();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickOnMap() async {
    final r = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
            initial: _picked == null ? null : LatLng(_picked!.lat, _picked!.lng)),
      ),
    );
    if (r != null && mounted) setState(() => _picked = r);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    double? lat;
    double? lng;
    String? addr;

    if (_addrMode == 'map') {
      final pk = _picked;
      if (pk == null) {
        testToast(context, 'Pick a location on the map first.', error: true);
        setState(() => _submitting = false);
        return;
      }
      lat = pk.lat;
      lng = pk.lng;
      addr = pk.address;
    } else if (_addrMode == 'current') {
      final pos = await _currentPosition();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
        addr = await _addressFor(pos);
      }
      // no location -> server falls back to retailer's saved address
    }

    try {
      final res = await TestService.createOrder(
        productName: _productCtrl.text.trim(),
        price: double.parse(_priceCtrl.text.trim()),
        quantity: int.parse(_qtyCtrl.text.trim()),
        latitude: lat,
        longitude: lng,
        address: addr,
      );
      if (!mounted) return;
      Navigator.of(context).pop('${res['order_number']}');
    } catch (e) {
      if (mounted) {
        testToast(context, testErr(e), error: true);
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: testAppBar(context, title: 'Create Order'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TestCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LabeledField(
                    label: 'Product name',
                    controller: _productCtrl,
                    hint: 'e.g. Parle-G',
                    validator: requiredValidator,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: LabeledField(
                          label: 'Price (₹)',
                          controller: _priceCtrl,
                          hint: '0.00',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            return (n == null || n <= 0) ? 'Enter price' : null;
                          },
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LabeledField(
                          label: 'Quantity',
                          controller: _qtyCtrl,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            return (n == null || n <= 0) ? 'Enter qty' : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Delivery address',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const [
                        ['saved', 'Saved address'],
                        ['current', 'Current location'],
                        ['map', 'Pick on map'],
                      ])
                        ChoiceChip(
                          label: Text(m[1]),
                          selected: _addrMode == m[0],
                          onSelected: _submitting
                              ? null
                              : (_) {
                                  setState(() => _addrMode = m[0]);
                                  if (m[0] == 'map' && _picked == null) {
                                    _pickOnMap();
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_addrMode == 'saved')
                    const Text('Saved retailer address will be used.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted))
                  else if (_addrMode == 'current')
                    const Text(
                        'GPS location now. If off/denied, saved address is used.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted))
                  else if (_picked == null)
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickOnMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open map'),
                    )
                  else ...[
                    TestLine(Icons.place_outlined, _picked!.address),
                    TestLine(Icons.my_location,
                        '${_picked!.lat.toStringAsFixed(6)}, ${_picked!.lng.toStringAsFixed(6)}'),
                    TextButton.icon(
                      onPressed: _submitting ? null : _pickOnMap,
                      icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                      label: const Text('Change on map'),
                    ),
                  ],
                  const SizedBox(height: 4),
                  GradientButton(
                    label: 'Place Order',
                    loading: _submitting,
                    onPressed: _submitting ? null : _submit,
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

// ───────────────────────── Where is my order ─────────────────────────

class RetailerOrdersScreen extends StatefulWidget {
  const RetailerOrdersScreen({super.key});

  @override
  State<RetailerOrdersScreen> createState() => _RetailerOrdersScreenState();
}

class _RetailerOrdersScreenState extends State<RetailerOrdersScreen> {
  bool _loading = true;
  String? _error;
  List<TestOrder> _orders = [];

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
      final list = await TestService.myOrders();
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = testErr(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: testAppBar(context, title: 'Where is my order'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_loading && _orders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              TestError(_error!, onRetry: _load)
            else if (_orders.isEmpty)
              const TestEmpty('No orders yet.\nCreate an order first.')
            else
              ..._orders.map((o) => InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RetailerTrackScreen(order: o)));
                      if (mounted) _load();
                    },
                    child: TestOrderCard(o: o, showTracker: true),
                  )),
          ],
        ),
      ),
    );
  }
}
