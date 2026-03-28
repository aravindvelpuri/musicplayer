import 'package:flutter/material.dart';
import '../services/device_music_service.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  final DeviceMusicService _musicService = DeviceMusicService();
  Map<String, dynamic>? _eqData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEqualizer();
  }

  Future<void> _loadEqualizer() async {
    final data = await _musicService.getEqualizerBands();
    if (mounted) {
      setState(() {
        _eqData = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleEnabled(bool enabled) async {
    final success = await _musicService.setEqualizerEnabled(enabled);
    if (success) {
      _loadEqualizer();
    }
  }

  Future<void> _setBandLevel(int index, int level) async {
    final success = await _musicService.setEqualizerBandLevel(index, level);
    if (success) {
      _loadEqualizer();
    }
  }

  Future<void> _resetEqualizer() async {
    if (_eqData == null) return;
    final bands = _eqData!['bands'] as List;
    for (var band in bands) {
      final index = band['index'] as int;
      await _musicService.setEqualizerBandLevel(index, 0);
    }
    _loadEqualizer();
  }

  String _formatFreq(int milliHz) {
    if (milliHz >= 1000000) {
      return '${(milliHz / 1000000).toStringAsFixed(1)} kHz';
    }
    return '${(milliHz / 1000).toStringAsFixed(0)} Hz';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Equalizer', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_eqData != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reset to default',
              onPressed: _resetEqualizer,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _eqData == null
              ? const Center(child: Text('Equalizer not available while not playing.'))
              : Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Enable Equalizer', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: _eqData!['enabled'] as bool? ?? false,
                      onChanged: _toggleEnabled,
                      activeThumbColor: theme.colorScheme.primary,
                    ),
                    const Divider(),
                    Expanded(
                      child: Opacity(
                        opacity: (_eqData!['enabled'] as bool? ?? false) ? 1.0 : 0.5,
                        child: IgnorePointer(
                          ignoring: !(_eqData!['enabled'] as bool? ?? false),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                for (var band in (_eqData!['bands'] as List))
                                  _buildBandSlider(band as Map, theme),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildBandSlider(Map band, ThemeData theme) {
    final index = band['index'] as int;
    final freq = band['centerFrq'] as int;
    final min = band['minLevel'] as int;
    final max = band['maxLevel'] as int;
    final current = band['currentLevel'] as int;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatFreq(freq), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${current > 0 ? '+' : ''}${current / 100} dB'),
            ],
          ),
          Slider(
            value: current.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            onChanged: (value) => _setBandLevel(index, value.toInt()),
            activeColor: theme.colorScheme.primary,
            inactiveColor: theme.colorScheme.primaryContainer,
          ),
        ],
      ),
    );
  }
}
