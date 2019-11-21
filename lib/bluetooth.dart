import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:reset_equipment/main.dart';

import 'gears.dart';

MyBluetooth myBluetooth = MyBluetooth();

enum ScannerError {
  DuplicatesFound,

  /// Timeout of scanning - could not found complete gear set in time.
  NotFound,
  None,
}

class MyBluetooth {
  String logs;
  /// If true - more verbose prints will be shown.
  static const IS_DEBUGGING = true;
  /// If true - every found device will be reset to initial ID.
  /// It is required that device passes the scanning by having correct ID.
  static const IS_RESETTING = true;

  /// Create fake models as if devices were actually connected but they are not.
  /// Use only for testing and be careful not to forget to reset it to FALSE
  /// after test.
  static const HAS_FAKE_MODELS = false;

  static const Duration INITIAL_ID_SCAN_TIMEOUT = Duration(seconds: 40);

  PipelinedScanner scanner;

  _SpGun _spGun;
  _SpVest _spVest;
  _SpHeadset _spHeadset;

  _SpGun get gun => _spGun;
  _SpVest get vest => _spVest;
  _SpHeadset get headset => _spHeadset;

  // When connection status changes these callbacks will get fired.
  Function(bool isConnected) onGunConnectionChanged = (_) {};
  Function(bool isConnected) onHeadsetConnectionChanged = (_) {};
  Function(bool isConnected) onVestConnectionChanged = (_) {};
  /// Is fired when any of device connection changes.
  Function(bool isAllConnected) onAnyConnectionChanged = (_) {};
  Function(bool isAllConnected) onAnyConnectionChanged2 = (_) {};

  Future<bool> get isOn => _blue.isOn;

  Function() onDisable = () {};
  Function() onEnable = () {};
  Function(bool isEnabled) onStateChange = (_) {};

  void resetDeviceCallbacks() {
    onGunConnectionChanged = (_) {};
    onHeadsetConnectionChanged = (_) {};
    onVestConnectionChanged = (_) {};
    onAnyConnectionChanged = (_) {};
    onAnyConnectionChanged2 = (_) {};
  }

  void resetStateCallbacks() {
    onDisable = () {};
    onEnable = () {};
    onStateChange = (_) {};
  }

  bool get hasAllConnected {
    if (_spGun == null || _spVest == null || _spHeadset == null) {
      return false;
    }
    return !_spGun.isDisconnected
        && !_spHeadset.isDisconnected && !_spVest.isDisconnected;
  }

  bool get hasAnyConnected {
    if (_spGun != null) {
      if (!_spGun.isDisconnected)
        return true;
    }
    if (_spVest != null) {
      if (!_spVest.isDisconnected)
        return true;
    }
    if (_spHeadset != null) {
      if (!_spHeadset.isDisconnected)
        return true;
    }
    return false;
  }

  bool get areBatteriesGood {
    if (!hasAllConnected)
      return null;
    if (!_spGun.model.isBatteryGood)
      return false;
    if (!_spVest.model.isBatteryGood)
      return false;
    if (!_spHeadset.model.isBatteryGood)
      return false;
    return true;
  }

  FlutterBlue _blue = FlutterBlue.instance;

  MyBluetooth() {
    if (HAS_FAKE_MODELS) {
      _spGun = _SpGun(null);
      _spVest = _SpVest(null);
      _spHeadset = _SpHeadset(null);
      _spGun._model = Gun();
      _spHeadset._model = Headset();
      _spVest._model = Vest();
    }
    scanner = PipelinedScanner(this);
    _blue.state.listen((BluetoothState state) {
      if (state != BluetoothState.on) {
        onDisable();
        onStateChange(false);
        disconnectAll();
      } else {
        onEnable();
        onStateChange(true);
      }
    });
  }

  GearId get currentSetId {
    if (gun == null || vest == null || headset == null)
      return null;

    if (gun.id() == vest.id() && gun.id() == headset.id()) {
      return gun.id();
    } else {
      print('ID mismatch! Something went badly wrong');
      logs = 'ID mismatch! Something went badly wrong';
      return null;
    }
  }

