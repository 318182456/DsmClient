import 'package:flutter/material.dart';

Future<String> showMediaActions(BuildContext context, String title,
        {bool canDelete = false, bool more = false}) =>
    showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (sheet) => SafeArea(
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(sheet).textTheme.subtitle1)),
              for (final entry in <String, String>{
                'restart': '从头播放',
                'continuous': '从这里连续播放',
                'details': '详细信息',
                if (canDelete) 'delete': '删除',
                if (more) 'more': '更多文件操作'
              }.entries)
                ListTile(
                    leading: Icon(
                        const {
                          'restart': Icons.replay,
                          'continuous': Icons.playlist_play,
                          'details': Icons.info_outline,
                          'delete': Icons.delete_outline,
                          'more': Icons.more_horiz
                        }[entry.key],
                        color: entry.key == 'delete'
                            ? Theme.of(sheet).colorScheme.error
                            : null),
                    title: Text(entry.value,
                        style: entry.key == 'delete'
                            ? TextStyle(
                                color: Theme.of(sheet).colorScheme.error)
                            : null),
                    onTap: () => Navigator.pop(sheet, entry.key)),
              Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                      width: double.infinity,
                      child: TextButton(
                          onPressed: () => Navigator.pop(sheet),
                          child: Text('取消')))),
            ]))));
