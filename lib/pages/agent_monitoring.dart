import 'dart:async';

import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../services/api_service.dart';

const Color _blue = Color(0xFF1565C0);

class AgentMonitoringPage extends StatefulWidget {
  const AgentMonitoringPage({super.key});

  @override
  State<AgentMonitoringPage> createState() => _AgentMonitoringPageState();
}

class _AgentMonitoringPageState extends State<AgentMonitoringPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _centerAnimationController;
  final flutter_map.MapController _mapController = flutter_map.MapController();
  LatLng? _animationStartCenter;
  LatLng? _animationTargetCenter;
  double _animationStartZoom = 11;

  List<Map<String, dynamic>> _agents = [];
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _centerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_updateMapCenterAnimation);
    _loadAgents();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _loadAgents());
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

  void _animateMapToAgent(LatLng targetLocation) {
    _animationStartCenter = _mapController.camera.center;
    _animationTargetCenter = targetLocation;
    _animationStartZoom = _mapController.camera.zoom;
    _centerAnimationController.forward(from: 0);
  }

  Future<void> _loadAgents() async {
    if (!mounted) return;

    try {
      final result = await ApiService.getAgents();
      final data = result['data'];

      if (data is! Map || data['success'] != true) {
        throw Exception('Respons API tidak valid.');
      }

      final rawAgents = data['data'];
      if (rawAgents is! List) {
        throw Exception('Format daftar agen tidak valid.');
      }

      final agents = rawAgents
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((agent) {
            final lat = double.tryParse(agent['latitude']?.toString() ?? '');
            final lng = double.tryParse(agent['longitude']?.toString() ?? '');
            return lat != null &&
                lng != null &&
                lat >= -90 &&
                lat <= 90 &&
                lng >= -180 &&
                lng <= 180;
          })
          .toList();

      if (!mounted) return;

      setState(() {
        _agents = agents;
        _loading = false;
        _error = null;
        _lastUpdated = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  LatLng _coordinates(Map<String, dynamic> agent) {
    return LatLng(
      double.parse(agent['latitude'].toString()),
      double.parse(agent['longitude'].toString()),
    );
  }

  String _updatedAt(Map<String, dynamic> agent) {
    final raw = agent['lastUpdated']?.toString();
    if (raw == null) return 'Belum tersedia';

    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'Belum tersedia';

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _centerAnimationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arguments = ModalRoute.of(context)?.settings.arguments;
    final user = arguments is Map
        ? Map<String, dynamic>.from(arguments)
        : <String, dynamic>{};

    final level =
        (user['LEVEL_USER'] ?? user['level_user'] ?? user['level'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

    // Pemeriksaan tambahan di UI. Backend tetap wajib
    // memverifikasi hak akses admin.
    if (level != 'A') {
      return Scaffold(
        headers: [
          AppBar(
            title: const Text('Agent Monitoring'),
            leading: [
              IconButton(
                variance: ButtonVariance.ghost,
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Akses hanya tersedia untuk admin.'),
          ),
        ),
      );
    }

    final center = _agents.isNotEmpty
        ? _coordinates(_agents.first)
        : const LatLng(-6.2000, 106.8167);

    return Scaffold(
      headers: [
        AppBar(
          title: const Text('Agent Monitoring'),
          leading: [
            IconButton(
              variance: ButtonVariance.ghost,
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          trailing: [
            IconButton(
              variance: ButtonVariance.ghost,
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: _loadAgents,
            ),
          ],
        ),
      ],
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(LucideIcons.users, color: _blue, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Agen aktif',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_agents.length} agen dengan koordinat',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Gagal memuat agen: $_error',
                  style: const TextStyle(color: Color(0xFFDC2626)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: flutter_map.FlutterMap(
                    mapController: _mapController,
                    options: flutter_map.MapOptions(
                      initialCenter: center,
                      initialZoom: 11,
                    ),
                    children: [
                      flutter_map.TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.agent_inteligence',
                      ),
                      flutter_map.MarkerLayer(
                        markers: _agents.map((agent) {
                          return flutter_map.Marker(
                            point: _coordinates(agent),
                            width: 48,
                            height: 48,
                            child: Tooltip(
                              tooltip: (context) => Text(
                                '${agent['nama'] ?? agent['stambuk'] ?? 'Agen'}',
                              ),
                              child: const Icon(
                                LucideIcons.mapPin,
                                color: _blue,
                                size: 40,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _lastUpdated == null
                      ? 'Belum diperbarui'
                      : 'Diperbarui pukul '
                            '${_updatedAt({'lastUpdated': _lastUpdated!.toIso8601String()})}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _agents.isEmpty && !_loading
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          _error == null
                              ? 'Belum ada agen aktif dengan lokasi.'
                              : 'Data agen belum dapat ditampilkan.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _agents.length,
                      itemBuilder: (context, index) {
                        final agent = _agents[index];
                        final point = _coordinates(agent);

                        return Card(
                          child: GestureDetector(
                            onTap: () {
                              _animateMapToAgent(point);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(1),
                              child: Row(
                                children: [
                                  const Icon(
                                    LucideIcons.mapPin,
                                    color: _blue,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (agent['nama'] ??
                                                  agent['stambuk'] ??
                                                  'Agen')
                                              .toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Kantor: ${agent['kantor'] ?? '-'}',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        Text(
                                          '${point.latitude.toStringAsFixed(6)}, '
                                          '${point.longitude.toStringAsFixed(6)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          'Update: ${_updatedAt(agent)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    LucideIcons.chevronRight,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
