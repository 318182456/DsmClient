// @dart=2.10
import '../models/app_release.dart';

class UpdateRoute {
  static const domestic = 'https://edgeone.gh-proxy.org/';
  static String download(String original, String prefix) {
    final uri = Uri.tryParse(original ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com' || uri.port != 443 ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        !uri.path.startsWith('/${AppRelease.repository}/releases/download/') ||
        uri.pathSegments.length != 6 ||
        uri.pathSegments.any((p) => p == '.' || p == '..' || p.contains('/') || p.contains('\\'))) {
      throw FormatException('更新地址不是本项目的 GitHub 发布附件');
    }
    if ((prefix ?? '').isEmpty) return original;
    final proxy = Uri.tryParse(prefix.trim());
    if (proxy == null || proxy.scheme != 'https' || proxy.host.isEmpty ||
        proxy.userInfo.isNotEmpty || proxy.hasQuery || proxy.hasFragment) {
      throw FormatException('代理前缀必须是有效的 HTTPS 地址');
    }
    return '${proxy.toString().replaceFirst(RegExp(r'/+$'), '')}/$original';
  }
}
