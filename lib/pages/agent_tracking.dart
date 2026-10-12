
import 'dart:async';

import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const Color _blueDark = Color(0xFF0D47A1);
const Color _blueLight = Color(0xFF2196F3);
const Color _pageStart = Color(0xFFF8FBFF);
const Color _pageEnd = Color(0xFFEAF3FF);

const LinearGradient _brandGradient = LinearGradient(
  colors: [_blueDark, _blueLight],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

const List<Color> _brandGradientColors = [Color(0xFF0D47A1), Color(0xFF1B72D7)];

const BoxShadow _softComponentShadow = BoxShadow(
  color: Color(0x260F172A),
  blurRadius: 14,
  offset: Offset(0, 6),
);

AbstractButtonStyle _brandButtonStyle() {
  return ButtonStyle.primary().copyWith(
    decoration: (context, states, defaultDecoration) {
      if (states.contains(WidgetState.disabled)) {
        return defaultDecoration;
      }

      final decoration = defaultDecoration is BoxDecoration
          ? defaultDecoration
          : const BoxDecoration();
      return decoration.copyWith(
        color: null,
        gradient: const LinearGradient(
          colors: _brandGradientColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: const [_softComponentShadow],
      );
    },
  );
}

class AgentTrackingPage extends StatefulWidget {
  const AgentTrackingPage({super.key});

  @override
  State<AgentTrackingPage> createState() =>
      _AgentTrackingPageState();
}

class _AgentTrackingPageState extends State<AgentTrackingPage> {
  final flutter_map.MapController _mapController =
      flutter_map.MapController();

  StreamSubscription<Position>? _positionStream;

  Position? _position;
  bool _isTracking = false;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastUpdated;

  static const LatLng _defaultCenter = LatLng(-6.2000, 106.8167);

  Future<void> _startTracking() async {
    if (_isLoading || _isTracking) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Pastikan layanan lokasi aktif.
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception(
          'GPS belum aktif. Aktifkan lokasi di pengaturan HP.',
        );
      }

      // Periksa dan minta izin lokasi.
      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw Exception('Izin lokasi belum diberikan.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Izin lokasi ditolak permanen. '
          'Aktifkan melalui pengaturan aplikasi.',
        );
      }

      // Ambil posisi pertama sebelum memulai stream.
      final firstPosition =
          await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      setState(() {
        _position = firstPosition;
        _lastUpdated = DateTime.now();
        _isTracking = true;
        _isLoading = false;
      });

      _mapController.move(
        LatLng(firstPosition.latitude, firstPosition.longitude),
        16,
      );

      // Dengarkan perubahan lokasi selanjutnya.
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (Position position) {
          if (!mounted) return;

          setState(() {
            _position = position;
            _lastUpdated = DateTime.now();
          });

          _mapController.move(
            LatLng(position.latitude, position.longitude),
            16,
          );
        },
        onError: (Object error) {
          if (!mounted) return;

          setState(() {
            _errorMessage = 'Gagal memperbarui lokasi: $error';
          });
        },
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error
            .toString()
            .replaceFirst('Exception: ', '');
        _isTracking = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _stopTracking() async {
    await _positionStream?.cancel();
    _positionStream = null;

    if (!mounted) return;

    setState(() {
      _isTracking = false;
      _isLoading = false;
    });
  }

  String _formatCoordinate(double? value) {
    return value == null ? '--' : value.toStringAsFixed(6);
  }

  String _formatUpdatedAt() {
    final time = _lastUpdated;

    if (time == null) return 'Belum tersedia';

    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
    String? unit,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F0FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _blueDark, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF14264D),
                ),
              ),
              if (unit != null)
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;

    final center = position == null
        ? _defaultCenter
        : LatLng(position.latitude, position.longitude);

    return Scaffold(
      headers: [
        AppBar(
          title: const Text('Agent Tracking'),
          leading: [
            IconButton(
              variance: ButtonVariance.ghost,
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pageStart, _pageEnd],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors:  _brandGradientColors
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x260D47A1),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.mapPin,
                        color: Colors.white,
                        size: 32,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Pantau Lokasi Anda',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Halaman pengujian GPS perangkat.',
                        style: TextStyle(
                          color: Color(0xFFE3EEFF),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // STATUS
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFDCE8F8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _isTracking
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Status Tracking',
                              style: TextStyle(
                                color: Color(0xFF14264D),
                                fontWeight: FontWeight.w700,
                                fontSize: 16
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isTracking
                                  ? 'GPS sedang diperbarui'
                                  : 'Tracking belum aktif',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _isTracking ? 'AKTIF' : 'NONAKTIF',
                        style: TextStyle(
                          color: _isTracking
                              ? const Color(0xFF15803D)
                              : const Color(0xFF64748B),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // MAP
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 270,
                    child: Stack(
                      children: [
                        flutter_map.FlutterMap(
                          mapController: _mapController,
                          options: flutter_map.MapOptions(
                            initialCenter: _defaultCenter,
                            initialZoom: 12,
                          ),
                          children: [
                            flutter_map.TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'com.example.agent_inteligence',
                            ),
                            if (position != null)
                              flutter_map.MarkerLayer(
                                markers: [
                                  flutter_map.Marker(
                                    point: center,
                                    width: 52,
                                    height: 52,
                                    child: const Icon(
                                      LucideIcons.mapPin,
                                      color: _blueDark,
                                      size: 42,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (position == null)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Aktifkan GPS untuk menampilkan posisi Anda.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // LOCATION INFORMATION
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFDCE8F8),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F172A),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Informasi Lokasi',
                        style: TextStyle(
                          color: Color(0xFF14264D),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pembaruan terakhir: ${_formatUpdatedAt()}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _infoTile(
                              icon: LucideIcons.mapPin,
                              title: 'Latitude',
                              value: _formatCoordinate(
                                position?.latitude,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _infoTile(
                              icon: LucideIcons.compass,
                              title: 'Longitude',
                              value: _formatCoordinate(
                                position?.longitude,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: _infoTile(
                              icon: LucideIcons.crosshair,
                              title: 'Akurasi',
                              value: position == null
                                  ? '--'
                                  : position.accuracy
                                      .toStringAsFixed(1),
                              unit: 'meter',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _infoTile(
                              icon: LucideIcons.gauge,
                              title: 'Kecepatan',
                              value: position == null
                                  ? '--'
                                  : (position.speed * 3.6)
                                      .toStringAsFixed(1),
                              unit: 'km/jam',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFECACA),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          LucideIcons.circleAlert,
                          color: Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Color(0xFF991B1B),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // START / STOP BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: Button(
                    style: _brandButtonStyle(),
                    onPressed: _isLoading
                        ? null
                        : (_isTracking
                            ? _stopTracking
                            : _startTracking),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else
                          Icon(
                            _isTracking
                                ? LucideIcons.square
                                : LucideIcons.play,
                            size: 19,
                          ),
                        const SizedBox(width: 10),
                        Text(
                          _isLoading
                              ? 'Memeriksa GPS...'
                              : (_isTracking
                                  ? 'Selesai Bertugas'
                                  : 'Mulai Bertugas'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  'Pengujian ini hanya membaca lokasi perangkat. '
                  'Koordinat belum dikirim atau disimpan ke server.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}