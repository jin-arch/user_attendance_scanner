import 'package:get/get.dart';

import '../controllers/logs_controller.dart';

class TimeLogsBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    final map = args is Map ? args : const <Object?, Object?>{};
    final siteId = map['siteId']?.toString();

    if (Get.isRegistered<LogsController>()) {
      Get.delete<LogsController>(force: true);
    }

    Get.lazyPut<LogsController>(
      () => LogsController(siteId: siteId),
      fenix: true,
    );
  }
}
