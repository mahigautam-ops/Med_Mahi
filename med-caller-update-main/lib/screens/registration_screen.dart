import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../core/app_design.dart';
import 'login_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+91');
  final _emailController = TextEditingController();
  final _specializationController = TextEditingController();
  final _registrationController = TextEditingController();
  final _experienceController = TextEditingController();
  File? _certificateFile;
  String? _certificateName;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickCertificate() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 60,
    );
    if (picked != null) {
      setState(() {
        _certificateFile = File(picked.path);
        _certificateName = picked.name;
      });
    }
  }

  void _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_certificateFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload your medical certificate (required)')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final phone = _phoneController.text.trim();

      final existingDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .get();

      if (existingDoc.exists) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('An account with this phone number already exists. Please login.')),
          );
        }
        return;
      }

      String certificateBase64 = '';
      if (_certificateFile != null) {
        final bytes = await _certificateFile!.readAsBytes();
        if (bytes.length > 700000) {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Certificate image too large. Please use a smaller image (under 500KB).')),
            );
          }
          return;
        }
        certificateBase64 = base64Encode(bytes);
      }

      await FirebaseFirestore.instance.collection('users').doc(phone).set({
        'fullName': _nameController.text.trim(),
        'phoneNumber': phone,
        'email': _emailController.text.trim(),
        'specialization': _specializationController.text.trim(),
        'registrationNumber': _registrationController.text.trim(),
        'experience': _experienceController.text.trim(),
        'certificateName': _certificateName ?? '',
        'certificateBase64': certificateBase64,
        'role': 'doctor',
        'isApproved': false,
        'isRejected': false,
        'accessToken': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() => _isLoading = false);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => PendingVerificationScreen(phoneNumber: phone)),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Clinica AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D3B4D))),
                  ],
                ),
                const SizedBox(height: 32),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: const Color(0xFFE8F0F3), shape: BoxShape.circle),
                  child: Icon(Icons.group_add_outlined, color: AppColors.primary, size: 30),
                ),
                const SizedBox(height: 16),
                const Text('Join the Med Network', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 8),
                Text('Complete your profile to request\nclinical portal access.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey[500], height: 1.5)),
                const SizedBox(height: 28),
                _buildCard(
                  children: [
                    _buildField('Full Name', _nameController, Icons.person_outline, 'Dr. First Last', required: true),
                    _buildField('Phone Number', _phoneController, Icons.phone_outlined, '+91 XXXXX XXXXX', keyboardType: TextInputType.phone, required: true),
                    _buildField('Email', _emailController, Icons.email_outlined, 'doctor@hospital.com', keyboardType: TextInputType.emailAddress),
                    _buildField('Specialization', _specializationController, Icons.local_hospital_outlined, 'e.g., Cardiology'),
                    _buildField('Registration No.', _registrationController, Icons.badge_outlined, 'Medical council reg. number'),
                    _buildField('Experience (years)', _experienceController, Icons.work_outline, 'e.g., 5', keyboardType: TextInputType.number),
                  ],
                ),
                const SizedBox(height: 16),
                _buildCard(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified_outlined, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        const Text('Medical Certificate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
                          child: const Text('Required', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickCertificate,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _certificateFile != null ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _certificateFile != null ? const Color(0xFF16A34A) : AppColors.border,
                            width: _certificateFile != null ? 2 : 1.5,
                          ),
                        ),
                        child: _certificateFile != null
                            ? Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)),
                                    child: const Icon(Icons.description_outlined, color: Color(0xFF16A34A), size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_certificateName ?? 'Certificate', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                        const SizedBox(height: 2),
                                        Text('Uploaded successfully', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.check_circle, color: const Color(0xFF16A34A), size: 22),
                                ],
                              )
                            : Column(
                                children: [
                                  Icon(Icons.cloud_upload_outlined, color: Colors.grey[400], size: 36),
                                  const SizedBox(height: 10),
                                  Text('Tap to upload certificate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                                  const SizedBox(height: 4),
                                  Text('PDF, JPG or PNG (max 10MB)', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey[500], size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your credentials will be verified by our team. This typically takes 24-48 business hours.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D3B4D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Submit Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account? ', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text('Sign In', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0D3B4D))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, String hint, {TextInputType? keyboardType, bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
              if (required) ...[
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(fontSize: 14, color: Color(0xFFDC2626))),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
              style: const TextStyle(fontSize: 15, color: Color(0xFF1E293B)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
