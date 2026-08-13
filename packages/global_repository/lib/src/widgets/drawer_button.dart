import 'package:flutter/material.dart';
import 'custom_icon_button.dart';
import '../screen_adaptor/view_metric.dart';

class DrawerOpenButton extends StatelessWidget {
  const DrawerOpenButton({Key? key, this.scaffoldContext}) : super(key: key);
  final BuildContext? scaffoldContext;

  @override
  Widget build(BuildContext context) {
    return NiIconButton(
      child: Icon(
        Icons.menu,
        size: context.w(24),
      ),
      onTap: () {
        Scaffold.of(scaffoldContext ?? context).openDrawer();
      },
    );
  }
}
