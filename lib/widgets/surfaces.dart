import 'package:flutter/material.dart';
import 'package:neumorphic/neumorphic.dart'
    show CurveType, NeumorphicDecoration;
export 'package:neumorphic/neumorphic.dart' hide NeuCard, NeuButton;

// Shared surfaces retain the existing page layout API during the visual migration.
Color _surface(BuildContext context, NeumorphicDecoration decoration) {
  final theme = Theme.of(context);
  final color = decoration?.color;
  return color == null ||
          color == theme.scaffoldBackgroundColor ||
          color == theme.backgroundColor
      ? theme.cardColor
      : color;
}

OutlinedBorder _shape(BuildContext context, NeumorphicDecoration decoration,
    {bool selected = false}) {
  final border = decoration?.border;
  final side = border is Border && border.isUniform
      ? border.top
      : BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(.32)
              : Theme.of(context).dividerColor,
          width: 1);
  return decoration?.shape == BoxShape.circle
      ? CircleBorder(side: side)
      : RoundedRectangleBorder(
          borderRadius: decoration?.borderRadius ?? BorderRadius.circular(16),
          side: side);
}

class NeuCard extends StatelessWidget {
  final Widget child;
  final double bevel, width, height;
  final CurveType curveType;
  final NeumorphicDecoration decoration;
  final AlignmentGeometry alignment;
  final BoxConstraints constraints;
  final EdgeInsetsGeometry margin, padding;
  final Matrix4 transform;
  final Color color;
  final VoidCallback onPressed;
  const NeuCard(
      {Key key,
      this.child,
      this.bevel = 0,
      this.curveType,
      this.decoration,
      this.width,
      this.height,
      this.alignment,
      this.constraints,
      this.margin,
      this.padding,
      this.transform,
      this.color,
      this.onPressed})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = curveType == CurveType.emboss;
    final background = color ?? _surface(context, decoration);
    Widget content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    if (alignment != null)
      content = Align(alignment: alignment, child: content);
    if (onPressed != null)
      content = InkWell(
          customBorder: _shape(context, decoration),
          onTap: onPressed,
          child: content);
    return Container(
        width: width,
        height: height,
        constraints: constraints,
        margin: margin,
        transform: transform,
        child: Material(
            color: selected && background == theme.cardColor
                ? Color.alphaBlend(
                    theme.colorScheme.primary.withOpacity(.1), background)
                : background,
            shape: _shape(context, decoration, selected: selected),
            clipBehavior: decoration?.clipBehavior ?? Clip.antiAlias,
            child: content));
  }
}

class NeuButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed, onLongPress;
  final EdgeInsetsGeometry padding, margin;
  final NeumorphicDecoration decoration;
  final double bevel;
  final bool enabled;
  const NeuButton(
      {Key key,
      this.child,
      this.onPressed,
      this.onLongPress,
      this.padding = const EdgeInsets.all(12),
      this.margin,
      this.decoration,
      this.bevel = 0,
      this.enabled = true})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final active = enabled && (onPressed != null || onLongPress != null);
    return Padding(
        padding: margin ?? EdgeInsets.zero,
        child: Semantics(
            button: true,
            enabled: active,
            child: Material(
                color: _surface(context, decoration),
                shape: _shape(context, decoration),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                    onTap: active ? onPressed : null,
                    onLongPress: active ? onLongPress : null,
                    customBorder: _shape(context, decoration),
                    child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: 48, minWidth: 48),
                        child: Padding(
                            padding: padding ?? EdgeInsets.zero,
                            child: Opacity(
                                opacity: active ? 1 : .5, child: child)))))));
  }
}
