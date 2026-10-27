import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/services/logging/log_service.dart';
import 'package:obdrive/services/sync/bluetooth_sync_service.dart';

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

/// Minimal interface information for in-car network candidate evaluation.
class NetworkInterfaceInfo {
  final String name;
  final List<String> addresses;

  const NetworkInterfaceInfo({
    required this.name,
    required this.addresses,
  });
}

/// Discovered in-car network candidate interface and gateway address.
class InCarGatewayCandidate {
  final String interfaceName;
  final String localAddress;
  final String gatewayAddress;
  final bool isAndroidAutoSubnet;

  const InCarGatewayCandidate({
    required this.interfaceName,
    required this.localAddress,
    required this.gatewayAddress,
    required this.isAndroidAutoSubnet,
  });
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
  static const String prefTargetHostKey = 'sync_pref_custom_target_host';

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

  String? _discoveredTargetHost;
  String? get discoveredTargetHost => _discoveredTargetHost;
  String get activeTargetHost => _discoveredTargetHost ?? _connectedPeerAddress ?? defaultAndroidAutoGateway;

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

  /// Loads any previously saved target host IP from [SharedPreferences].
  Future<void> loadSavedTargetHost() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefTargetHostKey);
      if (saved != null && saved.trim().isNotEmpty) {
        _discoveredTargetHost = saved.trim();
        _safeNotifyListeners();
      }
    } catch (_) {}
  }

  /// Sets and persists a user-specified Headunit target host IP.
  Future<void> setCustomTargetHost(String host) async {
    final clean = host.trim();
    if (clean.isEmpty) return;
    _discoveredTargetHost = clean;
    _safeNotifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefTargetHostKey, clean);
    } catch (_) {}
  }

  /// Discovers active in-car network interfaces and derives the target headunit gateway.
  Future<InCarGatewayCandidate?> discoverInCarGateway({
    List<NetworkInterfaceInfo>? interfaces,
  }) async {
    try {
      if (interfaces == null) {
        final rawInterfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        interfaces = rawInterfaces
            .map((i) => NetworkInterfaceInfo(
                  name: i.name,
                  addresses: i.addresses.map((a) => a.address).toList(),
                ))
            .toList();
      }
      return evaluateInCarCandidates(interfaces);
    } catch (_) {
      return null;
    }
  }

  /// Checks whether two IPv4 addresses belong to the same /24 subnet.
  static bool sharesSubnet(String ip1, String ip2) {
    final p1 = ip1.split('.');
    final p2 = ip2.split('.');
    if (p1.length == 4 && p2.length == 4) {
      return p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2];
    }
    return false;
  }

  /// Evaluates network interface candidates and returns the best in-car gateway candidate.
  static InCarGatewayCandidate? evaluateInCarCandidates(
    List<NetworkInterfaceInfo> interfaces,
  ) {
    // Filter out known cellular modems & VPN tunnels
    final inCarInterfaces = interfaces.where((iface) {
      final name = iface.name.toLowerCase();
      final isCellular = name.startsWith('rmnet') ||
          name.startsWith('ccmni') ||
          name.startsWith('pdp') ||
          name.startsWith('wwan') ||
          name.startsWith('tun') ||
          name.startsWith('dummy');
      return !isCellular;
    }).toList();

    // Sort: p2p (Wi-Fi Direct for AA) and wlan first
    inCarInterfaces.sort((a, b) {
      final aScore = a.name.startsWith('p2p') ? 2 : (a.name.startsWith('wlan') ? 1 : 0);
      final bScore = b.name.startsWith('p2p') ? 2 : (b.name.startsWith('wlan') ? 1 : 0);
      return bScore.compareTo(aScore);
    });

    for (final iface in inCarInterfaces) {
      for (final ip in iface.addresses) {
        if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;

        final parts = ip.split('.');
        if (parts.length == 4) {
          final oct4 = int.tryParse(parts[3]) ?? 0;
          String gateway;
          if (oct4 != 1) {
            gateway = '${parts[0]}.${parts[1]}.${parts[2]}.1';
          } else {
            gateway = '${parts[0]}.${parts[1]}.${parts[2]}.2';
          }

          final isSubnet = ip.startsWith('192.168.43.') ||
              ip.startsWith('192.168.49.') ||
              ip.startsWith('192.168.50.') ||
              iface.name.startsWith('p2p') ||
              iface.name.startsWith('wlan');

          return InCarGatewayCandidate(
            interfaceName: iface.name,
            localAddress: ip,
            gatewayAddress: gateway,
            isAndroidAutoSubnet: isSubnet,
          );
        }
      }
    }
    return null;
  }

  /// Starts the TCP Sync Server on the Headunit.
  Future<bool> startServer({int port = defaultPort}) async {
    await stopServer();
    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
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
      LogService.d('Initial bind failed on port $port ($e), retrying after short backoff...', tag: 'Sync');
      try {
        await Future.delayed(const Duration(milliseconds: 250));
        _serverSocket = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          port,
          shared: true,
        );
        _serverPort = port;
        _isServerRunning = true;
        _lastError = null;
        _safeNotifyListeners();

        LogService.i('NetworkSyncManager server listening on port $port (after retry)', tag: 'Sync');

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
      } catch (retryError) {
        _lastError = 'Failed to bind server on port $port: $retryError';
        _isServerRunning = false;
        _safeNotifyListeners();
        LogService.w(_lastError!, tag: 'Sync');
        return false;
      }
    }
  }

  void _handleIncomingConnection(Socket socket) async {
    LogService.i('Incoming sync connection from ${socket.remoteAddress.address}:${socket.port}', tag: 'Sync');
    _connectedPeerAddress = socket.remoteAddress.address;

    await _activeTransport?.close();
    try {
      _activeClientSocket?.destroy();
    } catch (_) {}

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
    try {
      _activeClientSocket?.destroy();
    } catch (_) {}
    _activeClientSocket = null;
    _connectedPeerAddress = null;

    // Brief yield to allow the OS kernel to release port resources
    await Future.delayed(const Duration(milliseconds: 100));

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

    final candidate = await discoverInCarGateway();
    final effectiveHost = (host != defaultAndroidAutoGateway)
        ? host
        : (_discoveredTargetHost ?? candidate?.gatewayAddress ?? defaultAndroidAutoGateway);
    final sourceAddress = candidate?.localAddress;

    try {
      LogService.i(
        'Connecting to Headunit Sync Server at $effectiveHost:$port (source: ${sourceAddress ?? "any"})...',
        tag: 'Sync',
      );

      Socket socket;
      final useSourceFirst = sourceAddress != null &&
          sourceAddress.isNotEmpty &&
          sharesSubnet(sourceAddress, effectiveHost);

      if (useSourceFirst) {
        try {
          socket = await Socket.connect(
            effectiveHost,
            port,
            sourceAddress: sourceAddress,
            timeout: timeout,
          );
        } catch (sourceErr) {
          LogService.d('Subnet sourceAddress connect failed ($sourceErr), falling back to default route', tag: 'Sync');
          socket = await Socket.connect(effectiveHost, port, timeout: timeout);
        }
      } else {
        try {
          socket = await Socket.connect(effectiveHost, port, timeout: timeout);
        } catch (directErr) {
          if (sourceAddress != null && sourceAddress.isNotEmpty) {
            LogService.d('Direct connect failed ($directErr), retrying with sourceAddress $sourceAddress', tag: 'Sync');
            socket = await Socket.connect(
              effectiveHost,
              port,
              sourceAddress: sourceAddress,
              timeout: timeout,
            );
          } else {
            rethrow;
          }
        }
      }

      _connectedPeerAddress = effectiveHost;
      _discoveredTargetHost = effectiveHost;

      await _activeTransport?.close();
      try {
        _activeClientSocket?.destroy();
      } catch (_) {}

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
      _lastError = 'Connection to $effectiveHost:$port failed: $e';
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

  /// Checks whether any local IPv4 network interface is in an in-car Android Auto subnet.
  Future<bool> isAndroidAutoSubnetActive() async {
    final candidate = await discoverInCarGateway();
    return candidate != null && candidate.isAndroidAutoSubnet;
  }

  /// Helper to probe a single TCP socket endpoint.
  Future<int?> _probeSocketEndpoint(
    String host,
    int port,
    Duration timeout, [
    String? sourceAddress,
  ]) async {
    final sw = Stopwatch()..start();
    Socket? s;
    final useSourceFirst = sourceAddress != null &&
        sourceAddress.isNotEmpty &&
        sharesSubnet(sourceAddress, host);

    try {
      if (useSourceFirst) {
        try {
          s = await Socket.connect(
            host,
            port,
            sourceAddress: sourceAddress,
            timeout: timeout,
          );
        } catch (_) {
          s = await Socket.connect(host, port, timeout: timeout);
        }
      } else {
        try {
          s = await Socket.connect(host, port, timeout: timeout);
        } catch (directErr) {
          if (sourceAddress != null && sourceAddress.isNotEmpty) {
            s = await Socket.connect(
              host,
              port,
              sourceAddress: sourceAddress,
              timeout: timeout,
            );
          } else {
            rethrow;
          }
        }
      }
      sw.stop();
      try {
        await s.close();
      } catch (_) {}
      s.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      try {
        s?.destroy();
      } catch (_) {}
      return null;
    }
  }

  /// Probes TCP reachability of the Headunit server without keeping a socket open.
  /// If [autoProbeFallbacks] is enabled, checks other automotive gateways on failure.
  /// Returns ping latency in milliseconds, or null if unreachable.
  Future<int?> pingHeadunit({
    String host = defaultAndroidAutoGateway,
    int port = defaultPort,
    Duration timeout = const Duration(seconds: 3),
    bool autoProbeFallbacks = true,
  }) async {
    final candidate = await discoverInCarGateway();
    final effectiveHost = (host != defaultAndroidAutoGateway)
        ? host
        : (_discoveredTargetHost ?? candidate?.gatewayAddress ?? defaultAndroidAutoGateway);
    final sourceAddress = candidate?.localAddress;

    // 1. Probe primary target
    final primaryPing = await _probeSocketEndpoint(
      effectiveHost,
      port,
      timeout,
      sourceAddress,
    );
    if (primaryPing != null) {
      _discoveredTargetHost = effectiveHost;
      return primaryPing;
    }

    // 2. If fallback probing is disabled or custom host was explicitly requested, stop here
    if (!autoProbeFallbacks || host != defaultAndroidAutoGateway) {
      return null;
    }

    // 3. Fallback automotive gateway candidates (Hotspot, Wi-Fi Direct, Dongles, Loopback)
    final fallbackCandidates = <String>{
      if (candidate?.gatewayAddress != null) candidate!.gatewayAddress,
      defaultAndroidAutoGateway,
      '192.168.49.1', // Android Auto P2P Wi-Fi Direct GO
      '192.168.50.2', // Carlinkit / AutoKit
      '192.168.50.1', // Alternative dongle gateway
      '127.0.0.1',    // Local test / loopback
    }..remove(effectiveHost);

    for (final fallbackHost in fallbackCandidates) {
      final fallbackPing = await _probeSocketEndpoint(
        fallbackHost,
        port,
        const Duration(milliseconds: 1200),
      );
      if (fallbackPing != null) {
        LogService.i(
          'Discovered Headunit Sync Server on alternative gateway $fallbackHost:$port (${fallbackPing}ms)',
          tag: 'Sync',
        );
        _discoveredTargetHost = fallbackHost;
        _safeNotifyListeners();
        return fallbackPing;
      }
    }

    return null;
  }

  /// Runs the 4-step link self-test from the Phone Companion perspective:
  /// 1. Phone Wi-Fi enabled check
  /// 2. In-car Android Auto subnet check (192.168.43.x, 192.168.49.x, etc.)
  /// 3. Headunit Socket Ping (port 7355) with source address binding and automotive gateway probe
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

    // 2. In-Car Android Auto Subnet & Gateway Discovery
    final ifaceInfos = interfaces
        .map((i) => NetworkInterfaceInfo(
              name: i.name,
              addresses: i.addresses.map((a) => a.address).toList(),
            ))
        .toList();
    final candidate = await discoverInCarGateway(interfaces: ifaceInfos);
    final effectiveHost = (host != defaultAndroidAutoGateway)
        ? host
        : (_discoveredTargetHost ?? candidate?.gatewayAddress ?? defaultAndroidAutoGateway);

    if (candidate != null && candidate.isAndroidAutoSubnet) {
      results.add(LinkStepResult(
        step: LinkSelfTestStep.androidAutoSubnet,
        status: LinkStepStatus.passed,
        title: 'Android Auto Subnet',
        details: 'Connected on ${candidate.interfaceName} (${candidate.localAddress}). Target gateway: $effectiveHost.',
      ));
    } else {
      results.add(LinkStepResult(
        step: LinkSelfTestStep.androidAutoSubnet,
        status: LinkStepStatus.warning,
        title: 'Android Auto Subnet',
        details: 'Phone is not on recognized in-car subnet (Current: ${localIps.first}). Targeting gateway $effectiveHost.',
      ));
    }

    // 3. Headunit Socket Ping with multi-gateway probe
    final ping = await pingHeadunit(
      host: effectiveHost,
      port: port,
      autoProbeFallbacks: true,
    );
    final resolvedHost = _discoveredTargetHost ?? effectiveHost;

    if (ping != null) {
      results.add(LinkStepResult(
        step: LinkSelfTestStep.headunitSocketPing,
        status: LinkStepStatus.passed,
        title: 'Headunit Socket Ping',
        details: 'Headunit server at $resolvedHost:$port responded in ${ping}ms.',
        pingMs: ping,
      ));
    } else {
      final probedHosts = <String>{
        effectiveHost,
        if (candidate?.gatewayAddress != null) candidate!.gatewayAddress,
        defaultAndroidAutoGateway,
        '192.168.49.1',
      }.join(', ');

      results.add(LinkStepResult(
        step: LinkSelfTestStep.headunitSocketPing,
        status: LinkStepStatus.failed,
        title: 'Headunit Socket Ping',
        details: 'Cannot reach Headunit server on port $port (probed: $probedHosts). Socket connection timed out.',
      ));
      diagnosticTip = 'Headunit OBDrive server may be asleep (ignition off) or on a different IP. Verify "Server Listening" on Headunit screen.';
      return LinkSelfTestReport(
        steps: results,
        timestamp: DateTime.now(),
        overallSuccess: false,
        diagnosticTip: diagnosticTip,
      );
    }

    // Brief pause between ping close and handshake connect to allow headunit server socket transition
    await Future.delayed(const Duration(milliseconds: 150));

    // 4. Protocol Handshake & State
    final connected = await connectToHeadunit(host: resolvedHost, port: port);
    if (connected) {
      results.add(const LinkStepResult(
        step: LinkSelfTestStep.protocolHandshake,
        status: LinkStepStatus.passed,
        title: 'Protocol Handshake & Status',
        details: 'OBDrive v2 frame handshake verified. Headunit is awake and synchronized.',
      ));
    } else {
      results.add(LinkStepResult(
        step: LinkSelfTestStep.protocolHandshake,
        status: LinkStepStatus.failed,
        title: 'Protocol Handshake & Status',
        details: 'Failed to complete protocol handshake: ${_lastError ?? "Unknown error"}',
      ));
      diagnosticTip = 'Handshake failed. Check if another client is connected or restart Headunit OBDrive.';
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

    final candidate = await discoverInCarGateway();
    final effectiveHost = (host != defaultAndroidAutoGateway)
        ? host
        : (_discoveredTargetHost ?? candidate?.gatewayAddress ?? defaultAndroidAutoGateway);

    // Attempt 1: Connect to Headunit
    bool connected = await connectToHeadunit(
      host: effectiveHost,
      port: port,
      timeout: const Duration(seconds: 4),
    );

    if (!connected) {
      // Retry once after 2-second boot delay in case headunit service was starting
      await Future.delayed(retryDelay);
      connected = await connectToHeadunit(
        host: effectiveHost,
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