  Future<List<dynamic>> disconnectAll() {
    var f1 = _spVest?.disconnect();
    var f2 = _spGun?.disconnect();
    var f3 = _spHeadset?.disconnect();
    _spHeadset = null;
    _spVest = null;
    _spGun = null;

    var futures = List<Future>();
    if (f1 != null)
      futures.add(f1);
    if (f2 != null)
      futures.add(f2);
    if (f3 != null)
      futures.add(f3);

    return Future.wait(futures);
  }
}

class PipelinedScanner {

  static const SCAN_ITERATION_DURATION = Duration(seconds: 3);
  /// How much to wait for gear sending its state just after connection.
  static const DATA_RESPONSE_TIMEOUT = Duration(seconds: 5);

  MyBluetooth _b;

  GearId _currentScanId;
  int _currentScannerIdentifier = 0;
  Timer _timeout;
  List<BluetoothDevice> _ignoreList = [];
  List<DeviceIdentifier> _currentMacScan = [];
  set slogs(String msg) => update(msg);
  bool get isScanning => _currentScannerIdentifier != 0;

  PipelinedScanner(this._b);

  Future<void> scanForMacs(List<DeviceIdentifier> ids,
      {Function(ScannerError err) onFinish}) async {
    onFinish ??= (_) {};
    if (_currentScanId != null) {
      print('Tried to start scanning for MACs while '
          'Gear ID scanner was running. Only one type of scan is supported at '
          'once');
      slogs = 'Tried to start scanning for MACs while '
          'Gear ID scanner was running. Only one type of scan is supported at '
          'once';
      return;
    }
    _currentMacScan.addAll(ids);
    if (_checkScanStopped()) {
      print('Start scanning for devices: $ids');
      slogs = 'Start scanning for devices: $ids';
    } else {
      print('Adding more IDs to scanner: $ids');
      slogs = 'Adding more IDs to scanner: $ids';
      return;
    }
    _currentScannerIdentifier = DateTime.now().millisecondsSinceEpoch;
    var currentScannerIdentifier = _currentScannerIdentifier;

    while (_isThisScanning(currentScannerIdentifier)) {
      if (MyBluetooth.IS_DEBUGGING)
        print('Start scanner');
      await _b._blue.stopScan(); // ensure scanner is off.
      var result = await _b._blue.startScan(timeout: SCAN_ITERATION_DURATION);

      // Stop scanner as otherwise it may interfere with connecting.
      // Also, we need to stop scanner to avoid error because of 'continue'
      // operator that skips in the start of the loop, where scanner starts,
      // which causes double-start error.
      if (MyBluetooth.IS_DEBUGGING)
        print('Stop scanner');
      slogs = 'Stop scanner';
      await _b._blue.stopScan();

      for (ScanResult result in result) {
        if (!_isThisScanning(currentScannerIdentifier))
          break;
        if (!_currentMacScan.contains(result.device.id))
          continue;

        _SpDevice sp = _SpDevice._from(result.device);
        if (sp == null)
          continue;
        if (!_shouldCheck(sp))
          continue;

        await _connect(sp, onFinish);
      }
    }
  }

