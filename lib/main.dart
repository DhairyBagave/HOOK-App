import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
// import 'package:charts_flutter/flutter.dart' as charts;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_blue/flutter_blue.dart';


FlutterBlue flutterBlue = FlutterBlue.instance;
BluetoothDevice? targetDevice;
BluetoothCharacteristic? targetCharacteristic;

Future<void> initializeBluetooth() async {
  print("Starting Bluetooth scan...");
  flutterBlue.startScan(timeout: Duration(seconds: 4)); // Increased to 10 seconds

  flutterBlue.scanResults.listen((results) async {
    for (ScanResult r in results) {
      print('Found device: ${r.device.name}, id: ${r.device.id}');
      if (r.device.name == "esp32" || r.device.id == 'E4:65:BB:E7:20:F6') {
        print('Device found. Attempting to connect...');
        targetDevice = r.device;
        flutterBlue.stopScan();
        try {
          await targetDevice?.connect();
          print('Connected to ESP32');
          await discoverServices();
        } catch (e) {
          print('Failed to connect: $e');
        }
        break;
      } else {
        print('Unable to find device');
      }
    }
  });

  await Future.delayed(Duration(seconds: 2));
  flutterBlue.stopScan();
}

Future<void> discoverServices() async {
  if (targetDevice == null) return;
  print('Discovering services...');
  List<BluetoothService>? services = await targetDevice?.discoverServices();
  if (services == null || services.isEmpty) {
    print('No services found.');
    return;
  }
  for (BluetoothService service in services) {
    print('Found service: ${service.uuid}');
    for (BluetoothCharacteristic characteristic in service.characteristics) {
      print('Found characteristic: ${characteristic.uuid}');
      if (characteristic.uuid.toString() == "87654321-4321-4321-4321-210987654321") {
        targetCharacteristic = characteristic;
        print('Target characteristic found: ${characteristic.uuid}');
        break;
      }
    }
  }
}

Future<String?> readCharacteristic() async {
  if (targetCharacteristic == null) return null;
  List<int>? value = await targetCharacteristic?.read();
  return utf8.decode(value!);
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print('Firebase initialized successfully');
  } catch (e) {
    print('Error initializing Firebase: $e');
  }

  await initializeBluetooth().then((_) {
    print('Bluetooth initialized');
  }).catchError((e) {
    print('Error initializing Bluetooth: $e');
  });

  runApp(MyApp());
}

final FirebaseFirestore _firestore = FirebaseFirestore.instance;

double rpm = 0.00; // Mocked speed value for demonstration

double _distance = 00.0000; // Mocked distance value for demonstration

int _selectedMode=1;

String _username = '';

double _time=0.00;
int minutes=0;
bool timer_on=false;

bool pause=false;

int cnt=0;

double batteryPercentage=85.00;

double latit=0.0;
double longi=0.0;

Timer? _timer;

GoogleMapController? _controller;
LocationData? _currentLocation;
Location _location = Location();
Set<Polyline> _polylines = {};
List<LatLng> _route = [];
StreamSubscription<LocationData>? _locationSubscription;
TextEditingController _searchController = TextEditingController();
Marker? _destinationMarker;


void _saveDT() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  prefs.setDouble('distance', _distance);
  prefs.setDouble('time', _time);
  print("Distance saved");
}

double _calculateSPEED(double rpm) {
  return (rpm * pi * 60 * 85/1000000);
}

// void fetchRPMData() async {
//   try {
//     final response = await http.get(Uri.parse('http://192.168.4.1/getData')); // Replace with your ESP8266 IP address
//     if (response.statusCode == 200) {
//       // Check and print the raw response for debugging
//       print('Response status: ${response.statusCode}');
//       print('Response headers: ${response.headers}');
//       print('Response body: ${response.body}');
//
//       final data = jsonDecode(response.body);
//       // rpm = data['rpm'];
//       rpm=double.tryParse(data['rpm'].toString()) ?? 0.0;
//       rpm=rpm/14;
//       print(rpm);
//       // batteryPercentage = data['battery'];
//       batteryPercentage=double.tryParse(data['battery'].toString()) ?? 0.0;
//       batteryPercentage = 100-(42-batteryPercentage)*8.333; //(42-inVOL)*100/(42-30)
//       print(batteryPercentage);
//
//       _selectedMode=int.tryParse(data['mode'].toString()) ?? 1;
//       print(_selectedMode);
//     } else {
//       rpm=0;
//       print('Failed to load data. Status code: ${response.statusCode}');
//     }
//   } catch (e) {
//     print('Error fetching data: $e');
//   }
// }

Future<void> fetchRPMData() async {
  try {
    String? response = await readCharacteristic();

    if (response != null) {
      // Check and print the raw response for debugging
      print('Response: $response');

      final data = jsonDecode(response);
      rpm = double.tryParse(data['rpm'].toString()) ?? 0.0;
      rpm = rpm / 14;
      print(rpm);
      batteryPercentage = double.tryParse(data['battery'].toString()) ?? 0.0;
      batteryPercentage = 100 - (42 - batteryPercentage) * 8.333; //(42-inVOL)*100/(42-30)
      print(batteryPercentage);

      _selectedMode = int.tryParse(data['mode'].toString()) ?? 1;
      print(_selectedMode);
    } else {
      rpm = 0;
      print('Failed to load data.');
    }
  } catch (e) {
    print('Error fetching data: $e');
  }
}

void _sendData() {
  final data = {
    'speed': rpm * pi * 60 * 85/1000000,
    'rpm': rpm,
    'distance': _distance,
    'batteryPercentage': batteryPercentage,
    'Mode': _selectedMode,
    'time': DateTime.now().toIso8601String(),
    'Latitude': latit,
    'Longitude': longi,
  };

  _firestore.collection(_username).add(data)
      .then((_) => print('Data sent successfully'))
      .catchError((error) => print('Failed to send data: $error'));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dimension Six E-Bike',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => HomeScreen(),
        '/speedometer': (context) => SpeedometerScreen(),
        '/gps': (context) => GPSScreen(),
        // '/analytics': (context) => AnalyticScreen(),
        '/kiosk': (context) => KioskScreen(),
        '/battery': (context) => BatteryStatus(),
        '/settings': (context) => SettingsScreen(),
      },
    );
  }
}


