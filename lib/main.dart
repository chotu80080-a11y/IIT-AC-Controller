import 'package:flutter/material.dart';

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
  bool servoOn = false;
  bool autoMode = false;
  bool personDetected = false;
  bool screenOn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IIT AC Controller'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            // ESP32 STATUS
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.circle,
                  color: Colors.green,
                ),
                title: const Text('ESP32'),
                subtitle: const Text('ONLINE'),
              ),
            ),

            const SizedBox(height: 15),

            // SERVO
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
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
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [

                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              servoOn = true;
                            });
                          },
                          child: const Text('ON'),
                        ),

                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              servoOn = false;
                            });
                          },
                          child: const Text('OFF'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      servoOn ? 'Servo: ON' : 'Servo: OFF',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            // AUTO MODE
            Card(
              child: SwitchListTile(
                title: const Text('AUTO MODE'),
                subtitle: Text(
                  autoMode ? 'Automatic control enabled' : 'Manual control',
                ),
                value: autoMode,
                onChanged: (value) {
                  setState(() {
                    autoMode = value;
                  });
                },
              ),
            ),

            const SizedBox(height: 15),

            // SENSOR STATUS
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
                    title: const Text('Person'),
                    trailing: Text(
                      personDetected ? 'DETECTED' : 'NOT DETECTED',
                    ),
                  ),

                  ListTile(
                    leading: Icon(
                      Icons.tv,
                      color: screenOn
                          ? Colors.green
                          : Colors.grey,
                    ),
                    title: const Text('Screen'),
                    trailing: Text(
                      screenOn ? 'ON' : 'OFF',
                    ),
                  ),

                  ListTile(
                    leading: const Icon(Icons.radar),
                    title: const Text('Radar'),
                    trailing: const Text('ACTIVE'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // TEST BUTTONS
            OutlinedButton(
              onPressed: () {
                setState(() {
                  personDetected = !personDetected;
                });
              },
              child: const Text('Test Person Detection'),
            ),

            const SizedBox(height: 10),

            OutlinedButton(
              onPressed: () {
                setState(() {
                  screenOn = !screenOn;
                });
              },
              child: const Text('Test Screen Status'),
            ),
          ],
        ),
      ),
    );
  }
}
