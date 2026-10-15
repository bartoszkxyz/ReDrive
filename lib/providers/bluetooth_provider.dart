import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:redrive/services/bluetooth/models/bluetooth_status.dart';
import 'package:redrive/services/bluetooth/permissions/bluetooth_permission_service.dart';
import 'package:redrive/services/bluetooth/models/bluetooth_obd_device.dart';
import 'package:redrive/services/settings/app_preferences.dart';
import 'package:redrive/services/logging/log_service.dart';

/// [BluetoothProvider] — центральный узел управления Classic Bluetooth (SPP).
///
/// Обеспечивает жизненный цикл соединений: от сканирования до обмена данными.
/// Реализует защиту от race conditions с помощью системы уникальных ID вызовов.
class BluetoothProvider extends ChangeNotifier {
  final FlutterBlueClassic _bluetooth = FlutterBlueClassic();

  /// сканируется ?
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  /// подключается ?
  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  BluetoothObdDevice? _connectedDevice;
  BluetoothObdDevice? get connectedDevice => _connectedDevice;

  final List<BluetoothObdDevice> _discoveredDevices = [];
  List<BluetoothObdDevice> get discoveredDevices => _discoveredDevices;

  final Map<String, BluetoothDevice> _deviceMap = {};

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSubscription;
  StreamSubscription<BluetoothDevice>? _scanSubscription;

  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionStateController.stream;

  final _reconnectingStateController = StreamController<bool>.broadcast();
  Stream<bool> get reconnectingState => _reconnectingStateController.stream;

  // === ТРУБА ДЛЯ ДАННЫХ ===
  // Через этот стрим ObdProvider будет получать ответы
  final _rxController = StreamController<String>.broadcast();
  Stream<String> get rxStream => _rxController.stream;

  /// отвечает за подключение, где айдишник отвечает
  /// за подключение, если пользовтель нажмёт отмену,
  /// и начнёт подключаться к другому, под капотомо
  /// оно может ещё грузиться и если айдишник не = айди вызова
  /// подключения на тот момент, то ничего не произойдёт
  int _connectionId = 0;

  /// вывод статусы подключения в loader
  /// при попытке подключения к устройству
  String _connectionMessage = "";
  String get connectionMessage => _connectionMessage;

  String _backgroundMessage = "";
  String get backgroundMessage => _backgroundMessage;

  bool _isReconnectingBackground = false;
  bool get isReconnectingBackground => _isReconnectingBackground;

  static const Duration _quickDropWindow = Duration(seconds: 15);
  static const int _maxQuickDrops = 3;

  DateTime? _lastReconnectSuccessAt;
  int _quickDrops = 0;

  Timer? _scanTimer;

  bool _isHardwareOn = false;
  bool get isHardwareOn => _isHardwareOn;

  bool _isToggleOn = false;
  bool get isToggleOn => _isToggleOn;

  bool _pendingScan = false;

  void _log(String message, {LogLevel level = LogLevel.info, Object? error, StackTrace? stackTrace}) {
    LogService.log(message, level: level, tag: 'Bluetooth', error: error, stackTrace: stackTrace);
  }

  void _setConnected(bool state) {
    if (_isConnected == state) return;

    _isConnected = state;
    _connectionStateController.add(state);
  }

  void _setReconnecting(bool state) {
    if (_isReconnectingBackground == state) return;

    _isReconnectingBackground = state;
    _reconnectingStateController.add(state);
  }

  /// =подписка на состояние Bluetooth адаптера системы
  BluetoothProvider() {
    _bluetooth.adapterStateNow.then((BluetoothAdapterState state) {
      _isHardwareOn = state == BluetoothAdapterState.on;
      notifyListeners();
      if (_isHardwareOn) {
        autoConnectLastDevice();
      }
    }).catchError((_) {
      // Platform does not support classic bluetooth (e.g. Linux desktop preview)
    });

    _bluetooth.adapterState.listen((BluetoothAdapterState state) {
      _isHardwareOn = state == BluetoothAdapterState.on;

      if (state == BluetoothAdapterState.off) {
        _log("⚠️ Bluetooth turned OFF", level: LogLevel.warning);
        _isToggleOn = false;
        disconnect();
        _stopScan();
        _discoveredDevices.clear();
        _deviceMap.clear();
      } else if (state == BluetoothAdapterState.on) {
        _log("✅ Bluetooth turned ON");
        if (_pendingScan) {
          _pendingScan = false;
          startScan();
        } else {
          autoConnectLastDevice();
        }
      }
      notifyListeners();
    }, onError: (_) {
      // Ignored on non-supported platforms
    });
  }

