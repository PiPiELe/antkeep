import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'domain/memorial.dart';
import 'domain/models.dart';
import 'domain/share_card_data.dart';
import 'memorial_share_page.dart';
import 'share_cards_page.dart';

class ShareContentPage extends StatefulWidget {
  const ShareContentPage({super.key});

  @override
  State<ShareContentPage> createState() => _ShareContentPageState();
}

class _ShareContentPageState extends State<ShareContentPage> {
  // Null selects the memorial template.
  ShareCardKind? _kind = ShareCardKind.colony;
  late Future<(List<Colony>, List<Memorial>)> _content;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  Future<(List<Colony>, List<Memorial>)> _load() async {
    final colonies = await AppDatabase.instance.listColonies();
    final memorials = await AppDatabase.instance.listMemorials();
    return (colonies, memorials);
  }

  Future<void> _openColony(Colony colony) async {
    if (_opening) return;
    final kind = _kind!;
    setState(() => _opening = true);
    try {
      final records = await AppDatabase.instance.listRecords(colony.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShareCardsPage(
            colony: colony,
            records: records,
            initialKind: kind,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('读取分享内容失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('选择分享内容')),
    body: AbsorbPointer(
      absorbing: _opening,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final kind in ShareCardKind.values)
                      ChoiceChip(
                        label: Text(kind.label),
                        selected: _kind == kind,
                        onSelected: (_) => setState(() => _kind = kind),
                      ),
                    ChoiceChip(
                      label: const Text('纪念分享图'),
                      selected: _kind == null,
                      onSelected: (_) => setState(() => _kind = null),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_kind == null ? '选择纪念，预览并生成图片' : '选择蚁群，再调整分享内容并生成图片'),
              ],
            ),
          ),
          if (_opening) const LinearProgressIndicator(),
          Expanded(
            child: FutureBuilder<(List<Colony>, List<Memorial>)>(
              future: _content,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _content = _load();
                        });
                      },
                      child: const Text('加载失败，点击重试'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final (colonies, memorials) = snapshot.data!;
                final isMemorial = _kind == null;
                final count = isMemorial ? memorials.length : colonies.length;
                if (count == 0) {
                  return Center(
                    child: Text(isMemorial ? '还没有纪念，请先在英灵殿添加' : '还没有蚁群，请先添加蚁群'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: count,
                  itemBuilder: (context, index) {
                    if (isMemorial) {
                      final memorial = memorials[index];
                      return ListTile(
                        leading: const Icon(Icons.landscape_outlined),
                        title: Text(memorial.name),
                        subtitle: Text(memorial.kind.label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                MemorialSharePage(memorial: memorial),
                          ),
                        ),
                      );
                    }
                    final colony = colonies[index];
                    return ListTile(
                      leading: const Icon(Icons.hive_outlined),
                      title: Text(colony.name),
                      subtitle: colony.species == null
                          ? null
                          : Text(colony.species!),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openColony(colony),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
