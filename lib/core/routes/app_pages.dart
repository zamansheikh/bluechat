import 'package:bluechat/features/bluechat/bindings/bluechat_binding.dart';
import 'package:bluechat/features/bluechat/view/bluechat_view.dart';
import 'package:get/get.dart';

import '../../features/home/bindings/home_binding.dart';
import '../../features/home/views/home_view.dart';

part 'app_routes.dart';

class AppPages {
  static const initial = Routes.bluechat;

  static final routes = [
    GetPage(
      name: Routes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: Routes.bluechat,
      page: () => BluechatView(),
      binding: BluechatBinding(),
    ),
  ];
}
