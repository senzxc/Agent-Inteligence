import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import '../services/api_service.dart';

const _branchMapGradientColors = [Color(0xFF0D47A1), Color(0xFF1565C0)];
const _agentMarkerColors = [
  Color(0xFF0284C7),
  Color(0xFFDB2777),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFEA580C),
  Color(0xFF0D9488),
  Color(0xFFDC2626),
  Color(0xFF4F46E5),
  Color(0xFFCA8A04),
  Color(0xFF64748B),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
];
const _pageStart = Color(0xFFF8FBFF);
const _pageEnd = Color(0xFFEAF3FF);
const _softCardShadow = BoxShadow(
  color: Color(0x260F172A),
  blurRadius: 14,
  offset: Offset(0, 6),
);

class AgentListPage extends StatefulWidget {
  const AgentListPage({super.key});

  @override
  State<AgentListPage> createState() => _AgentListPageState();
}

class _AgentListPageState extends State<AgentListPage>
    with SingleTickerProviderStateMixin {
  final flutter_map.MapController _mapController = flutter_map.MapController();
  late final AnimationController _centerAnimationController;
  LatLng? _animationStartCenter;
  LatLng? _animationTargetCenter;
  double _animationStartZoom = 15;

  List<Map<String, dynamic>> _agents = [];
  bool _loading = true;
  String? _error;
  String? _kantor;
  String? _namaKantor;
  String? _alamatKantor;
  double? _latitude;
  double? _longitude;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is Map) {
      _kantor = arguments['KODE_KANTOR']?.toString().trim();
      _namaKantor = arguments['NAMA_KANTOR']?.toString().trim();
      _alamatKantor = arguments['ALAMAT_KANTOR']?.toString().trim();
      _latitude = _parseCoordinate(arguments['LATITUDE']);
      _longitude = _parseCoordinate(arguments['LONGITUDE']);
    } else if (arguments is String) {
      _kantor = arguments.trim();
    }

    if (_kantor == null || _kantor!.isEmpty) return;
    _loadAgents();
  }

  @override
  void initState() {
    super.initState();
    _centerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_updateMapCenterAnimation);
  }

  void _updateMapCenterAnimation() {
    final start = _animationStartCenter;
    final target = _animationTargetCenter;
    if (start == null || target == null) return;

    final progress = Curves.easeInOutCubic.transform(
      _centerAnimationController.value,
    );
    final center = LatLng(
      start.latitude + (target.latitude - start.latitude) * progress,
      start.longitude + (target.longitude - start.longitude) * progress,
    );
    final zoom = _animationStartZoom + (16 - _animationStartZoom) * progress;
    _mapController.move(center, zoom);
  }

  double? _parseCoordinate(Object? value) {
    final coordinate = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    return coordinate != null && coordinate.isFinite ? coordinate : null;
  }

  bool get _hasValidCoordinates {
    final latitude = _latitude;
    final longitude = _longitude;
    return latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  void _recenterMap() {
    if (!_hasValidCoordinates) return;
    _animationStartCenter = _mapController.camera.center;
    _animationTargetCenter = LatLng(_latitude!, _longitude!);
    _animationStartZoom = _mapController.camera.zoom;
    _centerAnimationController.forward(from: 0);
  }

  String _agentInitials(Object? value) {
    final name = (value ?? '').toString().trim();
    if (name.isEmpty) return '??';
    return name.characters.take(2).toString().toUpperCase();
  }

  Color _agentMarkerColor(Object? identity) {
    final key = (identity ?? '').toString().trim().toUpperCase();
    if (key.isEmpty) return _agentMarkerColors[0];

    var hash = 0;
    for (final codeUnit in key.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7FFFFFFF;
    }
    return _agentMarkerColors[hash % _agentMarkerColors.length];
  }

  Widget _agentMarker(String name, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            _agentInitials(name),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      ],
    );
  }

  Future<void> _loadAgents() async {
    if (_kantor == null || _kantor!.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ApiService.getAgentList(kantor: _kantor);
      final data = result['data'];

      if (data is! Map || data['success'] != true) {
        throw Exception(
          data is Map
              ? data['message']?.toString() ?? 'Gagal memuat daftar agen.'
              : 'Format respons server tidak valid.',
        );
      }

      final rows = data['data'];
      if (rows is! List) {
        throw Exception('Data agen dari server tidak valid.');
      }

      if (!mounted) return;

      setState(() {
        _agents = rows
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _centerAnimationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Widget _buildBranchHero() {
    final address = _alamatKantor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE8F8)),
        boxShadow: const [_softCardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_city_rounded,
                color: Color(0xFF0D47A1),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _namaKantor ?? 'Lokasi Kantor',
                  style: const TextStyle(
                    color: Color(0xFF14264D),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              address,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 280,
              child: _hasValidCoordinates
                  ? Stack(
                      children: [
                        flutter_map.FlutterMap(
                          mapController: _mapController,
                          options: flutter_map.MapOptions(
                            initialCenter: LatLng(_latitude!, _longitude!),
                            initialZoom: 15,
                          ),
                          children: [
                            flutter_map.TileLayer(
                              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                              userAgentPackageName:
                                  'com.devasatrio.bi_cabang_tracker',
                            ),
                            flutter_map.MarkerLayer(
                              markers: [
                                flutter_map.Marker(
                                  point: LatLng(_latitude!, _longitude!),
                                  width: 50,
                                  height: 50,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: _branchMapGradientColors,
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF1565C0)
                                              .withValues(alpha: 0.35),
                                          blurRadius: 15,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      shadcn.LucideIcons.mapPin,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Material(
                            color: Colors.white,
                            elevation: 4,
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Pusatkan ke lokasi kantor',
                              onPressed: _recenterMap,
                              icon: const Icon(
                                Icons.my_location_rounded,
                                color: Color(0xFF0D47A1),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: const Color(0xFFEAF3FF),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(20),
                      child: const Text(
                        'Koordinat lokasi kantor belum tersedia.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF475569)),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          _namaKantor == null || _namaKantor!.isEmpty
              ? 'Daftar Agen'
              : 'Agen - $_namaKantor',
        ),
        actions: [
          if (_kantor != null && _kantor!.isNotEmpty)
            IconButton(
              onPressed: _loadAgents,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      backgroundColor: _pageStart,
      body: _kantor == null || _kantor!.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Pilih cabang terlebih dahulu untuk melihat daftar agen.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAgents,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_pageStart, _pageEnd],
                  ),
                ),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildBranchHero(),
                    const SizedBox(height: 20),
                    const Text(
                      'Daftar Agen',
                      style: TextStyle(
                        color: Color(0xFF14264D),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 42,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadAgents,
                              child: const Text('Coba Lagi'),
                            ),
                          ],
                        ),
                      )
                    else if (_agents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('Belum ada data agen.')),
                      )
                    else
                      for (final agent in _agents) ...[
                        _buildAgentCard(agent),
                        if (agent != _agents.last) const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAgentCard(Map<String, dynamic> agent) {
    final name = (agent['NAMA'] ?? '-').toString();
    final stambuk = (agent['STAMBUK'] ?? '-').toString();
    final kantor = (agent['KANTOR'] ?? '-').toString();
    final tracking = agent['isTracking'] == true;
    final markerColor = _agentMarkerColor(stambuk);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [_softCardShadow],
      ),
      child: Card(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: SizedBox(
            width: 44,
            height: 48,
            child: Center(child: _agentMarker(name, markerColor)),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('Stambuk: $stambuk\nKantor: $kantor'),
          isThreeLine: true,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: tracking ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 4),
              Text(
                tracking ? 'Tracking' : 'Offline',
                style: TextStyle(
                  fontSize: 11,
                  color: tracking
                      ? Colors.green.shade800
                      : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
