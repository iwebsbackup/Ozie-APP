import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/scan_order_models.dart';
import '../core/scan_order_service.dart';
import '../widgets/app_widgets.dart';
import 'checkout_screen.dart';

/// Quick Action -> "Create Order" (AI & Scan Upload).
///
/// Flow (API: v1/retailer/scan-order):
///   1. Take photo / pick image of a purchase order or invoice.
///   2. action=scan        -> AI reads lines + matches to catalog.
///   3. Fix lines (qty, pick product, add/remove). action=recalculate
///      keeps totals + schemes in sync.
///   4. action=confirm     -> lines go to cart -> Checkout.
class CreateOrderScreen extends StatefulWidget {
  /// AppBar title. Mic button opens this screen as "Orderbox".
  final String title;
  const CreateOrderScreen({super.key, this.title = 'Create Order'});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  static const Color _orange = Color(0xFFFF8A00);
  static const Color _orangeBg = Color(0xFFFFF1DD);
  static const Color _orangeText = Color(0xFF9A5200);

  final _picker = ImagePicker();
  Timer? _debounce;

  /// 0 = Upload File (gallery), 1 = Take Photo (camera).
  int _mode = 0;

  ScanCatalog? _catalog;
  Uint8List? _imageBytes;

  final List<ScanItem> _items = [];
  bool _hasResult = false;

  double _subtotal = 0;
  double _savings = 0;
  List<AppliedScheme> _applied = const [];
  List<SuggestedScheme> _suggested = const [];

  bool _scanning = false;
  bool _recalcBusy = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  double get _grand => (_subtotal - _savings).clamp(0, double.infinity);
  List<ScanItem> get _matched => _items.where((e) => e.isMatched).toList();
  int get _unmatchedCount => _items.where((e) => !e.isMatched).length;

  /* ----------------------------- data ----------------------------- */

