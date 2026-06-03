import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/enrollment_saving_page_controller.dart';

class EnrollmentSavingPage extends StatelessWidget {
  const EnrollmentSavingPage({
    super.key,
    required this.saveFuture,
    this.timeout = const Duration(minutes: 3),
    this.onLocalSaved,
  });

  final Future<bool> saveFuture;
  final Duration timeout;
  final VoidCallback? onLocalSaved;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<EnrollmentSavingPageController>(
      init: EnrollmentSavingPageController(
        saveFuture: saveFuture,
        timeout: timeout,
        onLocalSaved: onLocalSaved,
      ),
      global: false,
      builder: (logic) {
        final size = MediaQuery.sizeOf(context);
        final w = size.width;
        final h = size.height;

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/Main BG.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: Center(
              child: Container(
                width: w * 0.56,
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.04,
                  vertical: h * 0.05,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B2742).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(w * 0.03),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: logic.pulseScale,
                      child: Icon(
                        Icons.fingerprint_rounded,
                        size: w * 0.09,
                        color: const Color(0xFF44D980),
                      ),
                    ),
                    SizedBox(height: h * 0.02),
                    Text(
                      'SAVING ENROLLMENT',
                      style: TextStyle(
                        fontFamily: 'CEORUSE',
                        fontSize: w * 0.028,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: h * 0.018),
                    Text(
                      'Saving both fingerprints to this device…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: w * 0.013,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: h * 0.028),
                    const CircularProgressIndicator(color: Color(0xFF44D980)),
                    SizedBox(height: h * 0.022),
                    Text(
                      'Returning to Home when local save completes.\n'
                      'In Online mode, fingerprints upload to HRIS in the background.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: w * 0.0105,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
