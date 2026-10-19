import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:redrive/services/logging/log_service.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';

/// Concrete [SyncTransport] implementation wrapping a standard bidirectional TCP [Socket].
///
/// Designed to operate over the local Wi-Fi link established by Android Auto / CarLink
/// (or shared local vehicle hotspot) without competing with the ELM327 adapter for
/// the single Bluetooth SPP channel on Chinese Android headunits (Topway TS18).
class SocketSyncTransport implements SyncTransport {
  final Socket _socket;
  final StreamController<List<int>> _inbound = StreamController<List<int>>.broadcast();
  bool _closed = false;

  SocketSyncTransport(this._socket) {
    _socket.listen(
      (Uint8List data) {
        if (!_closed) {
          _inbound.add(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        LogService.w('SocketSyncTransport error: $error', tag: 'Sync');
        if (!_closed) {
          _inbound.addError(error, stackTrace);
        }
      },
      onDone: () {
        close();
      },
      cancelOnError: false,
    );
  }

  @override
  Stream<List<int>> get inboundBytes => _inbound.stream;

  @override
  void sendBytes(List<int> bytes) {
    if (!_closed) {
      try {
        _socket.add(bytes);
      } catch (e) {
        LogService.w('SocketSyncTransport send error: $e', tag: 'Sync');
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _inbound.close();
    } catch (_) {}
    try {
      await _socket.flush();
      await _socket.close();
      _socket.destroy();
    } catch (_) {}
  }
}

/// Individual verification steps for the 4-step link self-test.
enum LinkSelfTestStep {
  wifiEnabled,
  androidAutoSubnet,
  headunitSocketPing,
  protocolHandshake,
}

/// Status of an individual self-test check.
enum LinkStepStatus {
  pending,
  running,
  passed,
  failed,
  warning,
}

/// Result of an individual self-test verification step.
class LinkStepResult {
  final LinkSelfTestStep step;
  final LinkStepStatus status;
  final String title;
  final String details;
  final int? pingMs;

  const LinkStepResult({
    required this.step,
    required this.status,
    required this.title,
    required this.details,
    this.pingMs,
  });
}

/// Comprehensive report containing all 4 self-test results and an actionable diagnostic tip.
class LinkSelfTestReport {
  final List<LinkStepResult> steps;
  final DateTime timestamp;
  final bool overallSuccess;
  final String? diagnosticTip;

  const LinkSelfTestReport({
    required this.steps,
    required this.timestamp,
    required this.overallSuccess,
    this.diagnosticTip,
  });
}

/// Orchestrates local TCP network synchronization between the Headunit server
/// and Phone Companion client.
class NetworkSyncManager extends ChangeNotifier {
  static const int defaultPort = 7355;
  static const String defaultAndroidAutoGateway = '192.168.43.1';

  final BluetoothSyncService syncService;
  final bool isHeadunit;

  ServerSocket? _serverSocket;
  Socket? _activeClientSocket;
  SocketSyncTransport? _activeTransport;

  bool _isServerRunning = false;
  bool get isServerRunning => _isServerRunning;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  int _serverPort = defaultPort;
  int get serverPort => _serverPort;

  String? _lastError;
  String? get lastError => _lastError;

  String? _connectedPeerAddress;
  String? get connectedPeerAddress => _connectedPeerAddress;

  NetworkSyncManager({
    required this.syncService,
    required this.isHeadunit,
  });

  bool _isDisposed = false;

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Starts the TCP Sync Server on the Headunit.
  Future<bool> startServer({int port = defaultPort}) async {
    await stopServer();
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverPort = port;
      _isServerRunning = true;
      _lastError = null;
      _safeNotifyListeners();

      LogService.i('NetworkSyncManager server listening on port $port', tag: 'Sync');

      _serverSocket!.listen(
        _handleIncomingConnection,
        onError: (Object error) {
          _lastError = 'Server error: $error';
          _isServerRunning = false;
          _safeNotifyListeners();
          LogService.e('NetworkSyncManager server listen error', tag: 'Sync', error: error);
        },
        onDone: () {
          _isServerRunning = false;
          _safeNotifyListeners();
        },
      );
      return true;
    } catch (e) {
      _lastError = 'Failed to bind server on port $port: $e';
      _isServerRunning = false;
      _safeNotifyListeners();
      LogService.w(_lastError!, tag: 'Sync');
      return false;
    }
  }

  void _handleIncomingConnection(Socket socket) async {
    LogService.i('Incoming sync connection from ${socket.remoteAddress.address}:${socket.port}', tag: 'Sync');
    _connectedPeerAddress = socket.remoteAddress.address;

    await _activeTransport?.close();
    _activeClientSocket?.destroy();

    _activeClientSocket = socket;
    final transport = SocketSyncTransport(socket);
    _activeTransport = transport;

    // Attach transport to the sync service (Headunit server waits for peer hello)
    await syncService.attachTransport(transport, initiateHandshake: false);
    _safeNotifyListeners();
  }

  /// Stops the TCP Sync Server.
  Future<void> stopServer() async {
    _isServerRunning = false;
    try {
      await _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;

    await _activeTransport?.close();
    _activeTransport = null;
    _activeClientSocket?.destroy();
    _activeClientSocket = null;
    _connectedPeerAddress = null;

    _safeNotifyListeners();
  }

  /// Connects to the Headunit TCP Sync Server from the Phone Companion.
  Future<bool> connectToHeadunit({
    String host = defaultAndroidAutoGateway,
    int port = defaultPort,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_isConnecting) return false;

    _isConnecting = true;
    _lastError = null;
    _safeNotifyListeners();

    try {
      LogService.i('Connecting to Headunit Sync Server at $host:$port...', tag: 'Sync');
      final socket = await Socket.connect(host, port, timeout: timeout);
      _connectedPeerAddress = host;

      await _activeTransport?.close();
      _activeClientSocket?.destroy();

      _activeClientSocket = socket;
      final transport = SocketSyncTransport(socket);
      _activeTransport = transport;

      // Attach transport and initiate handshake from Phone Companion
      await syncService.attachTransport(transport, initiateHandshake: true);

      _isConnecting = false;
      _safeNotifyListeners();
      return true;
    } catch (e) {
      _isConnecting = false;
      _lastError = 'Connection to $host:$port failed: $e';
      _safeNotifyListeners();
      LogService.w(_lastError!, tag: 'Sync');
      return false;
    }
  }

  /// Retrieves list of local IPv4 network addresses (e.g. Wi-Fi hotspot address).
  Future<List<String>> getLocalIpAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          ips.add('${addr.address} (${iface.name})');
        }
      }
      return ips;
    } catch (_) {
      return [];
    }
  }

  /// Checks whether any local IPv4 network interface is in the Android Auto hotspot subnet (192.168.43.x).
  Future<bool> isAndroidAutoSubnetActive() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.43.')) {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Probes TCP reachability of the Headunit server without keeping a socket open.
  /// Returns ping latency in milliseconds, or null if unreachable.
  Future<int?> pingHeadunit({
    String host = defaultAndroidAutoGateway,
    int port = defaultPort,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      s.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// Runs the 4-step link self-test from the Phone Companion perspective:
  /// 1. Phone Wi-Fi enabled check
  /// 2. In-car Android Auto subnet check (192.168.43.x)
  /// 3. Headunit Socket Ping (port 7355)
  /// 4. Protocol handshake & Headunit status
  Future<LinkSelfTestReport> runLinkSelfTest({
    String host = defaultAndroidAutoGateway,
    int port = defaultPort,
  }) async {
    final results = <LinkStepResult>[];
    String? diagnosticTip;

    // 1. Phone Wi-Fi / Local Interface check
    List<NetworkInterface> interfaces = [];
    try {
      interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
    } catch (_) {}

    if (interfaces.isEmpty) {
      results.add(const LinkStepResult(
        step: LinkSelfTestStep.wifiEnabled,
        status: LinkStepStatus.failed,
        title: 'Phone Wi-Fi State',
        details: 'No active local network interfaces found. Wi-Fi may be disabled.',
      ));
      diagnosticTip = 'Enable Wi-Fi on your phone and connect to Android Auto or your car hotspot.';
      return LinkSelfTestReport(
        steps: results,
        timestamp: DateTime.now(),
        overallSuccess: false,
        diagnosticTip: diagnosticTip,
      );
    }

    final localIps = interfaces
        .expand((i) => i.addresses.map((a) => '${a.address} (${i.name})'))
        .toList();
    results.add(LinkStepResult(
      step: LinkSelfTestStep.wifiEnabled,
      status: LinkStepStatus.passed,
      title: 'Phone Wi-Fi State',
      details: 'Active interface(s): ${localIps.join(", ")}',
    ));

    // 2. Android Auto Subnet check
    final hasSubnet = localIps.any((ip) => ip.startsWith('192.168.43.'));
    if (hasSubnet) {
      results.add(const LinkStepResult(
        step: LinkSelfTestStep.androidAutoSubnet,
        status: LinkStepStatus.passed,
        title: 'Android Auto Subnet',
        details: 'Connected to in-car Android Auto hotspot subnet (192.168.43.x).',
      ));
    } else {
      results.add(LinkStepResult(
        step: LinkSelfTestStep.androidAutoSubnet,
        status: LinkStepStatus.warning,
        title: 'Android Auto Subnet',
        details: 'Phone is not on 192.168.43.x (Current: ${localIps.first}). Targeting gateway $host.',
      ));
    }

    // 3. Headunit Socket Ping
    final ping = await pingHeadunit(host: host, port: port);
    if (ping != null) {
      results.add(LinkStepResult(
        step: LinkSelfTestStep.headunitSocketPing,
        status: LinkStepStatus.passed,
        title: 'Headunit Socket Ping',
        details: 'Headunit server at $host:$port responded in ${ping}ms.',
        pingMs: ping,
      ));
    } else {
      results.add(LinkStepResult(
        step: LinkSelfTestStep.headunitSocketPing,
        status: LinkStepStatus.failed,
        title: 'Headunit Socket Ping',
        details: 'Cannot reach Headunit server at $host:$port. Socket connection timed out.',
      ));
      diagnosticTip = 'Headunit ReDrive service may be asleep (ignition off) or Android Auto Wi-Fi disconnected.';
      return LinkSelfTestReport(
        steps: results,
        timestamp: DateTime.now(),
        overallSuccess: false,
        diagnosticTip: diagnosticTip,
      );
    }

    // 4. Protocol Handshake & State
    final connected = await connectToHeadunit(host: host, port: port);
    if (connected) {
      results.add(const LinkStepResult(
        step: LinkSelfTestStep.protocolHandshake,
        status: LinkStepStatus.passed,
        title: 'Protocol Handshake & Status',
        details: 'ReDrive v2 frame handshake verified. Headunit is awake and synchronized.',
      ));
    } else {
      results.add(LinkStepResult(
        step: LinkSelfTestStep.protocolHandshake,
        status: LinkStepStatus.failed,
        title: 'Protocol Handshake & Status',
        details: 'Failed to complete protocol handshake: ${_lastError ?? "Unknown error"}',
      ));
      diagnosticTip = 'Handshake failed. Check if another client is connected or restart Headunit ReDrive.';
      return LinkSelfTestReport(
        steps: results,
        timestamp: DateTime.now(),
        overallSuccess: false,
        diagnosticTip: diagnosticTip,
      );
    }

    return LinkSelfTestReport(
      steps: results,
      timestamp: DateTime.now(),
      overallSuccess: true,
      diagnosticTip: 'All checks passed! Direct Android Auto link is operational.',
    );
  }

  /// Connects and triggers sync with 15s total budget and a single 2s retry.
  Future<bool> smartSyncWithHeadunit({
    String host = defaultAndroidAutoGateway,
    int port = defaultPort,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    // If transport is already active and healthy, trigger sync directly
    if (syncService.state == SyncConnectionState.connected ||
        syncService.state == SyncConnectionState.synced) {
      await syncService.startSyncSession();
      return true;
    }

    // Attempt 1: Connect to Headunit
    bool connected = await connectToHeadunit(
      host: host,
      port: port,
      timeout: const Duration(seconds: 3),
    );

    if (!connected) {
      // Retry once after 2-second boot delay in case headunit service was starting
      await Future.delayed(retryDelay);
      connected = await connectToHeadunit(
        host: host,
        port: port,
        timeout: const Duration(seconds: 4),
      );
    }

    if (connected) {
      await syncService.startSyncSession();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isServerRunning = false;
    try {
      _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;

    try {
      _activeTransport?.close();
    } catch (_) {}
    _activeTransport = null;

    try {
      _activeClientSocket?.destroy();
    } catch (_) {}
    _activeClientSocket = null;
    _connectedPeerAddress = null;

    super.dispose();
  }
}