  Future<void> _connect(_SpDevice sp, Function(ScannerError err) onFinish) {
    print('Next device to connect: $sp');
    slogs = 'Next device to connect: $sp';
    var onDrop = () {
      _ignoreList.remove(sp.device);
      _b.onAnyConnectionChanged(false);
      _b.onAnyConnectionChanged2(false);
      // We don't need to schedule scan if scanner is already working.
      // It will re-find this dropped device.
      print('Rescanning for $sp will begin now');
      slogs = 'Rescanning for $sp will begin now';
      scanForMacs([sp.device.id]);
    };
    return sp._connect(
      onResult: (isSuccess) async {
        if (isSuccess) {
          bool isErr = false;
          await sp._read(DATA_RESPONSE_TIMEOUT).catchError((_) {
            sp.disconnect();
            isErr = true;
            print('$sp was not responding so connection was interrupted');
            slogs = '$sp was not responding so connection was interrupted';
            onDrop();
          });
          if (isErr) {
            return;
          }

          if (_currentScanId == null || sp.id() == _currentScanId) {
            print('Found ID match in $sp');
            slogs = 'Found ID match in $sp';
            // Check if we already have connected to a SP with same ID
            // this allows to react on situation when several SP devices
            // of same type have the same ID (for example - several
            // 'SP1111' kits in the scan range).
            bool areDuplicates = false;
            var isGood = (_SpDevice device)
            => device != null && !(device?.isDisconnected ?? true);
            switch (sp.runtimeType) {
              case _SpGun:
              // If the gun is already set and connection is fine, then
              // we have duplicates.
                if (isGood(_b.gun)) {
                  areDuplicates = true;
                } else {
                  _b._spGun = sp;
                }
                _b.onGunConnectionChanged(true);
                sp._onDisconnect = () {
                  _b.onGunConnectionChanged(false);
                };
                _b.gun.model.stealthCallback = (isStealth) {
                  if (_b.hasAllConnected) {
                    _b.vest.model.isLightsOn = !isStealth;
                    _b.vest.applyData();
                  }
                };
                if (MyBluetooth.IS_RESETTING) {
                  _b.gun.model.id = GearId.initial();
                  _b.gun.applyData();
                }
                break;
              case _SpHeadset:
                if (isGood(_b._spHeadset)) {
                  areDuplicates = true;
                } else {
                  _b._spHeadset = sp;
                }
                _b.onHeadsetConnectionChanged(true);
                sp._onDisconnect = () {
                  _b.onHeadsetConnectionChanged(false);
                };
                if (MyBluetooth.IS_RESETTING) {
                  _b.headset.model.id = GearId.initial();
                  _b.headset.applyData();
                }
                break;
              case _SpVest:
                if (isGood(_b._spVest)) {
                  areDuplicates = true;
                } else {
                  _b._spVest = sp;
                }
                _b.onVestConnectionChanged(true);
                sp._onDisconnect = () {
                  _b.onVestConnectionChanged(false);
                };
                if (MyBluetooth.IS_RESETTING) {
                  _b.vest.model.id = GearId.initial();
                  _b.vest.applyData();
                }
                break;
              default:
                assert(false);
            }
            if (areDuplicates) {
              print('Found duplicated ID in device of type: ${sp.runtimeType}');
              slogs = 'Found duplicated ID in device of type: ${sp.runtimeType}';
              _b.disconnectAll();
              stopAndReset();
              onFinish(ScannerError.DuplicatesFound);
              return;
            }

            // Continue listening to device.
            sp._startReader();

            // If all devices already found - stop scanning.
            if (_b.hasAllConnected) {
              print('All devices were found, scanner will be stopped');
              _b.onAnyConnectionChanged(true);
              _b.onAnyConnectionChanged2(true);
              stopAndReset();
              onFinish(ScannerError.None);
            }
          } else {
            print('ID mismatch in $sp with ID ${sp.id()}, '
                'will be disconnected and ignored');
            slogs = 'ID mismatch in $sp with ID ${sp.id()}, '
                'will be disconnected and ignored';
            _ignoreList.add(sp.device);
            sp.disconnect();
          }

        } else {
          // Reprocessing may help discover missing characteristics.
          _ignoreList.remove(sp.device);
          sp.disconnect();
        }
      },
      onDrop: onDrop,
      onError: () {
        print('Failed to connect. Forgetting about $sp');
        slogs = 'Failed to connect. Forgetting about $sp';
        _ignoreList.remove(sp.device);
      },
    );
  }

  /// Check whether scanner is stopped and otherwise print
  /// messages.
  bool _checkScanStopped() {
    if (_currentScanId != null) {
      print('Already scanning for ID $_currentScanId, new scan request is ignored');
      slogs = 'Already scanning for ID $_currentScanId, new scan request is ignored';
      return false;
    }
    if (isScanning) {
      // MAC address scanner seem to be running.
      print('Scanner already running');
      slogs = 'Scanner already running';
      return false;
    }

    return true;
  }

