import 'package:flutter/material.dart';

import 'domain/milestone.dart';
import 'widgets/milestone_design.dart';

class MilestoneArtworkGalleryPage extends StatefulWidget {
  const MilestoneArtworkGalleryPage({super.key, required this.selected});

  final MilestoneArtwork selected;

  @override
  State<MilestoneArtworkGalleryPage> createState() =>
      _MilestoneArtworkGalleryPageState();
}

class _MilestoneArtworkGalleryPageState
    extends State<MilestoneArtworkGalleryPage> {
  late String _filter = widget.selected.category;

  @override
  Widget build(BuildContext context) {
    final artworks = MilestoneArtwork.displayOrder
        .where((artwork) => _filter == '全部' || artwork.category == _filter)
        .toList();
    const filters = ['全部', '种群发展', '战斗征程', '文明建设', '特殊事件'];
    return Theme(
      data: MilestoneDesign.theme(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('选择石刻画面')),
        body: Column(
          children: [
            SizedBox(
              height: 47,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final filter = filters[index];
                  return ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                    selectedColor: const Color(0xff87a4cf),
                    labelStyle: TextStyle(
                      color: _filter == filter
                          ? MilestoneDesign.background
                          : MilestoneDesign.textColor(context),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.88,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: artworks.length,
                itemBuilder: (context, index) {
                  final artwork = artworks[index];
                  return MilestoneArtworkTile(
                    artwork: artwork,
                    selected: artwork == widget.selected,
                    width: double.infinity,
                    height: double.infinity,
                    onTap: () => Navigator.pop(context, artwork),
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
