import 'dart:convert';
import 'dart:typed_data';

import 'package:crclib/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BLE Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: MyHomePage(title: 'Flutter BLE Demo'),
      );
}

class MyHomePage extends StatefulWidget {
  MyHomePage({super.key, required this.title});

  final String title;
  final List<BluetoothDevice> devicesList = <BluetoothDevice>[];
  final Map<Guid, List<int>> readValues = <Guid, List<int>>{};

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  final _writeController = TextEditingController();
  BluetoothDevice? _connectedDevice;
  List<BluetoothService> _services = [];

  _addDeviceToList(final BluetoothDevice device) {
    if (!widget.devicesList.contains(device)) {
      setState(() {
        widget.devicesList.add(device);
      });
    }
  }

  _initBluetooth() async {
    var subscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (results.isNotEmpty) {
          for (ScanResult result in results) {
            _addDeviceToList(result.device);
          }
        }
      },
      onError: (e) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      ),
    );

    FlutterBluePlus.cancelWhenScanComplete(subscription);

    await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;

    await FlutterBluePlus.startScan();

    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    FlutterBluePlus.connectedDevices.map((device) {
      _addDeviceToList(device);
    });
  }

  Future<String> loadJson(String filename) async {
    try {
      String jsonString = await rootBundle.loadString('assets/$filename');
      print("Loaded JSON file ($filename): \n$jsonString");
      return jsonString;
    } catch (e) {
      print("Error loading JSON file: $e");
      return "";
    }
  }

  @override
  void initState() {
    () async {
      var status = await Permission.location.status;
      if (status.isDenied) {
        final status = await Permission.location.request();
        if (status.isGranted || status.isLimited) {
          _initBluetooth();
        }
      } else if (status.isGranted || status.isLimited) {
        _initBluetooth();
      }

      if (await Permission.location.status.isPermanentlyDenied) {
        openAppSettings();
      }
    }();
    super.initState();
  }

  ListView _buildListViewOfDevices() {
    List<Widget> containers = <Widget>[];
    for (BluetoothDevice device in widget.devicesList) {
      containers.add(
        SizedBox(
          height: 50,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(device.platformName == '' ? '(unknown device)' : device.advName),
                    Text(device.remoteId.toString()),
                  ],
                ),
              ),
              TextButton(
                child: const Text(
                  'Connect',
                  style: TextStyle(color: Colors.black),
                ),
                onPressed: () async {
                  FlutterBluePlus.stopScan();
                  try {
                    await device.connect();
                  } on PlatformException catch (e) {
                    if (e.code != 'already_connected') {
                      rethrow;
                    }
                  } finally {
                    _services = await device.discoverServices();
                  }
                  setState(() {
                    _connectedDevice = device;
                  });
                },
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: <Widget>[
        ...containers,
      ],
    );
  }

  List<ButtonTheme> _buildReadWriteNotifyButton(BluetoothCharacteristic characteristic) {
    List<ButtonTheme> buttons = <ButtonTheme>[];

    if (characteristic.properties.read) {
      buttons.add(
        ButtonTheme(
          minWidth: 10,
          height: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextButton(
              child: const Text('READ', style: TextStyle(color: Colors.black)),
              onPressed: () async {
                var sub = characteristic.lastValueStream.listen((value) {
                  setState(() {
                    widget.readValues[characteristic.uuid] = value;
                  });
                });
                await characteristic.read();
                sub.cancel();
              },
            ),
          ),
        ),
      );
    }
    if (characteristic.properties.write) {
      buttons.add(
        ButtonTheme(
          minWidth: 10,
          height: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ElevatedButton(
              child: const Text('WRITE', style: TextStyle(color: Colors.black)),
              onPressed: () async {
                showDialog(
                  context: context,
                  builder: (context) {
                    String? selectedKey;
                    TextEditingController textController =
                        TextEditingController();

                    Map<String, String> jsonFileMap = {
                      "Broken": "example_settings_broken.json",
                      "Full": "example_settings_full.json",
                      "Invalid": "example_settings_invalid.json",
                      "Partial": "example_settings_part.json"
                    };

                    return StatefulBuilder(
                      builder: (context, setState) {
                        return AlertDialog(
                          title: Text("Update Device Config"),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DropdownButtonFormField<String>(
                                value: selectedKey,
                                hint: Text("Choose a JSON file"),
                                onChanged: (value) {
                                  setState(() {
                                    selectedKey = value;
                                  });
                                },
                                items: jsonFileMap.keys.map((displayName) {
                                  return DropdownMenuItem(
                                    value: displayName,
                                    child: Text(displayName),
                                  );
                                }).toList(),
                              ),
                              SizedBox(height: 10),
                              TextField(
                                controller: _writeController,
                                decoration: InputDecoration(
                                  labelText: "Text",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text("Cancel"),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                String inputText = _writeController.text;
                                if (selectedKey != null || inputText.isNotEmpty) {
                                  String dataToSend = (inputText.isEmpty)
                                      ? await loadJson(jsonFileMap[selectedKey]!)
                                      : inputText;

                                  Uint8List jsonData = Uint8List.fromList(utf8.encode(dataToSend));
                                  int totalLength = jsonData.length;

                                  int mtu = await characteristic.device.requestMtu(200);
                                  int chunkSize = mtu - 3;
                                  int chunks = (totalLength / chunkSize).ceil();

                                  ByteData magicBytes = ByteData(2);
                                  magicBytes.setUint16(0, 0xCAFE, Endian.little);
                                  print('Number of chunks: $chunks');

                                  ByteData chunkSizeBytes = ByteData(2);
                                  chunkSizeBytes.setUint16(
                                      0, totalLength, Endian.little);
                                  print('Number of chunks: $chunks');

                                  int checksum = Crc32().convert(jsonData).toBigInt().toInt();
                                  Uint8List checksumBytes = Uint8List(4)
                                    ..[3] = (checksum >> 24) & 0xFF
                                    ..[2] = (checksum >> 16) & 0xFF
                                    ..[1] = (checksum >> 8) & 0xFF
                                    ..[0] = checksum & 0xFF;
                                  print('CRC32 checksum: $checksum');

                                  Uint8List firstFrame = Uint8List.fromList([
                                    ...magicBytes.buffer.asUint8List(),
                                    ...chunkSizeBytes.buffer.asUint8List(),
                                    ...checksumBytes
                                  ]);
                                  characteristic.write(firstFrame);

                                  for (int i = 0; i < totalLength; i += chunkSize) {
                                    int end = (i + chunkSize > totalLength)
                                        ? totalLength
                                        : i + chunkSize;
                                    Uint8List chunk = jsonData.sublist(i, end);

                                    characteristic.write(chunk);
                                  }
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text("Please choose a file or input text")),
                                  );
                                }
                              },
                              child: const Text("Send"),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
                // await showDialog(
                //     context: context,
                //     builder: (BuildContext context) {
                //       return AlertDialog(
                //         title: const Text("Write"),
                //         content: Row(
                //           children: <Widget>[
                //             Expanded(
                //               child: TextField(
                //                 controller: _writeController,
                //               ),
                //             ),
                //           ],
                //         ),
                //         actions: <Widget>[
                //           TextButton(
                //             child: const Text("Send"),
                //             onPressed: () async {
                //               Uint8List jsonData = Uint8List.fromList(
                //                   utf8.encode(_writeController.value.text));
                //               int totalLength = jsonData.length;
                //
                //               int mtu =
                //                   await characteristic.device.requestMtu(200);
                //               int chunkSize = mtu - 3;
                //               int chunks = (totalLength / chunkSize).ceil();
                //
                //               ByteData magicBytes = ByteData(2);
                //               magicBytes.setUint16(0, 0xCAFE, Endian.little);
                //               print('Number of chunks: $chunks');
                //
                //               ByteData chunkSizeBytes = ByteData(2);
                //               chunkSizeBytes.setUint16(
                //                   0, totalLength, Endian.little);
                //               print('Number of chunks: $chunks');
                //
                //               int checksum =
                //                   Crc32().convert(jsonData).toBigInt().toInt();
                //               Uint8List checksumBytes = Uint8List(4)
                //                 ..[3] = (checksum >> 24) & 0xFF
                //                 ..[2] = (checksum >> 16) & 0xFF
                //                 ..[1] = (checksum >> 8) & 0xFF
                //                 ..[0] = checksum & 0xFF;
                //               print('CRC32 checksum: $checksum');
                //
                //               Uint8List firstFrame = Uint8List.fromList([
                //                 ...magicBytes.buffer.asUint8List(),
                //                 ...chunkSizeBytes.buffer.asUint8List(),
                //                 ...checksumBytes
                //               ]);
                //               characteristic.write(firstFrame);
                //
                //               for (int i = 0; i < totalLength; i += chunkSize) {
                //                 int end = (i + chunkSize > totalLength)
                //                     ? totalLength
                //                     : i + chunkSize;
                //                 Uint8List chunk = jsonData.sublist(i, end);
                //
                //                 characteristic.write(chunk);
                //               }
                //
                //               Navigator.pop(context);
                //             },
                //           ),
                //           TextButton(
                //             child: const Text("Cancel"),
                //             onPressed: () {
                //               Navigator.pop(context);
                //             },
                //           ),
                //         ],
                //       );
                //     });
              },
            ),
          ),
        ),
      );
    }
    if (characteristic.properties.notify) {
      buttons.add(
        ButtonTheme(
          minWidth: 10,
          height: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ElevatedButton(
              child:
                  const Text('NOTIFY', style: TextStyle(color: Colors.black)),
              onPressed: () async {
                characteristic.lastValueStream.listen((value) {
                  setState(() {
                    widget.readValues[characteristic.uuid] = value;
                  });
                });
                await characteristic
                    .setNotifyValue(!characteristic.isNotifying);
              },
            ),
          ),
        ),
      );
    }

    return buttons;
  }

  ListView _buildConnectDeviceView() {
    List<Widget> containers = <Widget>[];

    for (BluetoothService service in _services) {
      List<Widget> characteristicsWidget = <Widget>[];

      for (BluetoothCharacteristic characteristic in service.characteristics) {
        characteristicsWidget.add(
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(characteristic.uuid.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  children: <Widget>[
                    ..._buildReadWriteNotifyButton(characteristic),
                  ],
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                        child: Text(
                            'Value: ${widget.readValues[characteristic.uuid]}')),
                  ],
                ),
                const Divider(),
              ],
            ),
          ),
        );
      }
      containers.add(
        ExpansionTile(
            title: Text(service.uuid.toString()),
            children: characteristicsWidget),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: <Widget>[
        ...containers,
      ],
    );
  }

  ListView _buildView() {
    if (_connectedDevice != null) {
      return _buildConnectDeviceView();
    }
    return _buildListViewOfDevices();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: _buildView(),
      );
}