  bool _isThisScanning(int id) {
    if (isScanning)
      return _currentScannerIdentifier == id;
    return false;
  }

  Future<void> scanFor(GearId id, {
    Function(ScannerError err) onFinish,
    Duration timeout,
  }) async {
    if (!_checkScanStopped())
      return;
    onFinish ??= (_) {};
    print('Start scanning for ID: $id');
    slogs = 'Start scanning for ID: $id';
    _currentScanId = id;
    _currentScannerIdentifier = DateTime.now().millisecondsSinceEpoch;
    int currentScannerIdentifier = _currentScannerIdentifier;

    if (timeout != null) {
      _timeout = Timer(timeout, () async {
        if (_isThisScanning(currentScannerIdentifier)) {
          await stopAndReset();
          onFinish(ScannerError.NotFound);
        }
      });
    }

    while (_isThisScanning(currentScannerIdentifier)) {
      if (MyBluetooth.IS_DEBUGGING)
        print('Start scanner');
      slogs = 'Start scanner';
      var result;
      try {
        await _b._blue.stopScan(); // ensure scanner is stopped.
        result = await _b._blue.startScan(timeout: SCAN_ITERATION_DURATION);
      } catch (_) {
        // Can appear PlatformException if adapter is off.
        print('Scan iteration failed and scanner will be stoped');
        slogs = 'Scan iteration failed and scanner will be stoped';
        stopAndReset();
        return;
      }

      // Stop scanner as otherwise it may interfere with connecting.
      // Also, we need to stop scanner to avoid error because of 'continue'
      // operator that skips in the start of the loop, where scanner starts,
      // which causes double-start error.
      if (MyBluetooth.IS_DEBUGGING)
        print('Stop scanner');
      slogs = 'Stop scanner';
      await _b._blue.stopScan();

      if (MyBluetooth.IS_DEBUGGING) {
        print('List of scanned devices: ' + result.map((ScanResult r) => r.device.name).toString());
        slogs = 'List of scanned devices: ' + result.map((ScanResult r) => r.device.name).toString();
      }
      for (ScanResult result in result) {
        if (!_isThisScanning(currentScannerIdentifier))
          break;
        if (result.device.type != BluetoothDeviceType.le)
          continue;
        if (_ignoreList.contains(result.device))
          continue;

        _SpDevice sp = _SpDevice._from(result.device);
        if (sp == null)
          continue;
        if (!_shouldCheck(sp))
          continue;

        await _connect(sp, onFinish);
      }
    }
  }

  /// Whether we should connect this device (for example to compare ID).
  bool _shouldCheck(_SpDevice dev) {
    if (_currentScanId != null) {
      if (_currentScanId.isInitial) {
        return dev.runtimeType == _SpGun
            || dev.runtimeType == _SpVest
            || dev.runtimeType == _SpHeadset;
      }
    }
    switch (dev.runtimeType) {
      case _SpGun:
        if (_b.gun == null)
          return true;
        return _b.gun.isDisconnected;
        break;
      case _SpVest:
        if (_b.vest == null)
          return true;
        return _b.vest.isDisconnected;
        break;
      case _SpHeadset:
        if (_b.headset == null)
          return true;
        return _b.headset.isDisconnected;
        break;
      default:
        print(dev.runtimeType);
        assert(false);
        return true;
    }
  }

  Future<void> stopAndReset() async {
    _timeout?.cancel();
    _timeout = null;
    await _b._blue.stopScan();
    _currentScanId = null;
    _currentMacScan.clear();
    _ignoreList.clear();
    _currentScannerIdentifier = 0;
  }
}

abstract class _SpDevice {

  static const CONNECTION_TIMEOUT = Duration(seconds: 3);

  final BluetoothDevice device;
  BluetoothCharacteristic notifyCh;
  BluetoothCharacteristic writeCh;

  Gear _model;

