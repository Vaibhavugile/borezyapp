import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import 'admin_screen.dart';
import 'branch_dashboard.dart';
import 'subuser_dashboard.dart';
import '../providers/user_provider.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _loading = false;
  String? _error;

  String formatDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      final month = parts[1].padLeft(2, '0');
      final day = parts[2].padLeft(2, '0');
      return '${parts[0]}-$month-$day';
    }
    return dateStr;
  }

  Future<void> _handleLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final connectivity = await Connectivity().checkConnectivity();
    final prefs = await SharedPreferences.getInstance();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final hiveBox = Hive.box('offline_cache');

    if (connectivity == ConnectivityResult.none) {
      final savedEmail = prefs.getString('email');
      final savedPassword = prefs.getString('password');
      final savedUserData = hiveBox.get(email);

      if (savedEmail == email && savedPassword == password && savedUserData != null) {
        Provider.of<UserProvider>(context, listen: false).setUserData(savedUserData);
        final role = savedUserData['role'] ?? 'branch';
        if (role == 'admin') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminScreen()));
        } else if (role == 'subuser') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BranchDashboardScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BranchDashboardScreen()));
        }
      } else {
        setState(() => _error = 'Offline: Invalid credentials or no cached user data.');
      }
      setState(() => _loading = false);
      return;
    }

    try {
      final auth = FirebaseAuth.instance;
      final result = await auth.signInWithEmailAndPassword(email: email, password: password);
      final user = result.user;
      if (user == null) throw FirebaseAuthException(message: 'User not found', code: '');

      final token = await user.getIdToken();
      if (_rememberMe) {
        await prefs.setString('authToken', token ?? '');
        await prefs.setString('email', email);
        await prefs.setString('password', password);
      }

      final firestore = FirebaseFirestore.instance;

      final superAdmins = await firestore.collection('superadmins').where('email', isEqualTo: email).get();
      if (superAdmins.docs.isNotEmpty) {
        final data = superAdmins.docs.first.data();
        data['role'] = 'admin';
        Provider.of<UserProvider>(context, listen: false).setUserData(data);
        hiveBox.put(email, data);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminScreen()));
        return;
      }

      final branches = await firestore.collection('branches').where('emailId', isEqualTo: email).get();
      if (branches.docs.isNotEmpty) {
        final data = branches.docs.first.data();
        final now = DateTime.now();
        if (now.isBefore(DateTime.parse(formatDate(data['activeDate'])))) {
          setState(() => _error = 'Branch plan not active yet.');
          return;
        }
        if (now.isAfter(DateTime.parse(formatDate(data['deactiveDate'])))) {
          setState(() => _error = 'Branch plan expired.');
          return;
        }

        data['role'] = 'branch';
        Provider.of<UserProvider>(context, listen: false).setUserData(data);
        hiveBox.put(email, data);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BranchDashboardScreen()));
        return;
      }

      final subusers = await firestore.collection('subusers').where('email', isEqualTo: email).get();
      if (subusers.docs.isNotEmpty) {
        final data = subusers.docs.first.data();
        final now = DateTime.now();
        if (data['isActive'] != true) {
          setState(() => _error = 'Subuser inactive.');
          return;
        }
        if (now.isBefore(DateTime.parse(formatDate(data['activeDate'])))) {
          setState(() => _error = 'Subuser plan not active.');
          return;
        }
        if (now.isAfter(DateTime.parse(formatDate(data['deactiveDate'])))) {
          setState(() => _error = 'Subuser plan expired.');
          return;
        }

        final branch = await firestore.collection('branches').where('branchCode', isEqualTo: data['branchCode']).get();
        if (branch.docs.isEmpty) {
          setState(() => _error = 'Associated branch not found.');
          return;
        }

        final branchData = branch.docs.first.data();
        if (now.isBefore(DateTime.parse(formatDate(branchData['activeDate']))) ||
            now.isAfter(DateTime.parse(formatDate(branchData['deactiveDate'])))) {
          setState(() => _error = 'Branch plan invalid.');
          return;
        }

        data['role'] = 'subuser';
        Provider.of<UserProvider>(context, listen: false).setUserData(data);
        hiveBox.put(email, data);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BranchDashboardScreen()));
        return;
      }

      setState(() => _error = 'No user found with the provided credentials.');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _emailController.text = prefs.getString('email') ?? '';
    _passwordController.text = prefs.getString('password') ?? '';
    setState(() {
      _rememberMe = prefs.containsKey('authToken');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4), // light green background
      body: Center(
        child: SingleChildScrollView(
          child: Animate(
            effects: [FadeEffect(duration: 600.ms), MoveEffect(begin: Offset(0, 30))],
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 12,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Welcome to Borezy",
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                      ),
                      SizedBox(height: 20),
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email_outlined, color: Colors.green),
                          filled: true,
                          fillColor: Color(0xFFF0FDF4),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: Icon(Icons.lock_outline, color: Colors.green),
                          filled: true,
                          fillColor: Color(0xFFF0FDF4),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (val) => setState(() => _rememberMe = val ?? false),
                            activeColor: Colors.green,
                          ),
                          Text("Remember Me", style: TextStyle(color: Color(0xFF065F46))),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error!,
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                        ),
                      SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: _loading
                              ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                              : Icon(Icons.login),
                          label: Text("Login"),
                          onPressed: _loading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF10B981), // emerald green
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
