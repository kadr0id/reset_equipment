//! Re-implementation of gears.

import 'dart:convert';

enum GearType {
  Gun,
  Vest,
  Headset,
}

String gearTypeToString(GearType t) {
  switch (t) {
    case GearType.Gun:
      return 'SP-Gun';
    case GearType.Headset:
      return 'SP-Headset';
    case GearType.Vest:
      return 'SP-Vest';
    default:
      assert(false); // unreachable
  }

  return null; // unreachable
}

/// Gear class allows to control data related to gear. It DOES NOT contain
/// any code that uses Bluetooth. Instead it allows changing state of
/// particular gear and convert those changes to bytes that are ready to
/// be sent and vice verse - it can parse bytes received from Bluetooth
/// to update the state of gear on Flutter side.
abstract class Gear {

  GearId get id;

  /// Checksum for the data as it was received from the device.
  /// Is used to calculate new checksum for modified data so that
  /// new data packet was accepted by the device.
  int initialDataSum = 0;

  /// Update gear values from bytes received from Bluetooth.
  void updateFrom(List<int> bytes);

  /// Pack gear data into bytes to be sent via Bluetooth back to the device.
  List<int> toBytes();

  /// Set gear values to initial state. Some fields that are read-only (
  /// like battery level, plates out etc.) may be ignored and should
  /// not be expected to change or maintain correct state. Treat their value as
  /// undefined.
  void reset();

  /// Update this data packet by changing checksum in such a way so that
  /// this packet was accepted by the device that receives it. Old
  /// checksum is removed. Checksum is generated basing on this gear
  /// initialChecksum value and it is required to be valid.
  void _signChecksum(List<int> bytes) {
    assert(bytes.length == 20);
    bytes[19] = 0; // Remove old checksum.

    var sum = 0;
    bytes.forEach((b) => sum += b);

    bytes[19] = (initialDataSum - sum) % 256; // Set new checksum.
    if (bytes[19] < 0) {
      bytes[19] = -bytes[19];
    }
  }

  /// Level of the battery, where 0-10 = 0-100%. Sometimes it may be higher
  /// (when charging).
  int get battery;

  /// Check if battery level is sufficient for the game.
  bool get isBatteryGood => isBatteryOk(battery);

  static bool isBatteryLow(int battery) => battery > 3;

  static bool isBatteryOk(int battery) => battery >= 5;

  static bool isBatteryCritical(int battery) => battery <= 3;

  // Two callbacks are identical and are created correspondingly to
  // the two different places of listeners in battle screen.
  // TODO rework me properly.
  Function(int level) batteryCallback = (_) {};
  Function(int level) batteryCallback2 = (_) {};
}

enum GearIdLabel {
  SP,
  BC,
  CA,
  JS,
}

class GearId {
  /// If GearId could not be parsed into correct values from compact form,
  /// it is stored as initial bytes.
  List<int> unparseable;

  int number; // 0 - 9999.
  GearIdLabel label;

  bool get isNone {
    if (unparseable == null)
      return false;
    return unparseable[0] == 215 && unparseable[1] == 0 && unparseable[2] == 0;
  }

  bool get isInitial => number == 1111 && label == GearIdLabel.SP;

  GearId(this.label, this.number)
      : assert(number >= 0 && number <= 9999 && label != null);

  GearId.initial() : label = GearIdLabel.SP, number = 1111;

  GearId.fromBytes(List<int> bytes) : assert(bytes.length == 6) {
    String l = utf8.decode(bytes.getRange(0, 2).toList());
    String n = utf8.decode(bytes.getRange(2, 6).toList());

    label = stringToLabel(l);
    number = int.parse(n);

    if (label == null || number == null) {
      throw new Exception('Failed to parse input bytes');
    }
  }

  GearId.none() : unparseable = [215, 0, 0];

  GearId.fromCompact(List<int> compact) : assert(compact.length == 3) {
    int i = 0
    | (compact[0] << 16)
    | (compact[1] << 8)
    | (compact[2] << 0);

    int firstLetter = (i >> (5 + 14)) & 0x1F;
    int secondLetter = (i >> 14) & 0x1F;
    int num = i & 0x3FFF;

    this.number = num;

    firstLetter += 0x41; // normalize to ASCII;
    secondLetter += 0x41; // normalize to ASCII;

    List<int> charCodes = [firstLetter, secondLetter];
    this.label = stringToLabel(String.fromCharCodes(charCodes));

    if (label == null) {
      unparseable = compact;
    }
  }

  GearId.fromString(String str) {
    var lab = str.substring(0, 2);
    var num = str.substring(2, 6);

    label = stringToLabel(lab);
    number = int.parse(num);
  }