  /// Whether device was disconnected by the code instead of connection error.
  /// If device was not manually disconnected but still connection was
  /// aborted then the installed callback will be fired, if any was set.
  bool _isManualDisconnect = false;
  bool _isDisconnected = false;
  bool get isDisconnected => _isDisconnected;
  String slogs;

  /// Will be called when connection gets dropped or manually disconnected.
  Function() _onDisconnect = () {};

  _SpDevice(this.device);

  static _SpDevice _from(BluetoothDevice device) {
    var name = device.name;
    switch (name) {
      case 'SP-GUN   ':
        return _SpGun(device);
      case 'SP-VEST':
        return _SpVest(device);
      case 'SP-HEADSET_ble':
        return _SpHeadset(device);
      default:
        return null;
    }
  }

  /// Start connecting to a device. If connection gets established then
  /// onDrop (if set) will monitor the connection status. If it appears that
  /// connection gets interrupted (not by the application code) then onDrop
  /// will be executed to process this event.
  Future<void> _connect({
    Function(bool isSuccess) onResult,
    Function() onDrop,
    Function() onError,
  }) async {
    _isManualDisconnect = false;
    debugPrint('Start connecting $this');

    bool isErr = false;
    await device.connect(
      autoConnect: false,
    ).timeout(
        CONNECTION_TIMEOUT,
        onTimeout: () {
          throw new TimeoutException('Failed to connect to $this');
        }
    ).catchError((err) {
      // Make sure device connection is forgotten.
      device.disconnect();
      print(err);
      isErr = true;
    });
    if (isErr) {
      onError();
      return;
    }

    print('Connected to $this');
    slogs = 'Connected to $this';
    // Listen to changes in connection. React on disconnect.
    var listen;
    listen = device.state.listen((newState) {
      if (newState == BluetoothDeviceState.disconnected) {
        _isDisconnected = true;

        listen.cancel();
        if (!_isManualDisconnect) {
          device.disconnect(); // Make sure that device was forgotten by library.
          print('Connection of $this was dropped');
          _onDisconnect();
          onDrop();
        }
      }
    });

    await _setupCharacteristics();
    if (writeCh == null || notifyCh == null) {
      print('Failed to discover essential characteristics');
      onResult(false);
    } else {
      onResult(true);
    }
  }

  Guid writeCharacteristicUuid();

  Guid notifyCharacteristicUuid();

  Future<void> _setupCharacteristics() async {
    if (MyBluetooth.IS_DEBUGGING) {
      print('Setting up characteristics of $this');
      slogs = 'Setting up characteristics of $this';
    }

    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.uuid == writeCharacteristicUuid()) {
          writeCh = characteristic;
        } else if (characteristic.uuid == notifyCharacteristicUuid()) {
          notifyCh = characteristic;
        }

        if (writeCh != null && notifyCh != null) {
          try {
            if (Platform.isAndroid || this.runtimeType == _SpHeadset) {
              await notifyCh.setNotifyValue(true);
            }
          } catch (ex) {
            print(ex);
            // this will notify higher code that error with this characteristic appeared.
            notifyCh = null;
            return;
          }
          print('Characteristics of $this are set');
          slogs = 'Characteristics of $this are set';
          return;
        }
      }
    }
  }

  Future<dynamic> disconnect() {
    print('Disconnecting $this');
    slogs = 'Disconnecting $this';
    _isManualDisconnect = true;
    _onDisconnect();
    myBluetooth.onAnyConnectionChanged(false);
    myBluetooth.onAnyConnectionChanged2(false);
    return device.disconnect();
  }

  GearId id();

  void _startReader() {
    notifyCh.value.listen((newData) {
      _updateObjectWith(newData);
    });
  }

  Future<void> _read([Duration timeout]) async {
    Future<List<int>> future;
    if (timeout != null)
      future = notifyCh.value.first.timeout(timeout, onTimeout: () => null);
    else
      future = notifyCh.value.first;
    if (Platform.isIOS && this.runtimeType != _SpHeadset) {
      if (!notifyCh.isNotifying)
        notifyCh.setNotifyValue(true);
    }
    var data = await future;
    if (data == null)
      throw Exception('No data received');
    _updateObjectWith(data);
  }

  void _updateObjectWith(List<int> data);

  List<int> _objectToBytes();

  Future<Null> applyData([int retryCount = 5]) async {
    if (retryCount < 0) {
      print('Send retry counter has run down - failed to send data, aborting');
      slogs = 'Send retry counter has run down - failed to send data, aborting';
      return;
    }

    if (MyBluetooth.IS_DEBUGGING) {
      print('Sending data to $this: $_model, retry count: $retryCount');
      slogs = 'Sending data to $this: $_model, retry count: $retryCount';
    }
    var modelHash = _model.hashCode;
    var modelCopy = _model.toBytes();
    await writeCh.write(_objectToBytes()).catchError((err) {
      // Retry.
      applyData(retryCount - 1);
    });
    await _read();

    // Check whether data was accepted.
    if (modelHash != _model.hashCode) {
      if (MyBluetooth.IS_DEBUGGING) {
        print('Device did not accept packet, will resend');
        slogs = 'Device did not accept packet, will resend';
      }
      _model.updateFrom(modelCopy);
      applyData(retryCount - 1);
    }
  }

  DeviceIdentifier physicalId() => device.id;
}

