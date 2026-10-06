import 'package:flutter/material.dart';

class DefaultPageController extends StatelessWidget {
  final PageController controller;
  final Widget child;

  const DefaultPageController({
    super.key,
    required this.controller,
    required this.child,
  });

  static PageController of(BuildContext context) {
    final DefaultPageController? result = context.findAncestorWidgetOfExactType<DefaultPageController>();
    assert(result != null, 'No DefaultPageController found in context');
    return result!.controller;
  }

  @override
  Widget build(BuildContext context) {
    return child;
  }
} 