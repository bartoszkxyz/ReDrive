import 'package:flutter/widgets.dart';

/// App strings selected from the system locale.
/// zh-SG and other zh-* locales default to Simplified Chinese, while
/// zh-HK, zh-MO, zh-TW, and zh-Hant use Traditional Chinese.
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  bool get isChinese => locale.languageCode.toLowerCase() == 'zh';
  bool get isPolish => locale.languageCode.toLowerCase() == 'pl';
  bool get isTraditionalChinese {
    if (!isChinese) return false;
    final region = (locale.countryCode ?? '').toUpperCase();
    final script = (locale.scriptCode ?? '').toLowerCase();
    return script == 'hant' ||
        region == 'HK' ||
        region == 'MO' ||
        region == 'TW';
  }

  String _text(String simplified, String traditional, String english, [String? polish]) {
    if (isPolish && polish != null) return polish;
    if (!isChinese) return english;
    return isTraditionalChinese ? traditional : simplified;
  }

  String get home => _text('主页', '首頁', 'Home', 'Główny');
  String get dashboard => _text('仪表盘', '儀表板', 'Dashboard', 'Pulpit');
  String get connection => _text('连接', '連線', 'Connection', 'Połączenie');
  String get garage => _text('车库', '車庫', 'Garage', 'Garaż');
  String get dtc => _text('故障码', '故障碼', 'DTC', 'Błędy DTC');
  String get trips => _text('行程', '行程', 'Trips', 'Trasy');
  String get speed => _text('车速', '車速', 'Speed', 'Prędkość');
  String get rpm => _text('转速', '轉速', 'RPM', 'Obr/min');
  String get coolantTemp => _text('水温', '水溫', 'Coolant Temp', 'Płyn chłodzący');
  String get engineTemp => _text('发动机水温', '發動機水溫', 'Engine Temp', 'Temp. silnika');
  String get readyToDrive => _text('可行驶', '可行駛', 'Ready to Drive', 'Gotowy do jazdy');
  String get warmingUp => _text('热车中', '熱車中', 'Warming Up', 'Rozgrzewanie');
  String get activeTrip => _text('当前行程', '當前行程', 'Active Trip', 'Aktywna trasa');
  String get avgFuel => _text('平均油耗', '平均油耗', 'Avg Fuel', 'Średnie spalanie');
  String get instantFuel => _text('瞬时油耗', '瞬時油耗', 'Instant Fuel', 'Chwilowe spalanie');
  String get fuelLoad => _text('燃油负荷', '燃油負荷', 'Fuel Load', 'Dawka paliwa');
  String get engineLoad => _text('发动机负荷', '發動機負荷', 'Engine Load', 'Obciążenie silnika');
  String get preparing =>
      _text('准备连接...', '準備連線...', 'Preparing connection...', 'Przygotowywanie połączenia...');
  String get connectingEcu =>
      _text('正在连接车辆 ECU...', '正在連線車輛 ECU...', 'Connecting to ECU...', 'Łączenie z ECU pojazdu...');
  String get initializing =>
      _text('正在初始化 ELM327...', '正在初始化 ELM327...', 'Initializing ELM327...', 'Inicjalizacja ELM327...');
  String get connected => _text('已连接', '已連線', 'Connected', 'Połączono');
  String get recovering =>
      _text('正在恢复连接...', '正在恢復連線...', 'Recovering connection...', 'Wznawianie połączenia...');
  String get connectionError => _text('连接错误', '連線錯誤', 'Connection error', 'Błąd połączenia');
  String get cancel => _text('取消', '取消', 'Cancel', 'Anuluj');
  String get settings => _text('设置', '設定', 'Settings', 'Ustawienia');
  String get bluetooth => _text('蓝牙', '藍牙', 'Bluetooth', 'Bluetooth');
  String get wifi => _text('无线网络', '無線網路', 'Wi-Fi', 'Wi-Fi');
  String get usb => 'USB';
  String get wifiDeveloping => _text(
    'Wi‑Fi 连接功能正在开发中',
    'Wi‑Fi 連線功能正在開發中',
    'Wi-Fi connection is under development',
    'Połączenie Wi-Fi w trakcie realizacji',
  );
  String get usbDeveloping => _text(
    'USB 连接功能正在开发中',
    'USB 連線功能正在開發中',
    'USB connection is under development',
    'Połączenie USB w trakcie realizacji',
  );
  String get bluetoothConnection =>
      _text('蓝牙连接', '藍牙連線', 'Bluetooth Connection', 'Połączenie Bluetooth');
  String get bluetoothDescription => _text(
    '连接 OBD2 适配器后，\n即可查看车辆实时数据。',
    '連接 OBD2 適配器後，\n即可查看車輛即時資料。',
    'Connect your OBD2 adapter to see\nreal-time vehicle data.',
    'Połącz adapter OBD2, aby wyświetlić dane pojazdu w czasie rzeczywistym.',
  );
  String get startScanning => _text('开始扫描', '開始掃描', 'Start Scanning', 'Rozpocznij skanowanie');
  String get scanning => _text('扫描中...', '掃描中...', 'Scanning...', 'Skanowanie...');
  String get scanningComplete => _text('扫描完成', '掃描完成', 'Scanning complete', 'Skanowanie zakończone');
  String get searchingAdapter =>
      _text('正在搜索适配器...', '正在搜尋適配器...', 'Searching for your adapter...', 'Wyszukiwanie adaptera...');
  String devicesFound(int n) =>
      _text('发现 $n 个设备', '找到 $n 個裝置', 'Found $n devices', 'Znaleziono $n urządzeń');
  String get permissionTitle =>
      _text('蓝牙权限不足', '藍牙權限不足', 'Bluetooth access required', 'Wymagane uprawnienia Bluetooth');
  String get permissionDescription => _text(
    '蓝牙权限已被永久拒绝，请前往系统设置开启。',
    '藍牙權限已被永久拒絕，請前往系統設定開啟。',
    'Bluetooth permission was permanently denied. Please enable it from app settings.',
    'Uprawnienia Bluetooth zostały trwale odrzucone. Włącz je w ustawieniach systemu.',
  );
  String get openSettings => _text('打开设置', '開啟設定', 'Open settings', 'Otwórz ustawienia');
  String get garageTitle => _text('我的车库', '我的車庫', 'My Garage', 'Mój Garaż');
  String get garageDescription =>
      _text('这里将显示你的车辆', '這裡將顯示你的車輛', 'Your vehicles will appear here', 'Tutaj pojawią się Twoje pojazdy');
  String get noVehicles => _text('暂无车辆', '暫無車輛', 'No vehicles', 'Brak pojazdów');
  String get addFirstVehicle =>
      _text('添加你的第一辆\n汽车', '新增你的第一輛\n汽車', 'Add your first\nvehicle', 'Dodaj swój\npierwszy pojazd');
  String get addVehicle => _text('添加车辆', '新增車輛', 'Add vehicle', 'Dodaj pojazd');
  String get vehicleConnected =>
      _text('车辆已连接', '車輛已連線', 'Vehicle is connected', 'Pojazd połączony');
  String get connect => _text('连接', '連線', 'Connect', 'Połącz');
  String get disconnectDemo => _text('断开演示', '中斷示範', 'Disconnect', 'Odłącz');
  String get viewDemo => _text('查看演示', '查看示範', 'View demo', 'Zobacz demo');
  String get connectAdapterFirst => _text(
    '请先连接蓝牙、Wi‑Fi 或 USB 适配器',
    '請先連接藍牙、Wi‑Fi 或 USB 適配器',
    'Connect a Bluetooth, Wi-Fi, or USB adapter first',
    'Najpierw połącz adapter Bluetooth, Wi‑Fi lub USB',
  );
  String get ecuFailed =>
      _text('无法连接到车辆 ECU', '無法連線到車輛 ECU', 'Unable to connect to ECU', 'Nie można połączyć się z ECU pojazdu');
  String get disconnectEcuFirst =>
      _text('请先断开车辆 ECU 连接', '請先中斷車輛 ECU 連線', 'Disconnect from the ECU first', 'Najpierw odłącz się od ECU pojazdu');
  String get bannerRestoring =>
      _text('正在恢复连接', '正在恢復連線', 'Restoring connection', 'Wznawianie sesji diagnostycznej OBD...');
  String get bannerReconnecting => _text('正在重新连接', '正在重新連線', 'Reconnecting', 'Ponowne łączenie z adapterem OBD...');
  String get reconnectWait =>
      _text('正在重新连接，请稍候', '正在重新連線，請稍候', 'Reconnecting, please wait', 'Ponowne łączenie, proszę czekać');
  String get connectionLost => _text(
    '连接已断开，请重新连接',
    '連線已中斷，請重新連線',
    'Connection lost. Please connect again',
    'Utracono połączenie z OBD',
  );
  String get protocol => _text('协议', '協議', 'Protocol', 'Protokół');
  String get autoDetect => _text('自动检测', '自動偵測', 'Auto Detect', 'Wykryj automatycznie');
  String adapterNotResponding(String name) =>
      _text('错误: $name 无响应', '錯誤: $name 無回應', "Error: '$name' is not responding", "Błąd: urządzenie '$name' nie odpowiada");

  static const delegate = _AppLocalizationsDelegate();
  static const supportedLocales = [
    Locale('en'),
    Locale('pl'),
    Locale('zh'),
    Locale('zh', 'SG'),
    Locale('zh', 'HK'),
    Locale('zh', 'MO'),
    Locale('zh', 'TW'),
  ];
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    return code == 'en' || code == 'zh' || code == 'pl';
  }
  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