class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TextEditingController _usernameController = TextEditingController();
  TextEditingController _searchController = TextEditingController();
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _selectedDevice;
  String _searchText = '';
  bool _isConnected = false; // Track connection statu

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadDT();
    _startOther();
    _startBluetoothScan();
    _monitorBluetoothConnection(); // Monitor connection status
  }

  // Monitor Bluetooth connection status
  void _monitorBluetoothConnection() {
    flutterBlue.state.listen((state) {
      if (state == BluetoothState.on) {
        _startBluetoothScan();
      }
    });

    // Listen for connection state changes
    if (_selectedDevice != null) {
      _selectedDevice!.state.listen((state) {
        setState(() {
          _isConnected = (state == BluetoothDeviceState.connected);
        });
      });
    }
  }

  Future<void> _loadDT() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _distance = prefs.getDouble('distance') ?? 0.0;
      _time = prefs.getDouble('time') ?? 0;
    });
    print("Distance loaded");
  }

  void _startOther() {
    _timer = Timer.periodic(Duration(milliseconds: 100), (Timer timer) {
      setState(() {
        _distance += 0.1 / 3600; // Example distance increment
      });
      _saveDT();
      print("startOther Called");
      if (true) { // Replace with your RPM condition
        if (cnt == 10) {
          cnt = 0;
        }
        cnt += 1;
      }
    });
  }

  Future<void> _loadUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username')!;
    });
  }

  Future<void> _saveUsername(String name) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', name);
    setState(() {
      _username = name;
    });
  }

  void _showEditUsernameDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Username'),
          content: TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              hintText: 'Enter new username',
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
              child: Text('Save'),
              onPressed: () {
                String newName = _usernameController.text.trim();
                if (newName.isNotEmpty && !_containsInvalidChars(newName)) {
                  _saveUsername(newName);
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Invalid username. No spaces or inverted commas allowed.'),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  bool _containsInvalidChars(String str) {
    return str.contains(' ') || str.contains('"') || str.contains("'");
  }

  void _startBluetoothScan() {
    flutterBlue.startScan(timeout: Duration(seconds: 4));

    flutterBlue.scanResults.listen((results) {
      setState(() {
        _scanResults = results
            .where((r) => r.device.name.isNotEmpty && r.advertisementData.connectable)
            .toList();
      });
    });

    flutterBlue.stopScan();
  }


  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        _selectedDevice = device;
      });
      print('Connected to ${device.name}');
    } catch (e) {
      print('Failed to connect: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    bool isSmallScreen = screenHeight < 400;

    return Scaffold(
      appBar: AppBar(
        title: Text('Home'),
        backgroundColor: Colors.orange,
      ),
      drawer: NavigationDrawer(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 20),
              Image.asset(
                'assets/Images/HOOK_logo.jpeg',
                width: isSmallScreen ? 150 : 200,
                height: isSmallScreen ? 150 : 200,
                fit: BoxFit.cover,
              ),
              SizedBox(height: 20),
              Text(
                'HOOK',
                style: TextStyle(
                  fontSize: isSmallScreen ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrangeAccent,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              _username == null
                  ? TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Enter your username',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty && !_containsInvalidChars(value)) {
                    _saveUsername(value);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Invalid username. No spaces or inverted commas allowed.'),
                      ),
                    );
                  }
                },
              )
                  : Column(
                children: [
                  Text(
                    'Welcome, $_username!',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 18 : 20,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _showEditUsernameDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: Text('Edit Username'),
                  ),
                ],
              ),
              SizedBox(height: 20),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search devices',
                  border: OutlineInputBorder(),
                ),
                onChanged: (text) {
                  setState(() {
                    _searchText = text;
                  });
                },
              ),
              SizedBox(height: 20),
              _isConnected
                  ? Column(
                children: [
                  Text(
                    'Connected to ESP32',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 18 : 20,
                      color: Colors.green,
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      _selectedDevice?.disconnect();
                      setState(() {
                        _selectedDevice = null;
                        _isConnected = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    child: Text('Disconnect'),
                  ),
                ],
              )
                  : Expanded(
                child: ListView.builder(
                  itemCount: _scanResults.length,
                  itemBuilder: (context, index) {
                    final device = _scanResults[index].device;
                    if (_searchText.isEmpty ||
                        device.name
                            .toLowerCase()
                            .contains(_searchText.toLowerCase())) {
                      return ListTile(
                        title: Text(
                          device.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(device.id.toString()),
                        trailing: Icon(Icons.bluetooth),
                        onTap: () {
                          _connectToDevice(device);
                        },
                      );
                    } else {
                      return Container();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// class HomeScreen extends StatefulWidget {
//   @override
//   _HomeScreenState createState() => _HomeScreenState();
// }
//
// class _HomeScreenState extends State<HomeScreen> {
//   // String? username;
//   TextEditingController _usernameController = TextEditingController();
//
//   @override
//   void initState() {
//     super.initState();
//     _loadUsername();
//     _loadDT();
//     _startOther();
//   }
//
//   Future<void> _loadDT() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _distance = prefs.getDouble('distance') ?? 0.0;
//       _time = prefs.getDouble('time') ?? 0;
//     });
//     print("Distance loaded");
//   }
//
//   void _startOther() {
//     _timer = Timer.periodic(Duration(milliseconds: 100), (Timer timer) {
//       fetchRPMData();
//       double _speed = _calculateSPEED(rpm); // Calculate speed based on RPM
//       setState(() {
//         _distance += _speed * 0.1 / 3600; // Update distance
//       });
//       _saveDT();
//       print("startOther Called");
//       if(rpm>63){
//         if(cnt==10){
//           _sendData();
//           cnt=0;
//         }
//         cnt+=1;
//       }
//     });
//   }
//
//   Future<void> _loadUsername() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _username = prefs.getString('username')!;
//     });
//   }
//
//   Future<void> _saveUsername(String name) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.setString('username', name);
//     setState(() {
//       _username = name;
//     });
//   }
//
//   void _showEditUsernameDialog() {
//     showDialog(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: Text('Edit Username'),
//           content: TextField(
//             controller: _usernameController,
//             decoration: InputDecoration(
//               hintText: 'Enter new username',
//             ),
//           ),
//           actions: <Widget>[
//             ElevatedButton(
//               child: Text('Save'),
//               onPressed: () {
//                 String newName = _usernameController.text.trim();
//                 if (newName.isNotEmpty && !_containsInvalidChars(newName)) {
//                   _saveUsername(newName);
//                   Navigator.of(context).pop();
//                 } else {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     SnackBar(
//                       content: Text(
//                           'Invalid username. No spaces or inverted commas allowed.'),
//                     ),
//                   );
//                 }
//               },
//             ),
//           ],
//         );
//       },
//     );
//   }
//
//   bool _containsInvalidChars(String str) {
//     return str.contains(' ') || str.contains('"') || str.contains("'");
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Home'),
//         backgroundColor: Colors.blueAccent,
//       ),
//       drawer: NavigationDrawer(),
//       body: Center(
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 24.0),
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Image.asset(
//                 'assets/Images/HOOK_logo.jpeg',
//                 width: 200,
//                 height: 200,
//                 fit: BoxFit.cover,
//               ),
//               SizedBox(height: 20),
//               Text(
//                 'HOOK',
//                 style: TextStyle(
//                   fontSize: 24,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.blueAccent,
//                 ),
//                 textAlign: TextAlign.center,
//               ),
//               SizedBox(height: 20),
//               _username == null
//                   ? TextField(
//                 controller: _usernameController,
//                 decoration: InputDecoration(
//                   labelText: 'Enter your username',
//                   border: OutlineInputBorder(),
//                 ),
//                 onSubmitted: (value) {
//                   if (value.isNotEmpty && !_containsInvalidChars(value)) {
//                     _saveUsername(value);
//                   } else {
//                     ScaffoldMessenger.of(context).showSnackBar(
//                       SnackBar(
//                         content: Text(
//                             'Invalid username. No spaces or inverted commas allowed.'),
//                       ),
//                     );
//                   }
//                 },
//               )
//                   : Column(
//                 children: [
//                   Text(
//                     'Welcome, $_username!',
//                     style: TextStyle(
//                       fontSize: 20,
//                       color: Colors.blueGrey,
//                     ),
//                   ),
//                   SizedBox(height: 20),
//                   ElevatedButton(
//                     onPressed: _showEditUsernameDialog,
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.blueAccent,
//                     ),
//                     child: Text('Edit Username'),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

class SpeedometerScreen extends StatefulWidget {
  const SpeedometerScreen({super.key});

  @override
  _SpeedometerScreenState createState() => _SpeedometerScreenState();

}

class _SpeedometerScreenState extends State<SpeedometerScreen> {

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _loadDT();
    _startOther();
  }

  void _resetOdometer(){
    setState(() {
      _distance = 0.0;
    });
    _saveDT();
  }

  void _initializeLocation() async {
    await _location.requestPermission();
    await _location.requestService();

    _locationSubscription = _location.onLocationChanged.listen((locationData) {
      _updateLocation(locationData);
      latit=locationData.latitude!;
      longi=locationData.longitude!;
    });
  }

  void _updateLocation(LocationData locationData) {
    setState(() {
      _currentLocation = locationData;
      _route.add(LatLng(locationData.latitude!, locationData.longitude!));
      _polylines.add(Polyline(
        polylineId: PolylineId('route'),
        points: _route,
        color: Colors.orange,
        width: 5,
      ));
    });

    _controller?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(locationData.latitude!, locationData.longitude!),
      ),
    );
  }

  void TimerOn(){
    setState((){
      if(timer_on){
        timer_on=false;
        _time = 0.0;
        minutes=0;
      }else if(!timer_on){
        timer_on=true;
      }
    });
  }

  void PauseTimer(){
    setState((){
      pause=!pause;
    });
  }

  Future<void> _loadDT() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _distance = prefs.getDouble('distance') ?? 0.0;
      _time = prefs.getDouble('time') ?? 0;
    });
    print("Distance loaded");
  }


  void _startOther() {
    _timer = Timer.periodic(Duration(milliseconds: 100), (Timer timer) {
      fetchRPMData();
      double _speed = _calculateSPEED(rpm); // Calculate speed based on RPM
      setState(() {
        if (timer_on && !pause) {
          _time += 0.1;
          if (_time >= 60.0) {
            _time = 0.0;
            minutes += 1;
          }
        }
        _distance += _speed * 0.1 / 3600; // Update distance
      });
      _saveDT();
      print("startOther Called");
      if(rpm>63){
        if(cnt==10){
          _sendData();
          cnt=0;
        }
        cnt+=1;
      }

    });
  }

  // void setMode(String mode, int newMode) async {
  //   setState(() {
  //     _selectedMode = newMode;
  //   });
  //   print(_selectedMode);
  //   print("Transferred mode : ");
  //   print(mode);
  //   try {
  //     final response = await http.post(
  //       Uri.parse('http://192.168.4.1/setMode'),
  //       body: mode,
  //     );
  //
  //     if (response.statusCode == 200) {
  //       print('Mode set successfully');
  //     } else {
  //       print('Failed to set mode. Status code: ${response.statusCode}');
  //     }
  //   } catch (e) {
  //     print('Error setting mode: $e');
  //   }
  // }



  @override
  Widget build(BuildContext context) {
    double _speed = _calculateSPEED(rpm);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Speedometer',
          style: TextStyle(color: Colors.white), // Set the title text color to white
        ),
        backgroundColor: Colors.orange,
      ),
      drawer: NavigationDrawer(),
      body:Container(
        color: Colors.white,
        child:Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModeButton(1, 'Eco', Icons.eco),
                _buildModeButton(2, 'Power', Icons.bolt),
                _buildModeButton(3, 'Sport', Icons.local_fire_department_rounded),
              ],
            ),

            SizedBox(height: 20),

            // Analog Speedometer
            CustomPaint(
              size: Size(300, 300),
              painter: SpeedometerPainter(speed: _speed, rpm: rpm),
            ),
            SizedBox(height: 20),

            // Digital Speedometer and RPM
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    '${_speed.toStringAsFixed(1)} km/h',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                  ),
                  Text(
                    '${rpm.toStringAsFixed(0)} RPM',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                  ),
                ],
            ),

            SizedBox(height: 20),

            Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    '${_distance.toStringAsFixed(2)} km',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                  ),

                  Text(
                    '${minutes.toStringAsFixed(0)}:${_time.toStringAsFixed(0)} mins',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                  ),
                ],
            ),

            SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _resetOdometer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(15),
                    side: BorderSide(color: Colors.blueGrey, width: 2),
                  ),
                  child: Icon(
                    Icons.refresh, // Replace with the relevant icon you want to use
                    color: Colors.white,
                    size: 50, // Adjust icon size as needed
                  ),
                ),
                ElevatedButton(
                  onPressed: TimerOn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: timer_on ? Colors.deepOrange : Colors.orange,
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(15),
                    side: BorderSide(color: timer_on ? Colors.deepOrange : Colors.white, width: 2),
                  ),
                  child: Icon(
                    Icons.timer,
                    color: timer_on ? Colors.white : Colors.white,
                    size: 50
                  ),
                ),
                if (timer_on)
                  ElevatedButton(
                    onPressed: PauseTimer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pause ? Colors.green : Colors.orange,
                      shape: CircleBorder(),
                      padding: EdgeInsets.all(15),
                      side: BorderSide(color: pause ? Colors.green : Colors.deepOrange, width: 2),
                    ),
                    child: Icon(
                      Icons.pause_circle_outline_outlined,
                      color: pause ? Colors.white : Colors.white,
                      size: 50,
                    ),
                  ),
              ],
            ),

          ],
        ),
      ),
      )
    );
  }

  // Mode Button Builder with Icons
  Widget _buildModeButton(int mode, String text, IconData icon) {
    bool isSelected = _selectedMode == mode;
    return ElevatedButton(
      onPressed: () {
        // Your existing setMode or related functionality here
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.deepOrangeAccent : Colors.white60,
        shape: CircleBorder(), // Circular shape
        padding: EdgeInsets.all(15), // Adjust padding for size
        side: BorderSide(color: isSelected ? Colors.deepOrangeAccent : Colors.grey, width: 2), // Border styling
      ),
      child: Icon(
        icon,
        color: isSelected ? Colors.white : Colors.black, // Icon color changes based on selection
        size: 40, // Adjust icon size as needed
      ),
    );
  }


