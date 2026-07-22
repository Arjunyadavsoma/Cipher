import 'package:cipher_ai/features/home/controller/home_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeControllerProvider = ChangeNotifierProvider<HomeController>((ref) {
  return HomeController();
});
