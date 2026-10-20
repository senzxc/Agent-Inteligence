
import 'package:flutter/material.dart';

class AgentTaskPage extends StatelessWidget {
  final Map<String, dynamic> agent;

  const AgentTaskPage({
    super.key,
    required this.agent,
  });

  static const Color _pageStart = Color(0xFFF8FBFF);
  static const Color _pageEnd = Color(0xFFEAF3FF);
  static const Color _primary = Color(0xFF1565C0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);

  String _firstValue(List<String> keys, {String fallback = '-'}) {
    for (final key in keys) {
      final value = agent[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }

    return fallback;
  }

  String get _agentName => _firstValue([
        'NAMA_DEPAN',
        'NAMA',
        'N_AGEN',
        'nama',
      ], fallback: 'Agen');

  String get _agentNumber => _firstValue([
        'NOMOR_AGEN',
        'STAMBUK',
        'I_AGEN',
        'nomorAgen',
      ]);

  String get _agentPhone => _firstValue([
        'NOMOR_HP',
        'I_TELEPON_HP',
        'NO_HP',
        'nomorHp',
      ]);

  String get _agentAddress => _firstValue([
        'ALAMAT',
        'A_RUMAH',
        'ALAMAT_USER',
      ], fallback: 'Alamat belum tersedia');

  String get _today {
    const days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];

    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];

    final now = DateTime.now();

    return '${days[now.weekday - 1]}, '
        '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageEnd,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _textPrimary,
          ),
        ),
        title: const Text(
          'Tugas Agen',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_pageStart, _pageEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              _buildAgentCard(),
              const SizedBox(height: 20),
              _buildDateHeader(),
              const SizedBox(height: 16),
              _buildSummary(),
              const SizedBox(height: 24),
              _buildTaskHeader(),
              const SizedBox(height: 12),
              _buildEmptyState(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260D47A1),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
              ),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _agentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Nomor Agen: $_agentNumber',
                  style: const TextStyle(
                    color: Color(0xFFDCEBFF),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                _agentInfoRow(
                  Icons.phone_outlined,
                  _agentPhone,
                ),
                const SizedBox(height: 7),
                _agentInfoRow(
                  Icons.location_on_outlined,
                  _agentAddress,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _agentInfoRow(IconData icon, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: const Color(0xFFDCEBFF),
          size: 16,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFFEAF3FF),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.calendar_today_rounded,
            color: _primary,
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aktivitas Harian',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _today,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            title: 'Total Tugas',
            value: '0',
            
            icon: Icons.checklist_rounded,
            color: const Color(0xFF2563EB),
            background: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            title: 'Berjalan',
            value: '0',
            icon: Icons.pending_actions_rounded,
            color: const Color(0xFFD97706),
            background: const Color(0xFFFFF7ED),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            title: 'Selesai',
            value: '0',
            icon: Icons.task_alt_rounded,
            color: const Color(0xFF16A34A),
            background: const Color(0xFFF0FDF4),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskHeader() {
    return const Row(
      children: [
        Expanded(
          child: Text(
            'Daftar Tugas',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Icon(
          Icons.assignment_outlined,
          color: _primary,
          size: 21,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 32,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.playlist_add_check_rounded,
              color: _primary,
              size: 39,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Belum Ada Tugas',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Belum ada tugas harian yang tercatat '
            'untuk agen ini.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: _textSecondary,
                ),
                SizedBox(width: 7),
                Text(
                  'Mode pemantauan',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
