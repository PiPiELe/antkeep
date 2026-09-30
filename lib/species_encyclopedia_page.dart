import 'package:flutter/material.dart';

import 'domain/species_profile.dart';

class SpeciesEncyclopediaPage extends StatefulWidget {
  const SpeciesEncyclopediaPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SpeciesEncyclopediaPage> createState() =>
      _SpeciesEncyclopediaPageState();
}

class _SpeciesEncyclopediaPageState extends State<SpeciesEncyclopediaPage> {
  late final _search = TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = speciesProfiles
        .where((profile) => profile.matches(_search.text))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('蚂蚁百科')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '搜索名称、别名或学名',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除搜索',
                                onPressed: () => setState(_search.clear),
                                icon: const Icon(Icons.close),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '已收录 ${speciesProfiles.length} 种 · 离线可查',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (profiles.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.search_off, size: 40),
                      SizedBox(height: 12),
                      Text('暂无匹配的物种'),
                      SizedBox(height: 8),
                      Text('试试其他名称或别名，更多资料将陆续补充。'),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.builder(
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(profile.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.scientificName,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('别名：${profile.aliases.join('、')}'),
                            const SizedBox(height: 6),
                            Text('饲养难度 ${profile.difficulty}/5'),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SpeciesDetailPage(profile: profile),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SpeciesDetailPage extends StatelessWidget {
  const SpeciesDetailPage({super.key, required this.profile});

  final SpeciesProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(profile.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [colors.primaryContainer, colors.tertiaryContainer],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.scientificName,
                    style: TextStyle(
                      color: colors.onPrimaryContainer,
                      fontStyle: FontStyle.italic,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Chip(
                    avatar: const Icon(Icons.star_rounded),
                    label: Text('饲养难度 ${profile.difficulty}/5'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _InfoSection(
              title: '基础分类',
              icon: Icons.biotech_outlined,
              children: [
                _InfoRow('其他名称', profile.aliases.join('、')),
                _InfoRow('亚科', profile.subfamily),
                _InfoRow('属', profile.genus),
              ],
            ),
            _InfoSection(
              title: '体型数据',
              icon: Icons.straighten_outlined,
              children: [
                _InfoRow('蚁后', profile.queenSize),
                _InfoRow('工蚁', profile.workerSize),
                _InfoRow('工蚁分化', profile.workerDifferentiation),
              ],
            ),
            _InfoSection(
              title: '饲养信息',
              icon: Icons.cottage_outlined,
              children: [
                _InfoRow('温度', profile.temperature),
                _InfoRow('湿度', profile.humidity),
                const SizedBox(height: 8),
                Text('生物特性', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final trait in profile.traits)
                      Chip(label: Text(trait)),
                  ],
                ),
                const SizedBox(height: 8),
                _InfoRow('食物', profile.food),
                _InfoRow('筑巢', profile.nesting),
              ],
            ),
            _InfoSection(
              title: '资料说明',
              icon: Icons.info_outline,
              children: [Text(profile.source)],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
        final valueWidget = Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        );
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, const SizedBox(height: 4), valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 88, child: labelWidget),
            const SizedBox(width: 12),
            Expanded(child: valueWidget),
          ],
        );
      },
    ),
  );
}
