import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/call_provider.dart';
import '../core/providers/patient_provider.dart';
import '../core/models/patient.dart';
import '../core/app_design.dart';
import 'contacts_screen.dart';
import 'call_history_screen.dart';

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _dialedNumber = '';
  Patient? _matchedPatient;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onKeyPressed(String value) {
    setState(() => _dialedNumber += value);
    _lookupPatient();
  }

  void _onDelete() {
    if (_dialedNumber.isNotEmpty) {
      setState(() => _dialedNumber = _dialedNumber.substring(0, _dialedNumber.length - 1));
      _lookupPatient();
    }
  }

  Future<void> _lookupPatient() async {
    final number = _dialedNumber;
    if (number.length < 7) {
      setState(() => _matchedPatient = null);
      return;
    }
    setState(() => _looking = true);
    final p = await context.read<PatientProvider>().findByPhoneNumber(number);
    if (mounted && _dialedNumber == number) {
      setState(() {
        _matchedPatient = p;
        _looking = false;
      });
    }
  }

  Future<void> _makeCall() async {
    if (_dialedNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a number to call')),
      );
      return;
    }
    try {
      await context.read<CallProvider>().makeCall(_dialedNumber);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Tab bar
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textHint,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.dialpad), text: 'Dialer'),
                  Tab(icon: Icon(Icons.contacts_outlined), text: 'Contacts'),
                  Tab(icon: Icon(Icons.history), text: 'History'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildDialerTab(isDark),
                  const ContactsScreen(),
                  const CallHistoryScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialerTab(bool isDark) {
    return Column(
      children: [
        const SizedBox(height: 20),
        // Patient badge
        if (_looking)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_matchedPatient != null)
          _buildPatientBadge(_matchedPatient!)
        else
          const SizedBox(height: 12),

        // Number display - Clean white style like screenshot 3
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            children: [
              Text(
                _dialedNumber.isEmpty ? '' : _formatDisplay(_dialedNumber),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  color: _dialedNumber.isEmpty
                      ? const Color(0xFF94A3B8)
                      : AppColors.primary,
                  letterSpacing: 2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (_dialedNumber.isNotEmpty)
                const Text(
                  'Typing...',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textHint,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Keypad - Clean white circles like screenshot
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _keyRow(['1', '2', '3']),
                _keyRow(['4', '5', '6']),
                _keyRow(['7', '8', '9']),
                _keyRow(['*', '0', '#']),
              ],
            ),
          ),
        ),

        // Call and cancel buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 80),
              // Call button - Teal
              GestureDetector(
                onTap: _makeCall,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call, color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(width: 24),
              // Cancel button - Red/pink
              GestureDetector(
                onTap: _onDelete,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: AppColors.red, size: 24),
                ),
              ),
              const SizedBox(width: 80),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPatientBadge(Patient p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark, fontSize: 14)),
                  Text(p.healthIssue, style: const TextStyle(color: AppColors.textLight, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (p.isHighRisk)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(8)),
                child: const Text('HIGH RISK', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDisplay(String number) {
    if (number.length <= 5) return number;
    if (number.length <= 10) return '${number.substring(0, 5)} ${number.substring(5)}';
    return number;
  }

  Widget _keyRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _keyButton(d)).toList(),
    );
  }

  Widget _keyButton(String digit) {
    return GestureDetector(
      onTap: () => _onKeyPressed(digit),
      onLongPress: digit == '0' ? () => _onKeyPressed('+') : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            digit,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w400,
              color: AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}
