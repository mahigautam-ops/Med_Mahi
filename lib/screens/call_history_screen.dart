import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/providers/call_provider.dart';
import '../core/providers/patient_provider.dart';
import '../core/models/patient.dart';
import '../core/app_design.dart';
import 'dialer_screen.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallLogEntry> _logs = [];
  bool _isLoading = true;
  bool _permissionDenied = false;
  String _filter = 'patients'; // patients | missed
  bool _showDialpad = false;
  String _dialedNumber = '';
  Patient? _matchedPatient;
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final status = await Permission.phone.request();
    if (!status.isGranted) {
      setState(() { _permissionDenied = true; _isLoading = false; });
      return;
    }
    final entries = await CallLog.get();
    setState(() { _logs = entries.toList(); _isLoading = false; });
  }

  String _normalize(String? phone) {
    if (phone == null) return '';
    return phone.replaceAll(RegExp(r'\D'), '');
  }

  List<CallLogEntry> get _filtered {
    final patients = context.read<PatientProvider>().allPatients;
    final patientNumbers = patients.map((p) => _normalize(p.phoneNumber)).toSet();
    switch (_filter) {
      case 'patients':
        return _logs.where((e) => e.number != null && patientNumbers.contains(_normalize(e.number))).toList();
      case 'missed':
        return _logs.where((e) => e.callType == CallType.missed).toList();
      default:
        return _logs.where((e) => e.number != null && e.number!.isNotEmpty).toList();
    }
  }

  Future<void> _call(String number) async {
    try { await context.read<CallProvider>().makeCall(number); }
    catch (e) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e'))); }
  }

  void _onKeyPressed(String value) { setState(() => _dialedNumber += value); _lookupPatient(); }

  void _onDelete() {
    if (_dialedNumber.isNotEmpty) {
      setState(() => _dialedNumber = _dialedNumber.substring(0, _dialedNumber.length - 1));
      _lookupPatient();
    }
  }

  Future<Patient?> _lookupPatient() async {
    if (_dialedNumber.length < 5) { setState(() => _matchedPatient = null); return null; }
    final p = await context.read<PatientProvider>().findByPhoneNumber(_dialedNumber);
    if (mounted) setState(() => _matchedPatient = p);
    return p;
  }

  String _getEntryId(CallLogEntry entry) {
    try { return (entry as dynamic).id?.toString() ?? entry.timestamp?.toString() ?? 'unknown'; }
    catch (e) { return entry.timestamp?.toString() ?? 'unknown'; }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) _selectedIds.remove(id);
      else _selectedIds.add(id);
    });
  }

  void _selectAll() { setState(() => _selectedIds.addAll(_filtered.map(_getEntryId))); }
  void _deselectAll() { setState(() => _selectedIds.clear()); }
  void _clearSelection() { setState(() { _selectedIds.clear(); _selectionMode = false; }); }
  void _enterSelectionMode() { setState(() => _selectionMode = true); }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Call Logs'),
        content: Text('Are you sure you want to delete ${_selectedIds.length} selected logs?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        for (final id in _selectedIds) { await CallLog.deleteCallLog(id); }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${_selectedIds.length} logs')));
        _clearSelection(); _loadLogs();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete logs: $e')));
      }
    }
  }

  Future<void> _deleteLog(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Call Log'),
        content: const Text('Are you sure you want to delete this call log?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      try { await CallLog.deleteCallLog(id); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log deleted'))); _loadLogs(); }
      catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete log: $e'))); }
    }
  }

  Future<void> _deleteHistoryForNumber(String? number) async {
    if (number == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear History'),
        content: Text('Are you sure you want to delete ALL call logs for $number?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete All')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final logsToDelete = _logs.where((l) => l.number == number).toList();
        for (final log in logsToDelete) { final id = _getEntryId(log); if (id != 'unknown') await CallLog.deleteCallLog(id); }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${logsToDelete.length} logs for $number')));
        _loadLogs();
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear history: $e'))); }
    }
  }

  Future<void> _clearAllLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Logs'),
        content: const Text('Are you sure you want to delete ALL call logs from your phone? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Clear All')),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        for (final log in _logs) { final id = _getEntryId(log); if (id != 'unknown') await CallLog.deleteCallLog(id); }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All call logs cleared')));
        _loadLogs();
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear logs: $e'))); setState(() => _isLoading = false); }
    }
  }

  void _showDeleteMenu(CallLogEntry entry, String entryId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16.0), child: Text('Log Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Delete this log'), onTap: () { Navigator.pop(context); _deleteLog(entryId); }),
          ListTile(leading: const Icon(Icons.history, color: Colors.orange), title: Text('Delete all from ${entry.number ?? 'this number'}'), onTap: () { Navigator.pop(context); _deleteHistoryForNumber(entry.number); }),
          ListTile(leading: const Icon(Icons.checklist_rtl), title: const Text('Select multiple'), onTap: () { Navigator.pop(context); _toggleSelection(entryId); }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_permissionDenied) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.history, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        const Text('Phone permission required', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: openAppSettings, child: const Text('Open Settings')),
      ]));
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selection mode header
                if (_selectionMode)
                  Container(
                    color: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _clearSelection),
                      Expanded(child: Text(_selectedIds.isEmpty ? 'Select Logs' : '${_selectedIds.length} Selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      if (_selectedIds.length != _filtered.length)
                        TextButton(onPressed: _selectAll, child: const Text('Select All', style: TextStyle(color: Colors.white70, fontSize: 13)))
                      else
                        TextButton(onPressed: _deselectAll, child: const Text('Deselect All', style: TextStyle(color: Colors.white70, fontSize: 13))),
                      if (_selectedIds.isNotEmpty)
                        IconButton(icon: const Icon(Icons.delete, color: Colors.white), onPressed: _deleteSelected),
                    ]),
                  ),
                // Header
                if (!_selectionMode) _buildHeader(),
                // Tabs
                _buildTabs(),
                // List
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.call_outlined, size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(_filter == 'patients' ? 'No calls from saved patients' : 'No missed calls', style: TextStyle(color: Colors.grey[500], fontSize: 15, fontWeight: FontWeight.w500)),
                        ]))
                      : RefreshIndicator(
                          onRefresh: _loadLogs,
                          child: Consumer<PatientProvider>(
                            builder: (context, provider, _) {
                              return ListView.builder(
                                itemCount: _filtered.length,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemBuilder: (context, index) {
                                  final entry = _filtered[index];
                                  final entryId = _getEntryId(entry);
                                  final entryNum = _normalize(entry.number);
                                  final patient = provider.allPatients.cast<Patient?>().firstWhere((p) => _normalize(p?.phoneNumber) == entryNum, orElse: () => null);
                                  return _CallLogTile(
                                    entry: entry, patient: patient, isDark: isDark,
                                    isSelected: _selectedIds.contains(entryId), selectionMode: _selectionMode,
                                    onCall: () => _call(entry.number ?? ''),
                                    onTap: () { if (_selectionMode) _toggleSelection(entryId); else _call(entry.number ?? ''); },
                                    onLongPress: () { if (!_selectionMode) _showDeleteMenu(entry, entryId); else _toggleSelection(entryId); },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
            if (_showDialpad) _buildDialpadOverlay(isDark),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() { _showDialpad = !_showDialpad; if (!_showDialpad) _dialedNumber = ''; });
        },
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Icon(_showDialpad ? Icons.close : Icons.dialpad, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<PatientProvider>(
      builder: (context, pp, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)), clipBehavior: Clip.antiAlias, child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover)),
              const SizedBox(width: 10),
              Expanded(child: _buildDoctorName()),
              IconButton(onPressed: _loadLogs, icon: const Icon(Icons.refresh, color: AppColors.textDark, size: 22)),
              IconButton(onPressed: _clearAllLogs, icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 22)),
              const Icon(Icons.notifications_outlined, color: AppColors.textDark, size: 22),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDoctorName() {
    return FutureBuilder<String>(
      future: _getPhone(),
      builder: (context, phoneSnap) {
        final phone = phoneSnap.data ?? '';
        return StreamBuilder<DocumentSnapshot>(
          stream: phone.isNotEmpty ? FirebaseFirestore.instance.collection('users').doc(phone).snapshots() : null,
          builder: (context, snapshot) {
            String doctorName = 'Doctor';
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
              doctorName = data['fullName'] ?? 'Doctor';
            }
            return Text(doctorName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark), overflow: TextOverflow.ellipsis);
          },
        );
      },
    );
  }

  Future<String> _getPhone() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
      return user.phoneNumber!;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('loggedInPhone') ?? '';
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(children: [
        _tabButton('Patients', 'patients'),
        const SizedBox(width: 12),
        _tabButton('Missed Calls', 'missed'),
      ]),
    );
  }

  Widget _tabButton(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(color: selected ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textLight)),
      ),
    );
  }

  Widget _buildDialpadOverlay(bool isDark) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -5))]),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_matchedPatient != null)
            Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.person, color: AppColors.primary, size: 16), const SizedBox(width: 8), Expanded(child: Text(_matchedPatient!.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark), overflow: TextOverflow.ellipsis))])),
          Text(_dialedNumber.isEmpty ? 'Type Number' : _dialedNumber, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300, color: isDark ? Colors.white : AppColors.textDark, letterSpacing: 2)),
          const SizedBox(height: 20),
          _keyRow(['1', '2', '3']),
          _keyRow(['4', '5', '6']),
          _keyRow(['7', '8', '9']),
          _keyRow(['*', '0', '#']),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(width: 48),
            GestureDetector(onTap: () => _call(_dialedNumber), child: Container(width: 72, height: 72, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: const Icon(Icons.call, color: Colors.white, size: 32))),
            const SizedBox(width: 12),
            IconButton(onPressed: _onDelete, icon: const Icon(Icons.backspace_outlined, color: Colors.grey)),
          ]),
        ]),
      ),
    );
  }

  Widget _keyRow(List<String> digits) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: digits.map((d) => _keyButton(d)).toList()));
  }

  Widget _keyButton(String digit) {
    return GestureDetector(
      onTap: () => _onKeyPressed(digit),
      child: Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), shape: BoxShape.circle), child: Center(child: Text(digit, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400)))),
    );
  }
}

