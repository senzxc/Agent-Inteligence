import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:geocoding/geocoding.dart';

import '../services/api_service.dart';
import 'agent_task.dart';

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

enum _AgentMenuAction { details, location, centerAgent, locationDetails, tasks }

class _AgentMenuItem extends StatelessWidget {
  const _AgentMenuItem({
    required this.icon,
    required this.label,
    this.trailing,
    this.width = 150,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 46,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF1565C0), size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

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
  bool _isFetchingAgents = false;
  String? _error;
  String? _refreshError;
  Timer? _agentRefreshTimer;
  String? _kantor;
  String? _namaKantor;
  String? _alamatKantor;
  bool _isHeadMarketing = false;
  double? _latitude;
  double? _longitude;
  Offset? _agentMenuTapPosition;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is Map) {
      final appRole = (arguments['APP_ROLE'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final levelUser = (arguments['LEVEL_USER'] ?? '').toString().trim();
      _isHeadMarketing = appRole == 'HEAD_MARKETING' || levelUser == '1';
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
    _agentRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_loadAgents(showLoading: false)),
    );
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

  LatLng? _agentCoordinates(Map<String, dynamic> agent) {
    final latitude = _parseCoordinate(agent['latitude'] ?? agent['LATITUDE']);
    final longitude = _parseCoordinate(
      agent['longitude'] ?? agent['LONGITUDE'],
    );
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  List<flutter_map.Marker> _agentMarkers() {
    return _agents
        .map((agent) {
          final location = _agentCoordinates(agent);
          if (location == null) return null;

          final name = (agent['NAMA'] ?? 'Agen').toString();
          return flutter_map.Marker(
            point: location,
            width: 52,
            height: 60,
            child: _agentMarker(name, _agentMarkerColor(agent['STAMBUK'])),
          );
        })
        .whereType<flutter_map.Marker>()
        .toList();
  }

  Future<void> _showAgentMenu(
    BuildContext context,
    Map<String, dynamic> agent,
    Offset tapPosition,
  ) async {
    final screenSize = MediaQuery.sizeOf(context);
    const horizontalPadding = 8.0;
    const menuGap = 8.0;
    const menuMargin = 8.0;
    final menuWidth = ((screenSize.width - horizontalPadding * 2 - menuGap) / 2)
        .clamp(112.0, 166.0);
    final itemWidth = menuWidth - horizontalPadding * 2;
    const menuHeight = 156.0;

    final requestedLeft = tapPosition.dx < screenSize.width / 2
        ? tapPosition.dx
        : tapPosition.dx - menuWidth;
    final initialLeft = requestedLeft.clamp(
      menuMargin,
      screenSize.width - menuWidth - menuMargin,
    );
    final canOpenRight =
        initialLeft + menuWidth + menuGap + menuWidth <=
        screenSize.width - menuMargin;
    final canOpenLeft = initialLeft - menuGap - menuWidth >= menuMargin;
    final opensSubmenuRight =
        canOpenRight ||
        (!canOpenLeft &&
            tapPosition.dx + menuWidth + menuGap + menuWidth <=
                screenSize.width - menuMargin);
    final menuGroupLeft = opensSubmenuRight
        ? initialLeft.clamp(
            menuMargin,
            screenSize.width - menuWidth * 2 - menuGap - menuMargin,
          )
        : (initialLeft - menuWidth - menuGap).clamp(
            menuMargin,
            screenSize.width - menuWidth * 2 - menuGap - menuMargin,
          );
    final primaryLeft = opensSubmenuRight
        ? menuGroupLeft
        : menuGroupLeft + menuWidth + menuGap;
    final primaryTop =
        (tapPosition.dy < screenSize.height / 2
                ? tapPosition.dy
                : tapPosition.dy - menuHeight)
            .clamp(menuMargin, screenSize.height - menuHeight - menuMargin);
    final primaryAnchorX = primaryLeft + menuWidth / 2 < screenSize.width / 2
        ? primaryLeft
        : primaryLeft + menuWidth;
    final primaryAnchorY = primaryTop + menuHeight / 2 < screenSize.height / 2
        ? primaryTop
        : primaryTop + menuHeight;

    final isTracking =
        agent['isTracking'] == true || agent['isTracking']?.toString() == '1';

    final action = await showMenu<_AgentMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        primaryAnchorX,
        primaryAnchorY,
        screenSize.width - primaryAnchorX,
        screenSize.height - primaryAnchorY,
      ),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 12,
      shadowColor: const Color(0x260F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      items: [
        PopupMenuItem(
          value: _AgentMenuAction.details,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _AgentMenuItem(
            icon: Icons.badge_outlined,
            label: 'Detail Agen',
            width: itemWidth,
          ),
        ),
        if (isTracking)
          PopupMenuItem(
            value: _AgentMenuAction.location,
            enabled: false,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: IconTheme(
              data: const IconThemeData(opacity: 1),
              child: InkWell(
                onTap: () async {
                  await _showAgentLocationSubmenu(
                    context: context,
                    agent: agent,
                    screenSize: screenSize,
                    primaryLeft: primaryLeft,
                    primaryTop: primaryTop,
                    menuWidth: menuWidth,
                    menuGap: menuGap,
                    menuMargin: menuMargin,
                    opensSubmenuRight: opensSubmenuRight,
                    itemWidth: itemWidth,
                  );
                },
                child: _AgentMenuItem(
                  icon: Icons.location_on_outlined,
                  label: 'Lokasi Agen',
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                  width: itemWidth,
                ),
              ),
            ),
          ),
        PopupMenuItem(
          value: _AgentMenuAction.tasks,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _AgentMenuItem(
            icon: Icons.checklist_rounded,
            label: 'Tugas Agen',
            width: itemWidth,
          ),
        ),
      ],
    );
    if (!context.mounted || action == null) return;

    switch (action) {
      case _AgentMenuAction.details:
        await _showAgentDetails(agent);
      case _AgentMenuAction.location:
        break;
      case _AgentMenuAction.centerAgent:
        _showAgentLocation(agent);
      case _AgentMenuAction.locationDetails:
        await _showAgentLocationDetails(agent);
        break;
      case _AgentMenuAction.tasks:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                AgentTaskPage(agent: agent, canManageTasks: !_isHeadMarketing),
          ),
        );
    }
  }

  Future<void> _showAgentLocationSubmenu({
    required BuildContext context,
    required Map<String, dynamic> agent,
    required Size screenSize,
    required double primaryLeft,
    required double primaryTop,
    required double menuWidth,
    required double menuGap,
    required double menuMargin,
    required bool opensSubmenuRight,
    required double itemWidth,
  }) async {
    final submenuLeft = opensSubmenuRight
        ? primaryLeft + menuWidth + menuGap
        : primaryLeft - menuGap - menuWidth;
    const submenuHeight = 108.0;
    final submenuTop = (primaryTop + 60).clamp(
      menuMargin,
      screenSize.height - submenuHeight - menuMargin,
    );
    final submenuAnchorX = submenuLeft + menuWidth / 2 < screenSize.width / 2
        ? submenuLeft
        : submenuLeft + menuWidth;
    final submenuAnchorY =
        submenuTop + submenuHeight / 2 < screenSize.height / 2
        ? submenuTop
        : submenuTop + submenuHeight;
    final action = await showMenu<_AgentMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        submenuAnchorX,
        submenuAnchorY,
        screenSize.width - submenuAnchorX,
        screenSize.height - submenuAnchorY,
      ),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 12,
      shadowColor: const Color(0x260F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      items: [
        PopupMenuItem(
          value: _AgentMenuAction.centerAgent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _AgentMenuItem(
            icon: Icons.my_location_rounded,
            label: 'Pusatkan',
            width: itemWidth,
          ),
        ),
        PopupMenuItem(
          value: _AgentMenuAction.locationDetails,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _AgentMenuItem(
            icon: Icons.info_outline_rounded,
            label: 'Detail Lokasi',
            width: itemWidth,
          ),
        ),
      ],
    );
    if (!context.mounted) return;

    // The submenu route closes first; pop its parent menu afterward so both
    // menus disappear together when the user taps outside or picks an action.
    Navigator.of(context).pop();
    if (action == null || !context.mounted) return;

    switch (action) {
      case _AgentMenuAction.centerAgent:
        _showAgentLocation(agent);
      case _AgentMenuAction.locationDetails:
        await _showAgentLocationDetails(agent);
      case _AgentMenuAction.details:
      case _AgentMenuAction.location:
      case _AgentMenuAction.tasks:
        break;
    }
  }

  Future<void> _showAgentDetails(Map<String, dynamic> agent) {
    final name = (agent['NAMA'] ?? '-').toString();
    final stambuk = (agent['STAMBUK'] ?? '-').toString();
    final kantor = (agent['KANTOR'] ?? '-').toString();
    final tracking = agent['isTracking'] == true;
    final alamat = (agent['ALAMAT'] ?? agent['ALAMAT_USER'] ?? 'Belum tersedia')
        .toString()
        .trim();
    final email = (agent['EMAIL'] ?? 'Belum tersedia').toString().trim();
    final statusColor = tracking
        ? const Color(0xFF15803D)
        : const Color(0xFF64748B);

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.86,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 22, 16, 22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0D47A1), Color(0xFF1B72D7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          _agentInitials(name),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PROFIL AGEN',
                              style: TextStyle(
                                color: Color(0xFFDCEBFF),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                tracking
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 16,
                                color: statusColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tracking ? 'Sedang tracking' : 'Offline',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'INFORMASI AGEN',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _agentDetailTile(
                          icon: Icons.badge_outlined,
                          label: 'Stambuk',
                          value: stambuk,
                        ),
                        _agentDetailTile(
                          icon: Icons.apartment_rounded,
                          label: 'Kantor',
                          value: kantor,
                        ),
                        _agentDetailTile(
                          icon: Icons.location_on_outlined,
                          label: 'Alamat',
                          value: alamat.isEmpty ? 'Belum tersedia' : alamat,
                        ),
                        _agentDetailTile(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: email.isEmpty ? 'Belum tersedia' : email,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE8EEF6))),
                  ),
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Tutup'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String> _reverseGeocode(LatLng location) async {
    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isEmpty) {
        return 'Alamat belum dapat ditemukan';
      }

      final place = placemarks.first;

      final parts =
          [
                place.street,
                place.subLocality,
                place.locality,
                place.subAdministrativeArea,
                place.administrativeArea,
                place.postalCode,
                place.country,
              ]
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();

      // Hilangkan komponen alamat yang duplikat.
      final uniqueParts = <String>[];
      for (final part in parts) {
        if (!uniqueParts.any(
          (existing) => existing.toLowerCase() == part.toLowerCase(),
        )) {
          uniqueParts.add(part);
        }
      }

      if (uniqueParts.isEmpty) {
        return 'Alamat belum dapat ditemukan';
      }

      return uniqueParts.join(', ');
    } catch (e) {
      debugPrint('Reverse geocoding gagal: $e');
      return 'Alamat tidak dapat ditemukan saat ini';
    }
  }

  String _agentLastUpdateText(Map<String, dynamic> agent) {
    // Sesuaikan nama field jika API menggunakan nama lain.
    final candidates = [
      'LAST_UPDATE',
      'last_update',
      'UPDATED_AT',
      'updated_at',
      'updatedAt',
      'WAKTU_UPDATE',
      'TGL_UPDATE',
      'TGL_TRACKING',
      'timestamp',
      'TIMESTAMP',
    ];

    Object? rawValue;

    for (final key in candidates) {
      final value = agent[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        rawValue = value;
        break;
      }
    }

    if (rawValue == null) {
      return 'Belum tersedia dari server';
    }

    DateTime? date;

    if (rawValue is DateTime) {
      date = rawValue;
    } else if (rawValue is num) {
      // Mendukung timestamp Unix dalam detik atau milidetik.
      final value = rawValue.toInt();
      date = DateTime.fromMillisecondsSinceEpoch(
        value.abs() < 100000000000 ? value * 1000 : value,
      );
    } else {
      date = DateTime.tryParse(rawValue.toString().trim());
    }

    if (date == null) {
      return rawValue.toString();
    }

    date = date.toLocal();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(date.day)}-${twoDigits(date.month)}-${date.year} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}:${twoDigits(date.second)}';
  }

  Future<void> _showAgentLocationDetails(Map<String, dynamic> agent) async {
    final location = _agentCoordinates(agent);

    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Koordinat lokasi agen belum tersedia.')),
      );
      return;
    }

    final isTracking = agent['isTracking'] == true;
    final addressFuture = _reverseGeocode(location);
    final timestamp = _agentLastUpdateText(agent);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.86,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HEADER
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 20, 12, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF1B72D7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DETAIL LOKASI',
                                style: TextStyle(
                                  color: Color(0xFFDCEBFF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Lokasi Agen',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  // ISI DIALOG
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ALAMAT TERDETEKSI',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Alamat hasil reverse geocoding.
                          FutureBuilder<String>(
                            future: addressFuture,
                            builder: (context, snapshot) {
                              final loading =
                                  snapshot.connectionState ==
                                  ConnectionState.waiting;

                              final address =
                                  snapshot.data ??
                                  'Alamat belum dapat ditemukan';

                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF3FF),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: const Color(0xFFD5E5FA),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.map_rounded,
                                      color: Color(0xFF1565C0),
                                      size: 23,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: loading
                                          ? const Padding(
                                              padding: EdgeInsets.symmetric(
                                                vertical: 4,
                                              ),
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 17,
                                                    height: 17,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      'Mencari alamat...',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF475569,
                                                        ),
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : Text(
                                              address,
                                              style: const TextStyle(
                                                color: Color(0xFF14264D),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                height: 1.5,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 22),

                          const Text(
                            'INFORMASI TRACKING',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Status tracking.
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: isTracking
                                  ? const Color(0xFFF0FDF4)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isTracking
                                    ? const Color(0xFFBBF7D0)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isTracking
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color: isTracking
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFF64748B),
                                  size: 21,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Status Agen',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  isTracking ? 'Tracking' : 'Offline',
                                  style: TextStyle(
                                    color: isTracking
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFF64748B),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          _agentDetailTile(
                            icon: Icons.access_time_rounded,
                            label: 'Update Terakhir',
                            value: timestamp,
                          ),

                          _agentDetailTile(
                            icon: Icons.my_location_rounded,
                            label: 'Koordinat GPS',
                            value:
                                '${location.latitude.toStringAsFixed(6)}, '
                                '${location.longitude.toStringAsFixed(6)}',
                          ),

                          const SizedBox(height: 6),

                          // Tombol salin alamat.
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final address = await addressFuture;

                                if (!dialogContext.mounted) return;

                                if (address.startsWith('Alamat ')) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Alamat belum tersedia untuk disalin.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                await Clipboard.setData(
                                  ClipboardData(text: address),
                                );

                                if (!dialogContext.mounted) return;

                                ScaffoldMessenger.of(
                                  dialogContext,
                                ).showSnackBar(
                                  const SnackBar(
                                    content: Text('Alamat berhasil disalin.'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('Salin Alamat'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1565C0),
                                side: const BorderSide(
                                  color: Color(0xFF1565C0),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Pusatkan peta ke agen.
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _showAgentLocation(agent);
                              },
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('Lihat di Peta'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1565C0),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _agentDetailTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEF6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: const Color(0xFF1565C0), size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF14264D),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAgentLocation(Map<String, dynamic> agent) {
    final location = _agentCoordinates(agent);
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lokasi agen belum tersedia atau belum aktif tracking.',
          ),
        ),
      );
      return;
    }

    _animationStartCenter = _mapController.camera.center;
    _animationTargetCenter = location;
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

  Future<void> _loadAgents({bool showLoading = true}) async {
    if (_kantor == null || _kantor!.isEmpty || _isFetchingAgents) return;
    _isFetchingAgents = true;

    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

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
        _error = null;
        _refreshError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        final message = e.toString().replaceFirst('Exception: ', '');
        if (showLoading || _agents.isEmpty) {
          _error = message;
        } else {
          _refreshError = message;
        }
      });
    } finally {
      _isFetchingAgents = false;
    }
  }

  @override
  void dispose() {
    _agentRefreshTimer?.cancel();
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
          if (_refreshError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Lokasi terakhir tetap ditampilkan; gagal memperbarui: '
              '$_refreshError',
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
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
                                ..._agentMarkers(),
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
          const SizedBox(width: 10),
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _agentMenuTapPosition = details.globalPosition,
      onTap: () {
        final tapPosition = _agentMenuTapPosition;
        if (tapPosition != null) {
          _showAgentMenu(context, agent, tapPosition);
        }
      },
      child: Container(
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            minVerticalPadding: 12,
            titleAlignment: ListTileTitleAlignment.center,
            leading: SizedBox(
              width: 44,
              height: 56,
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
      ),
    );
  }
}
