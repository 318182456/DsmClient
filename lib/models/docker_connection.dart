// @dart=2.10
class DockerConnection {
  static String dockhandAddress(String nas, Map profile) {
    final base = Uri.tryParse(nas ?? '');
    if (base == null || !base.hasAuthority || !['http', 'https'].contains(base.scheme)) return '';
    final shortcut = profile['shortcut'];
    if (shortcut is Map && shortcut['enable_web_page'] == true) {
      final url = Uri.tryParse('${shortcut['web_page_url'] ?? ''}');
      if (url != null && ['http', 'https'].contains(url.scheme) && url.host.isNotEmpty &&
          url.userInfo.isEmpty && !url.hasQuery && !url.hasFragment) return url.toString();
    }
    final bindings = profile['port_bindings'];
    if (bindings is! List) return '';
    for (final item in (bindings as List).whereType<Map>()) {
      if ('${item['container_port']}' != '3000' || item['type'] == 'udp') continue;
      final port = int.tryParse('${item['host_port']}');
      if (port != null && port > 0 && port <= 65535)
        return Uri(scheme: 'http', host: base.host, port: port).toString();
    }
    return '';
  }
}
