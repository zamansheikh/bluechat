import 'package:get/get.dart';
import '../controllers/bluechat_controller.dart';

class BluechatBinding extends Bindings {
  @override
  void dependencies() {
    // Use lazyPut to create the controller only when the view is accessed
    Get.lazyPut<BluechatController>(() => BluechatController());
  }
}
