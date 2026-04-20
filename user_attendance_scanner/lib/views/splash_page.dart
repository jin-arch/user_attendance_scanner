// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../routes/app_routes.dart';
import '../services/local_db.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _animateProgress();

    try {
      await LocalDb.db;
    } catch (_) {
      // Best-effort; view will show errors later if needed.
    }

    while (_progress < 50) {
      await Future.delayed(const Duration(milliseconds: 20));
    }

    if (!mounted) return;

    setState(() => _progress = 100);
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;
    Get.offAllNamed(AppRoutes.home);
  }

  void _animateProgress() {
    Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_progress < 45) {
          _progress += 1.0;
        } else if (_progress < 80) {
          _progress += 0.3;
        } else if (_progress < 95) {
          _progress += 0.1;
        } else if (_progress >= 100) {
          timer.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.fingerprint,
                size: 80,
                color: Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(height: 40),
            const Text(
              'HIRS',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Text(
              'Human Resources Information System',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 60),
            Container(
              width: 200,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Stack(
                children: [
                  Container(
                    width: 200 * (_progress / 100),
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '${_progress.toInt()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
