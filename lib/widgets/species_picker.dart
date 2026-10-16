import 'package:flutter/material.dart';

import '../domain/imported_species_catalog.dart';

const _builtInSpeciesOptions = <String, List<String>>{
  '收获蚁': [
    '工匠收获蚁',
    '野蛮收获蚁（原生收获蚁）',
    '红胸收获蚁',
    '大头收获蚁',
    '强壮收获蚁',
    '针毛收获蚁',
    '无颚齿收获蚁',
    '勤劳收获蚁',
    '白刺收获蚁',
    '东方收获蚁',
    '巨首收获蚁（肯尼亚收获蚁）',
    '希伯来收获蚁',
  ],
  '弓背蚁': [
    '费氏弓背蚁',
    '大头弓背蚁',
    '尼科巴弓背蚁',
    '巴瑞弓背蚁',
    '拟光腹弓背蚁',
    '全黄土耳其弓背蚁',
    '日本弓背蚁',
    '广布弓背蚁',
    '窄颈弓背蚁（窄径）',
    '红头弓背蚁',
    '沃斯曼弓背蚁',
    '神圣弓背蚁',
    '统领弓背蚁（统领蚁）',
    '白纵斑弓背蚁（白纵斑蚁）',
  ],
  '猛蚁': [
    '横纹猛蚁',
    '横纹齿猛蚁',
    '聚纹双刺猛蚁',
    '大齿猛蚁',
    '扁头猛蚁',
    '红足穴猛蚁',
    '山大齿猛蚁',
    '双色曲颊猛蚁',
    '中华细猛蚁',
    '条纹细猛蚁',
    '金属皱突蚁（金属蚁）',
  ],
  '蜜罐蚁': ['墨西哥蜜罐蚁', '大平眼蜜罐蚁'],
  '孔蚁': ['巨人孔蚁'],
  '子弹蚁': ['子弹蚁'],
  '铺道蚁': ['双隆骨铺道蚁', '草地铺道蚁'],
  '多刺蚁': ['拟弓多刺蚁', '拟黑多刺蚁', '双齿多刺蚁', '梅氏多刺蚁'],
  '大头蚁': ['中华大头蚁', '皮氏大头蚁', '伊大头蚁', '宽结大头蚁', '史氏大头蚁'],
  '毛蚁': ['玉米毛蚁', '黑毛蚁', '黄墩蚁', '亮毛蚁'],
  '细长蚁': ['红黑细长蚁', '黑细长蚁', '宾氏细长蚁'],
  '巨首蚁': ['全异巨首蚁', '近缘巨首蚁'],
  '虹臭蚁': ['扁平虹臭蚁', '紫彩虹臭蚁'],
  '盾胸切叶蚁': ['二色盾胸切叶蚁'],
  '原蚁': ['蒙古原蚁'],
  '举腹蚁': ['大阪举腹蚁', '黑褐举腹蚁'],
  '林蚁': ['日本黑褐蚁', '丝光蚁', '红须蚁'],
  '织叶蚁': ['黄猄蚁'],
  '须蚁': ['红胡须蚁（巴巴特斯）'],
  '箭蚁': ['银丝箭蚁（银丝蚁）'],
};

// Retain recognition of saved names and common input variants without duplicate
// picker entries. Existing colony records are not rewritten.
const _builtInSpeciesAliases = <String, String>{
  '全黄弓背蚁': '全黄土耳其弓背蚁',
  '无恶齿收获蚁': '无颚齿收获蚁',
  '铺道蚁': '草地铺道蚁',
  '全蚁巨首蚁': '全异巨首蚁',
  '拟广腹弓背蚁': '拟光腹弓背蚁',
  '费氏弓背蚁（黑金弓背蚁）': '费氏弓背蚁',
  '费事弓背蚁': '费氏弓背蚁',
  '黑金弓背蚁': '费氏弓背蚁',
  '野蛮收获蚁': '野蛮收获蚁（原生收获蚁）',
  '原生收获蚁': '野蛮收获蚁（原生收获蚁）',
  '巨首收获蚁': '巨首收获蚁（肯尼亚收获蚁）',
  '肯尼亚收获蚁': '巨首收获蚁（肯尼亚收获蚁）',
  '希伯来': '希伯来收获蚁',
  '统领弓背蚁': '统领弓背蚁（统领蚁）',
  '统领蚁': '统领弓背蚁（统领蚁）',
  '白纵斑弓背蚁': '白纵斑弓背蚁（白纵斑蚁）',
  '白纵斑蚁': '白纵斑弓背蚁（白纵斑蚁）',
  '金属皱突蚁': '金属皱突蚁（金属蚁）',
  '金属皱猛蚁': '金属皱突蚁（金属蚁）',
  '金属蚁': '金属皱突蚁（金属蚁）',
  '红胡须蚁': '红胡须蚁（巴巴特斯）',
  '巴巴特斯': '红胡须蚁（巴巴特斯）',
  '巴巴斯特': '红胡须蚁（巴巴特斯）',
  '银丝箭蚁': '银丝箭蚁（银丝蚁）',
  '银丝蚁': '银丝箭蚁（银丝蚁）',
  '紫菜蚁': '紫彩虹臭蚁',
  '紫菜虹臭蚁': '紫彩虹臭蚁',
};

