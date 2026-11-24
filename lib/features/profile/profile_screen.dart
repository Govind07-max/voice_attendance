import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/database_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _facultyIdCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _thresholdCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  List<TeacherAvailability> _slots = const [];
  bool _loadingSlots = true;
  bool _savingSlot = false;

  static const List<String> _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSlots();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _facultyIdCtrl.dispose();
    _deptCtrl.dispose();
    _emailCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final auth = ref.read(authServiceProvider);
    final profile = await auth.fetchProfile();
    if (!mounted) return;

    if (profile != null) {
      _nameCtrl.text = profile.fullName;
      _facultyIdCtrl.text = profile.facultyId;
      _deptCtrl.text = profile.department;
      _emailCtrl.text = profile.email;
      _thresholdCtrl.text = profile.defaultThreshold.toStringAsFixed(1);
    } else {
      final user = ref.read(currentUserProvider);
      _nameCtrl.text = user?.userMetadata?['full_name'] ?? '';
      _emailCtrl.text = user?.email ?? '';
      _deptCtrl.text = 'Electronics & Telecommunication Engineering';
      _thresholdCtrl.text = '75.0';
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final auth = ref.read(authServiceProvider);
      final current = await auth.fetchProfile();
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      final profile = TeacherProfile(
        id: user.id,
        fullName: _nameCtrl.text.trim(),
        facultyId: _facultyIdCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty
            ? (user.email ?? '')
            : _emailCtrl.text.trim(),
        department: _deptCtrl.text.trim(),
        phone: current?.phone ?? '',
        timezone: current?.timezone ?? 'Asia/Kolkata',
        defaultThreshold:
            double.tryParse(_thresholdCtrl.text.trim()) ?? 75.0,
      );

      await auth.updateProfile(profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile details updated successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not save profile: ${AppErrors.humanize(e)}'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ------------------------------------------------------------------
  // Meeting slots
  // ------------------------------------------------------------------
  Future<void> _loadSlots() async {
    final teacherId = ref.read(currentUserProvider)?.id;
    if (teacherId == null) {
      if (mounted) setState(() => _loadingSlots = false);
      return;
    }
    try {
      final slots = await ref
          .read(databaseServiceProvider)
          .getTeacherAvailability(teacherId);
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _loadingSlots = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSlots = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load meeting slots: '
              '${AppErrors.humanize(e)}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _addSlot() async {
    var day = 1;
    var start = const TimeOfDay(hour: 10, minute: 0);
    var end = const TimeOfDay(hour: 11, minute: 0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Meeting Slot'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: day,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: [
                    for (var i = 1; i <= 7; i++)
                      DropdownMenuItem(
                          value: i, child: Text(_dayNames[i - 1])),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => day = value);
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: start,
                          );
                          if (picked != null) {
                            setDialogState(() => start = picked);
                          }
                        },
                        child: Text('From ${start.format(ctx)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: end,
                          );
                          if (picked != null) {
                            setDialogState(() => end = picked);
                          }
                        },
                        child: Text('To ${end.format(ctx)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Students who are below the attendance threshold get these '
                  'times in the email so they can meet you.',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add Slot')),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The end time must be after the start time.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final teacherId = ref.read(currentUserProvider)?.id;
    if (teacherId == null) return;

    setState(() => _savingSlot = true);
    try {
      await ref.read(databaseServiceProvider).addTeacherAvailability(
            teacherId: teacherId,
            dayOfWeek: day,
            startTime: _sqlTime(start),
            endTime: _sqlTime(end),
          );
      await _loadSlots();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meeting slot added.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add the slot: ${AppErrors.humanize(e)}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingSlot = false);
    }
  }

  Future<void> _deleteSlot(TeacherAvailability slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove this slot?'),
        content: Text(
            '${_dayNames[slot.dayOfWeek - 1]} '
            '${_shortTime(slot.startTime)} – ${_shortTime(slot.endTime)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(databaseServiceProvider)
          .deleteTeacherAvailability(slot.id);
      await _loadSlots();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Could not remove the slot: ${AppErrors.humanize(e)}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _sqlTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:00';

  String _shortTime(String sqlTime) {
    final parts = sqlTime.split(':');
    if (parts.length < 2) return sqlTime;
    return '${parts[0]}:${parts[1]}';
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign out?'),
        content: const Text('You can sign back in any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authServiceProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final countsAsync = ref.watch(teacherCountsProvider);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Teacher Profile & Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Profile & Settings',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primaryLight,
                    child: Text(
                      _initials(_nameCtrl.text),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_nameCtrl.text.isEmpty
                            ? 'Teacher'
                            : _nameCtrl.text,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          '${_deptCtrl.text.isEmpty ? 'Department not set' : _deptCtrl.text}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _emailCtrl.text.isEmpty
                              ? (user?.email ?? '')
                              : _emailCtrl.text,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            countsAsync.maybeWhen(
              data: (counts) => Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                        label: 'Classes',
                        value: '${counts['classes'] ?? 0}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                        label: 'Subjects',
                        value: '${counts['classSubjects'] ?? 0}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                        label: 'Students',
                        value: '${counts['students'] ?? 0}'),
                  ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            const Text('Personal Information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 12),
            TextField(
                controller: _facultyIdCtrl,
                decoration: const InputDecoration(labelText: 'Faculty ID')),
            const SizedBox(height: 12),
            TextField(
                controller: _deptCtrl,
                decoration: const InputDecoration(labelText: 'Department')),
            const SizedBox(height: 12),
            TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email Address')),
            const SizedBox(height: 24),

            const Text('Default Attendance Threshold (%)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Default Threshold (%)',
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                const Expanded(
                  child: Text('Weekly Meeting Slots',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: _savingSlot ? null : _addSlot,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingSlots)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_slots.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'No slots yet. The times you add here are shown to students '
                  'in low-attendance emails so they know when to meet you.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              )
            else
              for (final slot in _slots)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dayNames[slot.dayOfWeek - 1],
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_shortTime(slot.startTime)} – '
                              '${_shortTime(slot.endTime)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        color: AppColors.error,
                        tooltip: 'Remove slot',
                        onPressed: () => _deleteSlot(slot),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16)),
                onPressed: _isSaving ? null : _saveProfile,
                child: Text(_isSaving ? 'Saving…' : 'Save Profile Details'),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'T';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
