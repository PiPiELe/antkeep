import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_preferences.dart';
import 'online/online_api.dart';
import 'online/runtime.dart';

class PrivacyAgreement {
  const PrivacyAgreement({
    required this.version,
    required this.title,
    required this.effectiveDate,
    required this.developerName,
    required this.contact,
    required this.content,
  });

  final int version;
  final String title, effectiveDate, developerName, contact, content;

  factory PrivacyAgreement.decode(String source) {
    if (utf8.encode(source).length > 131072) {
      throw const FormatException('协议内容过大');
    }
    final data = jsonDecode(source) as Map<String, dynamic>;
    final version = data['version'];
    if (version is! int || version < 1) throw const FormatException('协议版本无效');
    return PrivacyAgreement(
      version: version,
      title: _text(data['title'], 1, 80),
      effectiveDate: _text(data['effectiveDate'], 10, 10),
      developerName: _text(data['developerName'], 1, 160),
      contact: _text(data['contact'], 3, 512),
      content: _text(data['content'], 100, 50000),
    );
  }

  static String _text(Object? value, int min, int max) {
    if (value is! String || value.trim().length < min || value.length > max) {
      throw const FormatException('协议字段无效');
    }
    return value;
  }
}

class PrivacyAgreementRepository {
  PrivacyAgreementRepository({OnlineApi? api})
    : _api = api ?? OnlineApi(baseUrl: onlineBaseUrl);

  final OnlineApi _api;

  Future<PrivacyAgreement> load() async {
    _api.setEnabled(true);
    try {
      return PrivacyAgreement.decode(
        await _api.request('/api/public/agreements/privacy'),
      );
    } finally {
      _api.setEnabled(false);
    }
  }
}

class PrivacyPolicyGate extends StatefulWidget {
  const PrivacyPolicyGate({
    super.key,
    required this.preferences,
    required this.child,
    this.repository,
  });

  final AppPreferences preferences;
  final Widget child;
  final PrivacyAgreementRepository? repository;

  @override
  State<PrivacyPolicyGate> createState() => _PrivacyPolicyGateState();
}

class _PrivacyPolicyGateState extends State<PrivacyPolicyGate> {
  late final PrivacyAgreementRepository _repository =
      widget.repository ?? PrivacyAgreementRepository();
  PrivacyAgreement? _agreement;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final agreement = await _repository.load();
      if (!mounted) return;
      setState(() => _agreement = agreement);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agreement = _agreement;
    if (_loading) return const _PrivacyLoadingPage();
    if (agreement == null) {
      if (widget.preferences.hasAcceptedPrivacyPolicy) return widget.child;
      return _PrivacyUnavailablePage(error: _error, onRetry: _load);
    }
    if (widget.preferences.hasAcceptedPrivacyPolicyVersion(agreement.version)) {
      return widget.child;
    }
    return PrivacyPolicyPage(
      agreement: agreement,
      requireAcceptance: true,
      onAccept: () => widget.preferences.acceptPrivacyPolicy(agreement.version),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({
    super.key,
    required this.agreement,
    this.requireAcceptance = false,
    this.onAccept,
  });

  final PrivacyAgreement agreement;
  final bool requireAcceptance;
  final Future<void> Function()? onAccept;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(agreement.title)),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agreement.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '版本 ${agreement.version} · 生效日期 ${agreement.effectiveDate}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '开发者：${agreement.developerName}\n联系方式：${agreement.contact}',
                    ),
                    const Divider(height: 32),
                    Text(
                      agreement.content,
                      style: const TextStyle(height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (requireAcceptance)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  TextButton(
                    onPressed: SystemNavigator.pop,
                    child: const Text('不同意并退出'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await onAccept!();
                      },
                      child: const Text('同意并继续使用'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class PrivacyPolicyDetailsPage extends StatefulWidget {
  const PrivacyPolicyDetailsPage({super.key});

  @override
  State<PrivacyPolicyDetailsPage> createState() =>
      _PrivacyPolicyDetailsPageState();
}

class _PrivacyPolicyDetailsPageState extends State<PrivacyPolicyDetailsPage> {
  final _repository = PrivacyAgreementRepository();
  PrivacyAgreement? _agreement;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final agreement = await _repository.load();
      if (mounted) setState(() => _agreement = agreement);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_agreement case final agreement?) {
      return PrivacyPolicyPage(agreement: agreement);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('暂时无法获取隐私政策。'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PrivacyLoadingPage extends StatelessWidget {
  const _PrivacyLoadingPage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _PrivacyUnavailablePage extends StatelessWidget {
  const _PrivacyUnavailablePage({required this.error, required this.onRetry});
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.privacy_tip_outlined, size: 44),
            const SizedBox(height: 16),
            Text('暂时无法获取隐私政策', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              '首次使用前需要阅读并同意最新隐私政策。请检查网络后重试。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => onRetry(), child: const Text('重新获取')),
          ],
        ),
      ),
    ),
  );
}
