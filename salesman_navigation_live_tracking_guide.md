# Complete Salesman Map & Live Navigation Guide

This document outlines the full integration process for **Google Maps** and **Mappls (MapmyIndia)** inside the **Ozie** salesman application. It covers package additions, Android manifest permissions, model updates to handle invalid coordinates (`0,0`), address list button bindings, and in-app live navigation screens with polyline rendering and live distance updates.

---

## 1. Updated Project Dependencies (`pubspec.yaml`)

Add the required map and routing packages to your existing `pubspec.yaml` file under `dependencies`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Existing dependencies in your project
  geolocator: ^14.1.1
  geocoding: ^5.0.0
  dio: ^5.11.1
  flutter_secure_storage: ^11.2.0

  # Map & Routing Dependencies
  google_maps_flutter: ^2.5.3
  flutter_polyline_points: ^2.0.0
  mappls_gl: ^0.3.0
```

Run `flutter pub get` after updating `pubspec.yaml`.

---

## 2. Android Configuration (`AndroidManifest.xml`)

Update your `android/app/src/main/AndroidManifest.xml` inside the `<application>` tag to inject your API keys:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <!-- Permissions already present in your project -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>

    <application
        android:label="ozie"
        android:name="${applicationName}"
        android:icon="@mipmap/launcher_icon">

        <!-- Google Maps API Key -->
        <meta-data
            android:name="com.google.android.geo.API_KEY"
            android:value="YOUR_GOOGLE_MAPS_API_KEY"/>

        <!-- Mappls Credentials -->
        <meta-data 
            android:name="com.mappls.sdk.maps.ACCESS_KEY" 
            android:value="YOUR_MAPPLS_MAP_SDK_KEY"/>
        <meta-data 
            android:name="com.mappls.sdk.maps.REST_API_KEY" 
            android:value="YOUR_MAPPLS_REST_API_KEY"/>

        <!-- Existing Activity and Service configuration -->
        <activity
            android:name=".MainActivity"
            android:exported="true"
            ... >
        </activity>

    </application>
</manifest>
```

---

## 3. Address Data Model (`lib/screens/salesman/salesman_models.dart`)

Ensure your address model handles missing or zeroed coordinates (`0,0`) so the UI can disable routing for unmapped retailers.

```dart
class RetailerAddress {
  final int retailerId;
  final String shopName;
  final String contactNumber;
  final String fullAddress;
  final double latitude;
  final double longitude;

  RetailerAddress({
    required this.retailerId,
    required this.shopName,
    required this.contactNumber,
    required this.fullAddress,
    required this.latitude,
    required this.longitude,
  });

  factory RetailerAddress.fromJson(Map<String, dynamic> json) {
    final addr = json['address'] ?? {};
    return RetailerAddress(
      retailerId: json['retailer_id'] ?? json['id'] ?? 0,
      shopName: json['shop_name'] ?? json['name'] ?? 'Unknown Shop',
      contactNumber: json['contact_number'] ?? json['phone'] ?? '',
      fullAddress: addr['full_address'] ?? addr['address_line'] ?? 'Address not updated',
      latitude: (addr['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (addr['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Helper flag to check if valid GPS coordinates exist
  bool get hasValidLocation => latitude != 0.0 && longitude != 0.0;
}
```

---

## 4. Address List UI Integration (`lib/screens/salesman/address_card.dart`)

Attach the **"View Direction"** action to each address item. If `hasValidLocation` is `false`, disable the button and alert the salesman.

