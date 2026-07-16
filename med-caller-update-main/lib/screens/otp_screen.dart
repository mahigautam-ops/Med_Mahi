import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_design.dart';
import 'login_screen.dart';
import 'main_layout.dart';

enum OtpFlow { tokenLogin, forgotAccess, registration }

class OtpScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final OtpFlow flow;

  const OtpScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    this.flow = OtpFlow.forgotAccess,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  int _resendSeconds = 58;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _resendSeconds = 58;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() {
          _resendSeconds--;
          if (_resendSeconds <= 0) {
            _timer?.cancel();
          }
        });
      }
    });
  }

  void _resendOTP() {
    if (_resendSeconds > 0) return;
    FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      verificationCompleted: (_) {},
      verificationFailed: (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${e.message}')));
      },
      codeSent: (id, _) {
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP resent!')));
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _verifyOTP() async {
    final code = _otpCode;
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter complete 6-digit OTP')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: code,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      if (widget.flow == OtpFlow.tokenLogin) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('loggedInPhone', widget.phoneNumber);
      }

      if (widget.flow == OtpFlow.forgotAccess) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('loggedInPhone', widget.phoneNumber);
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.phoneNumber)
            .get();
        if (doc.exists && doc.data()?['isApproved'] == true && (doc.data()?['accessToken'] ?? '').isEmpty) {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const SetAccessTokenScreen()),
              (route) => false,
            );
          }
        } else {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const MainLayout()),
              (route) => false,
            );
          }
        }
        return;
      }

      if (widget.flow == OtpFlow.registration) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.phoneNumber)
            .get();
        if (!doc.exists || doc.data()?['isApproved'] != true) {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => PendingVerificationScreen(phoneNumber: widget.phoneNumber)),
              (route) => false,
            );
          }
          return;
        }
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.phoneNumber)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        if (data['isApproved'] == false && data['isRejected'] == false) {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => PendingVerificationScreen(phoneNumber: widget.phoneNumber)),
              (route) => false,
            );
          }
          return;
        }
        if (data['isRejected'] == true) {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Account rejected: ${data['rejectionReason'] ?? 'Contact support'}')));
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
          }
          return;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('loggedInPhone', widget.phoneNumber);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainLayout()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid OTP: $e')));
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back, color: Colors.grey[600], size: 20),
                          const SizedBox(width: 4),
                          Text('Back to login', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: const Color(0xFFE8F0F3), shape: BoxShape.circle),
                      child: Icon(Icons.shield_outlined, color: AppColors.primary, size: 26),
                    ),
                    const SizedBox(height: 20),
                    const Text('Verify Your Access', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 10),
                    Text(
                      'OTP sent to your registered\nmobile number',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey[500], height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (i) {
                        return Container(
                          width: 48,
                          height: 56,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextField(
                            controller: _controllers[i],
                            focusNode: _focusNodes[i],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: _controllers[i].text.isNotEmpty ? AppColors.primary : AppColors.border, width: _controllers[i].text.isNotEmpty ? 2 : 1.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.primary, width: 2),
                              ),
                              filled: true,
                              fillColor: _controllers[i].text.isNotEmpty ? AppColors.primaryLight : const Color(0xFFF8FAFC),
                            ),
                            onChanged: (val) {
                              setState(() {});
                              if (val.isNotEmpty && i < 5) {
                                _focusNodes[i + 1].requestFocus();
                              }
                              if (val.isEmpty && i > 0) {
                                _focusNodes[i - 1].requestFocus();
                              }
                              if (_otpCode.length == 6) {
                                _verifyOTP();
                              }
                            },
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verifyOTP,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D3B4D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Verify', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text("Didn't receive the code?", style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _resendOTP,
                      child: Text(
                        'Resend OTP',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _resendSeconds > 0 ? Colors.grey[400] : AppColors.primary,
                        ),
                      ),
                    ),
                    if (_resendSeconds > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Available in 0:${_resendSeconds.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, color: Colors.grey[400], size: 14),
                  const SizedBox(width: 6),
                  Text('SECURE CLINICA PROTOCOL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[400], letterSpacing: 1.5)),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
