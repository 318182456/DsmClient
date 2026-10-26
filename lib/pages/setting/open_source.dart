import 'package:flutter/material.dart';

/// Use the licenses bundled with the actual build, rather than a stale manual
/// list that still mentioned removed tracking plugins.
class OpenSource extends StatelessWidget {
  const OpenSource({Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) => LicensePage(applicationName: 'DsmClient');
}
