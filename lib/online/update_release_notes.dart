import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Plain release notes with web links; no remote images or embedded content.
class UpdateReleaseNotes extends StatefulWidget {
  const UpdateReleaseNotes({super.key, required this.notes, this.openUrl});

  final String notes;
  final Future<bool> Function(Uri)? openUrl;

  @override
  State<UpdateReleaseNotes> createState() => _UpdateReleaseNotesState();
}

class _UpdateReleaseNotesState extends State<UpdateReleaseNotes> {
  static final _links = RegExp(
    r'\[([^\]\n]+)\]\((https?://[^\s)]+)\)|(https?://[^\s<>\[\]()，。；：！？、]+)',
    caseSensitive: false,
  );
  final _recognizers = <TapGestureRecognizer>[];
  String? _error;

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri url) async {
    var opened = false;
    try {
      opened =
          await (widget.openUrl?.call(url) ??
              launchUrl(url, mode: LaunchMode.externalApplication));
    } catch (_) {
      // Keep the update dialog available if the browser cannot be opened.
    }
    if (mounted) {
      setState(() => _error = opened ? null : '无法打开链接，请稍后重试。');
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in _links.allMatches(widget.notes)) {
      spans.add(TextSpan(text: widget.notes.substring(offset, match.start)));
      final rawUrl = match.group(2) ?? match.group(3)!;
      final urlText = match.group(2) != null
          ? rawUrl
          : rawUrl.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
      final url = Uri.tryParse(urlText);
      if (url == null || url.host.isEmpty || url.userInfo.isNotEmpty) {
        spans.add(TextSpan(text: match.group(0)));
      } else {
        final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: match.group(1) ?? urlText,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
        if (match.group(3) != null && rawUrl.length > urlText.length) {
          spans.add(TextSpan(text: rawUrl.substring(urlText.length)));
        }
      }
      offset = match.end;
    }
    spans.add(TextSpan(text: widget.notes.substring(offset)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(TextSpan(children: spans)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
