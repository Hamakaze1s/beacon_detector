import 'package:flutter/services.dart';

class BackgroundBeaconService {
  static const _channel = MethodChannel('beacon_detector/background_service');

  Future<void> start() {
    return _channel.invokeMethod<void>('start');
  }

  Future<void> stop() {
    return _channel.invokeMethod<void>('stop');
  }

  Future<bool> isRunning() async {
    final running = await _channel.invokeMethod<bool>('isRunning');
    return running ?? false;
  }
}
