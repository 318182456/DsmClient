import 'package:flutter/material.dart';
import 'package:dsm_client/models/torrent_presentation.dart';

Future<Map<String, String>> showTorrentFilters(
        BuildContext context, List<Map> tasks,
        {bool transmission = false, Map<String, String> current = const {}}) =>
    showModalBottomSheet<Map<String, String>>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) {
          final chosen = Map<String, String>.from(current);
          return StatefulBuilder(builder: (context, update) {
            Widget field(String key, String title, Iterable<String> options,
                String empty) {
              final values = options.toSet()..add('');
              if (chosen[key] != null) values.add(chosen[key]);
              final sorted = values.toList()..sort();
              return Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: DropdownButtonFormField<String>(
                      key: ValueKey('filter-$key'),
                      value: chosen[key] == null ? 'all' : 'v:${chosen[key]}',
                      isExpanded: true,
                      decoration: InputDecoration(labelText: title),
                      items: [
                        DropdownMenuItem(value: 'all', child: Text('全部')),
                        ...sorted.map((v) => DropdownMenuItem(
                            value: 'v:$v',
                            child: Text(v.isEmpty ? empty : v,
                                maxLines: 1, overflow: TextOverflow.ellipsis)))
                      ],
                      onChanged: (v) => update(() {
                            if (v == 'all')
                              chosen.remove(key);
                            else
                              chosen[key] = v.substring(2);
                          })));
            }

            return SafeArea(
                child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * .9),
                    child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(20, 20, 20,
                            20 + MediaQuery.of(context).viewInsets.bottom),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('筛选任务',
                                  style: Theme.of(context).textTheme.headline6),
                              SizedBox(height: 20),
                              if (!transmission)
                                field(
                                    'category',
                                    '分类',
                                    tasks.map(TorrentPresentation.category),
                                    '未分类'),
                              field(
                                  'tag',
                                  '标签',
                                  tasks.expand(TorrentPresentation.tags),
                                  '无标签'),
                              field(
                                  'tracker',
                                  'Tracker',
                                  tasks.expand(TorrentPresentation.trackers),
                                  '无 Tracker'),
                              field(
                                  'directory',
                                  '保存目录',
                                  tasks.map(TorrentPresentation.directory),
                                  '未设置目录'),
                              ElevatedButton(
                                  onPressed: () => Navigator.pop(sheet, chosen),
                                  child: Text('应用筛选')),
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(sheet, <String, String>{}),
                                  child: Text('清除筛选')),
                            ]))));
          });
        });
