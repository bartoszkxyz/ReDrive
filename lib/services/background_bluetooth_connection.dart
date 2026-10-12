import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:redrive/obd/connection/obd_connection.dart';

class BackgroundBluetoothConnection implements ObdConnection {
  final BluetoothConnection _connection;
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();

  BackgroundBluetoothConnection(this._connection) {
    _connectionStateController.add(true);
  }

  @override
  Stream<bool> get connectionState => _connectionStateController.stream;

  @override
  Stream<String> get incoming => _connection.input!.map((data) => String.fromCharCodes(data));

  @override
  bool get isConnected => _connection.isConnected;

  @override
  bool get isReconnecting => false;

  @override
  Stream<bool> get reconnectingState => const Stream.empty();

  @override
  Future<void> send(String command) async {
    _connection.output.add(Uint8List.fromList('$command\r'.codeUnits));
    await _connection.output.allSent;
  }

  @override
  Future<void> reconnect() async {
    // Simple implementation
  }

  @override
  Future<void> disconnect() async {
    _connection.dispose();
    _connectionStateController.add(false);
  }
}
