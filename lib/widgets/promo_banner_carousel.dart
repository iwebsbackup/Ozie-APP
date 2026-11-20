import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/banner_models.dart';
import '../core/retailer_service.dart';
import 'app_widgets.dart';

/// "Offers & Updates" section. Fetches active banners itself
/// (GET v1/retailer/banners) and hides completely when there are none
/// or the request fails.
///
/// Tap a banner:
///  - linked product  -> offer sheet (qty + Add to cart)
///  - link only       -> opens link in browser
///  - video           -> opens video in browser/player
///  - nothing else    -> full image preview
class PromoBannerCarousel extends StatefulWidget {
  const PromoBannerCarousel({super.key});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<PromoBannerCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.94);
  Timer? _timer;
  List<PromoBanner> _banners = const [];
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await RetailerService.getBanners();
      if (!mounted) return;
      setState(() => _banners = r.banners);
      _startTimer();
    } on ApiException {
      // Banners are optional. Stay hidden on error.
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_banners.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      _page = (_page + 1) % _banners.length;
      _controller.animateToPage(
        _page,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showStatus(context, 'Could not open link.', error: true);
    }
  }

  void _onTap(PromoBanner b) {
    if (b.hasProduct) {
      _openOfferSheet(b);
    } else if (b.isVideo) {
      _openUrl(b.mediaUrl);
    } else if (b.hasAction) {
      _openUrl(b.actionUrl);
    } else {
      _openPreview(b);
    }
  }

  void _openPreview(PromoBanner b) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                b.mediaUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 200,
                  child: Center(
                    child: Icon(Icons.image_outlined,
                        size: 40, color: Colors.white54),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOfferSheet(PromoBanner b) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _OfferSheet(
        banner: b,
        onOpenLink: b.hasAction ? () => _openUrl(b.actionUrl) : null,
      ),
    );
    if (added == true && mounted) showStatus(context, 'Added to cart.');
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Text(
          'Offers & Updates',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _controller,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _BannerTile(
                banner: _banners[i],
                onTap: () => _onTap(_banners[i]),
              ),
            ),
          ),
        ),
        if (_banners.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _banners.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? AppColors.blue : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BannerTile extends StatelessWidget {
  final PromoBanner banner;
  final VoidCallback onTap;
  const _BannerTile({required this.banner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.border),
            if (banner.isVideo)
              _videoTile()
            else
              Image.network(
                banner.mediaUrl,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const ColoredBox(color: AppColors.border),
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.image_outlined,
                      size: 40, color: AppColors.muted),
                ),
              ),
            if (banner.hasProduct && !banner.isVideo)
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Tap to view offer',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _videoTile() => Container(
        color: const Color(0xFF0F172A),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_fill, size: 48, color: Colors.white70),
            if (banner.title.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  banner.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      );
}

class _OfferSheet extends StatefulWidget {
  final PromoBanner banner;
  final VoidCallback? onOpenLink;
  const _OfferSheet({required this.banner, this.onOpenLink});

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  int _qty = 1;
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await RetailerService.addBannerToCart(
        productId: widget.banner.productId,
        quantity: _qty,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      showStatus(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.banner;
    final name = b.productName.isNotEmpty ? b.productName : b.title;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 140,
                width: double.infinity,
                child: b.isVideo
                    ? const ColoredBox(color: Color(0xFF0F172A))
                    : Image.network(
                        b.mediaUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: AppColors.border),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            if (b.title.isNotEmpty)
              Text(
                b.title,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            const SizedBox(height: 2),
            Text(
              name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (b.productPrice > 0) ...[
              const SizedBox(height: 4),
              Text(
                formatInr(b.productPrice),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Quantity',
                    style: TextStyle(fontSize: 13, color: AppColors.muted)),
                const Spacer(),
                IconButton(
                  onPressed:
                      _adding || _qty <= 1 ? null : () => setState(() => _qty--),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$_qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _adding ? null : () => setState(() => _qty++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GradientButton(
              label: 'Add to cart',
              loading: _adding,
              onPressed: _adding ? null : _add,
            ),
            if (widget.onOpenLink != null) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: widget.onOpenLink,
                  child: const Text('More details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}