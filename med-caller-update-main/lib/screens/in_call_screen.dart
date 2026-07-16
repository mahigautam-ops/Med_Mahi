import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_design.dart';
import '../core/providers/call_provider.dart';
import '../core/providers/patient_provider.dart';
import '../core/models/patient.dart';
import '../widgets/ai_quick_summary_card.dart';
import 'patient_detail_screen.dart';
import 'ai_live_call_screen.dart';
import 'add_edit_patient_screen.dart';

class InCallScreen extends StatefulWidget {
  const InCallScreen({super.key});

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> with SingleTickerProviderStateMixin {
  Patient? _patient;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;

  static const Color bgLight = Color(0xFFEDF2F7);
  static const Color teal = AppColors.primary;

  bool _showSuccessOverlay = false;
  Patient? _recentlyAddedPatient;
  bool _showDialpad = false;
  String _dialpadBuffer = '';

  String get _displayName {
    if (_patient != null) return _patient!.name;
    final cp = context.read<CallProvider>();
    if (cp.callerName.isNotEmpty) return cp.callerName;
    return cp.number.isNotEmpty ? cp.number : 'Unknown Number';
  }

  bool get _isUnknown => _patient == null;

  bool get _isActive => context.read<CallProvider>().state == CallState.active;
  bool get _isRinging => context.read<CallProvider>().state == CallState.ringing;
  bool get _isDialing => context.read<CallProvider>().state == CallState.dialing;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPatient();
    });
  }

  void _fetchPatient() async {
    final cp = context.read<CallProvider>();
    if (cp.number.isNotEmpty) {
      final pp = context.read<PatientProvider>();
      final p = await pp.findByPhoneNumber(cp.number);
      if (mounted) setState(() => _patient = p);
    }
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDuration += const Duration(seconds: 1));
    });
  }

  String get _durationStr {
    final m = _callDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _callDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<CallProvider>().state;
    if (state == CallState.active && !(_durationTimer?.isActive ?? false)) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, cp, _) {
        if (cp.state == CallState.ended || cp.state == CallState.idle) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.canPop(context)) Navigator.pop(context);
          });
        }
        if (cp.state == CallState.active && !(_durationTimer?.isActive ?? false)) {
          _startTimer();
        }

        if (_showSuccessOverlay) {
          return Scaffold(
            backgroundColor: bgLight,
            body: SafeArea(
              child: SingleChildScrollView(child: _buildSuccessOverlay()),
            ),
          );
        }

        if (_isDialing || _isActive) {
          return _buildOutgoingScreen(cp);
        }

        return _buildIncomingScreen(cp);
      },
    );
  }

  // ── INCOMING SCREEN ────────────────────────────────────────────────────────
  Widget _buildIncomingScreen(CallProvider cp) {
    return Scaffold(
      backgroundColor: bgLight,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildSecureLineHeader(),
            const SizedBox(height: 24),
            _buildIncomingLabel(),
            const SizedBox(height: 12),
            _buildCallerName(),
            const SizedBox(height: 4),
            _buildCallerNumber(),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _isUnknown ? _buildUnknownClinicalContext() : _buildKnownClinicalContext(),
                    const SizedBox(height: 24),
                    _buildIncomingActionButtons(cp),
                    const SizedBox(height: 24),
                    _buildInCallToolRow(cp),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildSlideToAnswer(cp),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSecureLineHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'CLINICA SECURE LINE',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          Icon(Icons.shield_outlined, color: Colors.grey[400], size: 20),
        ],
      ),
    );
  }

  Widget _buildIncomingLabel() {
    return Text(
      'INCOMING CLINICAL CALL',
      style: TextStyle(
        color: teal,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildCallerName() {
    return Text(
      _displayName,
      style: const TextStyle(
        color: teal,
        fontSize: 34,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildCallerNumber() {
    final number = context.read<CallProvider>().number;
    return Text(
      number.isNotEmpty ? number : '',
      style: TextStyle(
        color: Colors.grey[500],
        fontSize: 16,
      ),
    );
  }

  Widget _buildUnknownClinicalContext() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, color: teal, size: 20),
              const SizedBox(width: 10),
              const Text('Clinical Context', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Status', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    const Text('Unregistered Number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB91C1C))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKnownClinicalContext() {
    final p = _patient!;
    final statusColor = p.status == 'recovering' ? const Color(0xFF16A34A) :
                         p.status == 'improving' ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final statusBg = p.status == 'recovering' ? const Color(0xFFF0FDF4) :
                     p.status == 'improving' ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final statusText = p.status.replaceFirst(RegExp('.'), p.status.isEmpty ? '' : p.status[0].toUpperCase());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, color: teal, size: 20),
              const SizedBox(width: 10),
              const Text('Clinical Context', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
          const SizedBox(height: 16),
          _contextRow('Chief Complaint', p.healthIssue.isNotEmpty ? p.healthIssue : 'Chronic Migraine'),
          const SizedBox(height: 14),
          _contextRow('Prescribed Medication', p.medication.isNotEmpty ? p.medication : 'Sumatriptan 50mg'),
          const SizedBox(height: 14),
          _contextRow('Previous Issues', p.notes.isNotEmpty ? p.notes : 'Chronic Sinusitis'),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: p)));
            },
            child: Row(
              children: [
                Text('Status', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(statusText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const Spacer(),
        Flexible(
          child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
        ),
      ],
    );
  }

  Widget _buildIncomingActionButtons(CallProvider cp) {
    if (_isUnknown) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: _outlineActionButton(Icons.videocam_outlined, 'Video\nCall', () {}),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _outlineActionButton(Icons.person_add_outlined, 'Add New\nPatient', () {
                _addNewPatient();
              }),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: _outlineActionButton(Icons.person_add_outlined, 'Add New\nPatient', () {
                _addNewPatient();
              }),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _outlineActionButton(Icons.videocam_outlined, 'Video\nCall', () {}),
            ),
          ],
        ),
      );
    }
  }

  Widget _outlineActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: teal, size: 28),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildInCallToolRow(CallProvider cp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _toolButton(cp.isMuted ? Icons.mic_off : Icons.mic, 'Mute', () => cp.toggleMute()),
          _toolButton(Icons.dialpad, 'Keypad', () {
            setState(() {
              _showDialpad = !_showDialpad;
              if (!_showDialpad) _dialpadBuffer = '';
            });
          }),
          _toolButton(cp.isSpeakerOn ? Icons.volume_up : Icons.volume_down, 'Speaker', () => cp.toggleSpeaker()),
          _toolButton(Icons.circle_outlined, 'Record', () {}),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.grey[600], size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSlideToAnswer(CallProvider cp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => cp.rejectCall(),
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
                child: const Icon(Icons.phone, color: Colors.white, size: 26),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SLIDE TO ANSWER',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'OR DECLINE',
                    style: TextStyle(color: Colors.grey[400], fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => cp.answerCall(),
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                child: const Icon(Icons.phone, color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── OUTGOING / ACTIVE SCREEN ───────────────────────────────────────────────
  Widget _buildOutgoingScreen(CallProvider cp) {
    return Scaffold(
      backgroundColor: bgLight,
      body: SafeArea(
        child: _showDialpad
            ? _buildActiveDialpadView(cp)
            : Column(
                children: [
                  const SizedBox(height: 8),
                  _buildOutgoingHeader(),
                  const SizedBox(height: 20),
                  Text(
                    _displayName,
                    style: const TextStyle(color: teal, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.read<CallProvider>().number,
                    style: TextStyle(color: Colors.grey[500], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildCallStatusText(cp),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildPatientContextCard(),
                          const SizedBox(height: 24),
                          _buildActiveCallTools(cp),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  _buildEndCallButton(cp),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildOutgoingHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: teal),
            onPressed: () => Navigator.pop(context),
          ),
          const Text('Clinica AI', style: TextStyle(color: teal, fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('ENCRYPTED', style: TextStyle(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }

  Widget _buildCallStatusText(CallProvider cp) {
    String text = 'Calling...';
    String? icon;
    if (_isActive) {
      text = _durationStr;
      icon = 'timer';
    } else if (_isDialing) {
      text = 'Calling...';
      icon = 'phone';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon == 'phone') ...[
          Icon(Icons.phone_outlined, color: teal, size: 14),
          const SizedBox(width: 4),
        ],
        if (icon == 'timer') ...[
          Icon(Icons.access_time, color: teal, size: 14),
          const SizedBox(width: 4),
        ],
        Text(text, style: TextStyle(color: teal, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildPatientContextCard() {
    if (_patient == null) return const SizedBox.shrink();
    final p = _patient!;
    final statusColor = p.status == 'recovering' ? const Color(0xFF16A34A) :
                         p.status == 'improving' ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final statusBg = p.status == 'recovering' ? const Color(0xFFF0FDF4) :
                     p.status == 'improving' ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final statusText = p.status.replaceFirst(RegExp('.'), p.status.isEmpty ? '' : p.status[0].toUpperCase());

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
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
          Row(
            children: [
              Text('PATIENT CONTEXT', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('ID: #PX-${p.id.substring(0, 4).toUpperCase()}', style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medical_information_outlined, color: teal, size: 20),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Primary Condition', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text(p.healthIssue.isNotEmpty ? p.healthIssue : 'Chronic Migraine', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.assignment_outlined, color: Color(0xFF16A34A), size: 20),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Latest Status', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCallTools(CallProvider cp) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _activeToolButton(cp.isMuted ? Icons.mic_off : Icons.mic, 'Mute', () => cp.toggleMute(), isActive: cp.isMuted),
              _activeToolButton(Icons.dialpad, 'Keypad', () {
                setState(() {
                  _showDialpad = true;
                  _dialpadBuffer = '';
                });
              }),
              _activeToolButton(cp.isSpeakerOn ? Icons.volume_up : Icons.volume_down, 'Speaker', () => cp.toggleSpeaker(), isActive: cp.isSpeakerOn),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _activeToolButton(Icons.videocam_outlined, 'Video', () {}),
              _activeToolButton(Icons.circle_outlined, 'Record', () {}),
              _activeToolButton(Icons.add, 'Add', () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activeToolButton(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive ? teal : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Icon(icon, color: isActive ? Colors.white : Colors.grey[700], size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEndCallButton(CallProvider cp) {
    return GestureDetector(
      onTap: () => cp.hangupCall(),
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          color: Color(0xFFDC2626),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x33DC2626), blurRadius: 16, offset: Offset(0, 4)),
          ],
        ),
        child: const Icon(Icons.phone, color: Colors.white, size: 32),
      ),
    );
  }

  // ── ACTIVE DIALPAD OVERLAY ─────────────────────────────────────────────────
  Widget _buildActiveDialpadView(CallProvider cp) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: teal),
                onPressed: () => setState(() => _showDialpad = false),
              ),
              const Text('Clinica AI', style: TextStyle(color: teal, fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
                child: Text('ENCRYPTED', style: TextStyle(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(_displayName, style: const TextStyle(color: teal, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(context.read<CallProvider>().number, style: TextStyle(color: Colors.grey[500], fontSize: 15)),
        const SizedBox(height: 8),
        Text(_dialpadBuffer.isEmpty ? 'Dialpad' : _dialpadBuffer, style: TextStyle(color: Colors.grey[600], fontSize: 24, fontWeight: FontWeight.w600)),
        const Spacer(),
        ..._buildDialpadKeys(cp),
        const Spacer(),
        _buildEndCallButton(cp),
        const SizedBox(height: 24),
      ],
    );
  }

  List<Widget> _buildDialpadKeys(CallProvider cp) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    return keys.map((row) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((key) {
            return GestureDetector(
              onTapDown: (_) {
                cp.playDtmf(key);
                setState(() => _dialpadBuffer += key);
              },
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                child: Center(child: Text(key, style: TextStyle(color: Colors.grey[700], fontSize: 26, fontWeight: FontWeight.w400))),
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }

  // ── ADD NEW PATIENT ────────────────────────────────────────────────────────
  void _addNewPatient() async {
    final cp = context.read<CallProvider>();
    final num = cp.number.isNotEmpty ? cp.number : cp.callerName;
    final newPatient = await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => AddEditPatientScreen(initialPhoneNumber: num),
    ));
    if (newPatient != null && newPatient is Patient) {
      setState(() {
        _recentlyAddedPatient = newPatient;
        _showSuccessOverlay = true;
      });
    }
  }

  Widget _buildSuccessOverlay() {
    final p = _recentlyAddedPatient;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            color: Color(0xFF16A34A),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x3316A34A), blurRadius: 20, spreadRadius: 10)],
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 60),
        ),
        const SizedBox(height: 32),
        const Text('Patient Added\nSuccessfully!', textAlign: TextAlign.center, style: TextStyle(color: teal, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text('This number has been saved\nin your patient list.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        const SizedBox(height: 40),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text(p?.name.isNotEmpty == true ? p!.name[0].toUpperCase() : 'P', style: const TextStyle(color: Color(0xFF16A34A), fontSize: 20, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p?.name ?? 'Unknown', style: const TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(p?.phoneNumber ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  if (p != null) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: p)));
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: teal, borderRadius: BorderRadius.circular(12)),
                  child: const Center(child: Text('Open Patient Profile', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() { _showSuccessOverlay = false; _patient = p; }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('Done', style: TextStyle(color: Colors.grey[500], fontSize: 14, fontWeight: FontWeight.w600))),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