// Widget _buildModeButton(int mode, String text, String m) {
  // Widget _buildModeButton(int mode, String text) {
  //   bool isSelected = _selectedMode == mode;
  //   return ElevatedButton(
  //     onPressed: () {  },
  //         // () => setMode(m, mode),
  //     style: ElevatedButton.styleFrom(
  //       backgroundColor: isSelected ? Colors.blue : Colors.white60,
  //     ),
  //     child: Text(
  //       text,
  //       style: TextStyle(
  //         color: isSelected ? Colors.white : Colors.black,
  //       ),
  //     ),
  //   );
  // }
}

class SpeedometerPainter extends CustomPainter {
  final double speed;
  final double rpm;
  SpeedometerPainter({required this.speed, required this.rpm});

  @override
  void paint(Canvas canvas, Size size) {
    double centerX = size.width / 2;
    double centerY = size.height / 2;
    double radius = min(centerX, centerY);

    Paint backgroundPaint = Paint()
      ..color = Colors.grey.shade900
      ..style = PaintingStyle.fill;

    Paint scalePaint = Paint()
      ..strokeWidth = 2;

    Paint needlePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Draw the background circle
    canvas.drawCircle(Offset(centerX, centerY), radius, backgroundPaint);

    // Draw the outer arc for speed scale
    double startAngle = 3 * pi / 4;
    double sweepAngle = 3 * pi / 2;

    Rect arcRect = Rect.fromCircle(center: Offset(centerX, centerY), radius: radius * 0.92);
    canvas.drawArc(arcRect, startAngle, sweepAngle, false, scalePaint..color = Colors.yellow);

    arcRect = Rect.fromCircle(center: Offset(centerX, centerY), radius: radius * 0.9);
    canvas.drawArc(arcRect, startAngle, sweepAngle, false, scalePaint..color = Colors.white);

    // Draw speed markings and sections
    for (int i = 0; i <= 30; i += 5) {
      double angle = startAngle + sweepAngle * (i / 30);
      double startX = centerX + radius * 0.8 * cos(angle);
      double startY = centerY + radius * 0.8 * sin(angle);
      double endX = centerX + radius * 0.9 * cos(angle);
      double endY = centerY + radius * 0.9 * sin(angle);

      if (i < 10) {
        scalePaint.color = Colors.green;
      } else if(i < 20){
        scalePaint.color=Colors.yellow;
      }  else if(i < 30) {
        scalePaint.color = Colors.red;
      }

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), scalePaint);

