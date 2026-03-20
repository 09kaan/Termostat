import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;

  AuthProvider() {
    // Listen to auth state changes (auto-detects persistent session)
    _auth.authStateChanges().listen((user) {
      notifyListeners();
    });
  }

  /// Sign in with email and password
  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null; // Success
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return 'Kullanıcı bulunamadı.';
        case 'wrong-password':
          return 'Yanlış şifre.';
        case 'invalid-email':
          return 'Geçersiz e-posta adresi.';
        case 'user-disabled':
          return 'Bu hesap devre dışı bırakılmış.';
        case 'invalid-credential':
          return 'E-posta veya şifre hatalı.';
        default:
          return 'Giriş hatası: ${e.message}';
      }
    } catch (e) {
      return 'Beklenmeyen hata: $e';
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }
}
