import 'package:get/get.dart';

import '../controllers/enrollment_controller.dart';

class EnrollmentBinding extends Bindings {
  @override
  void dependencies() {
    if (Get.isRegistered<EnrollmentController>()) {
      Get.delete<EnrollmentController>(force: true);
    }

    final args = Get.arguments;
    final map = args is Map ? args : const <Object?, Object?>{};

    Get.put(
      EnrollmentController(
        siteId: map['siteId']?.toString(),
        isEditMode: map['isEditMode'] == true,
        employeeId: map['employeeId']?.toString(),
        employeeName: map['employeeName']?.toString(),
      ),
    );
  }
}
