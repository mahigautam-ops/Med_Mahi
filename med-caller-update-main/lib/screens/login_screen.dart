import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_design.dart';
import 'otp_screen.dart';
import 'registration_screen.dart';
import 'main_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController(text: '+91');
  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = false;
  bool _obscureToken = true;

  bool _needsTokenSetup = false;

  void _signIn() async {
    final phone = _phoneController.text.trim();
    final token = _tokenController.text.trim();

    if (phone.isEmpty || phone == '+91') {
      _showSnack('Please enter your phone number');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .get();

      if (!doc.exists) {
        setState(() => _isLoading = false);
        _showSnack('No account found. Please create an account first.');
        return;
      }

      final userData = doc.data()!;

      if (userData['isRejected'] == true) {
        setState(() => _isLoading = false);
        _showSnack('Your account has been rejected. ${userData['rejectionReason'] ?? 'Contact support.'}');
        return;
      }

      if (userData['isApproved'] == false) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PendingVerificationScreen(phoneNumber: phone)),
        );
        return;
      }

      final storedToken = userData['accessToken'] ?? '';

      if (storedToken.isNotEmpty) {
        if (token.isEmpty) {
          setState(() => _isLoading = false);
          _showSnack('Please enter your access token to login.');
          return;
        }
        if (storedToken != token) {
          setState(() => _isLoading = false);
          _showSnack('Invalid access token. Use Forgot Access to reset.');
          return;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('loggedInPhone', phone);
        setState(() => _isLoading = false);
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainLayout()),
            (route) => false,
          );
        }
        return;
      }

      if (storedToken.isEmpty) {
        setState(() => _isLoading = false);
        _showSnack('No access token set. Please use Forgot Access to set one.');
        return;
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Error: $e');
    }
  }

  void _forgotAccess() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone == '+91') {
      _showSnack('Enter your phone number first, then tap Forgot Access.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .get();

      if (!doc.exists) {
        setState(() => _isLoading = false);
        _showSnack('No account found. Please create an account first.');
        return;
      }

      final userData = doc.data()!;
      if (userData['isApproved'] != true) {
        setState(() => _isLoading = false);
        _showSnack('Account not approved yet. Please wait for admin approval.');
        return;
      }

      FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const SetAccessTokenScreen()),
            );
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showSnack('OTP failed: ${e.message}');
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OtpScreen(
                  verificationId: verificationId,
                  phoneNumber: phone,
                  flow: OtpFlow.forgotAccess,
                ),
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Error: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 32),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0F3),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_outlined, color: AppColors.primary, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'Clinica AI',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0D3B4D)),
              ),
              const SizedBox(height: 6),
              Text(
                'Practitioner Portal Access',
                style: TextStyle(fontSize: 15, color: Colors.grey[500]),
              ),
              const SizedBox(height: 28),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Phone number', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF1E293B)),
                        decoration: InputDecoration(
                          hintText: '+1 (555) 000-0000',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon: Icon(Icons.phone_outlined, color: Colors.grey[400], size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Access Token', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                        GestureDetector(
                          onTap: _forgotAccess,
                          child: const Text('Forgot Access?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0D3B4D))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TextField(
                        controller: _tokenController,
                        obscureText: _obscureToken,
                        keyboardType: TextInputType.visiblePassword,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF1E293B)),
                        decoration: InputDecoration(
                          hintText: '••••••••••',
                          hintStyle: TextStyle(color: Colors.grey[400], letterSpacing: 3),
                          prefixIcon: Icon(Icons.vpn_key_outlined, color: Colors.grey[400], size: 20),
                          suffixIcon: GestureDetector(
                            onTap: () => setState(() => _obscureToken = !_obscureToken),
                            child: Icon(
                              _obscureToken ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: Colors.grey[400],
                              size: 20,
                            ),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D3B4D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: Container(height: 1, color: AppColors.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('OR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[400], letterSpacing: 1.5)),
                        ),
                        Expanded(child: Container(height: 1, color: AppColors.border)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen()));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textDark,
                          side: const BorderSide(color: AppColors.border, width: 1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          backgroundColor: const Color(0xFFF8FAFC),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Create Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('New to the platform? ', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen())),
                      child: const Text('Create account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0D3B4D))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PendingVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  const PendingVerificationScreen({super.key, required this.phoneNumber});

  @override
  State<PendingVerificationScreen> createState() => _PendingVerificationScreenState();
}

class _PendingVerificationScreenState extends State<PendingVerificationScreen> {
  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.phoneNumber)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data()!;
      if (data['isApproved'] == true) {
        final hasToken = (data['accessToken'] ?? '').toString().isNotEmpty;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('loggedInPhone', widget.phoneNumber);
        });
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => hasToken ? const MainLayout() : const SetAccessTokenScreen()),
          (route) => false,
        );
      } else if (data['isRejected'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account rejected: ${data['rejectionReason'] ?? 'Contact support'}')),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Clinica AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  const Spacer(),
                  Icon(Icons.notifications_outlined, color: Colors.grey[500]),
                  const SizedBox(width: 12),
                  CircleAvatar(radius: 16, backgroundColor: AppColors.primaryLight, child: Icon(Icons.person, size: 18, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 40),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 4))],
                ),
                child: Icon(Icons.shield_outlined, color: AppColors.primary, size: 48),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[500])),
                    const SizedBox(width: 8),
                    Text('VERIFICATION IN PROGRESS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Your clinical access request is under review',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0D3B4D)),
              ),
              const SizedBox(height: 16),
              Text(
                'Our team is currently verifying your medical credentials and institutional affiliation to ensure patient data security.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[500], height: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                'You will receive a notification once approved.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () async {
                    final doc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(widget.phoneNumber)
                        .get();
                    if (doc.exists) {
                      final data = doc.data()!;
                      if (data['isApproved'] == true) {
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const MainLayout()),
                            (route) => false,
                          );
                        }
                      } else if (data['isRejected'] == true) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Account rejected: ${data['rejectionReason'] ?? 'Contact support'}')),
                          );
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Still under review. Please wait.')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D3B4D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, size: 18),
                      SizedBox(width: 8),
                      Text('Check Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0D3B4D),
                    side: const BorderSide(color: AppColors.border, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Contact Support', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.shield_outlined, color: Colors.grey[600], size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Standard Security Protocol', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                          const SizedBox(height: 4),
                          Text(
                            'Verification typically takes 24-48 business hours. We prioritize clinical integrity across the entire Clinica AI network.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class SetAccessTokenScreen extends StatefulWidget {
  const SetAccessTokenScreen({super.key});

  @override
  State<SetAccessTokenScreen> createState() => _SetAccessTokenScreenState();
}

class _SetAccessTokenScreenState extends State<SetAccessTokenScreen> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscureToken = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  void _updateToken() async {
    final token = _tokenController.text.trim();
    final confirm = _confirmController.text.trim();

    if (token.length < 4 || token.length > 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access token must be 4-8 characters')));
      return;
    }
    if (token != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tokens do not match')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPhone = prefs.getString('loggedInPhone') ?? '';
      final user = FirebaseAuth.instance.currentUser;
      final phone = savedPhone.isNotEmpty ? savedPhone : (user?.phoneNumber ?? '');
      if (phone.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No phone number found. Please login again.')));
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(phone).set({
        'accessToken': token,
      }, SetOptions(merge: true));

      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access token set successfully!')));
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainLayout()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error setting token: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Clinica AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D3B4D))),
                ],
              ),
              const SizedBox(height: 40),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0F3),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_outlined, color: AppColors.primary, size: 30),
              ),
              const SizedBox(height: 20),
              const Text(
                'Set New Access Token',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              Text(
                'Verification complete. Please choose\na secure access token for your\nclinical portal.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[500], height: 1.5),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New Access Token', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                      child: TextField(
                        controller: _tokenController,
                        obscureText: _obscureToken,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Enter alphanumeric token',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[400], size: 20),
                          suffixIcon: GestureDetector(
                            onTap: () => setState(() => _obscureToken = !_obscureToken),
                            child: Icon(_obscureToken ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey[400], size: 20),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Minimum 4 characters.', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                    ),
                    const SizedBox(height: 20),
                    const Text('Confirm Access Token', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                      child: TextField(
                        controller: _confirmController,
                        obscureText: _obscureConfirm,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Repeat access token',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon: Icon(Icons.check_circle_outline, color: Colors.grey[400], size: 20),
                          suffixIcon: GestureDetector(
                            onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            child: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey[400], size: 20),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.grey[500], size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your token is encrypted and never stored in plain text.',
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
                        onPressed: _isLoading ? null : _updateToken,
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
                                  Text('Update & Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 18),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.help_outline, color: Colors.grey[400], size: 16),
                  const SizedBox(width: 6),
                  Text('Need help with secure tokens?', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
