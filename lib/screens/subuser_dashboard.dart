import 'package:flutter/material.dart';

class SubuserDashboard extends StatelessWidget {
  const SubuserDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Subuser Dashboard"),
      ),
      body: const Center(
        child: Text(
          "Welcome, Subuser!",
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
