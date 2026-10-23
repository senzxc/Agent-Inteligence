import 'package:flutter/material.dart';

import '../services/api_service.dart';

const Color _pageTop = Color(0xFFF8FBFF);
const Color _pageBottom = Color(0xFFEAF3FF);
const Color _brandBlue = Color(0xFF1565C0);
const Color _ink = Color(0xFF172033);
const Color _muted = Color(0xFF718096);
const BoxShadow _cardShadow = BoxShadow(
  color: Color(0x180F172A),
  blurRadius: 18,
  offset: Offset(0, 7),
);

class KantorListPage extends StatefulWidget {
  const KantorListPage({super.key});

  @override
  State<KantorListPage> createState() => _KantorListPageState();
}

class _KantorListPageState extends State<KantorListPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _kantorList = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _searchFocused = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadKantor();
    _searchFocusNode.addListener(() {
      if (mounted) setState(() => _searchFocused = _searchFocusNode.hasFocus);
    });
    _searchController.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadKantor() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final result = await ApiService.getKantor();
      final data = result['data'];
      if (result['statusCode'] == 200 &&
          data is Map<String, dynamic> &&
          data['success'] == true &&
          data['data'] is List) {
        final rows = (data['data'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        if (!mounted) return;
        setState(() {
          _kantorList = rows;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredKantor {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) return _kantorList;
    final terms = query.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    return _kantorList.where((kantor) {
      final searchable = [
        kantor['KODE_KANTOR'],
        kantor['NAMA_KANTOR'],
        kantor['ALAMAT_KANTOR'],
        kantor['EMAIL'],
        kantor['KET_KANTOR'],
        kantor['ZONA'],
      ].map((value) => value?.toString() ?? '').join(' ').toLowerCase();
      return terms.every(searchable.contains);
    }).toList();
  }

  void _openKantor(Map<String, dynamic> kantor) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final user = args is Map ? args : const <String, dynamic>{};
    Navigator.pushNamed(
      context,
      '/agent-list',
      arguments: {
        'KODE_KANTOR': kantor['KODE_KANTOR']?.toString() ?? '',
        'NAMA_KANTOR': kantor['NAMA_KANTOR']?.toString() ?? '-',
        'ALAMAT_KANTOR': kantor['ALAMAT_KANTOR']?.toString() ?? '-',
        'LATITUDE': (kantor['LATITUDE'] as num?)?.toDouble() ?? 0.0,
        'LONGITUDE': (kantor['LONGITUDE'] as num?)?.toDouble() ?? 0.0,
        'APP_ROLE': (user['APP_ROLE'] ?? '').toString(),
        'LEVEL_USER': (user['LEVEL_USER'] ?? '').toString(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _filteredKantor;

    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        backgroundColor: _pageTop,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
        ),
        title: const Text(
          'Daftar Kantor',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 19),
        ),
        centerTitle: false,
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_pageTop, _pageBottom],
              ),
            ),
          ),
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Semua kantor cabang', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: _ink)),
                            const SizedBox(height: 5),
                            Text(
                              _isLoading ? 'Memuat data kantor…' : '${_kantorList.length} kantor terdaftar',
                              style: const TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCEBFF),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(Icons.apartment_rounded, color: _brandBlue, size: 23),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 88),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: _brandBlue))
                      : _hasError
                          ? _ErrorState(onRetry: _loadKantor)
                          : results.isEmpty
                              ? _EmptyState(query: _searchQuery)
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                                  itemCount: results.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final kantor = results[index];
                                    final kode = kantor['KODE_KANTOR']?.toString() ?? '-';
                                    final nama = kantor['NAMA_KANTOR']?.toString().trim();
                                    final alamat = kantor['ALAMAT_KANTOR']?.toString().trim();
                                    final status = kantor['KET_KANTOR']?.toString().trim();
                                    final normalizedStatus = status?.toUpperCase();
                                    final isCenter = normalizedStatus == 'P' || status?.toLowerCase().contains('pusat') == true;
                                    final statusLabel = normalizedStatus == 'C'
                                        ? 'Cabang'
                                        : normalizedStatus == 'P'
                                            ? 'Pusat'
                                            : (status == null || status.isEmpty ? 'Kantor cabang' : status);
                                    return Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => _openKantor(kantor),
                                        child: Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: const [_cardShadow],
                                            border: Border.all(color: const Color(0xFFEAF0F8)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(colors: [Color(0xFFEAF3FF), Color(0xFFD8E9FF)]),
                                                  borderRadius: BorderRadius.circular(15),
                                                ),
                                                child: const Icon(Icons.storefront_rounded, color: _brandBlue, size: 24),
                                              ),
                                              const SizedBox(width: 13),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(nama == null || nama.isEmpty ? 'Nama kantor tidak tersedia' : nama,
                                                      maxLines: 2, overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.25)),
                                                    const SizedBox(height: 7),
                                                    Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Icon(Icons.location_on_outlined, size: 15, color: _muted),
                                                        const SizedBox(width: 5),
                                                        Expanded(child: Text(alamat == null || alamat.isEmpty ? 'Alamat belum tersedia' : alamat,
                                                          maxLines: 2, overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.4))),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 11),
                                                    Wrap(
                                                      spacing: 7,
                                                      runSpacing: 6,
                                                      children: [
                                                        _InfoPill(icon: Icons.tag_rounded, label: kode),
                                                        _InfoPill(
                                                          icon: isCenter ? Icons.business_rounded : Icons.check_circle_outline_rounded,
                                                          label: statusLabel,
                                                          isBlue: true,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Padding(
                                                padding: EdgeInsets.only(top: 13),
                                                child: Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA8BA), size: 23),
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
          if (_searchFocused)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _searchFocusNode.unfocus(),
                child: Container(color: const Color(0x990B1220)),
              ),
            ),
          Positioned(
            top: 104,
            left: 18,
            right: 18,
            child: Material(
              color: Colors.white,
              elevation: _searchFocused ? 18 : 0,
              shadowColor: const Color(0x66000000),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _searchFocused ? const Color(0xFF8AB8F8) : const Color(0xFFE3EAF4), width: _searchFocused ? 1.5 : 1),
                  boxShadow: _searchFocused ? const [BoxShadow(color: Color(0x332563EB), blurRadius: 24, offset: Offset(0, 8))] : const [_cardShadow],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari nama, kode, atau alamat kantor…',
                    hintStyle: const TextStyle(color: Color(0xFF9AA7B8), fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search_rounded, color: _brandBlue, size: 23),
                    suffixIcon: _searchQuery.isEmpty
                        ? (_searchFocused ? IconButton(onPressed: () => _searchFocusNode.unfocus(), icon: const Icon(Icons.close_rounded, color: _muted)) : null)
                        : IconButton(
                            tooltip: 'Hapus pencarian',
                            onPressed: () {
                              _searchController.clear();
                              _searchFocusNode.requestFocus();
                            },
                            icon: const Icon(Icons.close_rounded, color: _muted),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 4),
                  ),
                ),
              ),
            ),
          ),
          if (_searchFocused && _searchQuery.isNotEmpty)
            Positioned(
              top: 170,
              left: 24,
              right: 24,
              child: IgnorePointer(
                child: Text(
                  '${results.length} hasil ditemukan',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label, this.isBlue = false});
  final IconData icon;
  final String label;
  final bool isBlue;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: isBlue ? const Color(0xFFEAF3FF) : const Color(0xFFF3F6FA),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isBlue ? _brandBlue : _muted),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: isBlue ? _brandBlue : const Color(0xFF596579))),
            ),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});
  final String query;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 76, height: 76, decoration: const BoxDecoration(color: Color(0xFFDCEBFF), shape: BoxShape.circle), child: const Icon(Icons.search_off_rounded, color: _brandBlue, size: 35)),
            const SizedBox(height: 18),
            const Text('Kantor tidak ditemukan', style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text('Tidak ada kantor yang cocok dengan “$query”. Coba kata kunci lain.', textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.45)),
          ]),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 46, color: _muted),
            const SizedBox(height: 12),
            const Text('Data kantor belum bisa dimuat', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            const Text('Periksa koneksi ke server, lalu coba lagi.', textAlign: TextAlign.center, style: TextStyle(color: _muted)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Coba lagi')),
          ]),
        ),
      );
}
