import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const IITACController());
}

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
  // ================= FIREBASE =================

  static const String firebaseUrl =
      'https://iit-automation-default-rtdb.firebaseio.com';

  Timer? timer;

  // ================= STATUS =================

  bool checking = true;
  bool esp32Online = false;
  bool personDetected = false;
  bool screenOn = false;
  bool autoMode = false;

  String flashStatus = 'OFF';
  String radarStatus = 'ACTIVE';
  String ipAddress = '--';

  int rssi = 0;
  double zoom = 1.0;

  String? photoData;

  String lastStatusTimestamp = '';
  DateTime? lastStatusChange;

  String message = '';

  // ================= INITIALIZATION =================

  @override
  void initState() {
    super.initState();

    readFirebase();

    timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => readFirebase(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // ================= SEND COMMAND TO ESP32 =================

  Future<void> sendCommand(String command, String value) async {
    try {
      final response = await http.put(
        Uri.parse('$firebaseUrl/commands.json'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          command: value,
        }),
      );

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        setState(() {
          message = '$command → $value';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$command → $value'),
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        setState(() {
          message =
              'Command failed: HTTP ${response.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = 'Command error';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot connect to Firebase'),
        ),
      );
    }
  }

  // ================= READ FIREBASE =================

  Future<void> readFirebase() async {
    try {
      // ---------- READ STATUS ----------

      final statusResponse = await http
          .get(
            Uri.parse('$firebaseUrl/status.json'),
          )
          .timeout(
            const Duration(seconds: 5),
          );

      if (statusResponse.statusCode == 200 &&
          statusResponse.body != 'null') {
        final decoded = jsonDecode(statusResponse.body);

        if (decoded is Map) {
          final data =
              Map<String, dynamic>.from(decoded);

          final newTimestamp =
              data['timestamp']?.toString() ?? '';

          // ESP32 uses millis() as timestamp.
          // Therefore compare successive Firebase updates.

          if (newTimestamp != lastStatusTimestamp) {
            lastStatusTimestamp = newTimestamp;
            lastStatusChange = DateTime.now();
          }

          // ==================================================
          // IMPORTANT:
          // ESP32 is considered ONLINE for 30 seconds after
          // the last status update.
          // ==================================================

          final changedRecently =
              lastStatusChange != null &&
              DateTime.now()
                      .difference(lastStatusChange!)
                      .inSeconds <=
                  30;

          if (mounted) {
            setState(() {
              checking = false;

              esp32Online = changedRecently;

              personDetected =
                  data['present'] == true;

              screenOn =
                  data['screen_state']
                          ?.toString()
                          .toUpperCase() ==
                      'ON';

              flashStatus =
                  data['flash']
                          ?.toString()
                          .toUpperCase() ??
                      'OFF';

              radarStatus =
                  data['radar']
                          ?.toString()
                          .toUpperCase() ??
                      'ACTIVE';

              ipAddress =
                  data['ip']?.toString() ?? '--';

              rssi =
                  int.tryParse(
                        data['rssi']?.toString() ?? '',
                      ) ??
                      0;

              zoom =
                  double.tryParse(
                        data['zoom']?.toString() ?? '',
                      ) ??
                      1.0;
            });
          }
        }
      } else if (mounted) {
        setState(() {
          checking = false;
          esp32Online = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          checking = false;
          esp32Online = false;
        });
      }
    }

    // ================= READ PHOTO =================

    try {
      final photoResponse = await http
          .get(
            Uri.parse('$firebaseUrl/photo.json'),
          )
          .timeout(
            const Duration(seconds: 5),
          );

      if (photoResponse.statusCode == 200 &&
          photoResponse.body != 'null') {
        final decoded =
            jsonDecode(photoResponse.body);

        if (decoded is Map &&
            decoded['data'] != null) {
          final newPhoto =
              decoded['data'].toString();

          if (mounted && newPhoto != photoData) {
            setState(() {
              photoData = newPhoto;
            });
          }
        }
      }
    } catch (e) {
      // Keep previous image if photo request fails.
    }
  }

  // ================= IMAGE DECODER =================

  Uint8List? getImageBytes() {
    if (photoData == null ||
        photoData!.isEmpty) {
      return null;
    }

    try {
      String value = photoData!;

      // Supports:
      // 1. Plain Base64
      // 2. data:image/...;base64,...

      if (value.contains(',')) {
        value =
            value.substring(
              value.indexOf(',') + 1,
            );
      }

      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  // ================= STATUS CARD =================

  Widget statusCard() {
    final color = checking
        ? Colors.orange
        : (esp32Online
            ? Colors.green
            : Colors.red);

    final text = checking
        ? 'CHECKING...'
        : (esp32Online
            ? 'ONLINE'
            : 'OFFLINE');

    return Card(
      child: ListTile(
        leading: Icon(
          Icons.circle,
          color: color,
          size: 18,
        ),
        title: const Text(
          'ESP32 STATUS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          ipAddress == '--'
              ? 'Firebase connected'
              : 'IP: $ipAddress',
        ),
        trailing: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ================= SERVO CARD =================

  Widget servoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text(
              'SERVO CONTROL',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () =>
                      sendCommand('servo', 'ON'),
                  icon: const Icon(Icons.power),
                  label: const Text('ON'),
                ),

                ElevatedButton.icon(
                  onPressed: () =>
                      sendCommand('servo', 'OFF'),
                  icon: const Icon(Icons.power_off),
                  label: const Text('OFF'),
                ),

                ElevatedButton.icon(
                  onPressed: () =>
                      sendCommand('servo', 'SWEEP'),
                  icon: const Icon(Icons.sync),
                  label: const Text('SWEEP'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================= AUTO MODE =================

  Widget autoCard() {
    return Card(
      child: SwitchListTile(
        title: const Text(
          'AUTO MODE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          autoMode
              ? 'Automatic control enabled'
              : 'Manual control',
        ),
        value: autoMode,
        onChanged: (value) {
          setState(() {
            autoMode = value;
          });

          sendCommand(
            'auto',
            value ? 'ON' : 'OFF',
          );
        },
      ),
    );
  }

  // ================= SENSOR CARD =================

  Widget sensorCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.person,
              color: personDetected
                  ? Colors.green
                  : Colors.grey,
            ),
            title: const Text('PERSON'),
            trailing: Text(
              personDetected
                  ? 'DETECTED'
                  : 'NOT DETECTED',
              style: TextStyle(
                color: personDetected
                    ? Colors.green
                    : null,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: Icon(
              Icons.tv,
              color: screenOn
                  ? Colors.green
                  : Colors.grey,
            ),
            title: const Text('SCREEN'),
            trailing: Text(
              screenOn ? 'ON' : 'OFF',
              style: TextStyle(
                color: screenOn
                    ? Colors.green
                    : null,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(
              Icons.radar,
            ),
            title: const Text('RADAR'),
            trailing: Text(radarStatus),
          ),

          ListTile(
            leading: const Icon(
              Icons.wifi,
            ),
            title: const Text('Wi-Fi Signal'),
            trailing: Text('$rssi dBm'),
          ),
        ],
      ),
    );
  }

  // ================= FLASH CARD =================

  Widget flashCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'FLASH',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () =>
                      sendCommand('flash', 'ON'),
                  child: const Text('ON'),
                ),

                ElevatedButton(
                  onPressed: () =>
                      sendCommand('flash', 'OFF'),
                  child: const Text('OFF'),
                ),

                ElevatedButton(
                  onPressed: () =>
                      sendCommand('flash', 'AUTO'),
                  child: const Text('AUTO'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Current: $flashStatus',
            ),
          ],
        ),
      ),
    );
  }

  // ================= ZOOM CARD =================

  Widget zoomCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CAMERA ZOOM',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                Text(
                  '${zoom.toStringAsFixed(1)}x',
                ),
              ],
            ),

            Slider(
              min: 1.0,
              max: 4.0,
              divisions: 6,
              value: zoom.clamp(1.0, 4.0),
              label:
                  '${zoom.toStringAsFixed(1)}x',

              onChanged: (value) {
                setState(() {
                  zoom = value;
                });
              },

              onChangeEnd: (value) {
                sendCommand(
                  'zoom',
                  value.toStringAsFixed(1),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ================= CAMERA CARD =================

  Widget cameraCard() {
    final bytes = getImageBytes();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              'ESP32-CAM',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            ClipRRect(
              borderRadius:
                  BorderRadius.circular(12),

              child: bytes != null
                  ? Image.memory(
                      bytes,
                      width: double.infinity,
                      height: 240,
                      fit: BoxFit.contain,

                      errorBuilder:
                          (_, __, ___) {
                        return const SizedBox(
                          height: 240,
                          child: Center(
                            child: Text(
                              'Image cannot be decoded',
                            ),
                          ),
                        );
                      },
                    )
                  : const SizedBox(
                      height: 240,
                      child: Center(
                        child: Text(
                          'Waiting for photo...',
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 10),

            if (message.isNotEmpty)
              Text(
                message,
                style:
                    const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  // ================= MAIN UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'IIT AC Controller',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: RefreshIndicator(
        onRefresh: readFirebase,

        child: SingleChildScrollView(
          physics:
              const AlwaysScrollableScrollPhysics(),

          padding:
              const EdgeInsets.all(16),

          child: Column(
            children: [
              statusCard(),

              const SizedBox(height: 12),

              cameraCard(),

              const SizedBox(height: 12),

              servoCard(),

              const SizedBox(height: 12),

              autoCard(),

              const SizedBox(height: 12),

              sensorCard(),

              const SizedBox(height: 12),

              flashCard(),

              const SizedBox(height: 12),

              zoomCard(),

              const SizedBox(height: 20),

              OutlinedButton.icon(
                onPressed: readFirebase,
                icon:
                    const Icon(Icons.refresh),
                label:
                    const Text('REFRESH'),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