  static String labelToString(GearIdLabel label) {
    switch (label) {
      case GearIdLabel.SP:
        return 'SP';
      case GearIdLabel.BC:
        return 'BC';
      case GearIdLabel.JS:
        return 'JS';
      case GearIdLabel.CA:
        return 'CA';
    }

    print(label);
    assert(false);
    return null;
  }

  static GearIdLabel stringToLabel(String s) {
    switch (s) {
      case 'SP':
        return GearIdLabel.SP;
      case 'BC':
        return GearIdLabel.BC;
      case 'JS':
        return GearIdLabel.JS;
      case 'CA':
        return GearIdLabel.CA;
    }

    return null;
  }

  @override
  String toString() {
    if (isNone) {
      return 'GearId (none)';
    }
    if (unparseable != null)
      return 'GearId (incomprehensible bytes: $unparseable)';
    return labelToString(label) + number.toString().padLeft(4, '0');
  }

  List<int> toBytes() {
    if (unparseable != null)
      return unparseable;
    return ascii.encode(toString());
  }

  List<int> toCompact() {
    if (unparseable != null)
      return unparseable;

    // Get letters and denormalize them from ASCII.
    int a = labelToString(label).codeUnitAt(0) - 0x41;
    int b = labelToString(label).codeUnitAt(1) - 0x41;

    int mix = (a << (5 + 14)) + (b << 14) + number;

    return [
      (mix >> 16) & 0xFF,
      (mix >> 8) & 0xFF,
      (mix >> 0) & 0xFF,
    ];
  }

  @override
  bool operator ==(other) {
    if (unparseable != null) {
      if (other.unparseable == null)
        return false;
      var u = unparseable;
      var i = other.unparseable;
      return u[0] == i[0] && u[1] == i[1] && u[2] == i[2];
    }
    return number == other.number && label == other.label;
  }

  @override
  int get hashCode {
    if (unparseable != null)
      return unparseable.hashCode;
    return label.index * 10000 + number;
  }

  GearId copy() {
    if (unparseable != null) {
      return GearId.fromCompact(unparseable);
    } else {
      return GearId(label, number);
    }
  }
}

/// Byte array is invalid and thus this exception raises.
class ByteParseException implements Exception {}

class Gun extends Gear {

  GearId id;
  int _battery;
  bool isTriggerEnabled;
  bool _isLightsOn;
  bool hasMagazines;
  bool _isAutoFiring;
  int _ammo;

  bool get isLightsOn => _isLightsOn;
  set isLightsOn(bool i) {
    if (_isLightsOn != i) {
      _isLightsOn = i;
      stealthCallback(!i);
    }
  }

  Function(int newAmmo) ammoCallback = (_) {};
  Function(int newAmmo) ammoCallback2 = (_) {};
  Function(bool isAutoFiring) firingModeCallback = (_) {};
  Function(bool isStealth) stealthCallback = (_) {};

  int get ammo => _ammo;
  set ammo(int val) {
    if (ammo != val) {
      _ammo = val;
      ammoCallback(val);
      ammoCallback2(val);
    }
  }

  bool get isAutoFiring => _isAutoFiring;
  set isAutoFiring(bool val) {
    if (val != isAutoFiring) {
      _isAutoFiring = val;
      firingModeCallback(val);
    }
  }

  int get battery => _battery;
  set battery(int newLevel) {
    if (battery != newLevel) {
      _battery = newLevel;
      batteryCallback(newLevel);
      batteryCallback2(newLevel);
    }
  }

  Gun() {
    reset();
  }

  Gun.from(List<int> bytes) {
    updateFrom(bytes);
  }

  @override
  void reset() {
    id = GearId.initial();
    battery = 0;
    isTriggerEnabled = true;
    isLightsOn = true;
    hasMagazines = true;
    isAutoFiring = true;
    ammo = 30;

    ammoCallback(ammo);
    ammoCallback2(ammo);
  }

  @override
  List<int> toBytes() {
    List<int> bytes = List();
    bytes.add(0xFF); // SOF
    bytes.addAll(id.toBytes());
    bytes.add(1); // device type - gun.
    bytes.add(battery);
    bytes.add(isTriggerEnabled ? 1 : 0);
    bytes.add(isLightsOn ? 1 : 0);
    bytes.add(hasMagazines ? 1 : 0);
    bytes.add(isAutoFiring ? 1 : 0);
    bytes.add(ammo);
    for (var i = 0; i < 5; i++) {
      bytes.add(0xFE); // padding.
    }

    bytes.add(0); // Add space for new checksum.
    _signChecksum(bytes); // Create checksum.

    return bytes;
  }

