import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:geocoding/geocoding.dart';

import '../services/api_service.dart';
import '../widgets/agent_marker.dart';
import 'agent_task.dart';

const _branchMapGradientColors = [Color(0xFF0D47A1), Color(0xFF1565C0)];
const _pageStart = Color(0xFFF8FBFF);
const _pageEnd = Color(0xFFEAF3FF);
const _softCardShadow = BoxShadow(
  color: Color(0x260F172A),
  blurRadius: 14,
  offset: Offset(0, 6),
);

enum _AgentMenuAction { details, location, centerAgent, locationDetails, tasks }

enum _AgentSortField { name, role }

InputDecoration _filterInputDecoration({required String hint}) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD5E5FA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD5E5FA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
    ),
  );
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1565C0), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

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
  final ScrollController _pageScrollController = ScrollController();
  final TextEditingController _agentSearchController = TextEditingController();
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
  bool _canAddTasks = true;
  double? _latitude;
  double? _longitude;
  Offset? _agentMenuTapPosition;
  bool _initialized = false;
  bool _showAgentSearch = false;
  String _selectedAgentRole = '';
  _AgentSortField _agentSortField = _AgentSortField.name;
  bool _sortAscending = true;

  List<Map<String, dynamic>> get _visibleAgents {
    final query = _agentSearchController.text.trim().toLowerCase();
    final agents = _agents.where((agent) {
      final role = (agent['C_AGENCY_JABATAN'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (_selectedAgentRole.isNotEmpty && role != _selectedAgentRole) {
        return false;
      }

      if (query.isEmpty) return true;
      return [
        agent['NAMA_AGEN'],
        agent['NOMOR_AGEN'],
        agent['NOMOR_HP'],
        agent['A_EMAIL'] ?? agent['EMAIL'],
        agent['C_AGENCY_JABATAN'],
      ].any((value) => (value ?? '').toString().toLowerCase().contains(query));
    }).toList();

    agents.sort((left, right) {
      final leftOnline = left['isTracking'] == true;
      final rightOnline = right['isTracking'] == true;
      if (leftOnline != rightOnline) return leftOnline ? -1 : 1;

      final leftValue = _agentSortField == _AgentSortField.name
          ? left['NAMA_AGEN']
          : left['C_AGENCY_JABATAN'];
      final rightValue = _agentSortField == _AgentSortField.name
          ? right['NAMA_AGEN']
          : right['C_AGENCY_JABATAN'];
      final comparison = (leftValue ?? '').toString().toLowerCase().compareTo(
        (rightValue ?? '').toString().toLowerCase(),
      );
      if (comparison == 0) {
        return (left['NAMA_AGEN'] ?? '').toString().toLowerCase().compareTo(
          (right['NAMA_AGEN'] ?? '').toString().toLowerCase(),
        );
      }
      return _sortAscending ? comparison : -comparison;
    });
    return agents;
  }

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
      final agencyRole = (arguments['C_AGENCY_JABATAN'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      _isHeadMarketing =
          appRole == 'HEAD_MARKETING' || agencyRole == 'KD' || levelUser == '1';
      _canAddTasks =
          !_isHeadMarketing &&
          appRole != 'HEAD_AGENT' &&
          !['AD', 'AM', 'AS'].contains(agencyRole);
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
        !(latitude == 0 && longitude == 0) &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  LatLng get _initialMapCenter {
    if (_hasValidCoordinates) return LatLng(_latitude!, _longitude!);

    for (final agent in _agents) {
      final location = _agentCoordinates(agent);
      if (location != null) return location;
    }

    return const LatLng(-2.5, 118);
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

          final name = (agent['NAMA_AGEN'] ?? 'Agen').toString();
          return flutter_map.Marker(
            point: location,
            width: 52,
            height: 60,
            child: AgentMarker(name: name, identity: agent['NOMOR_AGEN']),
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
        await _showAgentLocation(agent);
      case _AgentMenuAction.locationDetails:
        await _showAgentLocationDetails(agent);
        break;
      case _AgentMenuAction.tasks:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AgentTaskPage(
              agent: agent,
              canManageTasks: !_isHeadMarketing,
              canAddTasks: _canAddTasks,
            ),
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
        await _showAgentLocation(agent);
      case _AgentMenuAction.locationDetails:
        await _showAgentLocationDetails(agent);
      case _AgentMenuAction.details:
      case _AgentMenuAction.location:
      case _AgentMenuAction.tasks:
        break;
    }
  }

  Future<void> _showAgentDetails(Map<String, dynamic> agent) {
    final name = (agent['NAMA_AGEN'] ?? '-').toString();
    final agentNumber = (agent['NOMOR_AGEN'] ?? '-').toString();
    final namaKantor = (agent['NAMA_KANTOR'] ?? '').toString().trim();
    final kodeKantor = (agent['KODE_KANTOR'] ?? '').toString().trim();
    final kantor = namaKantor.isNotEmpty
        ? (kodeKantor.isNotEmpty ? '$namaKantor - ($kodeKantor)' : namaKantor)
        : (kodeKantor.isNotEmpty ? kodeKantor : '-');
    final tracking = agent['isTracking'] == true;
    final alamat = (agent['ALAMAT'] ?? 'Belum tersedia').toString().trim();
    final email = (agent['A_EMAIL'] ?? agent['EMAIL'] ?? 'Belum tersedia')
        .toString()
        .trim();
    final phone = (agent['NOMOR_HP'] ?? 'Belum tersedia').toString().trim();
    final jabatan = (agent['C_AGENCY_JABATAN'] ?? 'Belum tersedia')
        .toString()
        .trim();
    final tanggalLahir = (agent['TANGGAL_LAHIR'] ?? 'Belum tersedia')
        .toString()
        .trim();
    final tanggalLisensi = (agent['TANGGAL_LISENSI'] ?? 'Belum tersedia')
        .toString()
        .trim();
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
                          label: 'Nomor Agen',
                          value: agentNumber,
                        ),
                        _agentDetailTile(
                          icon: Icons.work_outline,
                          label: 'Jabatan',
                          value: jabatan,
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
                          icon: Icons.phone_outlined,
                          label: 'Nomor HP',
                          value: phone.isEmpty ? 'Belum tersedia' : phone,
                        ),
                        _agentDetailTile(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: email.isEmpty ? 'Belum tersedia' : email,
                        ),
                        _agentDetailTile(
                          icon: Icons.cake_outlined,
                          label: 'Tanggal Lahir',
                          value: tanggalLahir,
                        ),
                        // _agentDetailTile(
                        //   icon: Icons.verified_outlined,
                        //   label: 'Tanggal Lisensi',
                        //   value: tanggalLisensi,
                        // ),
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

                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFD),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE8EEF6),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE7F0FF),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: const Icon(
                                    Icons.my_location_rounded,
                                    color: Color(0xFF1565C0),
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Koordinat GPS',
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${location.latitude.toStringAsFixed(6)}, '
                                        '${location.longitude.toStringAsFixed(6)}',
                                        style: const TextStyle(
                                          color: Color(0xFF14264D),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Salin koordinat',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () async {
                                    final coordinates =
                                        '${location.latitude.toStringAsFixed(6)}, '
                                        '${location.longitude.toStringAsFixed(6)}';

                                    await Clipboard.setData(
                                      ClipboardData(text: coordinates),
                                    );

                                    if (!dialogContext.mounted) return;

                                    ScaffoldMessenger.of(dialogContext)
                                        .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Koordinat berhasil disalin.',
                                            ),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                  },
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    color: Color(0xFF1565C0),
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
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
                              onPressed: () async {
                                Navigator.pop(dialogContext);
                                await _showAgentLocation(agent);
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

  Future<void> _showAgentLocation(Map<String, dynamic> agent) async {
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

    if (_pageScrollController.hasClients) {
      await _pageScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
    if (!mounted) return;

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
      final results = await Future.wait([
        ApiService.getAgentList(kantor: _kantor),
        ApiService.getAgents(),
      ]);
      final profileData = results[0]['data'];

      if (profileData is! Map || profileData['success'] != true) {
        throw Exception(
          profileData is Map
              ? profileData['message']?.toString() ??
                    'Gagal memuat daftar agen.'
              : 'Format respons server tidak valid.',
        );
      }

      final profileRows = profileData['data'];
      if (profileRows is! List) {
        throw Exception('Data agen dari server tidak valid.');
      }

      final trackingData = results[1]['data'];
      if (trackingData is! Map || trackingData['success'] != true) {
        throw Exception(
          trackingData is Map
              ? trackingData['message']?.toString() ??
                    'Gagal memuat data tracking agen.'
              : 'Format respons tracking server tidak valid.',
        );
      }

      final trackingRows = trackingData['data'];
      if (trackingRows is! List) {
        throw Exception('Data tracking agen dari server tidak valid.');
      }

      final trackingByAgent = <String, Map<String, dynamic>>{};
      for (final item in trackingRows.whereType<Map>()) {
        final tracking = Map<String, dynamic>.from(item);
        final agentId =
            (tracking['stambuk'] ??
                    tracking['I_AGEN'] ??
                    tracking['NOMOR_AGEN'] ??
                    '')
                .toString()
                .trim();
        if (agentId.isNotEmpty) {
          trackingByAgent[agentId] = tracking;
        }
      }

      final agents = profileRows.whereType<Map>().map((item) {
        final profile = Map<String, dynamic>.from(item);
        final agentId = (profile['NOMOR_AGEN'] ?? '').toString().trim();
        final tracking = trackingByAgent[agentId];
        return {
          ...profile,
          if (tracking != null) ...{
            'latitude': tracking['latitude'],
            'longitude': tracking['longitude'],
            'accuracy': tracking['accuracy'],
            'speed': tracking['speed'],
            'lastUpdated': tracking['lastUpdated'],
          },
          'isTracking': tracking != null,
        };
      }).toList();
      if (!mounted) return;

      setState(() {
        _agents = agents;
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

  Future<void> _showAgentFilters() async {
    var selectedRole = _selectedAgentRole;
    var sortField = _agentSortField;
    var ascending = _sortAscending;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.only(top: 36),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
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
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Filter dan urutkan',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Atur daftar agen sesuai kebutuhan',
                                style: TextStyle(
                                  color: Color(0xFFDCEBFF),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        20 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _FilterSectionLabel(
                            icon: Icons.work_outline_rounded,
                            title: 'Jabatan agen',
                          ),
                          const SizedBox(height: 9),
                          DropdownButtonFormField<String>(
                            initialValue: selectedRole,
                            decoration: _filterInputDecoration(
                              hint: 'Pilih jabatan',
                            ),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFF1565C0),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '',
                                child: Text('Semua jabatan'),
                              ),
                              DropdownMenuItem(value: 'AD', child: Text('AD')),
                              DropdownMenuItem(value: 'AM', child: Text('AM')),
                              DropdownMenuItem(value: 'AS', child: Text('AS')),
                              DropdownMenuItem(value: 'WA', child: Text('WA')),
                            ],
                            onChanged: (value) =>
                                setSheetState(() => selectedRole = value ?? ''),
                          ),
                          const SizedBox(height: 20),
                          const _FilterSectionLabel(
                            icon: Icons.sort_by_alpha_rounded,
                            title: 'Urutkan daftar',
                          ),
                          const SizedBox(height: 9),
                          DropdownButtonFormField<_AgentSortField>(
                            initialValue: sortField,
                            decoration: _filterInputDecoration(
                              hint: 'Urutkan berdasarkan',
                            ),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFF1565C0),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: _AgentSortField.name,
                                child: Text('Nama agen'),
                              ),
                              DropdownMenuItem(
                                value: _AgentSortField.role,
                                child: Text('Jabatan'),
                              ),
                            ],
                            onChanged: (value) => setSheetState(
                              () => sortField = value ?? _AgentSortField.name,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const _FilterSectionLabel(
                            icon: Icons.swap_vert_rounded,
                            title: 'Urutan abjad',
                          ),
                          const SizedBox(height: 9),
                          SegmentedButton<bool>(
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? const Color(0xFFEAF3FF)
                                    : Colors.white,
                              ),
                              foregroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? const Color(0xFF0D47A1)
                                    : const Color(0xFF64748B),
                              ),
                              side: WidgetStateProperty.all(
                                const BorderSide(color: Color(0xFFD5E5FA)),
                              ),
                            ),
                            segments: const [
                              ButtonSegment(
                                value: true,
                                icon: Icon(Icons.arrow_upward_rounded),
                                label: Text('Ascending'),
                              ),
                              ButtonSegment(
                                value: false,
                                icon: Icon(Icons.arrow_downward_rounded),
                                label: Text('Descending'),
                              ),
                            ],
                            selected: {ascending},
                            onSelectionChanged: (selection) => setSheetState(
                              () => ascending = selection.first,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedAgentRole = '';
                                      _agentSortField = _AgentSortField.name;
                                      _sortAscending = true;
                                      _agentSearchController.clear();
                                      _showAgentSearch = false;
                                    });
                                    Navigator.pop(sheetContext);
                                  },
                                  icon: const Icon(Icons.restart_alt_rounded),
                                  label: const Text('Reset'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1565C0),
                                    side: const BorderSide(
                                      color: Color(0xFF9FC5F8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 19,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF0D47A1),
                                        Color(0xFF1B72D7),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _selectedAgentRole = selectedRole;
                                        _agentSortField = sortField;
                                        _sortAscending = ascending;
                                      });
                                      Navigator.pop(sheetContext);
                                    },
                                    icon: const Icon(Icons.check_rounded),
                                    label: const Text('Terapkan'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  @override
  void dispose() {
    _agentRefreshTimer?.cancel();
    _agentSearchController.dispose();
    _pageScrollController.dispose();
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
              child: Stack(
                children: [
                  flutter_map.FlutterMap(
                    mapController: _mapController,
                    options: flutter_map.MapOptions(
                      initialCenter: _initialMapCenter,
                      initialZoom: _hasValidCoordinates ? 15 : 12,
                    ),
                    children: [
                      flutter_map.TileLayer(
                        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName:
                            'com.devasatrio.bi_cabang_tracker',
                      ),
                      flutter_map.MarkerLayer(
                        markers: [
                          if (_hasValidCoordinates)
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
                  if (_hasValidCoordinates)
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleAgents = _visibleAgents;

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
                  controller: _pageScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildBranchHero(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Daftar Agen',
                            style: TextStyle(
                              color: Color(0xFF14264D),
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _showAgentSearch
                              ? 'Tutup pencarian'
                              : 'Cari agen',
                          onPressed: () {
                            setState(() {
                              _showAgentSearch = !_showAgentSearch;
                              if (!_showAgentSearch) {
                                _agentSearchController.clear();
                              }
                            });
                          },
                          icon: Icon(
                            _showAgentSearch
                                ? Icons.close_rounded
                                : Icons.search_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Filter dan urutkan',
                          onPressed: _showAgentFilters,
                          icon: Icon(
                            Icons.tune_rounded,
                            color:
                                _selectedAgentRole.isNotEmpty ||
                                    _agentSortField != _AgentSortField.name ||
                                    !_sortAscending
                                ? const Color(0xFF1565C0)
                                : null,
                          ),
                        ),
                      ],
                    ),
                    if (_showAgentSearch) ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: _agentSearchController,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Cari nama, ID, nomor telepon, email...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _agentSearchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Hapus pencarian',
                                  onPressed: () {
                                    _agentSearchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.clear_rounded),
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF1565C0),
                              width: 2,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFD5E5FA),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFD5E5FA),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                    else if (visibleAgents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Tidak ada agen yang cocok dengan pencarian atau filter.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      for (final agent in visibleAgents) ...[
                        _buildAgentCard(agent),
                        if (agent != visibleAgents.last)
                          const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAgentCard(Map<String, dynamic> agent) {
    final name = (agent['NAMA_AGEN'] ?? '-').toString();
    final agentNumber = (agent['NOMOR_AGEN'] ?? '-').toString();
    final tracking = agent['isTracking'] == true;
    final role = (agent['C_AGENCY_JABATAN'] ?? '-').toString();
    final phone = (agent['NOMOR_HP'] ?? '').toString().trim();

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
              width: 48,
              height: 56,
              child: Center(
                child: AgentMarker(
                  name: name,
                  identity: agentNumber,
                  isOnline: tracking,
                ),
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: tracking
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        tracking ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: tracking
                              ? const Color(0xFF15803D)
                              : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  TextSpan(
                    text:
                        ' · ID: $agentNumber${phone.isEmpty ? '' : ' · $phone'}',
                  ),
                ],
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                role,
                style: const TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