// ── Call log tile ─────────────────────────────────────────────────────────────
class _CallLogTile extends StatelessWidget {
  final CallLogEntry entry;
  final Patient? patient;
  final bool isDark;
  final VoidCallback onCall;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CallLogTile({required this.entry, this.patient, required this.isDark, required this.onCall, this.isSelected = false, this.selectionMode = false, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final typeData = _typeData(entry.callType);
    final name = patient?.name ?? (entry.name?.isNotEmpty == true ? entry.name! : entry.number ?? 'Unknown');
    final date = entry.timestamp != null ? _formatDate(entry.timestamp!) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryLight : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: isSelected ? AppColors.primary : typeData.color.withOpacity(0.1), shape: BoxShape.circle),
          child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : Icon(typeData.icon, color: typeData.color, size: 20),
        ),
        title: Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: entry.callType == CallType.missed ? Colors.red : AppColors.textDark)),
        subtitle: Text(date, style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
        trailing: GestureDetector(
          onTap: entry.number != null ? onCall : null,
          child: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), shape: BoxShape.circle), child: const Icon(Icons.phone, color: AppColors.primary, size: 18)),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  _TypeData _typeData(CallType? type) {
    switch (type) {
      case CallType.incoming: return _TypeData(Icons.call_made, const Color(0xFF0D3B4D), 'Incoming');
      case CallType.outgoing: return _TypeData(Icons.call_made, const Color(0xFF0D3B4D), 'Outgoing');
      case CallType.missed: return _TypeData(Icons.call_received, AppColors.red, 'Missed');
      case CallType.rejected: return _TypeData(Icons.call_end, Colors.orange, 'Declined');
      default: return _TypeData(Icons.call, Colors.grey, 'Unknown');
    }
  }

  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) return 'Today, ${DateFormat('HH:mm').format(dt)}';
    if (dt.year == now.year) return DateFormat('MMM d, HH:mm').format(dt);
    return DateFormat('MMM d, y').format(dt);
  }
}

class _TypeData {
  final IconData icon;
  final Color color;
  final String label;
  _TypeData(this.icon, this.color, this.label);
}
