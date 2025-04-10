// ignore_for_file: non_constant_identifier_names

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AppConstants {
  static const String appName = "BLE Chat App GetX";
// IMPORTANT: Use the SAME UUIDs on both devices running the app
  static final Guid SERVICE_UUID = Guid("5c23b4a9-c243-454e-b58a-343ac7c34d75"); // Replace! e.g., 5c23b4a9-c243-454e-b58a-343ac7c34d75
  static final Guid CHARACTERISTIC_UUID_MSG = Guid("8f7a3b10-4b9a-4512-9c3a-5f4b1d0f4e2c"); // Replace! e.g., 8f7a3b10-4b9a-4512-9c3a-5f4b1d0f4e2c
}