  Future<void> _loadCatalog() async {
    try {
      final c = await ScanOrderService.getCatalog();
      if (!mounted) return;
      setState(() => _catalog = c);
    } on ApiException {
      // Catalog only powers manual product pick; scan still works without it.
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        imageQuality: 80,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 5 * 1024 * 1024) {
        showStatus(context, 'Image 5MB se badi hai. Choti image choose karo.',
            error: true);
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _items.clear();
        _hasResult = false;
        _subtotal = 0;
        _savings = 0;
        _applied = const [];
        _suggested = const [];
      });
    } catch (_) {
      if (!mounted) return;
      showStatus(context, 'Could not open camera / gallery.', error: true);
    }
  }

  Future<void> _scan() async {
    final bytes = _imageBytes;
    if (bytes == null || _scanning) return;
    setState(() => _scanning = true);
    try {
      final r = await ScanOrderService.scan(base64Encode(bytes));
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.items);
        _hasResult = true;
        _scanning = false;
      });
      // Server subtotal counts unmatched lines too; re-sync on matched only.
      await _recalc();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      showStatus(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
      showStatus(context, 'Scan failed. Please try again.', error: true);
    }
  }

  void _scheduleRecalc() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _recalc);
  }

  Future<void> _recalc() async {
    final matched = _matched;
    if (matched.isEmpty) {
      if (!mounted) return;
      setState(() {
        _subtotal = 0;
        _savings = 0;
        _applied = const [];
        _suggested = const [];
      });
      return;
    }
    setState(() => _recalcBusy = true);
    try {
      final r = await ScanOrderService.recalculate(matched);
      if (!mounted) return;
      setState(() {
        _subtotal = r.subtotal;
        _savings = r.schemeSavings;
        _applied = r.applied;
        _suggested = r.suggested;
        _recalcBusy = false;
      });
    } on ApiException {
      if (!mounted) return;
      // Fallback: local math, no scheme info.
      setState(() {
        _subtotal = matched.fold<double>(0, (a, e) => a + e.lineTotal);
        _recalcBusy = false;
      });
    }
  }

  Future<void> _confirm() async {
    final matched = _matched;
    if (matched.isEmpty || _confirming) return;
    _debounce?.cancel();
    setState(() => _confirming = true);
    try {
      await ScanOrderService.confirm(matched);
      if (!mounted) return;
      setState(() => _confirming = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const CheckoutScreen()),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _confirming = false);
      showStatus(context, e.message, error: true);
    }
  }

  /* ----------------------------- line edits ----------------------------- */

  void _changeQty(ScanItem it, int delta) {
    final next = it.quantity + delta;
    if (next < 1 || next > 9999) return;
    setState(() => it.quantity = next);
    if (it.isMatched) {
      // Subtotal moves instantly; schemes catch up after the debounce.
      setState(() => _subtotal = _matched.fold<double>(0, (a, e) => a + e.lineTotal));
      _scheduleRecalc();
    }
  }

  void _removeItem(ScanItem it) {
    setState(() => _items.remove(it));
    _scheduleRecalc();
  }

  Future<void> _selectProduct(ScanItem it) async {
    final p = await _openPicker(suggestedIds: it.suggestedProductIds);
    if (p == null || !mounted) return;
    setState(() => it.assign(p));
    _scheduleRecalc();
  }

  Future<void> _addManual() async {
    final p = await _openPicker();
    if (p == null || !mounted) return;
    // Same product already in list -> bump qty instead of duplicate line.
    for (final e in _items) {
      if (e.productId == p.id) {
        _changeQty(e, 1);
        return;
      }
    }
    setState(() {
      _items.add(ScanItem.fromProduct(p));
      _hasResult = true;
    });
    _scheduleRecalc();
  }

  Future<ScanProduct?> _openPicker({List<int> suggestedIds = const []}) {
    final catalog = _catalog;
    if (catalog == null || catalog.products.isEmpty) {
      showStatus(context, 'Product list not loaded yet. Try again.', error: true);
      _loadCatalog();
      return Future.value(null);
    }
    return showModalBottomSheet<ScanProduct>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProductPicker(
        products: catalog.products,
        suggestedIds: suggestedIds,
      ),
    );
  }

  /* ----------------------------- build ----------------------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
        ),
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: AppColors.text,
            strokeWidth: 1.5,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildUploadCard(),
          if (!_hasResult &&
              _catalog != null &&
              _catalog!.schemeTitles.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildActiveSchemes(),
          ],
          if (_hasResult) ...[
            const SizedBox(height: 22),
            _buildItemsHeader(),
            const SizedBox(height: 10),
            if (_items.isEmpty) _buildEmptyItems() else _buildItemsBlock(),
            if (_matched.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSummary(),
            ],
          ],
        ],
      ),
      bottomNavigationBar: _hasResult ? _buildBottomBar() : null,
    );
  }

  BoxDecoration _cardDeco({double radius = 16}) => BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1E2A3B),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      );

  /* ---- upload card ---- */

  Widget _buildUploadCard() {
    final hasImage = _imageBytes != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.green, AppColors.blue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI & Scan Upload',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Photo lo, AI items match kar dega',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildModeToggle(),
          const SizedBox(height: 14),
          _buildDropBox(hasImage),
          const SizedBox(height: 14),
          _buildScanButton(hasImage),
          if (_scanning) ...[
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'Reading your order... thoda time lag sakta hai',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          ],
          if (!_hasResult) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _scanning ? null : _addManual,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  minimumSize: const Size(0, 36),
                ),
                child: const Text(
                  'Or add items manually',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "Upload File | Take Photo" segmented switch.
  Widget _buildModeToggle() {
    Widget seg(int i, String label, IconData icon) {
      final selected = _mode == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _scanning ? null : () => setState(() => _mode = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 42,
            decoration: BoxDecoration(
              color: selected ? AppColors.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x331A6FD4),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 17, color: selected ? Colors.white : AppColors.muted),
                const SizedBox(width: 8),
                Flexible(child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.muted,
                  ), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAEFF7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          seg(0, 'Upload File', Icons.file_upload_outlined),
          seg(1, 'Take Photo', Icons.photo_camera_outlined),
        ],
      ),
    );
  }

  /// Dashed blue drop zone. Shows the picked image once there is one.
  Widget _buildDropBox(bool hasImage) {
    final camera = _mode == 1;
    final onTap = _scanning
        ? null
        : () => _pick(camera ? ImageSource.camera : ImageSource.gallery);

    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        foregroundPainter: const _DashedRRectPainter(
          color: AppColors.blue,
          radius: 16,
          strokeWidth: 1.6,
          dash: 6,
          gap: 5,
        ),
        child: Container(
          height: hasImage ? 220 : 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: hasImage
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.text.withOpacity(0.78),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              camera
                                  ? Icons.photo_camera_outlined
                                  : Icons.swap_horiz_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              camera ? 'Retake' : 'Change',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      camera
                          ? Icons.photo_camera_outlined
                          : Icons.cloud_upload_outlined,
                      size: 46,
                      color: const Color(0xFF4A5568),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      camera ? 'Open Camera' : 'Select File',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'JPG or PNG (Max 5MB)',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Big blue -> green "SCAN & MATCH ITEMS" button.
  Widget _buildScanButton(bool hasImage) {
    final enabled = hasImage && !_scanning;
    final label = _scanning
        ? 'READING ORDER...'
        : (_hasResult ? 'SCAN AGAIN' : 'SCAN & MATCH ITEMS');
    return Opacity(
      opacity: (hasImage || _scanning) ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? _scan : null,
          child: Ink(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF1F6FFF), Color(0xFF22C58B)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x331F6FFF),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: _scanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.center_focus_strong_outlined,
                            size: 20, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSchemes() {
    final titles = _catalog!.schemeTitles.take(6).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_offer_outlined,
                  size: 18, color: AppColors.successText),
              SizedBox(width: 8),
              Flexible(child: Text(
                'Active schemes for you',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: titles
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.successText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  /* ---- items ---- */

  Widget _buildItemsHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Order Items (${_items.length})',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ),
        TextButton(
          onPressed: _addManual,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            '+ Add item',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyItems() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: _cardDeco(),
      child: const Column(
        children: [
          Icon(Icons.shopping_bag_outlined, size: 44, color: AppColors.muted),
          SizedBox(height: 10),
          Text(
            'No items yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Tap "+ Add item" to pick products',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  /// One grouped card (like the cart): warning banner on top, then rows.
  Widget _buildItemsBlock() {
    return Container(
      decoration: _cardDeco(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (_unmatchedCount > 0)
            Container(
              width: double.infinity,
              color: _orangeBg,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: _orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_unmatchedCount line match nahi hui. Product select karo, warna add nahi hogi.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _orangeText,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0 || _unmatchedCount > 0)
              const Divider(height: 1, color: AppColors.border),
            _ScanItemRow(
              item: _items[i],
              onMinus: () => _changeQty(_items[i], -1),
              onPlus: () => _changeQty(_items[i], 1),
              onRemove: () => _removeItem(_items[i]),
              onSelect: () => _selectProduct(_items[i]),
            ),
          ],
        ],
      ),
    );
  }

  /* ---- summary ---- */

  Widget _buildSummary() {
    Widget row(String l, String v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(
                l,
                style: TextStyle(
                  fontSize: bold ? 15 : 13.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Text(
                v,
                style: TextStyle(
                  fontSize: bold ? 17 : 13.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color ?? AppColors.text,
                ),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _cardDeco(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Summary',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          row('Subtotal', formatInr(_subtotal)),
          if (_savings > 0)
            row('Scheme savings', '- ${formatInr(_savings)}',
                color: AppColors.successText),
          const Divider(height: 18, color: AppColors.border),
          row('Grand Total', formatInr(_grand), bold: true),
          if (_applied.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._applied.map(
              (a) => _noteStrip(
                icon: Icons.check_circle,
                bg: AppColors.successBg,
                fg: AppColors.successText,
                text:
                    '${a.title}${a.code != null ? ' (${a.code})' : ''} · saved ${formatInr(a.discount)}',
              ),
            ),
          ],
          if (_suggested.isNotEmpty) ...[
            const SizedBox(height: 4),
            ..._suggested.map(
              (s) => _noteStrip(
                icon: Icons.lightbulb_outline,
                bg: _orangeBg,
                fg: _orangeText,
                text: '${s.title}: ${s.message}',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _noteStrip({
    required IconData icon,
    required Color bg,
    required Color fg,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ---- bottom bar (same as Cart) ---- */

  Widget _buildBottomBar() {
    final canConfirm = _matched.isNotEmpty && !_confirming && !_scanning;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      formatInr(_grand),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    if (_recalcBusy) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const Spacer(),
            FilledButton(
              onPressed: canConfirm ? _confirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _confirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Proceed to Checkout'),
            ),
          ],
        ),
      ),
    );
  }
}

/* ----------------------------- item row ----------------------------- */

/// One order line, laid out like the cart rows: thumb | name + price + qty.
class _ScanItemRow extends StatelessWidget {
  final ScanItem item;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onRemove;
  final VoidCallback onSelect;

  const _ScanItemRow({
    required this.item,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final matched = item.isMatched;
    final title = matched
        ? item.name
        : (item.extractedName.isNotEmpty ? item.extractedName : item.name);
    final sub = [
      if (item.brand.isNotEmpty) item.brand,
      if (item.unitSize.isNotEmpty) item.unitSize,
    ].join(' • ');
    final showRead = matched &&
        item.extractedName.trim().isNotEmpty &&
        item.extractedName.trim().toLowerCase() !=
            item.name.trim().toLowerCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: ColoredBox(
                color: matched ? AppColors.inputBg : const Color(0xFFFFF1DD),
                child: Icon(
                  matched ? Icons.inventory_2_outlined : Icons.help_outline,
                  color: matched ? AppColors.muted : const Color(0xFFFF8A00),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                if (matched) ...[
                  Text(
                    sub.isNotEmpty
                        ? '$sub  ·  ${formatInr(item.price)}/case'
                        : '${formatInr(item.price)}/case',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  if (showRead) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Read as: ${item.extractedName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _chip(
                        item.matchConfidence > 0
                            ? 'Matched ${item.matchConfidence}%'
                            : 'Matched',
                        AppColors.successBg,
                        AppColors.successText,
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onSelect,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'Change',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.blue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _QtyStepper(
                        quantity: item.quantity,
                        onMinus: onMinus,
                        onPlus: onPlus,
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          formatInr(item.lineTotal),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  _chip('Not matched', const Color(0xFFFFE8CC),
                      const Color(0xFF9A5200)),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: onSelect,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Select product'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline,
                size: 20, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
        ),
      );
}

/// Same stepper as the cart.
class _QtyStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _QtyStepper({
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inputBg,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _btn(Icons.remove, quantity > 1 ? onMinus : null),
            SizedBox(
              width: 28,
              child: Center(
                child: Text(
                  '$quantity',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
            _btn(Icons.add, onPlus),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.text : AppColors.muted,
        ),
      ),
    );
  }
}

/* ----------------------------- product picker ----------------------------- */

class _ProductPicker extends StatefulWidget {
  final List<ScanProduct> products;
  final List<int> suggestedIds;
  const _ProductPicker({required this.products, required this.suggestedIds});

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final suggested = <ScanProduct>[];
    for (final id in widget.suggestedIds) {
      for (final p in widget.products) {
        if (p.id == id) suggested.add(p);
      }
    }

    final filtered = q.isEmpty
        ? widget.products
        : widget.products.where((p) {
            final hay = '${p.name} ${p.brand} ${p.unitSize}'.toLowerCase();
            return q.split(RegExp(r'\s+')).every(hay.contains);
          }).toList();

    final showSuggested = q.isEmpty && suggested.isNotEmpty;
    final height = MediaQuery.of(context).size.height * 0.8;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget tile(ScanProduct p) => InkWell(
          onTap: () => Navigator.of(context).pop(p),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      size: 20, color: AppColors.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (p.brand.isNotEmpty) p.brand,
                          if (p.unitSize.isNotEmpty) p.unitSize,
                        ].join(' • '),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatInr(p.price),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        );

    Widget label(String t, Color c) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            t,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 14),
              const Text(
                'Select product',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _q = v),
                decoration:
                    inputDecoration(hint: 'Search name / brand / size').copyWith(
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView(
                  children: [
                    if (showSuggested) ...[
                      label('Suggested', AppColors.successText),
                      ...suggested.map(tile),
                      const Divider(height: 20, color: AppColors.border),
                      label('All products', AppColors.muted),
                    ],
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'No products found',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ),
                      )
                    else
                      ...filtered.take(150).map(tile),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Dashed rounded-rectangle border (no package needed).
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;
  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);
    final path = Path()..addRRect(rrect);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final end = d + dash > m.length ? m.length : d + dash;
        canvas.drawPath(m.extractPath(d, end), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}