      for(int j=0; (j<5 && i<30); j++){
        double anglem=angle+sweepAngle*(j/24);
        double miSX = centerX + radius * 0.85 * cos(anglem);
        double miSY = centerY + radius * 0.85 * sin(anglem);
        double endmX = centerX + radius * 0.9 * cos(anglem);
        double endmY = centerY + radius * 0.9 * sin(anglem);
        canvas.drawLine(Offset(miSX, miSY), Offset(endmX, endmY), scalePaint);
      }

      if (i % 5 == 0) {
        TextPainter textPainter = TextPainter(
          text: TextSpan(
            text: '$i',
            style: TextStyle(color: Colors.black, fontSize: 14),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        double textX = centerX + radius * 0.65 * cos(angle) - textPainter.width / 2;
        double textY = centerY + radius * 0.65 * sin(angle) - textPainter.height / 2;
        textPainter.paint(canvas, Offset(textX, textY));
      }
    }

    // Draw the inner arc for RPM scale
    Rect innerArcRect = Rect.fromCircle(center: Offset(centerX, centerY), radius: radius * 0.5);
    canvas.drawArc(innerArcRect, startAngle, sweepAngle, false, scalePaint..color = Colors.yellow);

    // Draw RPM markings
    for (int i = 0; i <= 300; i += 50) {
      double angle = startAngle + sweepAngle * (i / 300);
      double startX = centerX + radius * 0.4 * cos(angle);
      double startY = centerY + radius * 0.4 * sin(angle);
      double endX = centerX + radius * 0.5 * cos(angle);
      double endY = centerY + radius * 0.5 * sin(angle);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), scalePaint..color = Colors.yellow);

      if (i % 50 == 0) {
        double t=(i/50)*312;
        TextPainter textPainter = TextPainter(
          text: TextSpan(
            text: '$t',
            style: TextStyle(color: Colors.red, fontSize: 14),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        double textX = centerX + radius * 0.4 * cos(angle) - textPainter.width / 2;
        double textY = centerY + radius * 0.4 * sin(angle) - textPainter.height / 2;
        textPainter.paint(canvas, Offset(textX, textY));
      }
    }

    // Draw the needle for both speed and RPM
    double needleAngle = startAngle + sweepAngle * (speed / 30);
    double needleX = centerX + radius * 0.8 * cos(needleAngle);
    double needleY = centerY + radius * 0.8 * sin(needleAngle);
    canvas.drawLine(Offset(centerX, centerY), Offset(needleX, needleY), needlePaint);

    // Draw needle center
    Paint needleCenterPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 5, needleCenterPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}







// class SpeedometerPainter extends CustomPainter {
//   final double speed;
//   final double rpm;
//
//   SpeedometerPainter({required this.speed, required this.rpm});
//
//   @override
//   void paint(Canvas canvas, Size size) {
//     double centerX = size.width / 2;
//     double centerY = size.height / 2;
//     double radius = min(centerX, centerY);
//
//     Paint backgroundPaint = Paint()
//       ..color = Colors.black
//       ..style = PaintingStyle.fill;
//
//     Paint scalePaint = Paint()
//       ..strokeWidth = 3;
//
//     Paint needlePaint = Paint()
//       ..color = Colors.orange
//       ..strokeWidth = 6
//       ..strokeCap = StrokeCap.round;
//
//     // Draw the background circle with a gradient
//     Rect gradientRect = Rect.fromCircle(center: Offset(centerX, centerY), radius: radius);
//     Gradient gradient = RadialGradient(
//       colors: [Colors.grey.shade800, Colors.black],
//       stops: [0.6, 1],
//     );
//     backgroundPaint.shader = gradient.createShader(gradientRect);
//     canvas.drawCircle(Offset(centerX, centerY), radius, backgroundPaint);
//
//     // Draw the outer arc for speed scale with a gradient
//     double startAngle = 3 * pi / 4;
//     double sweepAngle = 3 * pi / 2;
//
//     Rect arcRect = Rect.fromCircle(center: Offset(centerX, centerY), radius: radius * 0.92);
//     Gradient arcGradient = SweepGradient(
//       colors: [Colors.green, Colors.yellow, Colors.orange, Colors.redAccent, Colors.red],
//       stops: [0.0, 0.33, 0.66, 0.83, 1.0],  // Adjusted stops to ensure green starts at 0km/h and red ends at 30km/h
//       startAngle: startAngle,
//       endAngle: sweepAngle,
//     );
//     scalePaint.shader = arcGradient.createShader(arcRect);
//     canvas.drawArc(arcRect, startAngle, sweepAngle, false, scalePaint);
//
//     // Draw speed markings and sections with shadow
//     for (int i = 0; i <= 30; i += 5) {
//       double angle = startAngle + sweepAngle * (i / 30);
//       double startX = centerX + radius * 0.8 * cos(angle);
//       double startY = centerY + radius * 0.8 * sin(angle);
//       double endX = centerX + radius * 0.9 * cos(angle);
//       double endY = centerY + radius * 0.9 * sin(angle);
//
//       canvas.drawLine(Offset(startX, startY), Offset(endX, endY), scalePaint);
//
//       // Draw shadow for markings
//       scalePaint.maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0);
//       for (int j = 0; j < 5; j++) {
//         double angleM = angle + sweepAngle * (j / 24);
//         double midStartX = centerX + radius * 0.85 * cos(angleM);
//         double midStartY = centerY + radius * 0.85 * sin(angleM);
//         double midEndX = centerX + radius * 0.9 * cos(angleM);
//         double midEndY = centerY + radius * 0.9 * sin(angleM);
//         canvas.drawLine(Offset(midStartX, midStartY), Offset(midEndX, midEndY), scalePaint);
//       }
//
//       // Draw speed numbers
//       if (i % 5 == 0) {
//         TextPainter textPainter = TextPainter(
//           text: TextSpan(
//             text: '$i',
//             style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
//           ),
//           textDirection: TextDirection.ltr,
//         );
//         textPainter.layout();
//         double textX = centerX + radius * 0.65 * cos(angle) - textPainter.width / 2;
//         double textY = centerY + radius * 0.65 * sin(angle) - textPainter.height / 2;
//         textPainter.paint(canvas, Offset(textX, textY));
//       }
//     }
//
//     // Draw the inner arc for RPM scale with a gradient
//     Rect innerArcRect = Rect.fromCircle(center: Offset(centerX, centerY), radius: radius * 0.5);
//     Gradient innerArcGradient = SweepGradient(
//       colors: [Colors.blue, Colors.purple, Colors.red],
//       stops: [0.0, 0.5, 1.0],
//       startAngle: startAngle,
//       endAngle: startAngle + sweepAngle,
//     );
//     scalePaint.shader = innerArcGradient.createShader(innerArcRect);
//     canvas.drawArc(innerArcRect, startAngle, sweepAngle, false, scalePaint);
//
//     // Draw RPM markings with a different color and shadow
//     for (int i = 0; i <= 300; i += 50) {
//       double angle = startAngle + sweepAngle * (i / 300);
//       double startX = centerX + radius * 0.4 * cos(angle);
//       double startY = centerY + radius * 0.4 * sin(angle);
//       double endX = centerX + radius * 0.5 * cos(angle);
//       double endY = centerY + radius * 0.5 * sin(angle);
//
//       scalePaint.color = Colors.white;
//       canvas.drawLine(Offset(startX, startY), Offset(endX, endY), scalePaint);
//
//       // Draw RPM numbers
//       if (i % 50 == 0) {
//         double rpmValue = (i / 50) * 312;
//         TextPainter textPainter = TextPainter(
//           text: TextSpan(
//             text: '$rpmValue',
//             style: TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold),
//           ),
//           textDirection: TextDirection.ltr,
//         );
//         textPainter.layout();
//         double textX = centerX + radius * 0.4 * cos(angle) - textPainter.width / 2;
//         double textY = centerY + radius * 0.4 * sin(angle) - textPainter.height / 2;
//         textPainter.paint(canvas, Offset(textX, textY));
//       }
//     }
//
//     // Draw the needle for both speed and RPM with a shadow
//     double needleAngle = startAngle + sweepAngle * (speed / 30);
//     double needleX = centerX + radius * 0.8 * cos(needleAngle);
//     double needleY = centerY + radius * 0.8 * sin(needleAngle);
//
//     Paint needleShadowPaint = Paint()
//       ..color = Colors.black.withOpacity(0.5)
//       ..strokeWidth = 8
//       ..strokeCap = StrokeCap.round;
//
//     canvas.drawLine(Offset(centerX, centerY), Offset(needleX, needleY), needleShadowPaint);
//     canvas.drawLine(Offset(centerX, centerY), Offset(needleX, needleY), needlePaint);
//
//     // Draw needle center with a gradient
//     Paint needleCenterPaint = Paint()
//       ..shader = LinearGradient(
//         colors: [Colors.orange, Colors.red],
//         begin: Alignment.topLeft,
//         end: Alignment.bottomRight,
//       ).createShader(Rect.fromCircle(center: Offset(centerX, centerY), radius: 5))
//       ..style = PaintingStyle.fill;
//
//     canvas.drawCircle(Offset(centerX, centerY), 7, needleCenterPaint);
//   }
//
//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) {
//     return true;
//   }
// }





class GPSScreen extends StatefulWidget {
  @override
  _GPSScreenState createState() => _GPSScreenState();
}

class _GPSScreenState extends State<GPSScreen> {

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _loadDT();
    _startOther();
  }

