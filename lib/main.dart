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
      const Duration(milliseconds: 700),
      (_) => readStatus(),
    );

    _initialLoad();
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    super.dispose();
  }

  Future<void> sendCommand(String command, String value) async {
    try {
      final response = await http.put(
        Uri.parse('$firebaseUrl/commands.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({command: value}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Command failed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Command error: $e');
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
      // Read the current Firebase photo timestamp first.
      int oldTimestamp = 0;
      try {
        final oldResponse = await http
            .get(Uri.parse('$firebaseUrl/photo.json'))
            .timeout(const Duration(seconds: 4));
        if (oldResponse.statusCode == 200 && oldResponse.body != 'null') {
          final oldData = jsonDecode(oldResponse.body);
          if (oldData is Map) {
            oldTimestamp = int.tryParse(
                    oldData['timestamp']?.toString() ?? '') ??
                0;
          }
        }
      } catch (e) {
        debugPrint('PHOTO: could not read old photo: $e');
      }

      // IMPORTANT: request exactly ONE fresh photo through Firebase.
      // ESP32 receives capture=NOW, captures, uploads photo.json,
      // then clears /commands.json so it cannot repeat.
      debugPrint('PHOTO: sending capture NOW to ESP32 through Firebase');
      await sendCommand('capture', 'NOW');

      // Wait for ESP32 to upload a NEW timestamp.
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 300));

        try {
          final checkResponse = await http
              .get(Uri.parse('$firebaseUrl/photo.json'))
              .timeout(const Duration(seconds: 3));

          if (checkResponse.statusCode != 200 ||
              checkResponse.body == 'null') {
            continue;
          }

          final data = jsonDecode(checkResponse.body);
          if (data is! Map) continue;

          final newTimestamp =
              int.tryParse(data['timestamp']?.toString() ?? '') ?? 0;

          if (newTimestamp != 0 && newTimestamp != oldTimestamp) {
            final encoded = data['data']?.toString() ?? '';
            if (encoded.isNotEmpty && mounted) {
              setState(() {
                photoData = encoded;
              });
              debugPrint(
                  'PHOTO: NEW photo loaded, timestamp=$newTimestamp');
            }
            return;
          }
        } catch (e) {
          debugPrint('PHOTO: waiting for new photo: $e');
        }
      }

      debugPrint('PHOTO: timeout waiting for ESP32 new photo');
    } catch (e) {
      debugPrint('PHOTO: Firebase capture error: $e');
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
      await readStatus();
      await captureAndLoadPhoto();
    } finally {
      refreshBusy = false;
    }
  }

  Widget statusCard() {
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.circle,
          color: esp32Online ? Colors.green : Colors.red,
        ),
        title: const Text(
          'ESP32 STATUS',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: Text(
          esp32Online ? 'ONLINE' : 'OFFLINE',
          style: TextStyle(
            color: esp32Online ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget servoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text(
              'SERVO CONTROL',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => servoOn = true);
                    sendCommand('servo', 'ON');
                  },
                  icon: const Icon(Icons.power),
                  label: const Text('ON'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => servoOn = false);
                    sendCommand('servo', 'OFF');
                  },
                  icon: const Icon(Icons.power_off),
                  label: const Text('OFF'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(servoOn ? 'Servo: ON' : 'Servo: OFF'),
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
              Icons.person,
              color: personDetected ? Colors.green : Colors.grey,
            ),
            title: const Text('PERSON'),
            trailing:
                Text(personDetected ? 'DETECTED' : 'NOT DETECTED'),
          ),
          ListTile(
            leading: Icon(
              Icons.tv,
              color: screenOn ? Colors.green : Colors.grey,
            ),
            title: const Text('SCREEN'),
            trailing: Text(screenOn ? 'ON' : 'OFF'),
          ),
          ListTile(
            leading: const Icon(Icons.flash_on),
            title: const Text('FLASH'),
            trailing: Text(flashStatus),
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (photoData != null && photoData!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(photoData!),
                  width: double.infinity,
                  height: 240,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 240,
                    child: Center(
                      child: Text('Image cannot be decoded'),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(
                height: 240,
                child: Center(child: Text('No photo yet')),
              ),
            const SizedBox(height: 10),
            Text(
              photoBusy
                  ? 'TAKING ONE FRESH PHOTO...'
                  : 'Photo updates only on APP OPEN or REFRESH',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
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
            statusCard(),
            const SizedBox(height: 12),
            servoCard(),
            const SizedBox(height: 12),
            sensorCard(),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Wi-Fi Signal'),
                trailing: Text('$rssi dBm'),
              ),
            ),
            const SizedBox(height: 12),
            cameraCard(),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: refreshAll,
              icon: const Icon(Icons.refresh),
              label: const Text('REFRESH — TAKE NEW PHOTO'),
            ),
          ],
        ),
      ),
    );
  }
}
