import 'dart:async';
import 'package:get/get.dart';
import '../routes/app_routes.dart';
import '../services/local_db.dart';

class SplashController extends GetxController {
  final RxDouble progress = 0.0.obs;
  Timer? _progressTimer;
  
  // Callbacks for UI updates
  Function()? onInitializationComplete;
  Function(String)? onError;
  
  @override
  void onInit() {
    super.onInit();
    initializeApp();
  }
  
  @override
  void onClose() {
    _progressTimer?.cancel();
    super.onClose();
  }
  
  Future<void> initializeApp() async {
    _animateProgress();

    try {
      // Initialize database
      await LocalDb.db;
      
      // Wait for minimum progress
      while (progress.value < 50) {
        await Future.delayed(const Duration(milliseconds: 20));
      }

      // Complete initialization
      progress.value = 100;
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Navigate to home page
      onInitializationComplete?.call();
      Get.offAllNamed(AppRoutes.home);
      
    } catch (e) {
      onError?.call('Database initialization failed: $e');
      // Still proceed to home page even if DB fails
      await Future.delayed(const Duration(seconds: 2));
      Get.offAllNamed(AppRoutes.home);
    }
  }
  
  void _animateProgress() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (progress.value < 45) {
        progress.value += 1.0;
      } else if (progress.value < 80) {
        progress.value += 0.3;
      } else if (progress.value < 95) {
        progress.value += 0.1;
      } else if (progress.value >= 100) {
        timer.cancel();
      }
    });
  }
  
  void skipAnimation() {
    _progressTimer?.cancel();
    progress.value = 100;
    initializeApp();
  }
}
