/*
 * 创建日期：23/12/19 下午 05:31
 * 版权所有：青岛人才在线企业服务管理有限公司
 */

import 'package:flutter/material.dart';
import 'dart:math';

class Label extends StatelessWidget {
  Label(this.name, this.color, {this.fill: false, this.fontSize, this.height});
  final String name;
  final Color color;
  final bool fill;
  final double fontSize;
  final double height;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = fill ? color : theme.cardColor;
    Color foreground = fill
        ? (color.computeLuminance() > .18 ? Color(0xff17243a) : Colors.white)
        : color;
    double contrast(Color a, Color b) =>
        (max(a.computeLuminance(), b.computeLuminance()) + .05) /
        (min(a.computeLuminance(), b.computeLuminance()) + .05);
    final ink = theme.colorScheme.onSurface;
    for (var step = 0;
        step < 10 && contrast(foreground, background) < 4.5;
        step++) {
      foreground = Color.lerp(foreground, ink, .25);
    }
    return Container(
      constraints: BoxConstraints(minHeight: max<double>(height ?? 0.0, 24.0)),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        color: fill ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        name,
        style: TextStyle(
            color: foreground,
            fontSize: max<double>(fontSize ?? 11.0, 11.0),
            fontWeight: FontWeight.w500),
      ),
    );
  }
}
