import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/xterm.dart';

import '../../controllers/terminal_controller.dart';
import 'terminal_theme.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  HomeController controller = Get.put(HomeController(), permanent: true);
  ManjaroTerminalTheme terminalTheme = ManjaroTerminalTheme();
  bool visible = false || kDebugMode;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: visible ? terminalTheme.background : Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            visible = !visible;
            setState(() {});
          },
          behavior: HitTestBehavior.translucent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: EdgeInsets.all(w(8)),
                child: Visibility(
                  visible: visible,
                  // IgnorePointer
                  child: AbsorbPointer(
                    absorbing: false,
                    child: RepaintBoundary(
                      child: TerminalView(
                        controller.terminal,
                        readOnly: false,
                        backgroundOpacity: 1,
                        theme: ManjaroTerminalTheme(),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Material(
                  borderRadius: BorderRadius.circular(w(12)),
                  color: Theme.of(context).colorScheme.surface,
                  child: SizedBox(
                    width: w(300),
                    child: Padding(
                      padding: EdgeInsets.all(w(12)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Center(
                            child: RepaintBoundary(
                              child: LoadingProgress(
                                minRadius: 6,
                                strokeWidth: 3,
                                increaseRadius: 3,
                              ),
                            ),
                          ),
                          SizedBox(height: w(12)),
                          GetBuilder<HomeController>(builder: (controller) {
                            return Column(
                              children: [
                                Stack(
                                  children: [
                                    Container(
                                      height: w(5),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(w(3)),
                                      ),
                                    ),
                                    AnimatedContainer(
                                      duration: 300.milliseconds,
                                      height: w(5),
                                      width: w(300) * controller.progress,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(w(3)),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: w(8)),
                                Text(
                                  controller.currentProgress.trim(),
                                  style: TextStyle(
                                    fontSize: w(12),
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
