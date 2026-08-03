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

  // 0: 隐藏, 1: 显示 MaiBot 终端, 2: 显示 NapCat 终端
  int displayMode = 0;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      displayMode = 1;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isVisible = displayMode != 0;
    return Scaffold(
      backgroundColor: isVisible
          ? terminalTheme.background
          : Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            setState(() {
              if (displayMode == 0) {
                // 切换到 MaiBot 终端
                displayMode = 1;
              } else if (displayMode == 1) {
                // 如果 NapCat 已经开始启动并创建了 terminal 实例，允许切换到 NapCat 终端
                if (controller.napcatClient.isConnected) {
                  displayMode = 2;
                } else {
                  // 未启动则直接恢复隐藏
                  displayMode = 0;
                }
              } else {
                // 恢复默认隐藏
                displayMode = 0;
              }
            });
          },
          behavior: HitTestBehavior.translucent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: EdgeInsets.all(w(8)),
                child: Visibility(
                  visible: isVisible,
                  child: AbsorbPointer(
                    absorbing: false,
                    child: displayMode == 2
                        ? TerminalView(
                            controller.napcatShowTerminal,
                            readOnly: false,
                            backgroundOpacity: 1,
                            theme: terminalTheme,
                          )
                        : TerminalView(
                            controller.terminal,
                            readOnly: false,
                            backgroundOpacity: 1,
                            theme: terminalTheme,
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
                            child: LoadingProgress(
                              minRadius: 6,
                              strokeWidth: 3,
                              increaseRadius: 3,
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
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.2),
                                        borderRadius:
                                            BorderRadius.circular(w(3)),
                                      ),
                                    ),
                                    AnimatedContainer(
                                      duration: 300.milliseconds,
                                      height: w(5),
                                      width: w(300) * controller.progress,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        borderRadius:
                                            BorderRadius.circular(w(3)),
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
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
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
