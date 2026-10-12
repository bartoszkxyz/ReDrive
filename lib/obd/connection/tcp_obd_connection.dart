import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:redrive/obd/connection/obd_connection.dart';

/// Implements [ObdConnection] over TCP sockets.
///
/// Used for connecting to ELM327 Wi-Fi adapters and desktop emulators
/// such as the ELM327-Emulator.
class TcpObdConnection implements ObdConnection {
  final String host;
  final int port;

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;

  final _incomingController = StreamController<String>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _reconnectingStateController = StreamController<bool>.broadcast();

  bool _isConnected = false;
  bool _isReconnecting = false;

  TcpObdConnection({
    this.host = '127.0.0.1',
    this.port = 35000,
  });

  @override
  Stream<String> get incoming => _incomingController.stream;

  @override
  Stream<bool> get connectionState => _connectionStateController.stream;

  @override
  Stream<bool> get reconnectingState => _reconnectingStateController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  bool get isReconnecting => _isReconnecting;

  void _setConnected(bool state) {
    if (_isConnected == state) return;
    _isConnected = state;
    _connectionStateController.add(state);
  }

  void _setReconnecting(bool state) {
    if (_isReconnecting == state) return;
    _isReconnecting = state;
    _reconnectingStateController.add(state);
  }

  Future<bool> connect() async {
    if (_isConnected) return true;

    try {
      developer.log("Connecting to TCP $host:$port...", name: 'TcpObd');
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      _setConnected(true);
      _setReconnecting(false);

      _subscription = _socket!.listen(
        (Uint8List data) {
          final text = String.fromCharCodes(data);
          developer.log("⬅️ RX: $text", name: 'TcpObd');
          _incomingController.add(text);
        },
        onError: (e) {
          developer.log("Socket error: $e", name: 'TcpObd', error: e);
          disconnect();
        },
        onDone: () {
          developer.log("Socket closed (onDone)", name: 'TcpObd');
          disconnect();
        },
        cancelOnError: true,
      );

      return true;
    } catch (e) {
      developer.log("Failed to connect to TCP $host:$port: $e", name: 'TcpObd', error: e);
      _setConnected(false);
      return false;
    }
  }

  @override
  Future<void> send(String command) async {
    if (!_isConnected || _socket == null) return;
    try {
      final cmd = command.endsWith('\r') ? command : '$command\r';
      developer.log("➡️ TX: ${cmd.trim()}", name: 'TcpObd');
      _socket!.add(Uint8List.fromList(cmd.codeUnits));
      await _socket!.flush();
    } catch (e) {
      developer.log("Send error: $e", name: 'TcpObd', error: e);
    }
  }

  @override
  Future<void> reconnect() async {
    _setReconnecting(true);
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 1000));
    await connect();
  }

  @override
  Future<void> disconnect() async {
    try {
      await _subscription?.cancel();
      _subscription = null;
      await _socket?.close();
      _socket = null;
    } catch (_) {}

    _setConnected(false);
    _setReconnecting(false);
  }

  void dispose() {
    disconnect();
    _incomingController.close();
    _connectionStateController.close();
    _reconnectingStateController.close();
  }
}
