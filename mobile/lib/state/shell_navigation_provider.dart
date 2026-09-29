import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab indices for [AppShell]'s destinations — shared so screens pushed on
/// top of the shell (Match Setup, Preflight) can redirect into a specific
/// tab (e.g. Preflight landing the umpire on Live once a broadcast starts)
/// without a global navigator key.
abstract class ShellTab {
  static const home = 0;
  static const live = 1;
  static const devices = 2;
  static const recordings = 3;
  static const settings = 4;
}

/// Backs [selectedShellTabProvider] — [AppShell] watches this for which
/// [ShellTab] index to show; `select()` is how anything outside the shell
/// (or its own NavigationBar) changes it.
class SelectedShellTabNotifier extends Notifier<int> {
  @override
  int build() => ShellTab.home;

  void select(int index) => state = index;
}

final selectedShellTabProvider =
    NotifierProvider<SelectedShellTabNotifier, int>(
      SelectedShellTabNotifier.new,
    );
