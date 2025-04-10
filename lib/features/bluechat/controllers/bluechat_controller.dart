// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config/app_constants.dart';

enum AppState { idle, scanning, advertising, connected, connecting, error }

class BluechatController extends GetxController {
  static final String SERVICE_UUID = AppConstants.SERVICE_UUID.toString();
  static final String CHARACTERISTIC_UUID_MSG =
      AppConstants.CHARACTERISTIC_UUID_MSG.toString();

  // Reactive State Variables
  final Rx<AppState> currentState = AppState.idle.obs;
  final RxList<ScanResult> scanResults = <ScanResult>[].obs;
  final Rxn<BluetoothDevice> connectedDevice = Rxn<BluetoothDevice>();
  final RxBool isConnected = false.obs;
  final RxList<String> chatMessages = <String>[].obs;
  final RxString errorMessage = "".obs;

  // Internal Variables
  BluetoothCharacteristic? _messageCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _messageSubscription;

  bool get isScanning => currentState.value == AppState.scanning;

  @override
  void onInit() {
    super.onInit();
    _init();
    ever(
      connectedDevice,
      (device) =>
          isConnected.value =
              (device != null && currentState.value == AppState.connected),
    );
    ever(
      currentState,
      (state) =>
          isConnected.value =
              (connectedDevice.value != null && state == AppState.connected),
    );
  }