  Future<void> _loadDT() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _distance = prefs.getDouble('distance') ?? 0.0;
      _time = prefs.getDouble('time') ?? 0;
    });
    print("Distance loaded");
  }

  void _startOther() {
    _timer = Timer.periodic(Duration(milliseconds: 100), (Timer timer) {
      fetchRPMData();
      double _speed = _calculateSPEED(rpm); // Calculate speed based on RPM
      setState(() {
        _distance += _speed * 0.1 / 3600; // Update distance
      });
      _saveDT();
      print("startOther Called");
      if(rpm>63){
        if(cnt==10){
          _sendData();
          cnt=0;
        }
        cnt+=1;
      }
    });
  }

  void _initializeLocation() async {
    await _location.requestPermission();
    await _location.requestService();

    _locationSubscription = _location.onLocationChanged.listen((locationData) {
      _updateLocation(locationData);
      latit=locationData.latitude!;
      longi=locationData.longitude!;
    });
  }

  void _updateLocation(LocationData locationData) {
    setState(() {
      _currentLocation = locationData;
      _route.add(LatLng(locationData.latitude!, locationData.longitude!));
      _polylines.add(Polyline(
        polylineId: PolylineId('route'),
        points: _route,
        color: Colors.deepOrangeAccent,
        width: 5,
      ));
    });

    _controller?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(locationData.latitude!, locationData.longitude!),
      ),
    );
  }

  void _clearRoute() {
    setState(() {
      _route.clear();
      _polylines.clear();
      _destinationMarker = null;
    });
  }

  Future<void> _searchPlace(String place) async {
    final response = await http.get(
      Uri.parse(
          'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=$place&inputtype=textquery&fields=geometry&key=AIzaSyCK5bd5zmX6zTv9ijhjGSa-vnlWJAToczU'),
    );
    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      final location = result['candidates'][0]['geometry']['location'];
      final lat = location['lat'];
      final lng = location['lng'];

      setState(() {
        _destinationMarker = Marker(
          markerId: MarkerId('destination'),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(title: place),
        );
      });

      _getDirections(LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!), LatLng(lat, lng));
    }
  }

  Future<void> _getDirections(LatLng origin, LatLng destination) async {
    final response = await http.get(
      Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=AIzaSyCK5bd5zmX6zTv9ijhjGSa-vnlWJAToczU'),
    );
    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      final route = result['routes'][0]['overview_polyline']['points'];
      setState(() {
        _polylines.add(
          Polyline(
            polylineId: PolylineId('directions'),
            points: _convertToLatLng(_decodePolyline(route)),
            color: Colors.red,
            width: 5,
          ),
        );
      });

      _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(
          _boundsFromLatLngList([
            origin,
            destination,
          ]),
          50,
        ),
      );
    }
  }

  List<LatLng> _convertToLatLng(List<dynamic> points) {
    List<LatLng> result = [];
    for (int i = 0; i < points.length; i++) {
      if (i % 2 == 0) {
        result.add(LatLng(points[i], points[i + 1]));
      }
    }
    return result;
  }

  List<dynamic> _decodePolyline(String poly) {
    var list = poly.codeUnits;
    var lList = new List<dynamic>.empty(growable: true);
    int index = 0;
    int len = poly.length;
    int c = 0;
    // repeating until all attributes are decoded
    do {
      var shift = 0;
      int result = 0;

      // for decoding value of one attribute
      do {
        c = list[index] - 63;
        result |= (c & 0x1F) << (shift * 5);
        index++;
        shift++;
      } while (c >= 32);
      /* if value is negative then bitwise not the value */
      if (result & 1 == 1) {
        result = ~(result >> 1);
      } else {
        result = (result >> 1);
      }

      lList.add((result).toDouble() / 1E5);
    } while (index < len);

    /*adding to previous value as done in encoding */
    for (var i = 2; i < lList.length; i++) lList[i] += lList[i - 2];

    return lList;
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    // Initialize with the first LatLng point
    double xa = list[0].latitude;
    double xb = list[0].latitude;
    double ya = list[0].longitude;
    double yb = list[0].longitude;

    for (LatLng latLng in list) {
      if (latLng.latitude > xb) xb = latLng.latitude;
      if (latLng.latitude < xa) xa = latLng.latitude;
      if (latLng.longitude > yb) yb = latLng.longitude;
      if (latLng.longitude < ya) ya = latLng.longitude;
    }

    return LatLngBounds(
      northeast: LatLng(xb, yb),
      southwest: LatLng(xa, ya),
    );
  }


  @override
  void dispose() {
    _locationSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('GPS Navigation'),
      ),
      drawer: NavigationDrawer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for a place',
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: () {
                    _searchPlace(_searchController.text);
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: _currentLocation == null
                ? Center(child: CircularProgressIndicator())
                : Stack(
              children: [
                GoogleMap(
                  onMapCreated: (controller) {
                    _controller = controller;
                  },
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _currentLocation!.latitude!,
                      _currentLocation!.longitude!,
                    ),
                    zoom: 15.0,
                  ),
                  myLocationEnabled: true,
                  mapType: MapType.normal,
                  polylines: _polylines,
                  markers: _destinationMarker != null
                      ? {
                    Marker(
                      markerId: MarkerId('current_location'),
                      position: LatLng(
                        _currentLocation!.latitude!,
                        _currentLocation!.longitude!,
                      ),
                      infoWindow:
                      InfoWindow(title: 'Current Location'),
                    ),
                    _destinationMarker!,
                  }
                      : {
                    Marker(
                      markerId: MarkerId('current_location'),
                      position: LatLng(
                        _currentLocation!.latitude!,
                        _currentLocation!.longitude!,
                      ),
                      infoWindow:
                      InfoWindow(title: 'Current Location'),
                    ),
                  },
                ),
                Positioned(
                  bottom: 16.0,
                  right: 16.0,
                  child: FloatingActionButton(
                    onPressed: () {
                      _initializeLocation(); // Refresh location
                    },
                    child: Icon(Icons.location_searching),
                  ),
                ),
                Positioned(
                  bottom: 16.0,
                  left: 16.0,
                  child: FloatingActionButton(
                    onPressed: () {
                      _clearRoute(); // Clear route
                    },
                    child: Icon(Icons.clear),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// class AnalyticScreen extends StatefulWidget {
//   const AnalyticScreen({super.key});
//
//   @override
//   _AnalyticScreenState createState() => _AnalyticScreenState();
// }

// class _AnalyticScreenState extends State<AnalyticScreen> {
//   final _firestore = FirebaseFirestore.instance;
//   late String _username;
//   Future<List<DataPoint>>? _speedDataFuture;
//   Future<List<DataPoint>>? _batteryDataFuture;
//   Future<List<DataPoint>>? _distanceDataFuture;
//   late Location _location;
//   late StreamSubscription<LocationData> _locationSubscription;
//   LocationData? _currentLocation;
//   List<LatLng> _route = [];
//   Set<Polyline> _polylines = {};
//
//   @override
//   void initState() {
//     super.initState();
//     _loadUsername();
//     _loadDT();
//     _startOther();
//     _initializeLocation();
//   }
//
//   void _initializeLocation() async {
//     _location = Location();
//     await _location.requestPermission();
//     await _location.requestService();
//
//     _locationSubscription = _location.onLocationChanged.listen((locationData) {
//       _updateLocation(locationData);
//       latit = locationData.latitude!;
//       longi = locationData.longitude!;
//     });
//   }
//
//   void _updateLocation(LocationData locationData) {
//     setState(() {
//       _currentLocation = locationData;
//       _route.add(LatLng(locationData.latitude!, locationData.longitude!));
//       _polylines.add(Polyline(
//         polylineId: PolylineId('route'),
//         points: _route,
//         color: Colors.blue,
//         width: 5,
//       ));
//     });
//   }
//
//   Future<void> _loadDT() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _distance = prefs.getDouble('distance') ?? 0.0;
//       _time = prefs.getDouble('time') ?? 0;
//     });
//   }
//
//   void _startOther() {
//     _timer = Timer.periodic(Duration(milliseconds: 100), (Timer timer) {
//       fetchRPMData();
//       double _speed = _calculateSPEED(rpm); // Calculate speed based on RPM
//       setState(() {
//         _distance += _speed * 0.1 / 3600; // Update distance
//       });
//       _saveDT();
//       if (rpm > 63) {
//         if (cnt == 10) {
//           _sendData();
//           cnt = 0;
//         }
//         cnt += 1;
//       }
//     });
//   }
//
//   Future<void> _loadUsername() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _username = prefs.getString('username') ?? 'default';
//       _speedDataFuture = _fetchLatestSpeedData();
//       _batteryDataFuture = _fetchLatestBatteryData();
//       _distanceDataFuture = _fetchLatestDistanceData();
//     });
//   }
//
//   Future<List<DataPoint>> _fetchLatestSpeedData() async {
//     try {
//       final now = DateTime.now();
//       final oneHourAgo = now.subtract(Duration(hours: 1));
//       final snapshot = await _firestore
//           .collection(_username)
//           .where('time', isGreaterThanOrEqualTo: oneHourAgo)
//           .orderBy('time', descending: true)
//           .get();
//       final data = snapshot.docs;
//       List<DataPoint> speedData = [];
//       for (var doc in data) {
//         final timestamp = doc['time'];
//         DateTime dateTime;
//         if (timestamp is Timestamp) {
//           dateTime = timestamp.toDate();
//         } else if (timestamp is String) {
//           dateTime = DateTime.parse(timestamp);
//         } else {
//           throw Exception('Unknown time format');
//         }
//         speedData.add(DataPoint(dateTime, doc['speed']));
//       }
//       return speedData.reversed.toList();
//     } catch (e) {
//       print("Error fetching speed data: $e");
//       return [];
//     }
//   }
//
//   Future<List<DataPoint>> _fetchLatestBatteryData() async {
//     try {
//       final now = DateTime.now();
//       final oneHourAgo = now.subtract(Duration(hours: 1));
//       final snapshot = await _firestore
//           .collection(_username)
//           .where('time', isGreaterThanOrEqualTo: oneHourAgo)
//           .orderBy('time', descending: true)
//           .get();
//       final data = snapshot.docs;
//       List<DataPoint> batteryData = [];
//       for (var doc in data) {
//         final timestamp = doc['time'];
//         DateTime dateTime;
//         if (timestamp is Timestamp) {
//           dateTime = timestamp.toDate();
//         } else if (timestamp is String) {
//           dateTime = DateTime.parse(timestamp);
//         } else {
//           throw Exception('Unknown time format');
//         }
//         batteryData.add(DataPoint(dateTime, doc['batteryPercentage']));
//       }
//       return batteryData.reversed.toList();
//     } catch (e) {
//       print("Error fetching battery data: $e");
//       return [];
//     }
//   }
//
//   Future<List<DataPoint>> _fetchLatestDistanceData() async {
//     try {
//       final now = DateTime.now();
//       final oneHourAgo = now.subtract(Duration(hours: 1));
//       final snapshot = await _firestore
//           .collection(_username)
//           .where('time', isGreaterThanOrEqualTo: oneHourAgo)
//           .orderBy('time', descending: true)
//           .get();
//       final data = snapshot.docs;
//       List<DataPoint> distanceData = [];
//       for (var doc in data) {
//         final timestamp = doc['time'];
//         DateTime dateTime;
//         if (timestamp is Timestamp) {
//           dateTime = timestamp.toDate();
//         } else if (timestamp is String) {
//           dateTime = DateTime.parse(timestamp);
//         } else {
//           throw Exception('Unknown time format');
//         }
//         distanceData.add(DataPoint(dateTime, doc['distance']));
//       }
//       return distanceData.reversed.toList();
//     } catch (e) {
//       print("Error fetching distance data: $e");
//       return [];
//     }
//   }
//
//   Widget _buildChart(Future<List<DataPoint>> dataFuture, String id, Color color, String xAxisLabel, String yAxisLabel, double yMax) {
//     return FutureBuilder<List<DataPoint>>(
//       future: dataFuture,
//       builder: (context, snapshot) {
//         if (snapshot.connectionState == ConnectionState.waiting) {
//           return Center(child: CircularProgressIndicator());
//         } else if (snapshot.hasError) {
//           return Center(child: Text('Error loading data'));
//         } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
//           return Center(child: Text('No data available'));
//         } else {
//           final data = snapshot.data!;
//           final series = [
//             charts.Series<DataPoint, DateTime>(
//               id: id,
//               colorFn: (_, __) => charts.ColorUtil.fromDartColor(color),
//               domainFn: (DataPoint point, _) => point.time,
//               measureFn: (DataPoint point, _) => point.value,
//               data: data,
//             )
//           ];
//           return Column(
//             children: [
//               Text(
//                 yAxisLabel,
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.black,
//                 ),
//               ),
//               Expanded(
//                 child: charts.TimeSeriesChart(
//                   series,
//                   animate: true,
//                   dateTimeFactory: const charts.LocalDateTimeFactory(),
//                   primaryMeasureAxis: charts.NumericAxisSpec(
//                     tickProviderSpec: charts.BasicNumericTickProviderSpec(
//                       zeroBound: false,
//                       dataIsInWholeNumbers: true,
//                       desiredTickCount: 6,
//                     ),
//                     viewport: charts.NumericExtents(0, yMax),
//                     renderSpec: charts.GridlineRendererSpec(
//                       labelStyle: charts.TextStyleSpec(
//                         fontSize: 14,
//                         fontWeight: 'bold',
//                         color: charts.MaterialPalette.black,
//                       ),
//                       lineStyle: charts.LineStyleSpec(
//                         color: charts.MaterialPalette.gray.shade300,
//                       ),
//                     ),
//                   ),
//                   domainAxis: charts.DateTimeAxisSpec(
//                     tickFormatterSpec: charts.AutoDateTimeTickFormatterSpec(
//                       minute: charts.TimeFormatterSpec(
//                         format: 'mm:ss',
//                         transitionFormat: 'mm:ss',
//                       ),
//                     ),
//                     renderSpec: charts.SmallTickRendererSpec(
//                       labelStyle: charts.TextStyleSpec(
//                         fontSize: 14,
//                         fontWeight: 'bold',
//                         color: charts.MaterialPalette.black,
//                       ),
//                       lineStyle: charts.LineStyleSpec(
//                         color: charts.MaterialPalette.gray.shade300,
//                       ),
//                     ),
//                   ),
//                   behaviors: [
//                     charts.LinePointHighlighter(
//                       symbolRenderer: CustomCircleSymbolRenderer(),
//                     ),
//                     charts.SelectNearest(
//                       eventTrigger: charts.SelectionTrigger.tapAndDrag,
//                     ),
//                   ],
//                 ),
//               ),
//               SizedBox(height: 10),
//               Text(
//                 xAxisLabel,
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.black,
//                 ),
//               ),
//             ],
//           );
//         }
//       },
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Your Rides'),
//         backgroundColor: Colors.deepOrangeAccent,
//       ),
//       drawer: NavigationDrawer(),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: PageView(
//           children: [
//             _buildChart(_speedDataFuture!, 'Speed', Colors.blue, 'Time', 'Speed (km/h)', 30),
//             _buildChart(_batteryDataFuture!, 'Battery', Colors.red, 'Time', 'Battery (%)', 100),
//             _buildChart(_distanceDataFuture!, 'Distance', Colors.green, 'Time', 'Distance (km)', 30),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class DataPoint {
//   final DateTime time;
//   final double value;
//
//   DataPoint(this.time, this.value);
// }

// class CustomCircleSymbolRenderer extends charts.CircleSymbolRenderer {
//   @override
//   void paint(
//       charts.ChartCanvas canvas,
//       Rectangle bounds, {
//         List<int>? dashPattern,
//         charts.Color? fillColor,
//         charts.FillPatternType? fillPattern,
//         charts.Color? strokeColor,
//         double? strokeWidthPx,
//       }) {
//     super.paint(
//       canvas,
//       bounds,
//       dashPattern: dashPattern,
//       fillColor: fillColor,
//       fillPattern: fillPattern,
//       strokeColor: strokeColor,
//       strokeWidthPx: strokeWidthPx,
//     );
//
//     canvas.drawRect(
//       Rectangle(
//         bounds.left - 5,
//         bounds.top - 30,
//         bounds.width + 10,
//         bounds.height + 10,
//       ),
//       fill: charts.Color.white,
//     );
//
//     final textStyle = charts.TextStyleSpec(
//       color: charts.MaterialPalette.black,
//       fontSize: 12,
//     );
//
//     // final textElement = charts.TextElement();
//     // textElement.textStyle = textStyle as charts.TextStyle?;
//     //
//     // canvas.drawText(
//     //   textElement,
//     //   (bounds.left).round(),
//     //   (bounds.top - 28).round(),
//     // );
//   }
// }


class KioskScreen extends StatefulWidget {
  const KioskScreen({Key? key}) : super(key: key);

  @override
  _KioskScreenState createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  @override
  void initState() {
    super.initState();
    productStatus();
  }

  bool isBattery1Charged = true;
  bool isBattery2Charged = false;
  bool isBattery3Charged = false;
  bool isBattery4Charged = false;

  // Product lock status variables
  bool product1 = false;
  bool product2 = false;
  bool product3 = false;
  bool product4 = false;

  // ESP32 endpoint
  final String esp32BaseUrl = 'http://192.168.4.1';

  // Fetch the battery status from ESP32
  Future<void> productStatus() async {
    try {
      final response = await http.get(Uri.parse('$esp32BaseUrl/status'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          isBattery1Charged = data['1'] == "1";
          isBattery2Charged = data['2'] == "1";
          isBattery3Charged = data['3'] == "1";
          isBattery4Charged = data['4'] == "1";
        });
        print('Status received: $data');
      } else {
        print('Failed to load battery status');
      }
    } catch (e) {
      print('Error fetching battery status: $e');
    }
  }

  // Send the product lock/unlock status to ESP32
  Future<void> sendProductStatus(int index, bool status) async {
    try {
      final response = await http.post(
        Uri.parse('$esp32BaseUrl/update'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, dynamic>{
          'productIndex': index,
          'status': status,
        }),
      );
      if (response.statusCode == 200) {
        print('Status updated successfully');
      } else {
        print('Failed to update status');
      }
    } catch (e) {
      print('Error updating status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiosk Screen'),
      ),
      drawer: NavigationDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          children: <Widget>[
            batteryTile(1, isBattery1Charged, product1),
            batteryTile(2, isBattery2Charged, product2),
            batteryTile(3, isBattery3Charged, product3),
            batteryTile(4, isBattery4Charged, product4),
          ],
        ),
      ),
    );
  }

  // Widget for displaying battery status and lock/unlock button
  // Widget batteryTile(int index, bool isCharged, bool productStatus) {
  //   Color backgroundColor = isCharged ? Colors.green : Colors.red;
  //   Color buttonColor = productStatus ? Colors.blue : Colors.orange;
  //
  //   return AnimatedContainer(
  //     duration: const Duration(milliseconds: 500),
  //     decoration: BoxDecoration(
  //       color: backgroundColor,
  //       borderRadius: BorderRadius.circular(12.0),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black26,
  //           blurRadius: 10,
  //           offset: Offset(2, 2),
  //         ),
  //       ],
  //     ),
  //     padding: const EdgeInsets.all(16.0),
  //     child: Column(
  //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //       children: <Widget>[
  //         Text(
  //           'Battery $index - ${isCharged ? 'Charged' : 'Charging'}',
  //           style: const TextStyle(
  //             color: Colors.white,
  //             fontWeight: FontWeight.bold,
  //             fontSize: 16,
  //           ),
  //           textAlign: TextAlign.center,
  //         ),
  //         ElevatedButton(
  //           onPressed: () async {
  //             setState(() {
  //               if (index == 1) {
  //                 product1 = !product1;
  //               } else if (index == 2) {
  //                 product2 = !product2;
  //               } else if (index == 3) {
  //                 product3 = !product3;
  //               } else if (index == 4) {
  //                 product4 = !product4;
  //               }
  //             });
  //             await sendProductStatus(index, !productStatus);
  //           },
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: buttonColor,
  //           ),
  //           child: Text(productStatus ? 'Unlock' : 'Lock'),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget batteryTile(int index, bool isCharged, bool productStatus) {
    Color backgroundColor = isCharged ? Colors.green : Colors.red;
    Color buttonColor = productStatus ? Colors.blue : Colors.orange;

    void _toggleProductStatus() async {
      // Toggle the product status based on index
      if (index == 1) {
        product1 = !product1;
      } else if (index == 2) {
        product2 = !product2;
      } else if (index == 3) {
        product3 = !product3;
      } else if (index == 4) {
        product4 = !product4;
      }

      // Call the function to update product status
      await sendProductStatus(index, !productStatus);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCharged
              ? [Colors.green.shade700, Colors.green.shade400]
              : [Colors.red.shade700, Colors.red.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: Offset(4, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          Text(
            'Battery $index - ${isCharged ? 'Charged' : 'Charging'}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          ElevatedButton(
            onPressed: _toggleProductStatus,
            style: ElevatedButton.styleFrom(
              iconColor: buttonColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 24.0),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              elevation: 6,
            ),
            child: Text(productStatus ? 'Unlock' : 'Lock'),
          ),
        ],
      ),
    );
  }
}


