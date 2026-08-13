import 'package:flutter/material.dart';
import 'package:global_repository/src/screen_adaptor/view_metric.dart';

class NiIconButton extends StatelessWidget {
  const NiIconButton({Key? key, this.child, this.onTap}) : super(key: key);
  final Widget? child;
  final GestureTapCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: context.w(48),
        height: context.w(48),
        child: InkWell(
          borderRadius: BorderRadius.circular(context.w(24)),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(context.w(12)),
            child: child,
          ),
        ),
      ),
    );
  }
}
