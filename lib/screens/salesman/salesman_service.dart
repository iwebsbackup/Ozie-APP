import '../../core/api_client.dart';
import 'salesman_models.dart';

class SalesmanService {
  SalesmanService._();

  static final ApiClient _api = ApiClient.instance;

  /// GET v1/salesman/addresses  (Bearer token added by ApiClient)
  static Future<SalesmanAddressPage> getAddresses({
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _api.get(
      'v1/salesman/addresses',
      query: {'page': page, 'limit': limit},
    );
    final data = res['data'];
    if (data is Map) {
      return SalesmanAddressPage.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException('Unexpected server response.');
  }

  /// Fetches EVERY assigned address (loops pages of 100 until done).
  static Future<List<SalesmanAddress>> getAllAddresses() async {
    final all = <SalesmanAddress>[];
    var page = 1;
    while (true) {
      final p = await getAddresses(page: page, limit: 100);
      all.addAll(p.addresses);
      if (!p.hasMore || p.addresses.isEmpty || page >= 50) break;
      page++;
    }
    return all;
  }
}