class _SpGun extends _SpDevice {

  Gun get model => _model;

  _SpGun(BluetoothDevice device) : super(device);

  @override
  Guid notifyCharacteristicUuid() =>
      Guid('0000FFF1-0000-1000-8000-00805F9B34FB');

  @override
  Guid writeCharacteristicUuid() =>
      Guid('0000FFF2-0000-1000-8000-00805F9B34FB');

  @override
  GearId id() => model.id;

  @override
  void _updateObjectWith(List<int> data) {
    if (_model == null) {
      _model = Gun.from(data);
    } else {
      _model.updateFrom(data);
    }
    if (MyBluetooth.IS_DEBUGGING) {
      print('Update object to: $_model');
      slogs = 'Update object to: $_model';
    }
  }

  @override
  List<int> _objectToBytes() => (_model ?? Gun()).toBytes();

  @override
  String toString() => 'Gun (${device.id})';
}

class _SpVest extends _SpDevice {

  Vest get model => _model;

  _SpVest(BluetoothDevice device) : super(device);

  @override
  Guid notifyCharacteristicUuid() =>
      Guid('0000FFF1-0000-1000-8000-00805F9B34FB');

  @override
  Guid writeCharacteristicUuid() =>
      Guid('0000FFF2-0000-1000-8000-00805F9B34FB');

  @override
  GearId id() => model.id;

  @override
  void _updateObjectWith(List<int> data) {
    if (_model == null) {
      _model = Vest.from(data);
    } else {
      _model.updateFrom(data);
    }
    if (MyBluetooth.IS_DEBUGGING) {
      print('Update object to: $_model');
      slogs = 'Update object to: $_model';
    }
  }

  @override
  List<int> _objectToBytes() => (_model ?? Vest()).toBytes();

  @override
  String toString() => 'Vest (${device.id})';

  @override
  void _startReader() {
    super._startReader();
  }
}

class _SpHeadset extends _SpDevice {

  Headset get model => _model;

  _SpHeadset(BluetoothDevice device) : super(device);

  @override
  Guid notifyCharacteristicUuid() =>
      Guid('00008888-0000-1000-8000-00805f9b34fb');

  @override
  Guid writeCharacteristicUuid() =>
      Guid('00008877-0000-1000-8000-00805F9B34FB');

  @override
  GearId id() => model.id;

  @override
  void _updateObjectWith(List<int> data) {
    if (_model == null) {
      _model = Headset.from(data);
    } else {
      _model.updateFrom(data);
    }
    if (MyBluetooth.IS_DEBUGGING) {
      print('Update object to: $_model');
      slogs = 'Update object to: $_model';
    }
  }

  @override
  List<int> _objectToBytes() => (_model ?? Headset()).toBytes();

  @override
  String toString() => 'Headset (${device.id})';

  @override
  void _startReader() {
    super._startReader();
  }
}
