import 'api.dart';

Future<void> deleteMediaFile(String path,
    {Future<Map> Function(List<String>) start,
    Future<Map> Function(String) status,
    Future<void> Function() wait}) async {
  if (path == null ||
      !path.startsWith('/') ||
      path == '/' ||
      path.split('/').contains('..')) throw ArgumentError('无效的文件路径');
  final response = await (start ?? Api.deleteTask)([path]);
  final id = '${(response['data'] ?? {})['taskid'] ?? ''}';
  if (response['success'] != true || id.isEmpty) throw StateError('删除请求失败');
  for (var attempt = 0; attempt < 60; attempt++) {
    final result = await (status ?? Api.deleteResult)(id);
    final data = result['data'] as Map ?? {};
    if (result['success'] != true ||
        data['has_fail'] == true ||
        (data['errors'] is List && (data['errors'] as List).isNotEmpty))
      throw StateError('删除失败，请检查文件权限');
    if (data['finished'] == true) return;
    if (wait != null)
      await wait();
    else
      await Future.delayed(Duration(milliseconds: 500));
  }
  throw StateError('删除任务尚未完成，请刷新文件列表确认结果');
}
