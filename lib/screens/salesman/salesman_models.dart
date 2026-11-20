/// Models for GET v1/salesman/addresses
///
/// Response shape:
/// { data: { salesman_id, salesman_name, total, page, limit,
///           addresses: [ { retailer_id, shop_name, ..., address: {...} } ] } }
class SalesmanAddress {
  final int retailerId;
  final String shopName;
  final String ownerName;
  final String contactNumber;
  final String fullAddress;
  final String areaLocality;
  final String city;
  final String state;
  final String pincode;
  final double latitude;
  final double longitude;
  final String outletType;
  final String finalStatus;
  final String tlReviewStatus;

  const SalesmanAddress({
    required this.retailerId,
    required this.shopName,
    required this.ownerName,
    required this.contactNumber,
    required this.fullAddress,
    required this.areaLocality,
    required this.city,
    required this.state,
    required this.pincode,
    required this.latitude,
    required this.longitude,
    required this.outletType,
    required this.finalStatus,
    required this.tlReviewStatus,
  });

  /// Route can only be drawn when the shop has a real map pin.
  bool get hasLocation => latitude != 0 && longitude != 0;

  String get displayAddress =>
      fullAddress.isNotEmpty ? fullAddress : 'Address not available';

  /// approved -> "Approved", under_review -> "Under Review" ...
  String get statusLabel {
    if (finalStatus.isEmpty) return 'Unknown';
    return finalStatus
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  factory SalesmanAddress.fromJson(Map<String, dynamic> j) {
    final a = j['address'] is Map
        ? Map<String, dynamic>.from(j['address'] as Map)
        : <String, dynamic>{};

    var lat = _toDouble(a['latitude']);
    var lng = _toDouble(a['longitude']);

    // API sometimes sends latitude/longitude as 0 but fills the
    // "gps_coordinates" string ("28.70, 77.11"). Use it as fallback.
    if (lat == 0 || lng == 0) {
      final parts = _toStr(a['gps_coordinates']).split(',');
      if (parts.length == 2) {
        final fLat = double.tryParse(parts[0].trim());
        final fLng = double.tryParse(parts[1].trim());
        if (fLat != null && fLng != null && fLat != 0 && fLng != 0) {
          lat = fLat;
          lng = fLng;
        }
      }
    }

    var full = _toStr(a['full_address']);
    if (full.isEmpty) {
      full = [
        _toStr(a['building_number']),
        _toStr(a['street_name']),
        _toStr(a['area_locality']),
        _toStr(a['city']),
        _toStr(a['state']),
        _toStr(a['pincode']),
      ].where((s) => s.isNotEmpty).join(', ');
    }

    return SalesmanAddress(
      retailerId: _toInt(j['retailer_id']),
      shopName: _toStr(j['shop_name']).trim(),
      ownerName: _toStr(j['license_vendor_name']).trim(),
      contactNumber: _toStr(j['contact_number']).trim(),
      fullAddress: full,
      areaLocality: _toStr(a['area_locality']),
      city: _toStr(a['city']),
      state: _toStr(a['state']),
      pincode: _toStr(a['pincode']),
      latitude: lat,
      longitude: lng,
      outletType: _toStr(j['outlet_type']),
      finalStatus: _toStr(j['final_status']),
      tlReviewStatus: _toStr(j['tl_review_status']),
    );
  }
}

class SalesmanAddressPage {
  final int salesmanId;
  final String salesmanName;
  final int total;
  final int page;
  final int limit;
  final List<SalesmanAddress> addresses;

  const SalesmanAddressPage({
    required this.salesmanId,
    required this.salesmanName,
    required this.total,
    required this.page,
    required this.limit,
    required this.addresses,
  });

  bool get hasMore => limit > 0 && page * limit < total;

  factory SalesmanAddressPage.fromJson(Map<String, dynamic> d) {
    final raw = d['addresses'];
    final list = <SalesmanAddress>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(SalesmanAddress.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return SalesmanAddressPage(
      salesmanId: _toInt(d['salesman_id']),
      salesmanName: _toStr(d['salesman_name']),
      total: _toInt(d['total']),
      page: _toInt(d['page']) == 0 ? 1 : _toInt(d['page']),
      limit: _toInt(d['limit']),
      addresses: list,
    );
  }
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0;
  return 0;
}

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

String _toStr(dynamic v) {
  if (v == null) return '';
  final s = v.toString();
  return s == 'null' ? '' : s;
}