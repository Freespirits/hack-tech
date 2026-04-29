/// Live monitoring screen — connects to the AM4100, streams readings,
/// renders vitals + ECG waveform, persists to SQLite, and surfaces
/// alarms when thresholds are breached.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../ble/am4100_commands.dart';
import '../../ble/am4100_protocol.dart';
import '../../ble/ble_constants.dart';
import '../../ble/connection_state_machine.dart';
import '../../core/di.dart';
import '../../data/models/alarm_thresholds.dart';
import '../../data/models/pet.dart';
import '../../data/models/reading.dart';
import '../../data/models/session.dart';
import '../../signal/hrv.dart';
import '../../signal/pan_tompkins.dart';
import '../../signal/pleth_quality.dart';
import '../../signal/species_baselines.dart';
import '../widgets/connection_status_chip.dart';
import '../widgets/ecg_waveform.dart';
import '../widgets/vital_card.dart';

class LiveSessionScreen extends ConsumerStatefulWidget {
  const LiveSessionScreen({super.key, required this.petId});
  final String petId;

  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen> {
  Pet? _pet;
  AlarmThresholds? _thresholds;
  MonitoringSession? _session;

  StreamSubscription<BleConnectionState>? _stateSub;
  StreamSubscription<Am4100Reading>? _readSub;
  Timer? _persistTimer;

  BleConnectionState _state = const Idle();

  // Latest displayed values.
  int? _hr;
  int? _spo2;
  int? _resp;
  double? _tempC;
  int? _battery;
  int? _nibpSys;
  int? _nibpDia;
  int? _nibpMap;
  double _pi = 0;

  final ListQueue<int> _ecgRing = ListQueue<int>();
  static const int _ecgRingMax = 250 * 8; // 8 s window @ 250 Hz
  final PanTompkinsDetector _detector = PanTompkinsDetector();
  final List<QrsDetection> _beats = <QrsDetection>[];
  final HrvCalculator _hrvCalc = HrvCalculator();
  final PlethQualityWindow _plethQ = PlethQualityWindow(windowSize: 240);
  final AudioPlayer _alarmPlayer = AudioPlayer();
  bool _alarming = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final pet = await ref.read(petRepositoryProvider).byId(widget.petId);
    final thresholds =
        await ref.read(alarmThresholdRepositoryProvider).forPet(widget.petId);
    if (!mounted || pet == null) return;
    setState(() {
      _pet = pet;
      _thresholds = thresholds;
    });
    await _alarmPlayer.setAsset('assets/sounds/alarm.wav');
  }

  Future<void> _connect() async {
    final ble = ref.read(bleServiceProvider);
    _stateSub = ble.state.listen((s) => setState(() => _state = s));
    _readSub = ble.readings.listen(_onReading);

    ScanResult? first;
    final scan = ble.scanFor();
    await for (final r in scan) {
      first = r;
      break;
    }
    if (first == null) return;
    await ble.connect(first.device);

    final pet = _pet!;
    _session = await ref.read(sessionRepositoryProvider).startSession(
          petId: pet.id,
          clinicId: pet.clinicId,
          startedBy: ref.read(supabaseProvider).userEmail ?? '',
          deviceId: first.device.remoteId.str,
          deviceName: first.device.platformName,
        );

    _persistTimer = Timer.periodic(const Duration(seconds: 1), (_) => _persistNow());
  }

  Future<void> _disconnect() async {
    await ref.read(bleServiceProvider).disconnect();
    final s = _session;
    if (s != null) {
      final summary = SessionSummary(
        minHr: _hr?.toDouble(),
        maxHr: _hr?.toDouble(),
        meanHr: _hr?.toDouble(),
        minSpo2: _spo2?.toDouble(),
        maxSpo2: _spo2?.toDouble(),
        meanSpo2: _spo2?.toDouble(),
        minTempC: _tempC,
        maxTempC: _tempC,
        meanTempC: _tempC,
        respMean: _resp?.toDouble(),
        nibpSystolic: _nibpSys,
        nibpDiastolic: _nibpDia,
        nibpMean: _nibpMap,
        beatCount: _beats.length,
        rmssdMs: _hrvCalc.compute(_beats).rmssdMs,
        sdnnMs: _hrvCalc.compute(_beats).sdnnMs,
        signalQuality: _plethQ.qualityScore(),
        alarmTriggers: const <String, int>{},
      );
      await ref
          .read(sessionRepositoryProvider)
          .endSession(sessionId: s.id, summary: summary);
    }
    _persistTimer?.cancel();
  }

  void _onReading(Am4100Reading r) {
    setState(() {
      switch (r) {
        case SpO2Reading():
          _spo2 = r.spo2 ?? _spo2;
          if (r.pulseRate != null) _hr = r.pulseRate;
          _plethQ.add(r.plethSample);
          _pi = _plethQ.perfusionIndex();
        case EcgReading():
          _ecgRing.addLast(r.sampleMicroVolts);
          while (_ecgRing.length > _ecgRingMax) {
            _ecgRing.removeFirst();
          }
          final det = _detector.process(
            r.sampleMicroVolts.toDouble(),
            r.timestamp,
          );
          if (det != null) {
            _beats.add(det);
            // Keep at most 60 s of beats.
            final cutoff =
                r.timestamp.subtract(const Duration(seconds: 60));
            _beats.removeWhere((b) => b.timestamp.isBefore(cutoff));
            final hrv = _hrvCalc.compute(_beats);
            if (hrv.isMeaningful) _hr = hrv.meanHrBpm.round();
          }
        case RespReading():
          // Resp waveform isn't rendered live yet; HrRespReading drives
          // the displayed RR. Per-sample persistence is on the roadmap.
          break;
        case HrRespReading():
          if (r.heartRate != null) _hr = r.heartRate;
          if (r.respirationRate != null) _resp = r.respirationRate;
        case TemperatureReading():
          _tempC = r.celsius;
        case NibpReading():
          _nibpSys = r.systolic;
          _nibpDia = r.diastolic;
          _nibpMap = r.mean;
        case BatteryReading():
          _battery = r.percent;
      }
      _checkAlarms();
    });
  }

