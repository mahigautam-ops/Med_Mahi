import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_design.dart';
import '../core/providers/patient_provider.dart';
import '../core/providers/call_provider.dart';
import '../core/models/patient.dart';
import 'add_edit_patient_screen.dart';
import 'patient_detail_screen.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _filter = 'all'; // all | critical | stable

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Patient> _applySearch(List<Patient> patients) {
    var filtered = patients;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      filtered = filtered.where((p) =>
          p.name.toLowerCase().contains(q) ||
          p.phoneNumber.contains(q)).toList();
    }
    // Apply status filter
    switch (_filter) {
      case 'critical':
        filtered = filtered.where((p) => p.status == 'no_improvement').toList();
        break;
      case 'stable':
        filtered = filtered.where((p) => p.status == 'recovering' || p.status == 'improving').toList();
        break;
    }
    return filtered;
  }

  Future<void> _makeCall(BuildContext context, String number) async {
    try {
      await context.read<CallProvider>().makeCall(number);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddEditPatientScreen()),
        ),
        backgroundColor: AppColors.primary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.person_add_outlined, color: Colors.white, size: 26),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            _buildSearchBar(),
            _buildFilterPills(),
            Expanded(child: _buildList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer<PatientProvider>(
      builder: (context, provider, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
                  ),
                  const Text(
                    'Patients',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.grid_view, color: AppColors.textDark, size: 22),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search, color: AppColors.textDark, size: 22),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 15, color: AppColors.textDark),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            prefixIcon: const Icon(Icons.search, color: AppColors.textHint, size: 20),
            suffixIcon: _query.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    child: const Icon(Icons.cancel, color: AppColors.textHint, size: 18),
                  )
                : null,
            hintText: 'Search by name, ID or condition...',
            hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPills() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          _filterPill('All Patients', 'all'),
          const SizedBox(width: 8),
          _filterPill('Critical', 'critical'),
          const SizedBox(width: 8),
          _filterPill('Stable', 'stable'),
        ],
      ),
    );
  }

  Widget _filterPill(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textLight,
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return Consumer<PatientProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final filtered = _applySearch(provider.allPatients);

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_search_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  _query.isEmpty ? 'No patients added yet' : 'No results for "$_query"',
                  style: const TextStyle(fontSize: 16, color: AppColors.textLight, fontWeight: FontWeight.w500),
                ),
                if (_query.isEmpty) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddEditPatientScreen()),
                    ),
                    child: const Text(
                      'Add your first patient',
                      style: TextStyle(fontSize: 15, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final patient = filtered[index];
            return _PatientCard(
              patient: patient,
              onCall: () => _makeCall(context, patient.phoneNumber),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: patient)),
              ),
              onLongPress: () => _showOptions(context, patient),
            );
          },
        );
      },
    );
  }

  void _showOptions(BuildContext context, Patient patient) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  PatientAvatar(name: patient.name, size: 60, fontSize: 24),
                  const SizedBox(height: 10),
                  Text(patient.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 2),
                  Text(patient.phoneNumber, style: const TextStyle(fontSize: 14, color: AppColors.textLight)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  ListTile(
                    leading: Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.call, color: AppColors.green, size: 18)),
                    title: const Text('Call', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textDark)),
                    onTap: () { Navigator.pop(ctx); _makeCall(context, patient.phoneNumber); },
                  ),
                  const Divider(height: 1, indent: 62),
                  ListTile(
                    leading: Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.person_outline, color: AppColors.primary, size: 18)),
                    title: const Text('View Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textDark)),
                    onTap: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: patient))); },
                  ),
                  const Divider(height: 1, indent: 62),
                  ListTile(
                    leading: Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.edit_outlined, color: Color(0xFFFF9800), size: 18)),
                    title: const Text('Edit Patient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textDark)),
                    onTap: () { Navigator.pop(ctx); Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddEditPatientScreen(patient: patient))); },
                  ),
                  const Divider(height: 1, indent: 62),
                  ListTile(
                    leading: Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_outline, color: AppColors.red, size: 18)),
                    title: const Text('Delete Patient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.red)),
                    onTap: () { Navigator.pop(ctx); _confirmDelete(context, patient); },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: const Center(child: Text('Cancel', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.primary))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Patient?'),
        content: Text('Are you sure you want to delete ${patient.name}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                await context.read<PatientProvider>().deletePatient(patient.phoneNumber);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${patient.name} deleted'), backgroundColor: Colors.redAccent),
                  );
                }
              } catch (e) {
                if (context.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Patient Card ─────────────────────────────────────────────────────────────
class _PatientCard extends StatelessWidget {
  final Patient patient;
  final VoidCallback onCall;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PatientCard({
    required this.patient,
    required this.onCall,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final statusCol = statusColor(patient.status);
    final statusLbl = statusLabel(patient.status);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PatientAvatar(name: patient.name, size: 48, fontSize: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              patient.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
                            ),
                          ),
                          if (patient.isHighRisk)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(6)),
                              child: const Text('HIGH RISK', style: TextStyle(color: AppColors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${patient.age > 0 ? patient.age : "—"} ${patient.gender}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textLight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusCol.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLbl.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusCol,
                ),
              ),
            ),
            if (patient.healthIssue.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                patient.healthIssue,
                style: const TextStyle(fontSize: 14, color: AppColors.textMid, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_outline, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('View Details', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onCall,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.phone, color: AppColors.primary, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
