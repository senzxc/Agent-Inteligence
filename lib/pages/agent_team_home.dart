import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/gps_tracking_service.dart';
import '../widgets/agent_marker.dart';

class AgentTeamHomePage extends StatefulWidget {
  const AgentTeamHomePage({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<AgentTeamHomePage> createState() => _AgentTeamHomePageState();
}

class _AgentTeamHomePageState extends State<AgentTeamHomePage> {
  static const Color _pageStart = Color(0xFFF8FBFF);
  static const Color _pageEnd = Color(0xFFEAF3FF);
  static const Color _primary = Color(0xFF1565C0);
  static const Color _ink = Color(0xFF172033);
  static const Color _muted = Color(0xFF64748B);

  List<Map<String, dynamic>> _agents = [];
  bool _isLoading = true;
  String? _error;
  bool _showingOnlineAgents = false;

  String get _agencyRole =>
      (widget.user['C_AGENCY_JABATAN'] ?? '').toString().trim().toUpperCase();

  String get _officeCode =>
      (widget.user['KODE_KANTOR'] ??
              widget.user['KANTOR'] ??
              widget.user['kantor'] ??
              '')
          .toString()
          .trim();

  String get _displayName =>
      (widget.user['NAMA_AGEN'] ??
              widget.user['NAMA'] ??
              widget.user['nama'] ??
              'Agen')
          .toString()
          .trim();

  String get _agentId =>
      (widget.user['I_AGEN'] ??
              widget.user['NOMOR_AGEN'] ??
              widget.user['STAMBUK'] ??
              widget.user['stambuk'] ??
              '-')
          .toString();

  String get _visibleRolesLabel => switch (_agencyRole) {
    'AD' => 'AM, AS, dan WA',
    'AM' => 'AS dan WA',
    'AS' => 'WA',
    _ => 'agen',
  };

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        ApiService.getAgentProfiles(),
        ApiService.getAgents(),
      ]);
      final profileData = results[0]['data'];
      if (results[0]['statusCode'] != 200 ||
          profileData is! Map ||
          profileData['success'] != true ||
          profileData['data'] is! List) {
        throw Exception(
          profileData is Map
              ? profileData['message']?.toString() ??
                    'Gagal memuat daftar agen.'
              : 'Format respons daftar agen tidak valid.',
        );
      }

      final trackingData = results[1]['data'];
      if (results[1]['statusCode'] != 200 ||
          trackingData is! Map ||
          trackingData['success'] != true ||
          trackingData['data'] is! List) {
        throw Exception(
          trackingData is Map
              ? trackingData['message']?.toString() ??
                    'Gagal memuat status tracking agen.'
              : 'Format respons status tracking tidak valid.',
        );
      }

      final onlineAgentIds = (trackingData['data'] as List)
          .whereType<Map>()
          .map(
            (agent) =>
                (agent['stambuk'] ?? agent['I_AGEN'] ?? agent['NOMOR_AGEN'])
                    ?.toString()
                    .trim(),
          )
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      final allAgents = (profileData['data'] as List).whereType<Map>().map((
        agent,
      ) {
        final profile = Map<String, dynamic>.from(agent);
        final agentId = (profile['NOMOR_AGEN'] ?? profile['I_AGEN'])
            ?.toString()
            .trim();
        profile['isTracking'] =
            agentId != null && onlineAgentIds.contains(agentId);
        return profile;
      }).toList();
      final onlineAgents = allAgents
          .where((agent) => agent['isTracking'] == true)
          .take(5)
          .toList();
      final showingOnlineAgents = onlineAgents.isNotEmpty;
      final visibleAgents = showingOnlineAgents
          ? onlineAgents
          : allAgents.take(5).toList();
      if (!mounted) return;

