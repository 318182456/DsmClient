// @dart=2.10
import 'dart:convert';

import '../models/api_model.dart';

/// Protocol compatibility independent of Flutter and the current NAS session.
class DsmCompatibility {
  static String firmwareVersion(String value) {
    final match = RegExp(r'(?:DSM\s*)?(\d+\.\d+(?:\.\d+)?(?:-\d+)?)',
            caseSensitive: false)
        .firstMatch(value ?? '');
    return match?.group(1) ?? '';
  }

  static int firmwareMajor(String value, {int fallback = 7}) {
    return int.tryParse(firmwareVersion(value).split('.').first) ?? fallback;
  }

  static int supportedVersion(ApiModel info, int preferred) {
    if (info == null) return preferred;
    final minimum = (info.minVersion ?? 1).toInt();
    final maximum = (info.maxVersion ?? minimum).toInt();
    if (maximum < minimum) return preferred;
    return preferred.clamp(minimum, maximum).toInt();
  }

  static String apiName(dynamic value) {
    final name = '$value';
    if (name.startsWith('"') && name.endsWith('"')) {
      try {
        return jsonDecode(name) as String;
      } catch (_) {}
    }
    return name;
  }

  static String apiPath(ApiModel info, String fallback) {
    final path = info?.path;
    if (path == null ||
        path.startsWith('/') ||
        path.contains('..') ||
        !RegExp(r'^[a-zA-Z0-9_./-]+\.cgi$').hasMatch(path)) return fallback;
    return path;
  }

  static Map<String, dynamic> prepareParameters(
      Map<String, dynamic> source, Map<String, ApiModel> catalog) {
    final result = Map<String, dynamic>.from(source ?? {});
    final info = catalog[apiName(result['api'])];
    final requested = int.tryParse(apiName(result['version']));
    if (requested != null && info != null) {
      result['version'] = supportedVersion(info, requested);
    }
    if (apiName(result['api']) == 'SYNO.Entry.Request' &&
        result['compound'] is String) {
      try {
        final compound = jsonDecode(result['compound']);
        if (compound is List) {
          result['compound'] = jsonEncode(compound
              .map((entry) =>
                  prepareParameters(Map<String, dynamic>.from(entry), catalog))
              .toList());
        }
      } catch (_) {
        // Let DSM report invalid compound data without changing its meaning.
      }
    }
    return result;
  }

  static String connectionKey(String baseUrl) {
    final uri = Uri.tryParse(baseUrl ?? '');
    if (uri == null || !uri.hasAuthority) return '';
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.port}'
        '${uri.path.replaceFirst(RegExp(r'/+$'), '')}';
  }

  static bool sameConnection(String first, String second) {
    final key = connectionKey(first);
    return key.isNotEmpty && key == connectionKey(second);
  }
}

/// Tokens are scoped by both connection and SID, including parallel NAS cards.
class DsmSessionTokens {
  final Map<String, String> _tokens = {};

  String _key(String host, String sid) =>
      '${DsmCompatibility.connectionKey(host)}|${sid ?? ''}';

  void remember(String host, String sid, String token) {
    if ((sid ?? '').isEmpty || DsmCompatibility.connectionKey(host).isEmpty)
      return;
    final key = _key(host, sid);
    if ((token ?? '').isEmpty) {
      _tokens.remove(key);
    } else {
      _tokens[key] = token;
    }
  }

  String tokenFor(String host, String sid) => _tokens[_key(host, sid)] ?? '';

  void clear() => _tokens.clear();
}