class BatteryStatus extends StatefulWidget {

  const BatteryStatus({super.key});
  @override
  State<BatteryStatus> createState() => _BatteryStatusState();
}

class _BatteryStatusState extends State<BatteryStatus> {
  @override
  void initState() {
    super.initState();
    // fetchRPMData();
    _loadDT();
    _startOther();
    _initializeLocation();
  }

  void _initializeLocation() async {
    await _location.requestPermission();
    await _location.requestService();

    _locationSubscription = _location.onLocationChanged.listen((locationData) {
      _updateLocation(locationData);
      latit=locationData.latitude!;
      longi=locationData.longitude!;
    });
  }

  void _updateLocation(LocationData locationData) {
    setState(() {
      _currentLocation = locationData;
      _route.add(LatLng(locationData.latitude!, locationData.longitude!));
      _polylines.add(Polyline(
        polylineId: PolylineId('route'),
        points: _route,
        color: Colors.blue,
        width: 5,
      ));
    });

    _controller?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(locationData.latitude!, locationData.longitude!),
      ),
    );
  }

  Future<void> _loadDT() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _distance = prefs.getDouble('distance') ?? 0.0;
      _time = prefs.getDouble('time') ?? 0;
    });
    print("Distance loaded");
  }

  void _startOther() {
    _timer = Timer.periodic(Duration(milliseconds: 100), (Timer timer) {
      fetchRPMData();
      double _speed = _calculateSPEED(rpm); // Calculate speed based on RPM
      setState(() {
        _distance += _speed * 0.1 / 3600; // Update distance
      });
      _saveDT();
      print("startOther Called");
      if(rpm>63){
        if(cnt==10){
          _sendData();
          cnt=0;
        }
        cnt+=1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double estimatedRange = _calculateRange(batteryPercentage);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Battery Status',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.deepOrangeAccent,
        elevation: 0,
      ),
      drawer: NavigationDrawer(),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Enhanced Battery Icon with Percentage
            Container(
              width: 150,
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [Colors.blueGrey[700]!, Colors.blueGrey[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.7),
                    offset: Offset(0, 10),
                    blurRadius: 25,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Battery outline with a more refined design
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 50,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.deepOrangeAccent,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
                        ),
                      ),
                    ),
                  ),
                  // Battery fill with a modern gradient
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: 140,
                      height: (batteryPercentage / 100) * 270,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.redAccent,
                            Colors.orangeAccent,
                            Colors.yellowAccent,
                            Colors.greenAccent,
                          ],
                          stops: [0.0, 0.4, 0.7, 1.0],
                        ),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  // Battery percentage text within the battery
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        '${batteryPercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: 10.0,
                              color: Colors.black.withOpacity(0.7),
                              offset: Offset(2.0, 2.0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 40),
            // Estimated Range with Dynamic Styling
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.blueGrey[800],
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.7),
                    offset: Offset(0, 10),
                    blurRadius: 25,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Estimated Range',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '${estimatedRange.toStringAsFixed(2)} km',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  // Calculate battery range based on percentage
  double _calculateRange(double percentage) {
    double maxRange = 40.0; // Max range in km
    return (maxRange * percentage) / 100;
  }
}


class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      drawer: NavigationDrawer(),
      body: Center(
        child: Text('Settings Screen'),
      ),
    );
  }
}


class NavigationDrawer extends StatelessWidget {
  const NavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.orange,
            ),
            child: Text(
              'Menu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.home),
            title: Text('Home'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
          ListTile(
            leading: Icon(Icons.speed),
            title: Text('Speedometer'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/speedometer');
            },
          ),
          ListTile(
            leading: Icon(Icons.gps_fixed),
            title: Text('GPS Tracking'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/gps');
            },
          ),
          // ListTile(
          //   leading: Icon(Icons.analytics_rounded),
          //   title: Text('Analytics'),
          //   onTap: () {
          //     Navigator.pushReplacementNamed(context, '/analytics');
          //   },
          // ),
          ListTile(
            leading: Icon(Icons.offline_bolt_sharp),
            title: Text('Kiosk'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/kiosk');
            },
          ),
          ListTile(
            leading: Icon(Icons.battery_full),
            title: Text('Battery Status'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/battery');
            },
          ),
          ListTile(
            leading: Icon(Icons.settings),
            title: Text('Settings'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/settings');
            },
          ),
        ],
      ),
    );
  }
}