final speciesOptions = <String, List<String>>{
  for (final category in {
    ..._builtInSpeciesOptions.keys,
    ...importedSpeciesOptions.keys,
  })
    category: [
      ...?_builtInSpeciesOptions[category],
      ...?importedSpeciesOptions[category],
    ],
};

final speciesAliases = <String, String>{
  ...importedSpeciesAliases,
  ..._builtInSpeciesAliases,
};

Future<String?> pickSpecies(BuildContext context) async {
  final first =
      await showModalBottomSheet<({String value, bool isSearchResult})>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ChoicePickerSheet(
          title: '品种分类/细分种类',
          options: speciesOptions.keys.toList(),
          searchOptions: {
            for (final entry in speciesOptions.entries)
              for (final species in entry.value) species: entry.key,
          },
        ),
      );
  if (first == null || !context.mounted) return null;
  if (first.isSearchResult) return first.value;
  final second =
      await showModalBottomSheet<({String value, bool isSearchResult})>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ChoicePickerSheet(
          title: '细分品种',
          options: speciesOptions[first.value] ?? const [],
        ),
      );
  return second?.value;
}

class ChoicePickerSheet extends StatefulWidget {
  const ChoicePickerSheet({
    super.key,
    required this.title,
    required this.options,
    this.searchOptions = const {},
    this.selectedValue,
    this.optionIcons = const {},
  });
  final String title;
  final List<String> options;
  final Map<String, String> searchOptions;
  final String? selectedValue;
  final Map<String, IconData> optionIcons;

  @override
  State<ChoicePickerSheet> createState() => ChoicePickerSheetState();
}

class ChoicePickerSheetState extends State<ChoicePickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.text.trim().toLowerCase();
    final options =
        <({String value, String? category})>[
              for (final option in widget.options)
                (value: option, category: null),
              if (normalizedQuery.isNotEmpty)
                for (final entry in widget.searchOptions.entries)
                  (value: entry.key, category: entry.value),
            ]
            .where(
              (option) =>
                  option.value.toLowerCase().contains(normalizedQuery) ||
                  speciesAliases.entries.any(
                    (alias) =>
                        alias.value == option.value &&
                        alias.key.toLowerCase().contains(normalizedQuery),
                  ) ||
                  importedSpeciesSearchAliases.entries.any(
                    (alias) =>
                        alias.value.contains(option.value) &&
                        alias.key.toLowerCase().contains(normalizedQuery),
                  ),
            )
            .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                autofocus: widget.optionIcons.isEmpty,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: widget.searchOptions.isEmpty
                      ? '输入名称搜索'
                      : '搜索分类或细分品种',
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: options.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_off_outlined,
                                size: 52,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '没有匹配项',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '换一个关键词试试。',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: options.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => ListTile(
                          leading:
                              widget.optionIcons[options[index].value] == null
                              ? null
                              : Icon(
                                  widget.optionIcons[options[index].value],
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          tileColor:
                              widget.selectedValue == options[index].value
                              ? Theme.of(context).colorScheme.primaryContainer
                                    .withValues(alpha: .45)
                              : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          title: Text(options[index].value),
                          subtitle:
                              options[index].category != null ||
                                  importedSpeciesDisambiguation.containsKey(
                                    options[index].value,
                                  )
                              ? Text(
                                  [
                                    ?options[index].category,
                                    ?importedSpeciesDisambiguation[options[index]
                                        .value],
                                  ].join(' · '),
                                )
                              : null,
                          trailing: Icon(
                            widget.selectedValue == options[index].value
                                ? Icons.check
                                : Icons.chevron_right,
                          ),
                          onTap: () => Navigator.pop(context, (
                            value: options[index].value,
                            isSearchResult: options[index].category != null,
                          )),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
