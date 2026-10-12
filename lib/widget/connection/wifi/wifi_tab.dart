import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:redrive/obd/connection/tcp_obd_connection.dart';
import 'package:redrive/providers/obd_provider.dart';

class WifiTab extends StatefulWidget {
  const WifiTab({super.key});

  @override
  State<WifiTab> createState() => _WifiTabState();
}

class _WifiTabState extends State<WifiTab> {
  final _ipController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '35000');

  TcpObdConnection? _activeTcpConnection;
  bool _isConnecting = false;
  String _statusMessage = 'Ready to connect';

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    final host = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 35000;

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to $host:$port...';
    });

    final obdProvider = context.read<ObdProvider>();
    final tcpConnection = TcpObdConnection(host: host, port: port);

    final success = await tcpConnection.connect();

    if (!mounted) return;

    if (success) {
      _activeTcpConnection = tcpConnection;
      obdProvider.attachConnection(tcpConnection);

      setState(() {
        _isConnecting = false;
        _statusMessage = 'Connected to $host:$port';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ELM327 at $host:$port'),
          backgroundColor: Colors.green,
        ),
      );

      // Automatically start live OBD session handshake
      await obdProvider.startRealMode();
    } else {
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Connection failed. Ensure emulator is running.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect to $host:$port'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleDisconnect() async {
    final obdProvider = context.read<ObdProvider>();
    await obdProvider.stopRealMode();
    await _activeTcpConnection?.disconnect();

    setState(() {
      _activeTcpConnection = null;
      _statusMessage = 'Disconnected';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isConnected = _activeTcpConnection?.isConnected == true;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected
                    ? colorScheme.primary
                    : Colors.white.withValues(alpha: 0.1),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isConnected ? colorScheme.primary : Colors.grey)
                            .withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.wifi,
                        color: isConnected ? colorScheme.primary : Colors.white70,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected
                                ? 'Connected to Adapter'
                                : 'Wi-Fi / ELM327 Emulator',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _statusMessage,
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ipController,
                  enabled: !isConnected && !_isConnecting,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'IP Address / Host',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portController,
                  enabled: !isConnected && !_isConnecting,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Port (Default: 35000)',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: context.watch<ObdProvider>().preferredProtocol,
                  dropdownColor: colorScheme.surfaceContainer,
                  decoration: InputDecoration(
                    labelText: 'OBD Protocol',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  items: const [
                    DropdownMenuItem(value: 'ATSP0', child: Text('Auto Detect (ATSP0)')),
                    DropdownMenuItem(value: 'ATSP5', child: Text('Suzuki Swift M15A - KWP Fast (ATSP5)')),
                    DropdownMenuItem(value: 'ATSP6', child: Text('CAN 11-bit / 500k (ATSP6)')),
                    DropdownMenuItem(value: 'ATSP3', child: Text('ISO 9141-2 (ATSP3)')),
                  ],
                  onChanged: isConnected || _isConnecting
                      ? null
                      : (val) {
                          if (val != null) {
                            context.read<ObdProvider>().setPreferredProtocol(val);
                          }
                        },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isConnected
                          ? Colors.redAccent
                          : colorScheme.primary,
                      foregroundColor: isConnected
                          ? Colors.white
                          : colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isConnecting
                        ? null
                        : (isConnected ? _handleDisconnect : _handleConnect),
                    child: _isConnecting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            isConnected ? 'Disconnect' : 'Connect to Emulator',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Quick presets
          if (!isConnected)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.bolt, size: 20),
                label: const Text('Reset to Local Emulator (127.0.0.1:35000)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _ipController.text = '127.0.0.1';
                    _portController.text = '35000';
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}