  /// Добавляет новое устройство в список, фильтруя дубликаты
  void _addDeviceToList(BluetoothDevice device, {bool connected = false}) {
    if (_deviceMap.containsKey(device.address)) return;

    _deviceMap[device.address] = device;
    _discoveredDevices.add(
      BluetoothObdDevice(
        name: device.name ?? "Неизвестное устройство",
        address: device.address,
        isBle: false,
      ),
    );
  }

  /// Сканирование блютуз в округе

  Future<BluetoothScanResult> startScan() async {
    if (_isScanning) return BluetoothScanResult.started;

    _log("Requesting Bluetooth permissions...");
    final permissionStatus = await requestBluetoothPermissions();

    if (permissionStatus == BluetoothPermissionStatus.permanentlyDenied) {
      _log("Bluetooth permissions permanently denied", level: LogLevel.warning);
      return BluetoothScanResult.permanentlyDenied;
    }

    if (permissionStatus != BluetoothPermissionStatus.granted) {
      _log("Bluetooth permissions not granted", level: LogLevel.warning);
      _isScanning = false;
      notifyListeners();
      return BluetoothScanResult.notStarted;
    }

    if (!_isHardwareOn) {
      _pendingScan = true;
      try {
        _bluetooth.turnOn();
      } catch (e) {
        _log("Failed to turn on Bluetooth: $e", level: LogLevel.error, error: e);
      }
      return BluetoothScanResult.notStarted;
    }

    _isToggleOn = true;
    _isScanning = true;
    _pendingScan = false;

    final activePhysicalDevice = (_isConnected && _connectedDevice != null)
        ? _deviceMap[_connectedDevice!.address]
        : null;

    _discoveredDevices.clear();
    _deviceMap.clear();

    if (activePhysicalDevice != null && _connectedDevice != null) {
      _deviceMap[activePhysicalDevice.address] = activePhysicalDevice;
      _discoveredDevices.add(_connectedDevice!);
    }

    notifyListeners();

    try {
      try {
        final bonded = await _bluetooth.bondedDevices;
        if (bonded != null) {
          for (final device in bonded) {
            _addDeviceToList(device);
          }
        }
      } catch (e) {
        _log("Failed to get bonded devices: $e", level: LogLevel.warning, error: e);
      }

      notifyListeners();

      _bluetooth.startScan();
      _log("Bluetooth discovery scan started");

      await _scanSubscription?.cancel();
      _scanSubscription = _bluetooth.scanResults.listen(
        (BluetoothDevice device) {
          if (!_deviceMap.containsKey(device.address)) {
            _addDeviceToList(
              device,
              connected: _connectedDevice?.address == device.address,
            );
            notifyListeners();
          }
        },
        onError: (err) {
          _log("Error in Bluetooth scan stream", level: LogLevel.error, error: err);
          _stopScan();
        },
      );

      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 15), () {
        if (_isScanning) {
          _log("Scan timer: 15s elapsed, auto-stopping scan");
          _stopScan();
        }
      });
    } catch (e) {
      _log("Scan error: $e", level: LogLevel.error, error: e);
      _isScanning = false;
      notifyListeners();
      return BluetoothScanResult.notStarted;
    }

    return BluetoothScanResult.started;
  }

  /// Останавливает сканирование и сбрасывает связанные таймеры и подписки
  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    _bluetooth.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    notifyListeners();
    _log("Bluetooth scan stopped");
  }

  /// Основной метод подключения к OBD2
  Future<bool> connectToDevice(BluetoothObdDevice device) async {
    if (_isConnected && _connectedDevice?.address == device.address) {
      return true;
    }
    if (_isConnecting) return false;

    _connectionId++;
    final int currentId = _connectionId;

    _setReconnecting(false);

    _isConnecting = true;
    _connectionMessage = "Connecting to ${device.name}...";

    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 500));

    await disconnect();

    // Verify process after closing old socket
    if (currentId != _connectionId) return false;

    final targetAddress = device.address;
    for (int i = 1; i <= 3; i++) {
      try {
        _log("Connection attempt to ${device.name} ($targetAddress) #$i");

        try {
          await _bluetooth.bondDevice(targetAddress);
        } catch (_) {}

        if (currentId != _connectionId) return false;

        if (i > 1) {
          _connectionMessage = "Connection attempt #${i - 1}";
        } else {
          _connectionMessage = "Exchanging data...";
        }
        notifyListeners();

        final newSocket = await _bluetooth
            .connect(targetAddress)
            .timeout(const Duration(seconds: 5));

        // если id изменился, закрываем новый сокет и выходим
        if (currentId != _connectionId) {
          _log("Connection canceled after connect", level: LogLevel.warning);
          await newSocket?.finish();
          return false;
        }

        // Brief delay for adapter UART stabilization
        await Future.delayed(const Duration(milliseconds: 300));
        if (currentId != _connectionId) {
          await newSocket?.finish();
          return false;
        }

        _connection = newSocket;
        _connectedDevice = device;
        _quickDrops = 0;
        _lastReconnectSuccessAt = null;
        _setConnected(true);
        _setupListen();

        _discoveredDevices.removeWhere((d) => d.address == device.address);
        _discoveredDevices.insert(0, device);

        _log("✅ Successfully connected to ${device.name}");
        unawaited(AppPreferences.saveLastConnectedDevice(
          mac: device.address,
          name: device.name,
        ));
        if (currentId == _connectionId) {
          _isConnecting = false;
        }
        notifyListeners();
        return true;
      } catch (e) {
        _log("❌ Connection error to ${device.name}: $e", level: LogLevel.error, error: e);

        if (currentId != _connectionId) return false;
        if (i < 3) {
          await Future.delayed(const Duration(milliseconds: 2000));
        } else {
          _setConnected(false);
          _connectedDevice = null;
          _isConnecting = false;
          notifyListeners();
          return false;
        }
      }
    }

    _isConnecting = false;
    notifyListeners();
    return false;
  }

  /// Automatically connects to the most recently used OBD adapter on startup/ignition
  /// with a settle delay and silent retry loop.
  Future<bool> autoConnectLastDevice({
    int maxAttempts = 10,
    Duration settleDelay = const Duration(milliseconds: 2500),
    Duration retryDelay = const Duration(seconds: 3),
  }) async {
    final isEnabled = await AppPreferences.isAutoConnectEnabled();
    if (!isEnabled) return false;

    final lastMac = await AppPreferences.getLastObdMac();
    if (lastMac == null || lastMac.isEmpty) return false;

    if (_isConnected || _isConnecting) return true;

    final lastName = await AppPreferences.getLastObdName() ?? "OBD Adapter";
    _log("🚗 Headunit Auto-Connect initiated for $lastName ($lastMac). Settling for voltage & adapter boot...");

    // 1. Initial stabilization delay for adapter boot & vehicle starter motor voltage dip
    if (settleDelay > Duration.zero) {
      await Future.delayed(settleDelay);
    }

    if (_isConnected) return true;

    final targetDevice = BluetoothObdDevice(
      name: lastName,
      address: lastMac,
      isBle: false,
    );

    // 2. Retry loop up to maxAttempts
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_isConnected) return true;

      _log("🚗 Headunit Auto-Connect attempt #$attempt of $maxAttempts to $lastName ($lastMac)...");
      _setReconnecting(true);
      _connectionMessage = "Connecting to $lastName ($attempt/$maxAttempts)...";
      notifyListeners();

      try {
        final bondedList = await _bluetooth.bondedDevices;
        if (bondedList != null) {
          for (final b in bondedList) {
            _deviceMap[b.address] = b;
            if (b.address.toLowerCase() == lastMac.toLowerCase()) {
              _deviceMap[lastMac] = b;
            }
          }
        }
      } catch (e) {
        _log("Failed to query bonded devices during auto-connect: $e", level: LogLevel.warning, error: e);
      }

      final success = await connectToDevice(targetDevice);
      if (success && _isConnected) {
        _setReconnecting(false);
        _log("✅ Headunit Auto-Connect succeeded on attempt #$attempt");
        return true;
      }

      if (attempt < maxAttempts) {
        await Future.delayed(retryDelay);
      }
    }

    _setReconnecting(false);
    _log("⚠️ Headunit Auto-Connect completed all $maxAttempts attempts without connection", level: LogLevel.warning);
    return false;
  }

  /// Настраивает прослушивание входного потока данных от обд сканера
  void _setupListen() {
    _inputSubscription = _connection!.input!.listen(
      (Uint8List data) {
        final incoming = String.fromCharCodes(data);
        _rxController.add(incoming);
      },
      onDone: () {
        _log("Data stream closed (onDone)", level: LogLevel.warning);
        disconnect(isIntentional: false);
      },
      onError: (e) {
        _log("Data stream error: $e", level: LogLevel.error, error: e);
        disconnect(isIntentional: false);
      },
      cancelOnError: true,
    );
  }

  void sendCommand(String command) {
    if (!_isConnected || _connection == null) return;

    try {
      // Команда превращается в байты и отправляется в сокет.
      // '\r' в конце — это стандарт ELM327 (как нажатие Enter).
      // Предотвращаем дублирование \r, если команда уже содержит перевод строки.
      final cmd = command.endsWith('\r') ? command : '$command\r';
      _connection!.output.add(Uint8List.fromList(cmd.codeUnits));
      _log("➡️ TX: ${cmd.trim()}", level: LogLevel.debug);
    } catch (e) {
      _log("❌ Command sending error: $e", level: LogLevel.error, error: e);
    }
  }

  /// Closes connection and releases resources
  Future<void> disconnect({bool isIntentional = true}) async {
    try {
      await _inputSubscription?.cancel();
      await _connection?.finish();
      _connection = null;
      _log("Bluetooth connection closed");
    } catch (e) {
      _log("Error disconnecting: $e", level: LogLevel.warning, error: e);
    }

    if (isIntentional) {
      _quickDrops = 0;
      _lastReconnectSuccessAt = null;
      _setConnected(false);
      _connectedDevice = null;
      _isConnecting = false;
      notifyListeners();
    } else {
      _startBackgroundReconnect();
    }
  }

  Future<void> _startBackgroundReconnect() async {
    if (_connectedDevice == null || _isReconnectingBackground) return;

    final lastSuccessAt = _lastReconnectSuccessAt;
    final isQuickDrop =
        lastSuccessAt != null &&
        DateTime.now().difference(lastSuccessAt) < _quickDropWindow;
    _quickDrops = isQuickDrop ? _quickDrops + 1 : 0;

    if (_quickDrops >= _maxQuickDrops) {
      _log("Connection drops immediately after reconnecting, giving up", level: LogLevel.warning);
      await disconnect();
      return;
    }

    _connectionId++;
    final int currentId = _connectionId;

    _setReconnecting(true);
    _backgroundMessage = "Reconnecting...";
    notifyListeners();

    final targetAddress = _connectedDevice!.address;

    for (int i = 1; i <= 3; i++) {
      try {
        await Future.delayed(const Duration(milliseconds: 4000));

        if (currentId != _connectionId) {
          _setReconnecting(false);
          notifyListeners();
          return;
        }
        _backgroundMessage = "Reconnecting... #$i";
        notifyListeners();

        final oldSocket = await _bluetooth
            .connect(targetAddress)
            .timeout(const Duration(seconds: 5));

        if (currentId != _connectionId) {
          await oldSocket?.finish();
          _setReconnecting(false);
          notifyListeners();
          return;
        }

        _connection = oldSocket;
        _setConnected(true);
        _setReconnecting(false);
        _setupListen();
        _lastReconnectSuccessAt = DateTime.now();
        notifyListeners();
        return;
      } catch (e) {
        _log("Emergency reconnect attempt #$i: $e", level: LogLevel.warning, error: e);
        if (currentId != _connectionId) {
          _setReconnecting(false);
          notifyListeners();
          return;
        }
        if (i == 3) {
          await disconnect();
          _setReconnecting(false);
          notifyListeners();
        }
      }
    }
  }

  /// Cancels connection attempt and notifies UI
  void cancelConnection() {
    _connectionId++;
    _isConnecting = false;
    _setReconnecting(false);
    disconnect();
    notifyListeners();
    _log("Connection canceled by user");
  }

  /// Полное выключение БЛЮТУЗА в приложении
  Future<void> turnOffBluetooth() async {
    _isToggleOn = false;
    cancelConnection();
    await disconnect();
    await _stopScan();
    _discoveredDevices.clear();
    _deviceMap.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopScan();
    disconnect();
    super.dispose();
  }
}
