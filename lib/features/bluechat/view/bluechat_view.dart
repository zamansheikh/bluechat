import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';

import '../controllers/bluechat_controller.dart';

class BluechatView extends GetView<BluechatController> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  BluechatView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(
          () => Text(
            controller.isConnected.value
                ? 'Chat with ${controller.connectedDevice.value?.platformName.isNotEmpty ?? false ? controller.connectedDevice.value!.platformName : "Peer"}'
                : 'BLE Chat - Find Devices',
          ),
        ),
        actions: [
          // Show disconnect button only when connected
          Obx(() {
            if (controller.isConnected.value) {
              return IconButton(
                icon: Icon(Icons.close),
                onPressed: () => controller.disconnect(),
                tooltip: 'Disconnect',
              );
            } else {
              // Show scan button when not connected
              return IconButton(
                icon: Icon(
                  controller.isScanning
                      ? Icons.stop_circle_outlined
                      : Icons.search,
                ),
                onPressed: () {
                  if (controller.isScanning) {
                    controller.stopScan();
                  } else {
                    controller.startScan();
                  }
                },
                tooltip:
                    controller.isScanning ? 'Stop Scan' : 'Scan for Devices',
              );
            }
          }),
        ],
      ),
      body: Obx(() {
        // Decide which view section to show based on connection status
        if (controller.isConnected.value) {
          _scrollToBottom(); // Scroll when messages update
          return _buildChatSection();
        } else {
          return _buildDiscoverySection();
        }
      }),
    );
  }

  // --- Discovery Section Widget ---
  Widget _buildDiscoverySection() {
    return Column(
      children: [
        // Show error message if any
        if (controller.errorMessage.value.isNotEmpty &&
            controller.currentState.value == AppState.error)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Error: ${controller.errorMessage.value}',
              style: TextStyle(color: Colors.red),
            ),
          ),

        // Show Scanning Indicator
        if (controller.currentState.value == AppState.scanning)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text("Scanning for devices..."),
              ],
            ),
          ),

        // Show Connecting Indicator
        if (controller.currentState.value == AppState.connecting)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text("Connecting..."),
              ],
            ),
          ),

        // Show "No Devices Found" message
        if (!controller.isScanning &&
            controller.scanResults.isEmpty &&
            controller.currentState.value != AppState.connecting &&
            controller.currentState.value != AppState.error)
          Expanded(
            child: Center(
              child: Text(
                "No chat devices found.\nEnsure the other device is running the app.",
                textAlign: TextAlign.center,
              ),
            ),
          ),

        // Show Device List
        Expanded(
          child: ListView.builder(
            itemCount: controller.scanResults.length,
            itemBuilder: (context, index) {
              ScanResult result = controller.scanResults[index];
              String deviceName =
                  result.device.platformName.isNotEmpty
                      ? result.device.platformName
                      : "Unknown Device";
              return ListTile(
                title: Text(deviceName),
                subtitle: Text(result.device.remoteId.toString()),
                trailing: ElevatedButton(
                  onPressed:
                      controller.currentState.value == AppState.connecting
                          ? null
                          : () => controller.connectToDevice(result.device),
                  child: Text('Connect'),
                ),
                onTap: null, // Only connect via button
              );
            },
          ),
        ),
      ],
    );
  }

  // --- Chat Section Widget ---
  Widget _buildChatSection() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(10.0),
            itemCount: controller.chatMessages.length,
            itemBuilder: (context, index) {
              final message = controller.chatMessages[index];
              final isMe =
                  message.startsWith("Me:") || message.startsWith("---");
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                  padding: EdgeInsets.symmetric(
                    vertical: 10.0,
                    horizontal: 14.0,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isMe
                            ? Theme.of(Get.context!).primaryColorLight
                            : Colors.grey[300], // Use Get.context!
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  child: Text(message),
                ),
              );
            },
          ),
        ),
        // Input Area
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Enter message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 15.0,
                      vertical: 10.0,
                    ),
                  ),
                  onSubmitted:
                      (value) => _sendMessage(), // Send on keyboard submit
                ),
              ),
              SizedBox(width: 8.0),
              IconButton(
                icon: Icon(Icons.send),
                onPressed: _sendMessage,
                color: Theme.of(Get.context!).primaryColor, // Use Get.context!
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _sendMessage() {
    if (_messageController.text.isNotEmpty) {
      controller.sendMessage(_messageController.text);
      _messageController.clear(); // Clear input field
    }
  }

  // Function to scroll to the bottom of the chat list
  void _scrollToBottom() {
    // Use addPostFrameCallback to ensure layout is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