  Future<void> _persistNow() async {
    final s = _session;
    if (s == null) return;
    final repo = ref.read(sessionRepositoryProvider);
    final now = DateTime.now().toUtc();
    if (_hr != null) {
      await repo.insertVitalReading(VitalReading(
        sessionId: s.id,
        timestamp: now,
        kind: VitalKind.heartRate,
        value: _hr!.toDouble(),
      ));
    }
    if (_spo2 != null) {
      await repo.insertVitalReading(VitalReading(
        sessionId: s.id,
        timestamp: now,
        kind: VitalKind.spo2,
        value: _spo2!.toDouble(),
      ));
    }
    if (_tempC != null) {
      await repo.insertVitalReading(VitalReading(
        sessionId: s.id,
        timestamp: now,
        kind: VitalKind.temperatureC,
        value: _tempC!,
      ));
    }
    if (_resp != null) {
      await repo.insertVitalReading(VitalReading(
        sessionId: s.id,
        timestamp: now,
        kind: VitalKind.respirationRate,
        value: _resp!.toDouble(),
      ));
    }
    await repo.insertVitalReading(VitalReading(
      sessionId: s.id,
      timestamp: now,
      kind: VitalKind.perfusionIndex,
      value: _pi,
    ));
  }

  void _checkAlarms() {
    final t = _thresholds;
    if (t == null) {
      _alarming = false;
      return;
    }
    final breach = (_spo2 != null && _spo2! < t.spo2Min) ||
        (_hr != null && (_hr! < t.hrMin || _hr! > t.hrMax)) ||
        (_tempC != null && (_tempC! < t.tempMinC || _tempC! > t.tempMaxC)) ||
        (_resp != null && (_resp! < t.respMin || _resp! > t.respMax));

    if (breach && !_alarming && t.alarmBeep) {
      _alarming = true;
      unawaited(_alarmPlayer.setLoopMode(LoopMode.one));
      unawaited(_alarmPlayer.play());
    } else if (!breach && _alarming) {
      _alarming = false;
      unawaited(_alarmPlayer.stop());
    }
  }

  Future<void> _startNibp() async {
    if (_state is! Connected) return;
    await ref.read(bleServiceProvider).sendCommand(Am4100Commands.startNibp());
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _readSub?.cancel();
    _persistTimer?.cancel();
    _alarmPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pet = _pet;
    if (pet == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final connected = _state is Connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(pet.name),
        actions: [
          if (_battery != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text('${_battery!}%',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConnectionStatusChip(state: _state),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: EcgWaveform(
                  samples: _ecgRing.toList(growable: false),
                  sampleHz: Am4100SampleRates.ecgHz.toDouble(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 3,
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 1.5,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  VitalCard(
                    label: 'Heart rate',
                    value: _hr?.toString() ?? '—',
                    unit: 'bpm',
                    subtitle: pet.species == Species.cat
                        ? 'cat: 120–220 BPM'
                        : 'dog: 60–160 BPM',
                    alarm: _isOutOfRange(
                        _hr?.toDouble(), _thresholds?.hrMin, _thresholds?.hrMax),
                  ),
                  VitalCard(
                    label: 'SpO₂',
                    value: _spo2?.toString() ?? '—',
                    unit: '%',
                    subtitle: 'PI ${_pi.toStringAsFixed(2)} %',
                    alarm: _isOutOfRange(_spo2?.toDouble(),
                        _thresholds?.spo2Min, double.infinity),
                  ),
                  VitalCard(
                    label: 'Temperature',
                    value: _tempC?.toStringAsFixed(1) ?? '—',
                    unit: '°C',
                    alarm: _isOutOfRange(_tempC, _thresholds?.tempMinC,
                        _thresholds?.tempMaxC),
                  ),
                  VitalCard(
                    label: 'Respiration',
                    value: _resp?.toString() ?? '—',
                    unit: 'rpm',
                    alarm: _isOutOfRange(_resp?.toDouble(),
                        _thresholds?.respMin, _thresholds?.respMax),
                  ),
                  VitalCard(
                    label: 'NIBP',
                    value: _nibpSys != null && _nibpDia != null
                        ? '$_nibpSys/$_nibpDia'
                        : '—',
                    unit: 'mmHg',
                    subtitle: _nibpMap == null ? null : 'MAP $_nibpMap',
                  ),
                  VitalCard(
                    label: 'HRV (RMSSD)',
                    value: _beats.length < 5
                        ? '—'
                        : _hrvCalc
                            .compute(_beats)
                            .rmssdMs
                            .toStringAsFixed(1),
                    unit: 'ms',
                    subtitle: 'beats: ${_beats.length}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: Icon(
                      connected ? Icons.stop_circle : Icons.bluetooth_searching,
                    ),
                    label: Text(connected ? 'End session' : 'Connect device'),
                    onPressed: connected ? _disconnect : _connect,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.compress),
                  label: const Text('Take BP'),
                  onPressed: connected ? _startNibp : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isOutOfRange(double? v, double? low, double? high) {
    if (v == null) return false;
    if (low != null && v < low) return true;
    if (high != null && v > high) return true;
    return false;
  }
}
