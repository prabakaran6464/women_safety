import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:volume_watcher_plus/volume_watcher_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: isLoggedIn ? const AccidentDetectionScreen() : const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  TextEditingController usernameController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController mobile1Controller = TextEditingController();
  TextEditingController mobile2Controller = TextEditingController();

  Future<void> _login() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', usernameController.text);
    await prefs.setString('password', passwordController.text);
    await prefs.setString('mobile1', mobile1Controller.text);
    await prefs.setString('mobile2', mobile2Controller.text);
    await prefs.setBool('isLoggedIn', true);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AccidentDetectionScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(controller: usernameController, decoration: const InputDecoration(labelText: "Username")),
            TextField(controller: passwordController, decoration: const InputDecoration(labelText: "Password"), obscureText: true),
            TextField(controller: mobile1Controller, decoration: const InputDecoration(labelText: "Add emergency mobile number one")),
            TextField(controller: mobile2Controller, decoration: const InputDecoration(labelText: "Add emergency mobile number two")),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _login, child: const Text("Login")),
          ],
        ),
      ),
    );
  }
}

class AccidentDetectionScreen extends StatefulWidget {
  const AccidentDetectionScreen({super.key});

  @override
  AccidentDetectionScreenState createState() => AccidentDetectionScreenState();
}

class AccidentDetectionScreenState extends State<AccidentDetectionScreen> {
  static const double threshold = 15.0;
  String locationText = "Waiting for Safety detection...";
  bool _locationFetched = false;
  double previousVolume = -1;
  late Function(double) volumeCallback;
  int volumePressCount = 0;
  DateTime? lastPressTime;
  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _setupVolumeWatcher();
    accelerometerEvents.listen((AccelerometerEvent event) {
      double acceleration = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (acceleration > threshold && !_locationFetched) {
        _getCurrentLocation();
      }
    });
  }
  @override
  void dispose() {
    VolumeWatcherPlus.removeListener(volumeCallback as int?);
    super.dispose();
  }


  Future<void> _requestLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        return;
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    if (_locationFetched) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() {
          locationText = "Location permission denied. Please enable it in settings.";
        });
        return;
      }
    }

    try {
      _locationFetched = true;
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String mobile1 = prefs.getString('mobile1') ?? "";
      String mobile2 = prefs.getString('mobile2') ?? "";

      setState(() {
        locationText = "Problem Detected!\nLatitude: ${position.latitude}\nLongitude: ${position.longitude}";
      });
      await _sendSMS(mobile1, position.latitude, position.longitude);
      await _sendSMS(mobile2, position.latitude, position.longitude);
    } catch (e) {
      setState(() {
        locationText = "Failed to get location: $e";
      });
    }
  }
  Future<void> _sendSMS(String to, double latitude, double longitude) async {
    if (to.isEmpty) return;
    String accountSid = "AC3b9d91a9fc446212e5c7dd33ab5e7f0c";
    String authToken = "446df44db875d75fdad5bd967ff50f20"; // Replace with actual Auth Token
    String from = "+13253264306"; // Replace with your Twilio number
    String message = "i am  in Problem. Help Me Location: https://maps.google.com/?q=$latitude,$longitude";

    String url = "https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json";

    await http.post(
      Uri.parse(url),
      headers: {
        "Authorization": "Basic ${base64Encode(utf8.encode("$accountSid:$authToken"))}",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: {
        "To": to,
        "From": from,
        "Body": message,
      },
    );

  }
  void _setupVolumeWatcher() {
    volumeCallback = (double currentVolume) {
      if (previousVolume == -1) {
        previousVolume = currentVolume;
        return;
      }

      // Detect volume down
      if (currentVolume < previousVolume) {
        DateTime now = DateTime.now();

        if (lastPressTime == null || now.difference(lastPressTime!) < Duration(seconds: 4)) {
          volumePressCount++;
          lastPressTime = now;

          if (volumePressCount == 3) {
            _getCurrentLocation(); // Emergency SMS
            volumePressCount = 0;
          }
        } else {
          volumePressCount = 1;
          lastPressTime = now;
        }
      }

      previousVolume = currentVolume;
    };

    VolumeWatcherPlus.addListener(volumeCallback);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Women Safety Detection"),
        actions: [
          IconButton(
            onPressed: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.remove('isLoggedIn');
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            },
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: Text(
              locationText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          ),
          SizedBox(height: 40),
          InkWell(
            onTap: () {
              setState(() {
                locationText = "Waiting for Safety detection...";
               _getCurrentLocation();
              });
            },
            child: Image.asset(
              "assets/sos_image.jpg",
              height: 300,
              width: 300,
            ),
          ),
        ],
      ),
    );
  }
}
