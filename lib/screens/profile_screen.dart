import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_design.dart';
import '../core/providers/ai_settings.dart';
import '../core/theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final aiSettings = context.watch<AiSettingsProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Profile avatar
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: const Center(
                  child: Icon(Icons.person, size: 50, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 16),
              _buildDoctorName(),
              const SizedBox(height: 4),
              _buildDoctorDepartment(),
              const SizedBox(height: 32),

              // AI Settings
              _sectionHeader('AI SETTINGS (Managed by Admin)'),
              const SizedBox(height: 12),
              _settingsCard([
                _infoTile(icon: Icons.api, label: 'NVIDIA API', value: aiSettings.isConfigured ? 'Connected' : 'Not configured', valueColor: aiSettings.isConfigured ? AppColors.green : Colors.orange),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _infoTile(icon: Icons.model_training, label: 'Active Model', value: aiSettings.model.split('/').last),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _infoTile(icon: Icons.thermostat, label: 'Temperature', value: aiSettings.temperature.toStringAsFixed(2)),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _infoTile(icon: Icons.token, label: 'Max Tokens', value: aiSettings.maxTokens.toString()),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI settings are managed from the Admin Panel. Contact your admin to make changes.',
                            style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('loggedInPhone');
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Log Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
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
            return Text(
              doctorName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark),
            );
          },
        );
      },
    );
  }

  Widget _buildDoctorDepartment() {
    return FutureBuilder<String>(
      future: _getPhone(),
      builder: (context, phoneSnap) {
        final phone = phoneSnap.data ?? '';
        return StreamBuilder<DocumentSnapshot>(
          stream: phone.isNotEmpty ? FirebaseFirestore.instance.collection('users').doc(phone).snapshots() : null,
          builder: (context, snapshot) {
            String specialization = '';
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
              specialization = data['specialization'] ?? '';
            }
            if (specialization.isEmpty) return const SizedBox.shrink();
            return Text(
              '$specialization Department',
              style: const TextStyle(color: AppColors.textLight, fontSize: 14),
            );
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

  Widget _sectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.textLight,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _settingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _infoTile({required IconData icon, required String label, required String value, Color? valueColor}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
      subtitle: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor ?? AppColors.textDark)),
    );
  }
}
