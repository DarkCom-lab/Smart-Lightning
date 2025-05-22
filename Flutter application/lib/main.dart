import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 LED Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ConnectionPage(),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final String _esp32Ip = '192.168.4.1';
  final int _esp32Port = 81;
  WebSocketChannel? _channel;
  String _connectionStatus = 'Disconnected';
  bool _isConnecting = false;
  final List<String> _logMessages = [];
  Timer? _reconnectTimer;

  Future<void> _connectToESP32() async {
    if (_isConnecting) return;
    _reconnectTimer?.cancel();

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
      _addLog('Connecting to ESP32...');
    });

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('ws://$_esp32Ip:$_esp32Port'),
        pingInterval: const Duration(seconds: 5),
      );

      await _channel!.ready.timeout(const Duration(seconds: 5));

      setState(() {
        _connectionStatus = 'Connected';
        _isConnecting = false;
        _addLog('Connected to ESP32');
      });

    } catch (e) {
      _addLog('Connection failed: ${e.toString()}');
      _scheduleReconnect();
    } finally {
      if (_isConnecting) {
        setState(() => _isConnecting = false);
      }
    }
  }

  void _addLog(String message) {
    setState(() {
      _logMessages.insert(0, '${DateTime.now().toString().substring(11, 19)}: $message');
      if (_logMessages.length > 10) _logMessages.removeLast();
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer = Timer(const Duration(seconds: 3), _connectToESP32);
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32 Connection')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  _connectionStatus == 'Connected' 
                      ? Icons.wifi 
                      : Icons.wifi_off,
                  color: _connectionStatus == 'Connected' 
                      ? Colors.green 
                      : Colors.red,
                  size: 40,
                ),
                const SizedBox(width: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status:',
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                    Text(_connectionStatus,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: _connectionStatus == 'Connected'
                      ? Colors.green
                      : Colors.blue,
                ),
                onPressed: _connectionStatus == 'Connected' ? null : _connectToESP32,
                child: _isConnecting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        _connectionStatus == 'Connected'
                            ? 'CONNECTED'
                            : 'CONNECT TO DEVICE',
                        style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),

            if (_connectionStatus == 'Connected')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LedControlPage(
                          channel: _channel!,
                        ),
                      ),
                    );
                  },
                  child: const Text('MANAGE LEDs',
                      style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            const SizedBox(height: 30),

            const Text('Connection Log:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListView.builder(
                  reverse: true,
                  itemCount: _logMessages.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _logMessages[index],
                      style: const TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: 14,
                          color: Colors.blueGrey),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LedControlPage extends StatefulWidget {
  final WebSocketChannel channel;

  const LedControlPage({super.key, required this.channel});

  @override
  State<LedControlPage> createState() => _LedControlPageState();
}

class _LedControlPageState extends State<LedControlPage> {
  final Map<int, Map<String, dynamic>> _leds = {};
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _renameController = TextEditingController();
  late SharedPreferences _prefs;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _initPreferences();
  }

  void _initPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSavedLeds();
    _setupWebSocketListener();
    _leds.keys.forEach((pin) => widget.channel.sink.add('GET_STATE:$pin'));
  }

  void _loadSavedLeds() {
    final savedLeds = _prefs.getStringList('leds') ?? [];
    setState(() {
      for (String ledData in savedLeds) {
        final parts = ledData.split('|');
        _leds[int.parse(parts[0])] = {
          'name': parts[1],
          'state': parts[2] == 'true'
        };
      }
    });
  }

  void _saveLeds() {
    final ledList = _leds.entries
        .map((e) => '${e.key}|${e.value['name']}|${e.value['state']}')
        .toList();
    _prefs.setStringList('leds', ledList);
  }

  void _setupWebSocketListener() {
    _subscription = widget.channel.stream.listen((data) {
      if (data is String) {
        if (data.startsWith('LED_UPDATE:')) {
          final parts = data.split(':');
          final pin = int.parse(parts[1]);
          final state = parts[2] == 'ON';
          final name = parts[3];
          setState(() {
            _leds[pin] = {'name': name, 'state': state};
          });
          _saveLeds();
        }
        else if (data.startsWith('LED_REMOVED:')) {
          final pin = int.parse(data.split(':')[1]);
          setState(() {
            _leds.remove(pin);
          });
          _saveLeds();
        }
      }
    });
  }

  void _addLed(int pin) {
    if (pin < 0 || pin > 39) return;
    if (!_leds.containsKey(pin)) {
      widget.channel.sink.add('ADD_LED:$pin');
    }
  }

  void _renameLed(int pin) {
    _renameController.text = _leds[pin]!['name'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename LED'),
        content: TextField(
          controller: _renameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_renameController.text.isNotEmpty) {
                widget.channel.sink
                    .add('RENAME_LED:$pin:${_renameController.text}');
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _removeLed(int pin) {
    widget.channel.sink.add('REMOVE_LED:$pin');
    setState(() {
      _leds.remove(pin);
    });
    _saveLeds();
  }

  void _toggleLed(int pin, bool state) {
    widget.channel.sink.add('SET_LED:$pin:${state ? 'ON' : 'OFF'}');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pinController.dispose();
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LED Control Panel'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Add New LED (0-39)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: () {
                          final pin = int.tryParse(_pinController.text);
                          if (pin != null) _addLed(pin);
                          _pinController.clear();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _leds.length,
                itemBuilder: (context, index) {
                  final pin = _leds.keys.elementAt(index);
                  final name = _leds[pin]!['name'];
                  final state = _leds[pin]!['state'];
                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(name),
                      subtitle: Text('GPIO $pin'),
                      leading: IconButton(
                        icon: const Icon(Icons.info_outline),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('LED Information'),
                            content: Text('Connected to GPIO Pin $pin'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK'),
                              )
                            ],
                          ),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _renameLed(pin),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeLed(pin),
                          ),
                          Switch(
                            value: state,
                            onChanged: (v) => _toggleLed(pin, v),
                            activeColor: Colors.green,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}