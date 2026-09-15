import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const IITACController());

class IITACController extends StatelessWidget {
  const IITACController({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IIT AC Controller',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String firebaseUrl =
      'https://iit-automation-default-rtdb.firebaseio.com';

  bool servoOn = false;
  bool personDetected = false;
  bool screenOn = false;
  bool esp32Online = false;
  String esp32Ip = '';
  String flashStatus = 'OFF';
  int rssi = 0;

  String? photoData;
  Timer? statusTimer;
  bool photoBusy = false;
  bool refreshBusy = false;

  @override
  void initState() {
    super.initState();

    // STATUS updates continuously.
    // PHOTO does NOT update continuously.
    statusTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => readLocalStatus(),
    );

    _initialLoad();
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    super.dispose();
  }

  Future<void> sendDirectCommand(String path) async {
    if (esp32Ip.isEmpty) {
      await readStatus();
    }
    if (esp32Ip.isEmpty) {
      debugPrint('DIRECT COMMAND: ESP32 IP unavailable');
      return;
    }
    try {
      final uri = Uri.parse(
        'http://$esp32Ip/$path?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 500));
      debugPrint('DIRECT COMMAND $path -> HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('DIRECT COMMAND $path error: $e');
    }
  }

  Future<void> readLocalStatus() async {
    if (esp32Ip.isEmpty) {
      await readStatus();
      return;
    }
    try {
      final response = await http
          .get(Uri.parse(
              'http://$esp32Ip/status?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(milliseconds: 350));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (data is! Map || !mounted) return;
      setState(() {
        esp32Online = true;
        personDetected = data['present'] == true;
        screenOn = data['screen_state']?.toString().toUpperCase() == 'ON';
        flashStatus = (data['flash'] == true ||
                data['flash']?.toString().toUpperCase() == 'ON')
            ? 'ON'
            : 'OFF';
        rssi = int.tryParse(data['rssi']?.toString() ?? '') ?? rssi;
      });
    } catch (e) {
      if (mounted) setState(() => esp32Online = false);
      debugPrint('Local status error: $e');
    }
  }

  Future<void> readStatus() async {
    try {
      final response =
          await http.get(Uri.parse('$firebaseUrl/status.json'));

      if (response.statusCode != 200 || response.body == 'null') {
        if (mounted) setState(() => esp32Online = false);
        return;
      }

      final data = jsonDecode(response.body);

      if (data is! Map || !mounted) return;

      setState(() {
        esp32Online = true;
        esp32Ip = data['ip']?.toString() ?? '';
        personDetected = data['present'] == true;
        screenOn =
            data['screen_state']?.toString().toUpperCase() == 'ON';
        flashStatus = data['flash']?.toString() ?? 'OFF';
        rssi = int.tryParse(data['rssi']?.toString() ?? '') ?? 0;
      });
    } catch (e) {
      if (mounted) setState(() => esp32Online = false);
      debugPrint('Status error: $e');
    }
  }

  Future<void> _initialLoad() async {
    await readStatus();
    await captureAndLoadPhoto();
  }

  Future<void> captureAndLoadPhoto() async {
    if (photoBusy) return;

    photoBusy = true;
    if (mounted) setState(() {});

    try {
      // Get the current ESP32 IP first. Status is still read from Firebase,
      // but the actual JPEG travels directly over the local Wi-Fi network.
      await readStatus();

      if (esp32Ip.isEmpty) {
        debugPrint('PHOTO: ESP32 IP is empty');
        return;
      }

      final uri = Uri.parse(
        'http://$esp32Ip/quick_capture?t=${DateTime.now().millisecondsSinceEpoch}',
      );

      debugPrint('PHOTO: DIRECT capture -> $uri');
      final response = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 900));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (mounted) {
          setState(() {
            photoData = base64Encode(response.bodyBytes);
          });
        }
        debugPrint(
          'PHOTO: DIRECT OK (${response.bodyBytes.length} bytes)',
        );
      } else {
        debugPrint(
          'PHOTO: DIRECT failed HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('PHOTO: DIRECT error: $e');
    } finally {
      photoBusy = false;
      if (mounted) setState(() {});
    }
  }

  // Refresh -> status + exactly ONE new photo.
  Future<void> refreshAll() async {
    if (refreshBusy) return;

    refreshBusy = true;
    try {
      await readLocalStatus();
      await captureAndLoadPhoto();
    } finally {
      refreshBusy = false;
    }
  }

  Widget statusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(
              Icons.circle,
              size: 18,
              color: esp32Online ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ESP32 STATUS',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'IP: ${esp32Ip.isEmpty ? '---' : esp32Ip}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            Text(
              esp32Online ? 'ONLINE' : 'OFFLINE',
              style: TextStyle(
                color: esp32Online ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget servoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Text(
              'SERVO CONTROL',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => servoOn = true);
                      sendDirectCommand('on');
                      Future.delayed(const Duration(milliseconds: 120), () {
                        if (mounted) setState(() => servoOn = false);
                      });
                    },
                    icon: const Icon(Icons.power, size: 20),
                    label: const Text('ON'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => servoOn = false);
                      sendDirectCommand('off');
                    },
                    icon: const Icon(Icons.power_off, size: 20),
                    label: const Text('OFF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(servoOn ? 'Servo: ON' : 'Servo: OFF'),
          ],
        ),
      ),
    );
  }

  Widget flashCard() {
    final isOn = flashStatus.toUpperCase() == 'ON';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Text(
              'FLASH CONTROL',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => flashStatus = 'ON');
                      sendDirectCommand('flash_on');
                    },
                    icon: const Icon(Icons.flash_on, size: 20),
                    label: const Text('ON'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => flashStatus = 'OFF');
                      sendDirectCommand('flash_off');
                    },
                    icon: const Icon(Icons.flash_off, size: 20),
                    label: const Text('OFF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Flash: ${isOn ? 'ON' : 'OFF'}'),
          ],
        ),
      ),
    );
  }

  Widget sensorCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.tv,
              color: screenOn ? Colors.green : Colors.grey,
            ),
            title: const Text(
              'SCREEN',
              style: TextStyle(fontSize: 18),
            ),
            trailing: Text(
              screenOn ? 'ON' : 'OFF',
              style: TextStyle(
                color: screenOn ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.person,
              color: personDetected ? Colors.green : Colors.grey,
            ),
            title: const Text(
              'PERSON',
              style: TextStyle(fontSize: 18),
            ),
            trailing: Text(
              personDetected ? 'DETECTED' : 'NOT DETECTED',
              style: TextStyle(
                color: personDetected ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget cameraCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              'ESP32-CAM',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: photoData != null && photoData!.isNotEmpty
                  ? Image.memory(
                      base64Decode(photoData!),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('Image cannot be decoded'),
                      ),
                    )
                  : const Center(child: Text('No photo yet')),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: photoBusy ? null : captureAndLoadPhoto,
                icon: const Icon(Icons.refresh),
                label: Text(photoBusy ? 'CAPTURING...' : 'REFRESH'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'IIT AC Controller',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // 1. IP + online status at the top
            statusCard(),
            const SizedBox(height: 12),

            // 2. Camera/photo frame directly below the IP
            cameraCard(),
            const SizedBox(height: 12),

            // 3. Servo and Flash controls side-by-side
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: servoCard()),
                const SizedBox(width: 10),
                Expanded(child: flashCard()),
              ],
            ),
            const SizedBox(height: 12),

            // 4. Screen and person status below the controls
            sensorCard(),
            const SizedBox(height: 12),

            // Wi-Fi signal kept below the requested status section
            Card(
              child: ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Wi-Fi Signal'),
                trailing: Text('$rssi dBm'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
