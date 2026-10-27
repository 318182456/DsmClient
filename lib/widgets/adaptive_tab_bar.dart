import 'dart:math';
import 'package:flutter/material.dart';

class AdaptiveTabBar extends StatelessWidget implements PreferredSizeWidget {
  final List<Widget> tabs;
  final TabController controller;
  final bool isScrollable;
  final TabBarIndicatorSize indicatorSize;
  final Color labelColor, unselectedLabelColor;
  final Decoration indicator;
  const AdaptiveTabBar(
      {Key key,
      @required this.tabs,
      this.controller,
      this.isScrollable = false,
      this.indicatorSize,
      this.labelColor,
      this.unselectedLabelColor,
      this.indicator})
      : super(key: key);
  @override
  Size get preferredSize => Size.fromHeight(48);
  double widthOf(BuildContext context, Widget widget) {
    if (widget is Padding)
      return widget.padding.resolve(Directionality.of(context)).horizontal +
          widthOf(context, widget.child);
    String text;
    if (widget is Tab) text = widget.text;
    if (widget is Text) text = widget.data;
    if (text == null) return 64;
    final theme = Theme.of(context);
    final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: (theme.tabBarTheme.labelStyle ?? theme.textTheme.bodyText2)
                .copyWith(fontWeight: FontWeight.w700)),
        textDirection: Directionality.of(context),
        textScaleFactor: MediaQuery.of(context).textScaleFactor)
      ..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final widths = tabs.map((tab) => widthOf(context, tab)).toList();
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final fixed = widths.isEmpty ||
            (widths.reduce(max) + 12) * widths.length <= available;
        final total = widths.fold<double>(0, (sum, width) => sum + width + 24);
        return TabBar(
            tabs: tabs,
            controller: controller,
            isScrollable: !fixed,
            labelPadding: EdgeInsets.symmetric(horizontal: fixed ? 6 : 12),
            physics: fixed || total <= available
                ? NeverScrollableScrollPhysics()
                : ClampingScrollPhysics(),
            indicatorSize: indicatorSize,
            indicator: indicator,
            labelColor: labelColor,
            unselectedLabelColor: unselectedLabelColor);
      });
}
