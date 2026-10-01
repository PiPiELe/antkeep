import 'package:flutter/material.dart';

/// Reveals an explicit delete action without deleting on swipe.
class DiaryRecordActions extends StatefulWidget {
  const DiaryRecordActions({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  State<DiaryRecordActions> createState() => _DiaryRecordActionsState();
}

class _DiaryRecordActionsState extends State<DiaryRecordActions> {
  static const _actionWidth = 88.0;
  double _offset = 0;
  bool _dragging = false;
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.onDelete();
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
          _offset = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      children: [
        if (_offset < 0)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _actionWidth,
                height: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _deleting ? null : _delete,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                          const Text('删除'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        AnimatedContainer(
          duration: Duration(milliseconds: _dragging ? 0 : 160),
          transform: Matrix4.translationValues(_offset, 0, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _deleting
                ? null
                : (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: _deleting
                ? null
                : (details) => setState(() {
                    _offset = (_offset + details.delta.dx).clamp(
                      -_actionWidth,
                      0.0,
                    );
                  }),
            onHorizontalDragEnd: _deleting
                ? null
                : (_) => setState(() {
                    _dragging = false;
                    _offset = _offset < -_actionWidth / 2 ? -_actionWidth : 0;
                  }),
            onHorizontalDragCancel: () => setState(() {
              _dragging = false;
              _offset = 0;
            }),
            onTap: _deleting
                ? null
                : () {
                    if (_offset < 0) {
                      setState(() => _offset = 0);
                    } else {
                      widget.onEdit();
                    }
                  },
            child: Semantics(button: true, label: '编辑日记', child: widget.child),
          ),
        ),
      ],
    ),
  );
}
