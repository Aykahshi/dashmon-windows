import 'dart:convert';
import 'dart:io';

class Dashmon {
  late Process _process;
  final List<String> args;

  Future? _throttler;
  final String _libAbsolutePrefix =
      Directory('lib').absolute.path.replaceAll('\\', '/');

  final List<String> _proxiedArgs = [];
  bool _isFvm = false;
  bool _isAttach = false;

  Dashmon(this.args) {
    _parseArgs();
  }

  void _parseArgs() {
    for (String arg in args) {
      if (arg == '--fvm') {
        _isFvm = true;
        continue;
      }

      if (arg == 'attach') {
        _isAttach = true;
        continue;
      }

      _proxiedArgs.add(arg);
    }
  }

  Future<void> _runUpdate() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _process.stdin.write('r');
  }

  void _print(String line) {
    final trim = line.trim();
    if (trim.isNotEmpty) {
      print(trim);
    }
  }

  void _processLine(String line) {
    if (line.contains('More than one device connected')) {
      _print(
          "Dashmon found multiple devices, device choosing menu isn't supported yet, please use the -d argument");
      _process.kill();
      exit(1);
    } else {
      _print(line);
    }
  }

  void _processError(String line) {
    _print(line);
  }

  void _configureStdin() {
    if (!stdin.hasTerminal) {
      return;
    }

    if (Platform.isWindows) {
      // Windows terminals typically reject raw mode toggles; keep defaults.
      return;
    }

    try {
      stdin.lineMode = false;
      stdin.echoMode = false;
    } on StdinException {
      // Fall back to default behaviour if the console does not support raw mode.
    }
  }

  bool _isLibPath(String path) {
    final normalized = path.replaceAll('\\', '/');

    return normalized.startsWith(_libAbsolutePrefix) ||
        normalized.startsWith('lib/') ||
        normalized.startsWith('./lib/');
  }

  Future<void> start() async {
    _process = await (_isFvm
        ? Process.start(
            'fvm', ['flutter', _isAttach ? 'attach' : 'run', ..._proxiedArgs])
        : Process.start(
            'flutter', [_isAttach ? 'attach' : 'run', ..._proxiedArgs]));

    _process.stdout.transform(utf8.decoder).forEach(_processLine);

    _process.stderr.transform(utf8.decoder).forEach(_processError);

    final currentDir = File('.');

    currentDir.watch(recursive: true).listen((event) {
      if (_isLibPath(event.path)) {
        if (_throttler == null) {
          _throttler = _runUpdate();
          _throttler?.then((_) {
            print('Sent reload request...');
            _throttler = null;
          });
        }
      }
    });

    _configureStdin();
    stdin.transform(utf8.decoder).forEach(_process.stdin.write);
    final exitCode = await _process.exitCode;
    exit(exitCode);
  }
}
