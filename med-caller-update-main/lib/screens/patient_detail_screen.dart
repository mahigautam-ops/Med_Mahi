import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_design.dart';
import '../core/models/patient.dart';
import '../core/providers/patient_provider.dart';
import 'add_edit_patient_screen.dart';
import 'patient_timeline_screen.dart';
import '../widgets/ai_patient_summary_sheet.dart';
import 'ai_live_call_screen.dart';

class PatientDetailScreen extends StatelessWidget {
  final Patient patient;
  const PatientDetailScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    final pProvider = context.watch<PatientProvider>();
    final p = pProvider.allPatients.firstWhere((element) => element.id == patient.id, orElse: () => patient);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAppBar(context, p),
              _buildProfileCard(p),
              const SizedBox(height: 16),
              _buildStatusCard(p),
              const SizedBox(height: 16),
              _buildGridMenu(context, p),
              const SizedBox(height: 16),
              _buildDetailSection(p),
              const SizedBox(height: 16),
              _buildClinicWisdom(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, Patient p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark), overflow: TextOverflow.ellipsis),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AddEditPatientScreen(patient: p),
            )),
            child: const Icon(Icons.edit_outlined, color: AppColors.textDark, size: 20),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.notifications_outlined, color: AppColors.textDark, size: 20),
        ],
      ),
    );
  }

  Widget _buildProfileCard(Patient p) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          PatientAvatar(name: p.name, size: 64, fontSize: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 14, color: AppColors.textLight),
                    const SizedBox(width: 4),
                    Text(p.phoneNumber, style: const TextStyle(fontSize: 14, color: AppColors.textLight)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    StatusPill(status: p.status),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Age: ${p.age > 0 ? p.age : "—"} Years  |  ${p.gender}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textLight),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(Patient p) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Current Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            p.notes.isNotEmpty ? p.notes : 'Patient reported recurring symptoms. Currently stable and showing significant improvement following prescribed protocol.',
            style: const TextStyle(fontSize: 14, color: AppColors.textMid, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildGridMenu(BuildContext context, Patient p) {
    final items = [
      _GridItem(Icons.timeline, 'Timeline', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientTimelineScreen(patient: p, initialTab: 'Timeline')))),
      _GridItem(Icons.receipt_long, 'Prescriptions', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientTimelineScreen(patient: p, initialTab: 'Prescriptions')))),
      _GridItem(Icons.bar_chart, 'Reports', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientTimelineScreen(patient: p, initialTab: 'Reports')))),
      _GridItem(Icons.auto_awesome, 'AI Summary', () => AIPatientSummarySheet.show(context, p)),
      _GridItem(Icons.psychology_outlined, 'AI Notes', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AILiveCallScreen(patient: p)))),
      _GridItem(Icons.add_circle_outline, 'Add Entry', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientTimelineScreen(patient: p, initialTab: 'Timeline')))),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.1,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildGridTile(items[i]),
      ),
    );
  }

  Widget _buildGridTile(_GridItem item) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              item.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSection(Patient p) {
    final consultStatus = p.consultationStatus;
    Color consultColor = consultStatus == 'Expired' ? AppColors.red : (consultStatus == 'Expiring Soon' ? const Color(0xFFCA8A04) : AppColors.textDark);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PATIENT RECORDS OVERVIEW',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          _detailRow(Icons.calendar_today_outlined, 'Last Visit', p.lastVisitDisplay),
          const SizedBox(height: 14),
          _detailRow(Icons.access_time, 'Last Update', _daysSinceLastVisit(p)),
          const SizedBox(height: 14),
          _detailRow(Icons.event_outlined, 'Next Follow-up', p.sinceWhen.isNotEmpty ? p.sinceWhen : '—'),
          const SizedBox(height: 14),
          _detailRow(Icons.verified_outlined, 'Consultation Valid Till', p.consultationValidTillDisplay, valueColor: consultColor),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textHint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textLight, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.textDark),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildClinicWisdom() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D3B4D), Color(0xFF1A56DB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'CLINIC WISDOM',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Focus on preventive care',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Regular wellness checkups reduce long-term clinical intervention needs...',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _daysSinceLastVisit(Patient p) {
    final diff = DateTime.now().difference(p.lastVisitDate).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '$diff Days Ago';
  }
}

class _GridItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  _GridItem(this.icon, this.label, this.onTap);
}