  Future<void> _init() async {
    if (!await _checkPermissions()) {
      _setError(
        "Permissions not granted. Please grant permissions in settings.",
      );
      return;
    }

    // Updated adapter state listening
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (state == BluetoothAdapterState.on) {
        debugPrint("Bluetooth ON");
        errorMessage.value = "";
        if (currentState.value == AppState.idle ||
            currentState.value == AppState.error) {
          startScan();
        }
      } else {
        debugPrint("Bluetooth OFF");
        _setError("Bluetooth is turned off.");
        stopScan();
        disconnect();
      }
    });
  }

  Future<bool> _checkPermissions() async {
    bool permissionsGranted = true;
    List<Permission> permissionsToRequest = [];

    if (Platform.isAndroid) {
      debugPrint("Checking Android permissions...");
      if (!await Permission.bluetoothScan.isGranted) {
        permissionsToRequest.add(Permission.bluetoothScan);
      }
      if (!await Permission.bluetoothConnect.isGranted) {
        permissionsToRequest.add(Permission.bluetoothConnect);
      }
      if (!await Permission.locationWhenInUse.isGranted) {
        permissionsToRequest.add(Permission.locationWhenInUse);
      }
    } else if (Platform.isIOS) {
      if (!await Permission.bluetooth.isGranted) {
        permissionsToRequest.add(Permission.bluetooth);
      }
      if (!await Permission.locationWhenInUse.isGranted) {
        permissionsToRequest.add(Permission.locationWhenInUse);
      }
    }

    if (permissionsToRequest.isNotEmpty) {
      Map<Permission, PermissionStatus> statuses =
          await permissionsToRequest.request();
      permissionsGranted = statuses.values.every((status) => status.isGranted);
    }

    if (!permissionsGranted) {
      debugPrint("Required permissions were not granted.");
    }
    return permissionsGranted;
  }

  void _setState(AppState newState) => currentState.value = newState;

  void _setError(String message) {
    errorMessage.value = message;
    _setState(AppState.error);
    debugPrint("BLE Error: $message");
  }

  Future<void> startScan() async {
    if (currentState.value == AppState.scanning ||
        currentState.value == AppState.connected ||
        currentState.value == AppState.connecting) {
      debugPrint("Cannot scan: Already scanning, connected, or connecting.");
      return;
    }

    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _setError("Bluetooth is off. Cannot scan.");
      return;
    }

    if (!await _checkPermissions()) {
      _setError("Cannot scan without required permissions.");
      return;
    }

    debugPrint("Starting Scan for service $SERVICE_UUID...");
    _setState(AppState.scanning);
    scanResults.clear();
    errorMessage.value = "";

    try {
      await _scanSubscription?.cancel();
      await FlutterBluePlus.stopScan(); // Ensure clean start
      await FlutterBluePlus.startScan(
        withServices: [Guid.fromString(SERVICE_UUID)],
        timeout: const Duration(seconds: 15),
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          final filteredResults =
              results
                  .where(
                    (r) => r.advertisementData.serviceUuids.contains(
                      Guid.fromString(SERVICE_UUID),
                    ),
                  )
                  .toList();
          scanResults.assignAll(filteredResults);
        },
        onError: (e) {
          _setError("Scan Error: $e");
          stopScan();
        },
      );

      Future.delayed(const Duration(seconds: 15), () {
        if (currentState.value == AppState.scanning) {
          stopScan();
        }
      });
    } catch (e) {
      _setError("Error starting scan: $e");
      stopScan();
    }
  }

  void stopScan() async {
    if (currentState.value != AppState.scanning) return;
    debugPrint("Stopping scan");
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();
    _scanSubscription = null;
    if (currentState.value == AppState.scanning) {
      _setState(AppState.idle);
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (connectedDevice.value != null ||
        currentState.value == AppState.connecting) {
      debugPrint("Already connected or connecting.");
      return;
    }

    stopScan();
    debugPrint("Connecting to ${device.remoteId}...");
    _setState(AppState.connecting);
    errorMessage.value = "";

    try {
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen(
        (BluetoothConnectionState state) {
          debugPrint("Device ${device.remoteId} state changed: $state");
          if (state == BluetoothConnectionState.disconnected) {
            _handleDisconnect(expected: false);
          } else if (state == BluetoothConnectionState.connected) {
            if (currentState.value != AppState.connected) {
              _finalizeConnection(device);
            }
          }
        },
        onError: (e) {
          debugPrint("Connection state listener error: $e");
          _handleDisconnect(expected: false);
        },
      );

      await device.connect(timeout: const Duration(seconds: 15));
      if (currentState.value != AppState.connected) {
        _finalizeConnection(device);
      }
    } catch (e) {
      debugPrint("Connection Error: $e");
      _setError("Failed to connect: ${e.toString()}");
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;
      connectedDevice.value = null;
      _setState(AppState.idle);
    }
  }

  Future<void> _finalizeConnection(BluetoothDevice device) async {
    debugPrint("Connected to ${device.platformName}");
    connectedDevice.value = device;
    chatMessages.clear();
    chatMessages.add(
      "Connected to ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}",
    );
    _setState(AppState.connected);
    await _discoverServicesAndSubscribe();
  }

  Future<void> _discoverServicesAndSubscribe() async {
    if (connectedDevice.value == null) return;

    debugPrint("Discovering services...");
    try {
      List<BluetoothService> services =
          await connectedDevice.value!.discoverServices();
      BluetoothService? targetService = services.firstWhereOrNull(
        (s) => s.serviceUuid == Guid.fromString(SERVICE_UUID),
      );

      if (targetService == null) {
        _setError("Chat Service not found on connected device.");
        disconnect();
        return;
      }

      debugPrint("Found Chat Service: ${targetService.serviceUuid}");
      _messageCharacteristic = targetService.characteristics.firstWhereOrNull(
        (c) => c.characteristicUuid == Guid.fromString(CHARACTERISTIC_UUID_MSG),
      );

      if (_messageCharacteristic == null) {
        _setError("Message Characteristic not found.");
        disconnect();
        return;
      }
      debugPrint(
        "Found Message Characteristic: ${_messageCharacteristic!.characteristicUuid}",
      );

      if (_messageCharacteristic!.isNotifying) {
        await _subscribeToMessages();
      } else {
        debugPrint(
          "Warning: Message characteristic does not support notifications.",
        );
      }
    } catch (e) {
      _setError("Service Discovery Error: $e");
      disconnect();
    }
  }

  Future<void> _subscribeToMessages() async {
    if (_messageCharacteristic == null ||
        !_messageCharacteristic!.isNotifying) {
      return;
    }

    try {
      await _messageCharacteristic!.setNotifyValue(true);
      debugPrint("Subscribed to message notifications.");

      await _messageSubscription?.cancel();
      _messageSubscription = _messageCharacteristic!.lastValueStream.listen(
        (value) {
          if (value.isNotEmpty) {
            String receivedMessage = utf8.decode(value);
            debugPrint("Received Msg: $receivedMessage");
            chatMessages.add("Peer: $receivedMessage");
          }
        },
        onError: (e) {
          debugPrint("Message Subscription Error: $e");
          _setError("Lost connection or message error: $e");
          _handleDisconnect(expected: false);
        },
      );
    } catch (e) {
      debugPrint("Error subscribing to messages: $e");
      _setError("Failed to subscribe to messages: $e");
      disconnect();
    }
  }

  Future<void> sendMessage(String message) async {
    if (connectedDevice.value == null ||
        _messageCharacteristic == null ||
        message.isEmpty) {
      debugPrint(
        "Cannot send message: Not connected or characteristic not found.",
      );
      return;
    }

    bool canWrite = _messageCharacteristic!.properties.write;
    bool canWriteWithoutResponse =
        _messageCharacteristic!.properties.writeWithoutResponse;

    if (!canWrite && !canWriteWithoutResponse) {
      debugPrint("Error: Message characteristic does not support writing.");
      _setError("Cannot send message (characteristic not writable).");
      return;
    }

    try {
      List<int> bytesToSend = utf8.encode(message);
      await _messageCharacteristic!.write(
        bytesToSend,
        withoutResponse: canWriteWithoutResponse,
      );

      debugPrint("Sent Msg: $message");
      chatMessages.add("Me: $message");
    } catch (e) {
      debugPrint("Send Message Error: $e");
      _setError("Failed to send message: $e");
    }
  }

  void _handleDisconnect({bool expected = true}) {
    if (!expected) {
      _setError("Device disconnected unexpectedly.");
    } else {
      debugPrint("Device disconnected.");
      errorMessage.value = "";
    }
    connectedDevice.value = null;
    _messageCharacteristic = null;
    _connectionStateSubscription?.cancel();
    _messageSubscription?.cancel();
    _connectionStateSubscription = null;
    _messageSubscription = null;
    chatMessages.add("--- Disconnected ---");
    _setState(AppState.idle);
    startScan();
  }

  Future<void> disconnect() async {
    if (connectedDevice.value != null) {
      debugPrint("Disconnecting from ${connectedDevice.value!.remoteId}");
      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;
      await _messageSubscription?.cancel();
      _messageSubscription = null;
      try {
        await connectedDevice.value!.disconnect();
        if (connectedDevice.value != null) {
          _handleDisconnect(expected: true);
        }
      } catch (e) {
        debugPrint("Error during disconnect: $e");
        _handleDisconnect(expected: true);
      }
    } else {
      if (currentState.value != AppState.idle &&
          currentState.value != AppState.scanning) {
        _handleDisconnect(expected: true);
      }
    }
  }

  @override
  void onClose() {
    debugPrint("Disposing BluechatController");
    stopScan();
    _connectionStateSubscription?.cancel();
    _messageSubscription?.cancel();
    if (connectedDevice.value != null) {
      connectedDevice.value!.disconnect().catchError((e) {
        debugPrint("Error disconnecting on close: $e");
      });
    }
    connectedDevice.value = null;
    super.onClose();
  }
}
