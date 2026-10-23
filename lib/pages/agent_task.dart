import 'package:flutter/material.dart';

import '../services/api_service.dart';

class AgentTaskPage extends StatefulWidget {
  final Map<String, dynamic> agent;
  final bool canManageTasks;
  final bool canAddTasks;

  const AgentTaskPage({
    super.key,
    required this.agent,
    this.canManageTasks = true,
    this.canAddTasks = true,
  });

  @override
  State<AgentTaskPage> createState() => _AgentTaskPageState();
}

class _AgentTaskPageState extends State<AgentTaskPage> {
  static const Color _pageStart = Color(0xFFF8FBFF);
  static const Color _pageEnd = Color(0xFFEAF3FF);
  static const Color _primary = Color(0xFF1565C0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);

  static const List<String> _statuses = [
    'Belum dimulai',
    'Berjalan',
    'Selesai',
  ];

  final List<Map<String, dynamic>> _tasks = [];
  final Set<String> _updatingTaskIds = {};

  bool _isLoading = true;
  String? _errorMessage;

  String _firstValue(List<String> keys, {String fallback = '-'}) {
    for (final key in keys) {
      final value = widget.agent[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }

    return fallback;
  }

  String get _agentName => _firstValue([
    'NAMA_AGEN',
    'NAMA_DEPAN',
    'NAMA',
    'N_AGEN',
    'nama',
  ], fallback: 'Agen');

  String get _agentNumber =>
      _firstValue(['NOMOR_AGEN', 'STAMBUK', 'I_AGEN', 'nomorAgen', 'stambuk']);

  String get _agentPhone =>
      _firstValue(['NOMOR_HP', 'I_TELEPON_HP', 'NO_HP', 'nomorHp']);

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

  int get _totalTasks => _tasks.length;

  int get _runningTasks => _tasks.where((task) {
    return _taskStatus(task) == 'Berjalan';
  }).length;

  int get _completedTasks => _tasks.where((task) {
    return _taskStatus(task) == 'Selesai';
  }).length;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  // Mendukung beberapa kemungkinan format respons API.
  List<Map<String, dynamic>> _parseTasks(Map<String, dynamic> response) {
    dynamic rawTasks = response['tasks'];

    rawTasks ??= response['data'];

    if (rawTasks is Map<String, dynamic>) {
      rawTasks = rawTasks['tasks'] ?? rawTasks['items'] ?? rawTasks['data'];
    }

    if (rawTasks is! List) {
      return [];
    }

    return rawTasks
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _taskStatus(Map<String, dynamic> task) {
    final status = (task['status'] ?? task['STATUS'] ?? 'Belum dimulai')
        .toString();

    if (_statuses.contains(status)) {
      return status;
    }

    return 'Belum dimulai';
  }

  String _taskId(Map<String, dynamic> task) {
    return (task['id'] ??
            task['taskId'] ??
            task['task_id'] ??
            task['idTugas'] ??
            '')
        .toString();
  }

  String _taskTitle(Map<String, dynamic> task) {
    return (task['judul'] ?? task['title'] ?? 'Tugas tanpa judul').toString();
  }

  String _taskDescription(Map<String, dynamic> task) {
    return (task['deskripsi'] ?? task['description'] ?? '').toString();
  }

  String _taskDeadline(Map<String, dynamic> task) {
    final raw = (task['tenggat'] ?? task['deadline'] ?? '').toString();

    if (raw.isEmpty) return 'Tidak ditentukan';

    final date = DateTime.tryParse(raw);
    if (date == null) return raw;

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _loadTasks() async {
    if (_agentNumber == '-') {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Nomor agen atau stambuk tidak ditemukan.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.getAgentTasks(_agentNumber);
      final data = result['data'] as Map<String, dynamic>;
      final tasks = _parseTasks(data);

      if (!mounted) return;

      setState(() {
        _tasks
          ..clear()
          ..addAll(tasks);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = _cleanError(error);
      });
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<String?> _createTask({
    required String judul,
    required String deskripsi,
    required String tenggat,
  }) async {
    try {
      await ApiService.createAgentTask(
        agentId: _agentNumber,
        judul: judul,
        deskripsi: deskripsi,
        tenggat: tenggat,
      );
      return null;
    } catch (error) {
      return _cleanError(error);
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> task, String status) async {
    final id = _taskId(task);

    if (id.isEmpty) {
      _showMessage(
        'ID tugas tidak ditemukan pada respons server.',
        isError: true,
      );
      return;
    }

    if (_updatingTaskIds.contains(id)) return;

    setState(() {
      _updatingTaskIds.add(id);
    });

    try {
      await ApiService.updateTaskStatus(taskId: id, status: status);

      await _loadTasks();

      if (!mounted) return;
      _showMessage('Status tugas berhasil diperbarui.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        'Gagal mengubah status: ${_cleanError(error)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingTaskIds.remove(id);
        });
      }
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final id = _taskId(task);

    if (id.isEmpty) {
      _showMessage(
        'ID tugas tidak ditemukan pada respons server.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 20, 12, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
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
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'KONFIRMASI',
                            style: TextStyle(
                              color: Color(0xFFDCEBFF),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Hapus Tugas',
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
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tugas berikut akan dihapus secara permanen:',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.assignment_outlined,
                            color: _primary,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _taskTitle(task),
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFFB45309),
                          size: 17,
                        ),
                        SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Tindakan ini tidak dapat dibatalkan.',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE8EEF6))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textSecondary,
                          minimumSize: const Size.fromHeight(46),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Hapus Tugas'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ApiService.deleteTask(id);
      await _loadTasks();

      if (!mounted) return;
      _showMessage('Tugas berhasil dihapus.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        'Gagal menghapus tugas: ${_cleanError(error)}',
        isError: true,
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Colors.red.shade700
            : const Color(0xFF15803D),
      ),
    );
  }

  Future<void> _showAddTaskDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    DateTime? deadline;
    bool isSubmitting = false;
    String? submitError;
    final formKey = GlobalKey<FormState>();

    final taskAdded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final dateLabel = deadline == null
                ? 'Pilih tenggat tugas'
                : 'Tenggat: '
                      '${deadline!.day.toString().padLeft(2, '0')}-'
                      '${deadline!.month.toString().padLeft(2, '0')}-'
                      '${deadline!.year}';

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 20, 14, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
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
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Icon(
                              Icons.add_task_rounded,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 13),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TUGAS BARU',
                                  style: TextStyle(
                                    color: Color(0xFFDCEBFF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Tambah Tugas',
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
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Form(
                        key: formKey,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Lengkapi informasi tugas untuk agen.',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              if (submitError != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Color(0xFFB91C1C),
                                        size: 19,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          'Gagal menambahkan tugas: $submitError',
                                          style: const TextStyle(
                                            color: Color(0xFF991B1B),
                                            fontSize: 12,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: titleController,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: _taskInputDecoration(
                                  label: 'Judul tugas',
                                  hint: 'Contoh: Kunjungan nasabah',
                                  icon: Icons.assignment_outlined,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Judul tugas wajib diisi.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: descriptionController,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                minLines: 3,
                                maxLines: 5,
                                decoration: _taskInputDecoration(
                                  label: 'Deskripsi',
                                  hint: 'Jelaskan detail tugas...',
                                  icon: Icons.notes_rounded,
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _primary,
                                  backgroundColor: const Color(0xFFF3F8FF),
                                  minimumSize: const Size(double.infinity, 52),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFFD5E5FA),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        final selected = await showDatePicker(
                                          context: dialogContext,
                                          initialDate:
                                              deadline ?? DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                          builder: (context, child) => Theme(
                                            data: Theme.of(context).copyWith(
                                              colorScheme: Theme.of(context)
                                                  .colorScheme
                                                  .copyWith(
                                                    primary: _primary,
                                                    surface: Colors.white,
                                                  ),
                                            ),
                                            child: child!,
                                          ),
                                        );

                                        if (selected != null &&
                                            dialogContext.mounted) {
                                          setDialogState(() {
                                            deadline = selected;
                                          });
                                        }
                                      },
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_month_outlined,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        dateLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: _textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Tenggat bersifat opsional.',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Color(0xFFE8EEF6)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textSecondary,
                                minimumSize: const Size.fromHeight(48),
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: const Text('Batal'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }

                                      final formattedDeadline = deadline == null
                                          ? ''
                                          : '${deadline!.year}-'
                                                '${deadline!.month.toString().padLeft(2, '0')}-'
                                                '${deadline!.day.toString().padLeft(2, '0')}';

                                      setDialogState(() {
                                        isSubmitting = true;
                                      });
                                      final errorMessage = await _createTask(
                                        judul: titleController.text.trim(),
                                        deskripsi: descriptionController.text
                                            .trim(),
                                        tenggat: formattedDeadline,
                                      );

                                      if (!dialogContext.mounted) return;

                                      if (errorMessage == null) {
                                        Navigator.of(dialogContext).pop(true);
                                      } else {
                                        setDialogState(() {
                                          isSubmitting = false;
                                          submitError = errorMessage;
                                        });
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: _primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              icon: isSubmitting
                                  ? const SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.add_rounded),
                              label: Text(
                                isSubmitting ? 'Menyimpan...' : 'Simpan Tugas',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    descriptionController.dispose();

    if (taskAdded != true || !mounted) return;

    await _loadTasks();

    if (!mounted) return;

    if (_errorMessage == null) {
      _showMessage('Tugas berhasil ditambahkan.');
    } else {
      _showMessage(
        'Tugas berhasil ditambahkan, tetapi daftar gagal diperbarui. '
        'Coba muat ulang.',
        isError: true,
      );
    }
  }

  InputDecoration _taskInputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _primary, size: 20),
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: const Color(0xFFF8FBFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE6F2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDCE6F2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
    );
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
          icon: const Icon(Icons.arrow_back_rounded, color: _textPrimary),
        ),
        title: const Text(
          'Tugas Agen',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang tugas',
            onPressed: _isLoading ? null : _loadTasks,
            icon: const Icon(Icons.refresh_rounded, color: _primary),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: widget.canManageTasks && widget.canAddTasks
          ? FloatingActionButton.extended(
              onPressed: _showAddTaskDialog,
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah Tugas'),
            )
          : null,
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
          child: RefreshIndicator(
            onRefresh: _loadTasks,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
              children: [
                _buildAgentCard(),
                const SizedBox(height: 20),
                if (!widget.canManageTasks) ...[
                  _buildReadOnlyNotice(),
                  const SizedBox(height: 16),
                ],
                _buildDateHeader(),
                const SizedBox(height: 16),
                _buildSummary(),
                const SizedBox(height: 24),
                _buildTaskHeader(),
                const SizedBox(height: 12),
                _buildTaskContent(),
              ],
            ),
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
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
                _agentInfoRow(Icons.phone_outlined, _agentPhone),
                const SizedBox(height: 7),
                _agentInfoRow(Icons.location_on_outlined, _agentAddress),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD5E5FA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0D47A1),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_outlined, color: _primary, size: 21),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mode pemantauan',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Anda hanya dapat melihat tugas agen ini.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
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
        Icon(icon, color: const Color(0xFFDCEBFF), size: 16),
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
                style: const TextStyle(color: _textSecondary, fontSize: 13),
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
            value: '$_totalTasks',
            icon: Icons.checklist_rounded,
            color: const Color(0xFF2563EB),
            background: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            title: 'Berjalan',
            value: '$_runningTasks',
            icon: Icons.pending_actions_rounded,
            color: const Color(0xFFD97706),
            background: const Color(0xFFFFF7ED),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            title: 'Selesai',
            value: '$_completedTasks',
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
            child: Icon(icon, color: color, size: 19),
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
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Daftar Tugas',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$_totalTasks tugas',
          style: const TextStyle(color: _textSecondary, fontSize: 12),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.assignment_outlined, color: _primary, size: 21),
      ],
    );
  }

  Widget _buildTaskContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 50),
        child: Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            const Text(
              'Gagal Memuat Tugas',
              style: TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadTasks,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return _buildEmptyState();
    }

    return Column(children: _tasks.map(_buildTaskCard).toList());
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final status = _taskStatus(task);
    final deadline = _taskDeadline(task);
    final taskId = _taskId(task);
    final isUpdating = _updatingTaskIds.contains(taskId);

    Color statusColor;
    Color statusBackground;
    IconData statusIcon;

    switch (status) {
      case 'Berjalan':
        statusColor = const Color(0xFFD97706);
        statusBackground = const Color(0xFFFFF7ED);
        statusIcon = Icons.autorenew_rounded;
        break;
      case 'Selesai':
        statusColor = const Color(0xFF15803D);
        statusBackground = const Color(0xFFF0FDF4);
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      default:
        statusColor = const Color(0xFF1565C0);
        statusBackground = const Color(0xFFEAF3FF);
        statusIcon = Icons.radio_button_unchecked_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE8F5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0D47A1),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEAF3FF), Color(0xFFDCEBFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.assignment_rounded,
                  color: _primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _taskTitle(task),
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              if (widget.canManageTasks)
                PopupMenuButton<String>(
                  tooltip: 'Aksi tugas',
                  padding: EdgeInsets.zero,
                  splashRadius: 20,
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: _textSecondary,
                  ),
                  color: Colors.white,
                  elevation: 10,
                  shadowColor: const Color(0x260F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  onSelected: (action) {
                    if (action == 'delete') {
                      _deleteTask(task);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      height: 48,
                      child: const Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Hapus tugas',
                            style: TextStyle(
                              color: Color(0xFFB91C1C),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (_taskDescription(task).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _taskDescription(task),
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_outlined,
                        size: 17,
                        color: _primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          deadline == 'Tidak ditentukan'
                              ? 'Tanpa tenggat'
                              : deadline,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 15),
                    const SizedBox(width: 5),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.canManageTasks)
            Container(
              padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE0ECF9)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: isUpdating
                        ? const Padding(
                            padding: EdgeInsets.all(7),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _primary,
                            ),
                          )
                        : const Icon(
                            Icons.sync_alt_rounded,
                            color: _primary,
                            size: 18,
                          ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUpdating ? 'Menyimpan perubahan...' : 'Ubah status',
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDCE6F2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: status,
                        isDense: true,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(12),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _primary,
                        ),
                        style: const TextStyle(
                          color: _primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        items: _statuses.map((value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: isUpdating || _isLoading
                            ? null
                            : (value) {
                                if (value != null && value != status) {
                                  _updateStatus(task, value);
                                }
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
            'Belum ada tugas yang tercatat untuk agen ini. '
            'Tekan tombol Tambah Tugas untuk membuat tugas baru.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  size: 16,
                  color: _textSecondary,
                ),
                SizedBox(width: 7),
                Text(
                  'Terhubung ke server',
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
