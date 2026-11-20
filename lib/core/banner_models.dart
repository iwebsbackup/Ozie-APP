/// Promo banners (retailer).
/// API: GET/POST v1/retailer/banners.

String _bnStr(dynamic v) => v == null ? '' : '$v'.trim();

int _bnInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double _bnDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

class PromoBanner {
  final int id;
  final String title;
  final String mediaType; // static | dynamic (video)
  final String mediaUrl;
  final int productId;
  final String productName;
  final double productPrice;
  final String actionUrl;

  const PromoBanner({
    this.id = 0,
    this.title = '',
    this.mediaType = 'static',
    this.mediaUrl = '',
    this.productId = 0,
    this.productName = '',
    this.productPrice = 0,
    this.actionUrl = '',
  });

  factory PromoBanner.fromJson(Map<String, dynamic> j) => PromoBanner(
        id: _bnInt(j['id']),
        title: _bnStr(j['title']),
        mediaType: _bnStr(j['media_type']).toLowerCase(),
        mediaUrl: _bnStr(j['media_url']),
        productId: _bnInt(j['product_id']),
        productName: _bnStr(j['product_name']),
        productPrice: _bnDouble(j['product_price']),
        actionUrl: _bnStr(j['action_url']),
      );

  bool get isVideo {
    if (mediaType == 'dynamic' || mediaType == 'video') return true;
    final u = mediaUrl.toLowerCase().split('?').first;
    return u.endsWith('.mp4') ||
        u.endsWith('.webm') ||
        u.endsWith('.mov') ||
        u.endsWith('.avi') ||
        u.endsWith('.ogg');
  }

  bool get hasProduct => productId > 0;
  bool get hasAction => actionUrl.toLowerCase().startsWith('http');
}

/// GET v1/retailer/banners -> data.
class PromoBannersResult {
  final List<PromoBanner> banners;
  const PromoBannersResult({this.banners = const []});

  factory PromoBannersResult.fromJson(Map<String, dynamic> j) {
    final list = j['banners'] is List ? j['banners'] as List : const [];
    return PromoBannersResult(
      banners: list
          .whereType<Map>()
          .map((e) => PromoBanner.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.mediaUrl.isNotEmpty)
          .toList(),
    );
  }
}