      setState(() {
        _agents = visibleAgents;
        _showingOnlineAgents = showingOnlineAgents;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _openAgentMap() async {
    await Navigator.pushNamed(
      context,
      '/agent-list',
      arguments: {...widget.user, 'KODE_KANTOR': _officeCode},
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Yakin ingin keluar?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                child: Column(
                  children: [
                    const Text(
                      'Anda akan keluar dari sesi akun saat ini. Pastikan semua pekerjaan yang sedang dilakukan telah selesai sebelum keluar dari aplikasi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _primary,
                                side: const BorderSide(
                                  color: Color(0xFFBBD5F5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Batal'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Keluar'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (shouldLogout != true || !mounted) return;

    await ApiService.clearSession();
    await AgentGpsTrackingService.instance.disposeTrackingStream();
    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageEnd,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Dashboard Kantor',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
          ),
          IconButton(
            tooltip: 'Muat ulang daftar agen',
            onPressed: _isLoading ? null : _loadAgents,
            icon: const Icon(Icons.refresh_rounded, color: _primary),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_pageStart, _pageEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadAgents,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D47A1), _primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x260D47A1),
                      blurRadius: 16,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.person_outline_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selamat datang,',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _displayName,
                                maxLines: 1,
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
                      ],
                    ),
                    const SizedBox(height: 18),
                    _HeaderInfoRow(
                      icon: Icons.badge_outlined,
                      label: 'ID: $_agentId',
                    ),
                    const SizedBox(height: 9),
                    _HeaderInfoRow(
                      icon: Icons.business_outlined,
                      label:
                          'Kantor: ${_officeCode.isEmpty ? '-' : _officeCode}',
                    ),
                    const SizedBox(height: 9),
                    _HeaderInfoRow(
                      icon: Icons.work_outline,
                      label: 'Jabatan: $_agencyRole',
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.groups_outlined,
                            color: Colors.white,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              '${_agents.length} Agen ${_showingOnlineAgents ? 'online' : 'terdaftar'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.circle,
                            color: _showingOnlineAgents
                                ? Colors.lightGreenAccent
                                : Colors.white54,
                            size: 11,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showingOnlineAgents ? 'Online' : 'Offline',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Daftar Agen',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_agents.length} Agen',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                _showingOnlineAgents
                    ? 'Menampilkan agen $_visibleRolesLabel yang sedang online.'
                    : 'Tidak ada yang online. Menampilkan agen $_visibleRolesLabel di kantor ini.',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(
                    child: CircularProgressIndicator(color: _primary),
                  ),
                )
              else if (_error != null)
                _StatusCard(
                  icon: Icons.cloud_off_rounded,
                  message: _error!,
                  actionLabel: 'Coba lagi',
                  onPressed: _loadAgents,
                )
              else if (_agents.isEmpty)
                const _StatusCard(
                  icon: Icons.groups_2_outlined,
                  message: 'Belum ada agen dengan jabatan di bawah Anda.',
                )
              else ...[
                for (final agent in _agents) _AgentCard(agent: agent),
                const SizedBox(height: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openAgentMap,
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D47A1), _primary],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x261565C0),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.location_searching_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Lihat agen selengkapnya',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Buka peta dan status lokasi tim',
                                  style: TextStyle(
                                    color: Color(0xFFDCEBFF),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});

  final Map<String, dynamic> agent;

  @override
  Widget build(BuildContext context) {
    final name = (agent['NAMA_AGEN'] ?? 'Nama tidak tersedia').toString();
    final id = (agent['NOMOR_AGEN'] ?? '-').toString();
    final role = (agent['C_AGENCY_JABATAN'] ?? '-').toString();
    final phone = (agent['NOMOR_HP'] ?? '').toString().trim();
    final isOnline = agent['isTracking'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: AgentMarker(name: name, identity: id, isOnline: isOnline),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${isOnline ? 'Online' : 'Offline'} · ID: $id${phone.isEmpty ? '' : ' · $phone'}',
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
    );
  }
}

class _HeaderInfoRow extends StatelessWidget {
  const _HeaderInfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF64748B), size: 32),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onPressed != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onPressed, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
