import 'package:flutter/material.dart';

class WorkspaceHeader extends StatelessWidget {
  final String title, subtitle;
  final Widget leading, trailing;
  final EdgeInsetsGeometry padding;
  const WorkspaceHeader(
      {@required this.title,
      this.subtitle,
      this.leading,
      this.trailing,
      this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 20)});
  @override
  Widget build(BuildContext context) => Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (leading != null) ...[leading, SizedBox(width: 14)],
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.headline5),
          if (subtitle != null) ...[
            SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.caption)
          ],
        ])),
        if (trailing != null) trailing,
      ]));
}

class WorkspaceEmpty extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final Widget action;
  const WorkspaceEmpty(this.title,
      {this.icon = Icons.inbox_outlined, this.detail, this.action});
  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(children: [
        Container(
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24)),
            child: Icon(icon,
                size: 30,
                color: Theme.of(context).colorScheme.onPrimaryContainer)),
        SizedBox(height: 20),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.subtitle1),
        if (detail != null) ...[
          SizedBox(height: 8),
          Text(detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.caption)
        ],
        if (action != null) ...[SizedBox(height: 12), action],
      ]));
}
