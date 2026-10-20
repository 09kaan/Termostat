import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One stable shell and one horizontal pager for every main section.
/// Physical left-to-right order: Log | Evim | Termostat | Takvim.
/// A finger swipe to the RIGHT therefore goes Termostat -> Evim -> Log.
class HomePager extends StatefulWidget {
  const HomePager({
    super.key,
    required this.pages,
    required this.onRoomSettings,
    required this.onAppSettings,
    this.onRooms,
  }) : assert(pages.length == 4);

  final List<Widget> pages;
  final VoidCallback onRoomSettings;
  final VoidCallback onAppSettings;
  final VoidCallback? onRooms;

  @override
  State<HomePager> createState() => _HomePagerState();
}

class _HomePagerState extends State<HomePager> {
  final PageController _controller = PageController(initialPage: 2);
  int _index = 2;
  bool _roomOpen = false;
  static const _titles = ['Log', 'Evim', 'Termostat', 'Takvim'];
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _index == 1 && widget.onRooms != null
            ? IconButton(
                key: const ValueKey('open-rooms'),
                tooltip: 'Odalar',
                onPressed: widget.onRooms,
                icon: const Text('🏠', style: TextStyle(fontSize: 23)),
              )
            : null,
        title: Text(_titles[_index]),
        centerTitle: !AppAppearance.isWarm(context),
        actions: [
          IconButton(
            key: const ValueKey('section-settings'),
            icon: const Icon(Icons.tune),
            tooltip: _index == 1 ? 'Ev ve ampul ayarları' : 'Uygulama ayarları',
            onPressed: _index == 1
                ? widget.onRoomSettings
                : widget.onAppSettings,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: NotificationListener<RoomDetailNotification>(
          onNotification: (event) {
            if (_roomOpen != event.open) setState(() => _roomOpen = event.open);
            return true;
          },
          child: PageView(
            key: const ValueKey('main-pager'),
            controller: _controller,
            physics: _index == 1 && _roomOpen
                ? const NeverScrollableScrollPhysics()
                : null,
            // Don't let ambient RTL direction silently invert physical swipes.
            reverse: Directionality.of(context) == TextDirection.rtl,
            onPageChanged: (index) => setState(() => _index = index),
            children: [
              for (var i = 0; i < widget.pages.length; i++)
                _KeptPage(
                  key: ValueKey('kept-page-$i'),
                  child: MainSectionActive(
                    active: _index == i,
                    child: widget.pages[i],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeptPage extends StatefulWidget {
  const _KeptPage({super.key, required this.child});
  final Widget child;
  @override
  State<_KeptPage> createState() => _KeptPageState();
}

class _KeptPageState extends State<_KeptPage>
    with AutomaticKeepAliveClientMixin<_KeptPage> {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Kept-alive offscreen rooms must not intercept the system back button.
class MainSectionActive extends InheritedWidget {
  const MainSectionActive({
    super.key,
    required this.active,
    required super.child,
  });
  final bool active;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainSectionActive>()?.active ??
      true;
  @override
  bool updateShouldNotify(MainSectionActive oldWidget) =>
      active != oldWidget.active;
}

/// The detail owns horizontal gestures; the main pager resumes on the plan.
class RoomDetailNotification extends Notification {
  const RoomDetailNotification(this.open);
  final bool open;
}
