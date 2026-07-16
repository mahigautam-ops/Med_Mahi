import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/patient.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _cachedDoctorId;

  Future<String> _getDoctorId() async {
    if (_cachedDoctorId != null) return _cachedDoctorId!;
    final user = _auth.currentUser;
    if (user != null && user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
      _cachedDoctorId = user.phoneNumber!;
      return _cachedDoctorId!;
    }
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('loggedInPhone') ?? '';
    if (phone.isEmpty) {
      throw Exception('Unauthenticated: Doctor must be logged in.');
    }
    _cachedDoctorId = phone;
    return phone;
  }

  void clearCache() {
    _cachedDoctorId = null;
  }

  Future<CollectionReference> get _patientsRef async {
    final id = await _getDoctorId();
    return _db.collection('users').doc(id).collection('patients');
  }

  Future<CollectionReference> _timelineRef(String patientPhone) async {
    final ref = await _patientsRef;
    return ref.doc(patientPhone).collection('timeline');
  }

  // Auth Operations (Setup)
  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signUp(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;

  // CRUD Operations

  /// Add a new patient
  /// Uses phone number as document ID to allow quick retrieval and ensure uniqueness
  Future<void> addPatient(Patient patient) async {
    try {
      final docId = patient.phoneNumber;
      final ref = await _patientsRef;
      Map<String, dynamic> data = patient.toJson();
      await ref.doc(docId).set(data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Patient?> getPatientByPhone(String phoneNumber) async {
    try {
      final ref = await _patientsRef;
      final docSnapshot = await ref.doc(phoneNumber).get();
      
      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        return Patient.fromJson(data, docSnapshot.id);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> updatePatient(Patient patient) async {
    try {
      final docId = patient.phoneNumber;
      final ref = await _patientsRef;
      Map<String, dynamic> data = patient.toJson();
      await ref.doc(docId).update(data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deletePatient(String phoneNumber) async {
    try {
      final ref = await _patientsRef;
      await ref.doc(phoneNumber).delete();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Patient>> getDoctorsPatients() async {
    try {
      final ref = await _patientsRef;
      final querySnapshot = await ref.get();

      return querySnapshot.docs
          .map((doc) => Patient.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addTimelineEvent(String phoneNumber, Map<String, dynamic> event) async {
    try {
      final ref = await _timelineRef(phoneNumber);
      await ref.add({
        ...event,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Stream<QuerySnapshot> getTimelineStream(String phoneNumber) {
    return _db.collection('users').doc(_cachedDoctorId ?? '').collection('patients').doc(phoneNumber).collection('timeline')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> deleteTimelineEvent(String phoneNumber, String eventId) async {
    try {
      final ref = await _timelineRef(phoneNumber);
      await ref.doc(eventId).delete();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearTimeline(String phoneNumber) async {
    try {
      final ref = await _timelineRef(phoneNumber);
      final snapshot = await ref.get();
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }
}
