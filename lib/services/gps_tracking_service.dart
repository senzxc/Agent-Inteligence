import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as location_plugin;

import '../services/api_service.dart';

class AgentGpsTrackingService with WidgetsBindingObserver {
  AgentGpsTrackingService._();

  static final AgentGpsTrackingService instance = AgentGpsTrackingService._();

  final location_plugin.Location _locationService = location_plugin.Location();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<ServiceStatus>? _gpsStatusSubscription;

  bool _isTracking = false;
  bool _isStarting = false;
  bool _isRecoveringGps = false;
  bool _observerRegistered = false;

  bool get isTracking => _isTracking;

  Future<void> ensureGpsReady() async {
    // Ulangi permintaan sistem sampai GPS aktif.
    while (!await Geolocator.isLocationServiceEnabled()) {
      final enabled = await _locationService.requestService();

      if (!enabled) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }

    var permission = await Geolocator.checkPermission();

    while (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();

      throw Exception(
        'Izin lokasi ditolak permanen. Aktifkan izin lokasi '
        'di pengaturan aplikasi, kemudian coba lagi.',
      );
    }
  }

  Future<void> startAfterLogin() async {
    if (_isTracking || _isStarting) return;

    _isStarting = true;

    try {
      await ensureGpsReady();

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );

      final trackingResult = await ApiService.getTrackingStatus();
      final trackingData = trackingResult['data'];
      if (trackingData is! Map || trackingData['active'] is! bool) {
        throw Exception('Format status tracking dari server tidak valid.');
      }

      if (trackingData['active'] != true) {
        await ApiService.startTracking();
      }

      _isTracking = true;

      await _sendLocation(position);

      _registerGpsMonitoring();
      await _startPositionStream();
    } catch (_) {
      // Jangan menganggap tracking berhasil jika proses awal gagal.
      if (!_isTracking) {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
      }
      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  void _registerGpsMonitoring() {
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    _gpsStatusSubscription ??= Geolocator.getServiceStatusStream().listen((
      status,
    ) {
      if (status == ServiceStatus.disabled && _isTracking) {
        unawaited(_recoverGps());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Periksa lagi saat pengguna kembali ke aplikasi.
    if (state == AppLifecycleState.resumed && _isTracking) {
      unawaited(_recoverGps());
    }
  }

  Future<void> _startPositionStream() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          (position) {
            unawaited(_sendLocation(position));
          },
          onError: (Object error) {
            // Pemulihan akan dicoba saat status GPS berubah
            // atau saat aplikasi kembali ke foreground.
            _positionSubscription = null;
          },
        );
  }

  Future<void> _recoverGps() async {
    if (!_isTracking || _isRecoveringGps) return;

    _isRecoveringGps = true;

    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;

      // Jika GPS dimatikan, minta aktifkan kembali.
      await ensureGpsReady();

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );

      await _sendLocation(position);
      await _startPositionStream();
    } catch (error) {
      debugPrint('Pemulihan GPS gagal: $error');
    } finally {
      _isRecoveringGps = false;
    }
  }

  Future<void> _sendLocation(Position position) async {
    try {
      await ApiService.sendTrackingLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: position.speed,
      );
    } catch (error) {
      debugPrint('Gagal mengirim lokasi: $error');
    }
  }

  Future<void> disposeTrackingStream() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    await _gpsStatusSubscription?.cancel();
    _gpsStatusSubscription = null;

    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }

    _isTracking = false;
  }
}
