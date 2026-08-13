import 'dart:async';
import 'dart:convert';

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
  static const String firebaseUrl =
      'https://iit-automation-default-rtdb.firebaseio.com';

  bool servoOn = false;
  bool autoMode = false;

  bool personDetected = false;
  bool screenOn = false;
  bool esp32Online = false;

  String radarStatus = 'ACTIVE';
  String flashStatus = 'OFF';

  int rssi = 0;
  double zoom = 1.0;

  String? photoData;

  Timer? timer;

  @override
  void initState() {
    super.initState();

    // Read Firebase every 2 seconds.
    timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => readFirebase(),
    );

    readFirebase();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------
  // SEND COMMAND TO ESP32
  // ----------------------------------------------------------

  Future<void> sendCommand(String command, String value) async {
    try {
      final url = Uri.parse('$firebaseUrl/commands.json');

      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          command: value,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$command → $value'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Command error: $e');
    }
  }

  // ----------------------------------------------------------
  // READ STATUS FROM FIREBASE
  // ----------------------------------------------------------

  Future<void> readFirebase() async {
    try {
      final statusResponse = await http.get(
        Uri.parse('$firebaseUrl/status.json'),
      );

      if (statusResponse.statusCode == 200 &&
          statusResponse.body != 'null') {
        final data = jsonDecode(statusResponse.body);

        if (data is Map) {
          setState(() {
            esp32Online = true;

            personDetected = data['present'] == true;

            screenOn =
                data['screen_state'].toString().toUpperCase() == 'ON';

            flashStatus = data['flash']?.toString() ?? 'OFF';

            rssi = int.tryParse(
                  data['rssi']?.toString() ?? '0',
                ) ??
                0;

            zoom = double.tryParse(
                  data['zoom']?.toString() ?? '1',
                ) ??
                1.0;
          });
        }
      }
    } catch (e) {
      setState(() {
        esp32Online = false;
      });

      debugPrint('Status error: $e');
    }

    // --------------------------------------------------------
    // READ PHOTO
    // --------------------------------------------------------

    try {
      final photoResponse = await http.get(
        Uri.parse('$firebaseUrl/photo.json'),
      );

      if (photoResponse.statusCode == 200 &&
          photoResponse.body != 'null') {
        final data = jsonDecode(photoResponse.body);

        if (data is Map && data['data'] != null) {
          setState(() {
            photoData = data['data'].toString();
          });
        }
      }
    } catch (e) {
      debugPrint('Photo error: $e');
    }
  }

  // ----------------------------------------------------------
  // APP UI
  // ----------------------------------------------------------

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
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.all(16),

          child: Column(
            children: [

              // =================================================
              // ESP32 CONNECTION
              // =================================================

              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.circle,
                    color: esp32Online
                        ? Colors.green
                        : Colors.red,
                  ),

                  title: const Text(
                    'ESP32 STATUS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  trailing: Text(
                    esp32Online
                        ? 'ONLINE'
                        : 'OFFLINE',
                    style: TextStyle(
                      color: esp32Online
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // =================================================
              // SERVO CONTROL
              // =================================================

              Card(
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

                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceEvenly,

                        children: [

                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                servoOn = true;
                              });

                              sendCommand(
                                'servo',
                                'ON',
                              );
                            },

                            icon: const Icon(
                              Icons.power,
                            ),

                            label: const Text('ON'),
                          ),

                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                servoOn = false;
                              });

                              sendCommand(
                                'servo',
                                'OFF',
                              );
                            },

                            icon: const Icon(
                              Icons.power_off,
                            ),

                            label: const Text('OFF'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Text(
                        servoOn
                            ? 'Servo: ON'
                            : 'Servo: OFF',

                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // =================================================
              // AUTO MODE
              // =================================================

              Card(
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
              ),

              const SizedBox(height: 12),

              // =================================================
              // SENSOR STATUS
              // =================================================

              Card(
                child: Column(
                  children: [

                    ListTile(
                      leading: Icon(
                        Icons.person,
                        color: personDetected
                            ? Colors.green
                            : Colors.grey,
                      ),

                      title: const Text(
                        'PERSON',
                      ),

                      trailing: Text(
                        personDetected
                            ? 'DETECTED'
                            : 'NOT DETECTED',
                      ),
                    ),

                    ListTile(
                      leading: Icon(
                        Icons.tv,
                        color: screenOn
                            ? Colors.green
                            : Colors.grey,
                      ),

                      title: const Text(
                        'SCREEN',
                      ),

                      trailing: Text(
                        screenOn
                            ? 'ON'
                            : 'OFF',
                      ),
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.radar,
                      ),

                      title: const Text(
                        'RADAR',
                      ),

                      trailing: Text(
                        radarStatus,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // =================================================
              // ESP32 INFORMATION
              // =================================================

              Card(
                child: Column(
                  children: [

                    ListTile(
                      leading: const Icon(
                        Icons.wifi,
                      ),

                      title: const Text(
                        'Wi-Fi Signal',
                      ),

                      trailing: Text(
                        '$rssi dBm',
                      ),
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.flash_on,
                      ),

                      title: const Text(
                        'Flash',
                      ),

                      trailing: Text(
                        flashStatus,
                      ),
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.zoom_in,
                      ),

                      title: const Text(
                        'Camera Zoom',
                      ),

                      trailing: Text(
                        '${zoom.toStringAsFixed(1)}x',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // =================================================
              // CAMERA PHOTO
              // =================================================

              Card(
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

                      if (photoData != null &&
                          photoData!.isNotEmpty)

                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(12),

                          child: Image.memory(
                            base64Decode(photoData!),
                            fit: BoxFit.cover,
                          ),
                        )

                      else

                        const SizedBox(
                          height: 180,

                          child: Center(
                            child: Text(
                              'Waiting for photo...',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // =================================================
              // REFRESH
              // =================================================

              OutlinedButton.icon(
                onPressed: readFirebase,

                icon: const Icon(
                  Icons.refresh,
                ),

                label: const Text(
                  'REFRESH',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