  @override
  void updateFrom(List<int> bytes) {
    if (bytes.length != 20) {
      throw new ByteParseException();
    }
    if (bytes[7] != 1) {
      print('Unexpected device type: ${bytes[7]}');
      throw new ByteParseException();
    }

    id = GearId.fromBytes(bytes.getRange(1, 7).toList());
    battery = bytes[8];
    isTriggerEnabled = bytes[9] != 0;
    isLightsOn = bytes[10] != 0;
    hasMagazines = bytes[11] != 0;
    isAutoFiring = bytes[12] != 0;
    ammo = bytes[13];

    initialDataSum = 0;
    bytes.forEach((b) => initialDataSum += b);
  }

  @override
  String toString() {
    return 'Gun { '
        'id: $id, '
        'battery: $battery, '
        'isTriggerEnabled: $isTriggerEnabled, '
        'isLightsOn: $isLightsOn, '
        'hasMagazines: $hasMagazines, '
        'isAutoFiring: $isAutoFiring, '
        'ammo: $ammo }';
  }
}

enum VestImmunity {
  Normal,
  Immune,
  ShootingRangeMode,
}

enum PlateState {
  Inserted,
  Out,
  OutLedOn,
  OutBlinking,
}

class Vest extends Gear {

  GearId id;
  int battery;
  VestImmunity immunity;
  bool isLightsOn;
  PlateState _plate1;
  PlateState _plate2;
  bool _isPlate3Out;
  GearId _shotBy;

  Function() lastPlateFiredCallback = () {};
  Function(bool isIn) plate1Callback = (_) {};
  Function(bool isIn) plate2Callback = (_) {};
  Function(bool isIn) plate3Callback = (_) {};
  Function(GearId shooter) shotCallback = (_) {};
  Function(GearId shooter) shotCallback2 = (_) {};

  bool get isPlate1Out => _plate1 != PlateState.Inserted;
  bool get isPlate2Out => _plate2 != PlateState.Inserted;
  bool get isTwoPlatesOut => isPlate1Out && isPlate2Out && !isPlate3Out;
  bool get hasAllIn => !isPlate1Out && !isPlate2Out && !isPlate3Out;

  set shotBy(GearId val) {
    if (val == GearId.initial()) {
      _shotBy = val;
      return;
    }
    if (_shotBy != val) {
      _shotBy = val;
      shotCallback(val);
      shotCallback2(val);
    }
  }

  GearId get shotBy => _shotBy;

  void resetShotBy() => _shotBy = GearId.initial();

  void fireAllPlates() {
    // We must only modify only this value because otherwise it would not work
    // if some plates are out or when all are in, depending on the field values
    isPlate3Out = true;
  }

  bool get isPlate3Out => _isPlate3Out;
  set isPlate3Out(bool val) {
    if (_isPlate3Out != val) {
      _isPlate3Out = val;
      lastPlateFiredCallback();
    }
  }

  set plate1(PlateState val) {
    var isIn = _plate1 == PlateState.Inserted;
    var valIsIn = val == PlateState.Inserted;

    _plate1 = val;

    if (isIn != valIsIn) {
      plate1Callback(valIsIn);
    }
  }

  set plate2(PlateState val) {
    var isIn = _plate2 == PlateState.Inserted;
    var valIsIn = val == PlateState.Inserted;

    _plate2 = val;

    if (isIn != valIsIn) {
      plate2Callback(valIsIn);
    }
  }

  Vest() {
    reset();
  }

  Vest.from(List<int> bytes) {
    updateFrom(bytes);
  }

  static int immunityToInt(VestImmunity i) {
    switch (i) {
      case VestImmunity.Normal:
        return 0;
      case VestImmunity.Immune:
        return 1;
      case VestImmunity.ShootingRangeMode:
        return 2;
    }

    assert(false);
    return null;
  }

  static VestImmunity intToImmunity(int i) {
    switch (i) {
      case 0:
        return VestImmunity.Normal;
      case 1:
        return VestImmunity.Immune;
      case 2:
        return VestImmunity.ShootingRangeMode;
    }

    assert(false);
    return null;
  }

  static PlateState intToPlateState(int i) {
    switch (i) {
      case 0x00:
        return PlateState.Inserted;
      case 0x01:
        return PlateState.Out;
      case 0x11:
        return PlateState.OutLedOn;
      case 0x21:
        return PlateState.OutBlinking;
    }

    print('Strange plate state: $i');
    assert(false);
    return null;
  }

  static int plateStateToInt(PlateState i) {
    switch (i) {
      case PlateState.Inserted:
        return 0x00;
      case PlateState.Out:
        return 0x01;
      case PlateState.OutLedOn:
        return 0x11;
      case PlateState.OutBlinking:
        return 0x21;
    }

    assert(false);
    return null;
  }

