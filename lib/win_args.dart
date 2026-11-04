import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Reads the real Windows command line (GetCommandLineW + CommandLineToArgvW).
/// Used for "Open with" / double-click, in case Flutter does not forward the file path.
List<String> windowsCommandLineArgs() {
  try {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final s32 = DynamicLibrary.open('shell32.dll');
    final getCmd = k32.lookupFunction<Pointer<Utf16> Function(), Pointer<Utf16> Function()>(
        'GetCommandLineW');
    final toArgv = s32.lookupFunction<
        Pointer<Pointer<Utf16>> Function(Pointer<Utf16>, Pointer<Int32>),
        Pointer<Pointer<Utf16>> Function(Pointer<Utf16>, Pointer<Int32>)>('CommandLineToArgvW');
    final count = calloc<Int32>();
    final argv = toArgv(getCmd(), count);
    final out = <String>[];
    if (argv.address != 0) {
      for (var i = 1; i < count.value; i++) {
        out.add(argv[i].toDartString());
      }
    }
    calloc.free(count);
    return out;
  } catch (_) {
    return const [];
  }
}
