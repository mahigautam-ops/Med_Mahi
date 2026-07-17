import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_design.dart';
import '../core/models/patient.dart';
import '../core/providers/patient_provider.dart';
import 'notification_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              _buildStatsGrid(context),
              const SizedBox(height: 28),
              _buildPatientInsights(context),
              const SizedBox(height: 28),
              _buildRecentActivities(context),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome back,',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textLight,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            doctorName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationScreen()),
                    ),
                    child: const Icon(Icons.notifications_outlined, color: AppColors.textDark, size: 26),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    return Consumer<PatientProvider>(
      builder: (context, pp, _) {
        final all = pp.allPatients;
        final total = all.length;
        final critical = all.where((p) => p.status == 'no_improvement').length;
        final recovering = all.where((p) => p.status == 'recovering').length;
        final newCalls = all.where((p) => p.lastVisitDate.isAfter(DateTime.now().subtract(const Duration(days: 7)))).length;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _statCard(Icons.people_outline, 'Total Patients', '$total', AppColors.primary),
              _statCard(Icons.warning_amber_rounded, 'Critical', '$critical', AppColors.red),
              _statCard(Icons.favorite_outline, 'Recovering', '$recovering', AppColors.primary),
              _statCard(Icons.phone_outlined, 'New Calls', '$newCalls', AppColors.primary),
              _buildTokenCard(),
            ],
          ),
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

  Widget _buildTokenCard() {
    return FutureBuilder<String>(
      future: _getPhone(),
      builder: (context, phoneSnap) {
        final phone = phoneSnap.data ?? '';
        if (phone.isEmpty) return _statCard(Icons.token_outlined, 'AI Tokens', '--', AppColors.primary);
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(phone).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return _statCard(Icons.token_outlined, 'AI Tokens', '--', AppColors.primary);
            }
            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final used = data['tokensUsed'] ?? 0;
            final max = data['maxTokens'] ?? 500000;
            final usedStr = used >= 1000000 ? '${(used / 1000000).toStringAsFixed(1)}M' : used >= 1000 ? '${(used / 1000).toStringAsFixed(0)}k' : '$used';
            final maxStr = max >= 1000000 ? '${(max / 1000000).toStringAsFixed(1)}M' : max >= 1000 ? '${(max / 1000).toStringAsFixed(0)}k' : '$max';
            return _statCard(Icons.token_outlined, 'AI Tokens', '$usedStr / $maxStr', AppColors.primary);
          },
        );
      },
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatientInsights(BuildContext context) {
    return Consumer<PatientProvider>(
      builder: (context, pp, _) {
        final all = pp.allPatients;
        final total = all.length > 0 ? all.length : 1;
        final improving = all.where((p) => p.status == 'improving').length;
        final stable = all.where((p) => p.status == 'recovering').length;
        final declining = all.where((p) => p.status == 'no_improvement').length;
        final impPct = (improving / total * 100).round();
        final stPct = (stable / total * 100).round();
        final decPct = (declining / total * 100).round();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Patient Insights', style: AppTextStyles.sectionTitle),
                  GestureDetector(
                    onTap: () {},
                    child: const Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
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
                  children: [
                    // Percentage labels
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '$impPct%',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Improving',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textLight,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '$stPct%',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Stable',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textLight,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '$decPct%',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.red,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Declining',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textLight,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 12,
                        child: Row(
                          children: [
                            if (impPct > 0)
                              Expanded(
                                flex: impPct,
                                child: Container(color: AppColors.primary),
                              ),
                            if (stPct > 0)
                              Expanded(
                                flex: stPct,
                                child: Container(color: AppColors.green),
                              ),
                            if (decPct > 0)
                              Expanded(
                                flex: decPct,
                                child: Container(color: AppColors.red),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentActivities(BuildContext context) {
    return Consumer<PatientProvider>(
      builder: (context, pp, _) {
        final sorted = List<Patient>.from(pp.allPatients)
          ..sort((a, b) => b.lastVisitDate.compareTo(a.lastVisitDate));
        final recent = sorted.take(3).toList();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Activity', style: AppTextStyles.sectionTitle),
                  GestureDetector(
                    onTap: () {},
                    child: const Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (recent.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Text(
                      'No recent activity',
                      style: TextStyle(color: AppColors.textHint, fontSize: 14),
                    ),
                  ),
                )
              else
                ...recent.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
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
                    child: Row(
                      children: [
                        PatientAvatar(name: p.name, size: 48, fontSize: 16),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.lastVisitDisplay,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
                      ],
                    ),
                  ),
                )),
            ],
          ),
        );
      },
    );
  }
}
