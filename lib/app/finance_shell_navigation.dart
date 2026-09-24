import 'package:flutter/material.dart';

/// Exposes the shell destinations to shortcut pages without pushing a route
/// above the application's primary navigation.
class FinanceShellNavigation extends InheritedWidget {
  const FinanceShellNavigation({
    required this.selectDestination,
    required super.child,
    super.key,
  });

  static const accountsIndex = 1;
  static const foundationIndex = 2;
  static const envelopesIndex = 3;
  static const savingsGoalsIndex = 4;
  static const prioritiesIndex = 6;
  static const importsIndex = 7;

  final ValueChanged<int> selectDestination;

  static FinanceShellNavigation of(BuildContext context) {
    final navigation = maybeOf(context);
    assert(navigation != null, 'FinanceShellNavigation is required.');
    return navigation!;
  }

  static FinanceShellNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FinanceShellNavigation>();

  @override
  bool updateShouldNotify(FinanceShellNavigation oldWidget) =>
      selectDestination != oldWidget.selectDestination;
}