```dart
import 'package:flutter/material.dart';
import 'salesman_models.dart';
import 'salesman_google_nav_screen.dart'; // Navigation Screen file

class RetailerAddressCard extends StatelessWidget {
  final RetailerAddress address;

  const RetailerAddressCard({Key? key, required this.address}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              address.shopName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              address.hasValidLocation
                  ? address.fullAddress
                  : "Address location not mapped (Lat/Lng: 0,0)",
              style: TextStyle(
                color: address.hasValidLocation ? Colors.grey[700] : Colors.red[700],
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Ph: ${address.contactNumber.isNotEmpty ? address.contactNumber : 'N/A'}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text("View Direction"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: address.hasValidLocation ? Colors.deepPurple : Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: !address.hasValidLocation
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SalesmanGoogleNavScreen(
                                targetAddress: address,
                              ),
                            ),
                          );
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 5. In-App Google Live Navigation Screen (`lib/screens/salesman/salesman_google_nav_screen.dart`)

This screen opens inside the app when **"View Direction"** is tapped. It streams salesman's live location, updates the camera position, calculates real-time distance/ETA, and renders the dynamic polyline route to the target shop.

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'salesman_models.dart';

class SalesmanGoogleNavScreen extends StatefulWidget {
  final RetailerAddress targetAddress;

  const SalesmanGoogleNavScreen({Key? key, required this.targetAddress}) : super(key: key);

  @override
  State<SalesmanGoogleNavScreen> createState() => _SalesmanGoogleNavScreenState();
}

class _SalesmanGoogleNavScreenState extends State<SalesmanGoogleNavScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionStreamSubscription;

  LatLng? _currentPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  String _remainingDistance = "Calculating...";
  String _estimatedTime = "-- mins";
  bool _isLoading = true;

  // Replace with your Google Maps API Key
  final String _googleApiKey = "YOUR_GOOGLE_MAPS_API_KEY";

  @override
  void initState() {
    super.initState();
    _startLiveTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _startLiveTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable Location Services (GPS)")),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // Initial position fetch
    Position initialPos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    _updateSalesmanLocation(LatLng(initialPos.latitude, initialPos.longitude));

    // Listen to continuous live location stream
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update location every 10 meters moved
      ),
    ).listen((Position position) {
      _updateSalesmanLocation(LatLng(position.latitude, position.longitude));
    });
  }

  Future<void> _updateSalesmanLocation(LatLng salesmanLatLng) async {
    setState(() {
      _currentPosition = salesmanLatLng;
    });

    // Destination point from retailer address
    LatLng destinationLatLng = LatLng(
      widget.targetAddress.latitude,
      widget.targetAddress.longitude,
    );

    // Update Markers
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('salesman_live'),
          position: salesmanLatLng,
          infoWindow: const InfoWindow(title: "Your Location (Salesman)"),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
        Marker(
          markerId: const MarkerId('target_shop'),
          position: destinationLatLng,
          infoWindow: InfoWindow(title: widget.targetAddress.shopName),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };
    });

    // Move camera smoothly to track salesman
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: salesmanLatLng, zoom: 16.0),
      ),
    );

    // Fetch dynamic route and calculations
    await _getDirectionsAndDrawRoute(salesmanLatLng, destinationLatLng);

    if (_isLoading) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _getDirectionsAndDrawRoute(LatLng origin, LatLng destination) async {
    final String url =
        "https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&mode=driving&key=$_googleApiKey";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];

          // Decode Polyline points
          String encodedPoints = route['overview_polyline']['points'];
          PolylinePoints polylinePoints = PolylinePoints();
          List<PointLatLng> decodedPoints = polylinePoints.decodePolyline(encodedPoints);

          List<LatLng> polylineCoordinates = decodedPoints
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();

          setState(() {
            _remainingDistance = leg['distance']['text'];
            _estimatedTime = leg['duration']['text'];

            _polylines = {
              Polyline(
                polylineId: const PolylineId('live_salesman_route'),
                color: Colors.deepPurple,
                width: 6,
                points: polylineCoordinates,
              ),
            };
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching route directions: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Navigating to: ${widget.targetAddress.shopName}"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition ??
                        LatLng(widget.targetAddress.latitude, widget.targetAddress.longitude),
                    zoom: 15.0,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                  onMapCreated: (controller) => _mapController = controller,
                ),

                // Top Info Panel: Shows Distance & Time
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.straighten, color: Colors.deepPurple),
                              const SizedBox(height: 4),
                              const Text("Distance", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(
                                _remainingDistance,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(height: 35, width: 1, color: Colors.grey[300]),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.access_time, color: Colors.deepPurple),
                              const SizedBox(height: 4),
                              const Text("ETA", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(
                                _estimatedTime,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
```

---

## 6. Optional Mappls (MapmyIndia) Alternative Screen (`lib/screens/salesman/salesman_mappls_nav_screen.dart`)

If you want to offer Mappls for precise Indian street mapping, initialize Mappls in `main.dart` and use this widget screen:

### `main.dart` Setup:
```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  MapplsAccountManager.setMapSDKKey("YOUR_MAPPLS_MAP_SDK_KEY");
  MapplsAccountManager.setRestAPIKey("YOUR_MAPPLS_REST_API_KEY");
  MapplsAccountManager.setGrantType("client_credentials");
  MapplsAccountManager.setClientId("YOUR_CLIENT_ID");
  MapplsAccountManager.setClientSecret("YOUR_CLIENT_SECRET");

  runApp(const MyApp());
}
```

### Mappls Navigation Widget:
```dart
import 'package:flutter/material.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'salesman_models.dart';

class SalesmanMapplsNavScreen extends StatefulWidget {
  final RetailerAddress targetAddress;

  const SalesmanMapplsNavScreen({Key? key, required this.targetAddress}) : super(key: key);

  @override
  State<SalesmanMapplsNavScreen> createState() => _SalesmanMapplsNavScreenState();
}

class _SalesmanMapplsNavScreenState extends State<SalesmanMapplsNavScreen> {
  MapplsMapController? _mapplsController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Mappls Navigation: ${widget.targetAddress.shopName}"),
        backgroundColor: Colors.deepOrange,
      ),
      body: MapplsMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(widget.targetAddress.latitude, widget.targetAddress.longitude),
          zoom: 15.0,
        ),
        onMapCreated: (MapplsMapController controller) {
          _mapplsController = controller;
          _mapplsController?.addMarker(
            SymbolOptions(
              geometry: LatLng(widget.targetAddress.latitude, widget.targetAddress.longitude),
              textField: widget.targetAddress.shopName,
              textSize: 12.0,
            ),
          );
        },
        myLocationEnabled: true,
        myLocationTrackingMode: MyLocationTrackingMode.Tracking,
      ),
    );
  }
}
```