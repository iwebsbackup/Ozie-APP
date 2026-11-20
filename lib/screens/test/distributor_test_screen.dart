import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/router.dart';
import '../../widgets/app_widgets.dart';
import 'distributor_live_screen.dart';
import 'test_models.dart';
import 'test_service.dart';
import 'test_widgets.dart';

/// Distributor home in TEST MODE: no bottom menu, no old dashboard data.
/// Only Quick Actions: Create Delivery Boys, View Orders, Assign Orders.
class DistributorTestHome extends StatelessWidget {
  final Session session;
  const DistributorTestHome({super.key, required this.session});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
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
          const Text('Distributor',
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
                icon: Icons.person_add_alt_1_outlined,
                label: 'Create Delivery Boys',
                subtitle: 'Name & mobile number',
                onTap: () => _open(context, const DeliveryBoysScreen()),
              ),
              TestActionTile(
                icon: Icons.receipt_long_outlined,
                label: 'View Orders',
                subtitle: 'Accept or reject orders',
                onTap: () => _open(context, const DistributorOrdersScreen()),
              ),
              TestActionTile(
                icon: Icons.assignment_ind_outlined,
                label: 'Assign Orders',
                subtitle: 'Give accepted orders to a boy',
                onTap: () => _open(context, const AssignOrdersScreen()),
              ),
              TestActionTile(
                icon: Icons.my_location,
                label: 'View Live Tracking',
                subtitle: 'Delivery boys on map + today\'s record',
                onTap: () => _open(context, const DistributorLiveScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── View Orders ─────────────────────────

class DistributorOrdersScreen extends StatefulWidget {
  const DistributorOrdersScreen({super.key});

  @override
  State<DistributorOrdersScreen> createState() =>
      _DistributorOrdersScreenState();
}

class _DistributorOrdersScreenState extends State<DistributorOrdersScreen> {
  String _status = 'Pending';
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
      final list = await TestService.distributorOrders(status: _status);
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

  Future<void> _act(TestOrder o, bool accept) async {
    try {
      await TestService.actOnOrder(o.id, accept: accept);
      if (!mounted) return;
      testToast(context,
          'Order #${o.orderNumber} ${accept ? 'accepted' : 'rejected'}.');
      await _load();
    } catch (e) {
      if (mounted) testToast(context, testErr(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: testAppBar(context, title: 'View Orders'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Wrap(
              spacing: 8,
              children: ['Pending', 'Accepted', 'Rejected', 'all']
                  .map((s) => ChoiceChip(
                        label: Text(s == 'all' ? 'All' : s),
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
              const TestEmpty('No orders.')
            else
              ..._orders.map((o) => TestOrderCard(
                    o: o,
                    showRetailer: true,
                    actions: o.status == 'Pending'
                        ? [
                            TestBtn('Reject',
                                outlined: true,
                                color: AppColors.dangerText,
                                onPressed: () => _act(o, false)),
                            TestBtn('Accept',
                                color: AppColors.green,
                                onPressed: () => _act(o, true)),
                          ]
                        : const [],
                  )),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Create Delivery Boys ─────────────────────────

class DeliveryBoysScreen extends StatefulWidget {
  const DeliveryBoysScreen({super.key});

  @override
  State<DeliveryBoysScreen> createState() => _DeliveryBoysScreenState();
}

class _DeliveryBoysScreenState extends State<DeliveryBoysScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  bool _saving = false;
  bool _loading = true;
  String? _error;
  List<TestDeliveryBoy> _boys = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await TestService.deliveryBoys();
      if (!mounted) return;
      setState(() {
        _boys = list;
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

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await TestService.createDeliveryBoy(
          _nameCtrl.text.trim(), _mobileCtrl.text.trim());
      if (!mounted) return;
      testToast(context, 'Delivery boy created.');
      _nameCtrl.clear();
      _mobileCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) testToast(context, testErr(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: testAppBar(context, title: 'Create Delivery Boys'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            TestCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    ),
                    const SizedBox(height: 16),
                    GradientButton(
                      label: 'Create',
                      loading: _saving,
                      onPressed: _saving ? null : _create,
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 4, 2, 10),
              child: Text('My delivery boys',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
            ),
            if (_loading && _boys.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              TestError(_error!, onRetry: _load)
            else if (_boys.isEmpty)
              const TestEmpty('No delivery boys yet.')
            else
              ..._boys.map((b) => TestCard(
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFFDCEBFF),
                          child: Icon(Icons.delivery_dining,
                              color: AppColors.blue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.text)),
                              const SizedBox(height: 2),
                              Text(b.mobile,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        TestStatusChip(b.activeOrders > 0
                            ? '${b.activeOrders} active'
                            : 'Free'),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Assign Orders ─────────────────────────

class AssignOrdersScreen extends StatefulWidget {
  const AssignOrdersScreen({super.key});

  @override
  State<AssignOrdersScreen> createState() => _AssignOrdersScreenState();
}

class _AssignOrdersScreenState extends State<AssignOrdersScreen> {
  String _filter = 'unassigned';
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
      final list = await TestService.acceptedOrders(filter: _filter);
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

  Future<void> _assign(TestOrder o) async {
    List<TestDeliveryBoy> boys;
    try {
      boys = await TestService.deliveryBoys();
    } catch (e) {
      if (mounted) testToast(context, testErr(e), error: true);
      return;
    }
    if (!mounted) return;
    final active = boys.where((b) => b.active).toList();
    if (active.isEmpty) {
      testToast(context, 'Create a delivery boy first.', error: true);
      return;
    }

    final picked = await showModalBottomSheet<TestDeliveryBoy>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Select delivery boy',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ...active.map((b) => ListTile(
                  leading: const Icon(Icons.delivery_dining),
                  title: Text(b.name),
                  subtitle: Text(b.mobile),
                  trailing: Text('${b.activeOrders} active',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                  onTap: () => Navigator.of(ctx).pop(b),
                )),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    try {
      await TestService.assignOrder(o.id, picked.id);
      if (!mounted) return;
      testToast(
          context, 'Order #${o.orderNumber} assigned to ${picked.name}.');
      await _load();
    } catch (e) {
      if (mounted) testToast(context, testErr(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: testAppBar(context, title: 'Assign Orders'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Wrap(
              spacing: 8,
              children: [
                ['unassigned', 'To assign'],
                ['assigned', 'Assigned'],
                ['all', 'All'],
              ]
                  .map((f) => ChoiceChip(
                        label: Text(f[1]),
                        selected: _filter == f[0],
                        onSelected: (_) {
                          setState(() => _filter = f[0]);
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
              const TestEmpty(
                  'No accepted orders here.\nAccept an order in View Orders first.')
            else
              ..._orders.map((o) => TestOrderCard(
                    o: o,
                    showRetailer: true,
                    actions: o.isAssigned
                        ? const []
                        : [
                            TestBtn('Assign delivery boy',
                                onPressed: () => _assign(o))
                          ],
                  )),
          ],
        ),
      ),
    );
  }
}