  @override
  void reset() {
    id = GearId.initial();
    battery = 0;
    isLightsOn = true;
    immunity = VestImmunity.Normal;
    _plate1 = PlateState.Inserted;
    _plate2 = PlateState.Inserted;
    isPlate3Out = false;
    shotBy = GearId.none();
  }

  @override
  List<int> toBytes() {
    var bytes = List<int>();

    bytes.add(0xFF);
    bytes.addAll(id.toBytes());
    bytes.add(2); // device type - vest.
    bytes.add(battery);
    bytes.add(immunityToInt(immunity));
    bytes.add(isLightsOn ? 1 : 0);
    bytes.add(plateStateToInt(_plate1));
    bytes.add(plateStateToInt(_plate2));
    bytes.add(isPlate3Out ? 1 : 0);
    bytes.addAll(shotBy.toCompact());

    // padding.
    bytes.add(0xFE);
    bytes.add(0xFE);

    // generate checksum.
    bytes.add(0);
    _signChecksum(bytes);

    return bytes;
  }

  @override
  void updateFrom(List<int> bytes) {
    if (bytes.length != 20) {
      print(bytes);
      throw new ByteParseException();
    }
    if (bytes[7] != 2) {
      print('Unexpected device type: ${bytes[7]}');
      throw new ByteParseException();
    }

    id = GearId.fromBytes(bytes.getRange(1, 7).toList());
    battery = bytes[8];
    immunity = intToImmunity(bytes[9]);
    isLightsOn = bytes[10] != 0;
    plate1 = intToPlateState(bytes[11]);
    plate2 = intToPlateState(bytes[12]);
    isPlate3Out = bytes[13] != 0;
    shotBy = GearId.fromCompact(bytes.getRange(14, 17).toList());

    initialDataSum = 0;
    bytes.forEach((b) => initialDataSum += b);
  }

  @override
  String toString() {
    return 'Vest { '
        'id: $id, '
        'battery: $battery, '
        'immunity: $immunity, '
        'isLightsOn: $isLightsOn, '
        'plate1: $_plate1, '
        'plate2: $_plate2, '
        'isPlate3Out: $isPlate3Out, '
        'shotBy: $shotBy }';
  }
}

class Headset extends Gear {

  GearId id;
  int battery;
  bool isImmune;
  bool isHeadshot;
  GearId _shotBy;

  set shotBy(GearId val) {
    if (val == GearId.initial()) {
      _shotBy = val;
      return;
    }
    if (_shotBy != val) {
      _shotBy = val;
      shotCallback(val);
      shotCallback2(val);
    }
  }

  GearId get shotBy => _shotBy;

  Function(GearId shooter) shotCallback = (_) {};
  Function(GearId shooter) shotCallback2 = (_) {};

  void resetShotBy() => _shotBy = GearId.initial();

  Headset() {
    reset();
  }

  Headset.from(List<int> bytes) {
    updateFrom(bytes);
  }

  @override
  void reset() {
    id = GearId.initial();
    battery = 0;
    isImmune = false;
    isHeadshot = false;
    shotBy = GearId.none();
  }

  @override
  List<int> toBytes() {
    var bytes = List<int>();

    bytes.add(0xFF); // SOF
    bytes.addAll(id.toBytes());
    bytes.add(3); // device type - headset.
    bytes.add(battery);
    bytes.add(isImmune ? 1 : 0);
    if (isHeadshot) {
      bytes.add(1);
      bytes.add(1);
      bytes.add(1);
    } else {
      bytes.add(0);
      bytes.add(0);
      bytes.add(0);
    }
    bytes.addAll(shotBy.toCompact());
    for (var i = 0; i < 3; i++)
      bytes.add(0xFE); // padding.

    bytes.add(0);
    _signChecksum(bytes);

    return bytes;
  }

  @override
  void updateFrom(List<int> bytes) {
    if (bytes.length != 20) {
      throw new ByteParseException();
    }
    if (bytes[7] != 3) {
      print('Unexpected device type: ${bytes[7]}');
      throw new ByteParseException();
    }

    id = GearId.fromBytes(bytes.getRange(1, 7).toList());
    battery = bytes[8];
    isImmune = bytes[9] != 0;
    isHeadshot = bytes[10] != 0;
    // 11, 12 are the same as 10.
    shotBy = GearId.fromCompact(bytes.getRange(13, 16).toList());

    initialDataSum = 0;
    bytes.forEach((b) => initialDataSum += b);
  }

  @override
  String toString() {
    return 'Headset { '
        'id: $id, '
        'battery: $battery, '
        'isImmune: $isImmune, '
        'isHeadshot: $isHeadshot, '
        'shotBy: $shotBy }';
  }
}
