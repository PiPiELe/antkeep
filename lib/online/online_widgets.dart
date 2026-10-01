import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update.dart';
import 'app_update_controller.dart';
import 'content.dart';
import 'online_controller.dart';

class OnlineSettings extends StatelessWidget {
  const OnlineSettings({
    super.key,
    required this.controller,
    required this.updates,
    required this.useOffline,
  });
  final OnlineController controller;
  final AppUpdateController updates;
  final Future<void> Function() useOffline;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, updates]),
    builder: (context, _) => Column(
      children: [
        if (updates.availability == AppUpdateAvailability.required)
          _RequiredUpdateCard(updates: updates, useOffline: useOffline),
        if (controller.enabled) ...[
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(controller.user?.username ?? '游客 · 未登录'),
            subtitle: const Text('账号只关联签到，不关联本机养殖数据。'),
            trailing: controller.user == null
                ? TextButton(
                    onPressed: controller.busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LoginPage(controller: controller),
                            ),
                          ),
                    child: const Text('登录 / 注册'),
                  )
                : TextButton(
                    onPressed: controller.busy ? null : controller.logout,
                    child: const Text('退出'),
                  ),
          ),
          if (controller.user == null && controller.hasSession)
            TextButton(
              onPressed: controller.busy ? null : controller.logout,
              child: const Text('清除本机会话'),
            ),
          if (controller.user != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('每日签到 · 北京时间'),
                    Text(
                      controller.checkin == null
                          ? '签到状态尚未读取'
                          : '${controller.checkin!.date} · 连续 ${controller.checkin!.consecutiveDays} 天 · 累计 ${controller.checkin!.totalDays} 天',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: controller.busy
                              ? null
                              : () => controller.refreshCheckin(submit: true),
                          child: Text(
                            controller.checkin?.checkedInToday == true
                                ? '已签到 · 再次确认'
                                : '签到',
                          ),
                        ),
                        TextButton(
                          onPressed: controller.busy
                              ? null
                              : controller.refreshCheckin,
                          child: const Text('刷新状态'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ListTile(
            title: Text(
              controller.content.version == 0
                  ? '公共资料 · 内置版本'
                  : '公共资料 · 版本 ${controller.content.version}',
            ),
            subtitle: Text(controller.contentNotice ?? '物品模板与新手资料'),
            trailing: TextButton(
              onPressed: controller.refreshing
                  ? null
                  : controller.refreshContent,
              child: Text(controller.refreshing ? '更新中…' : '更新'),
            ),
          ),
        ],
        const _InstalledAppVersion(),
        ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(
            updates.availability == AppUpdateAvailability.none
                ? (updates.policy == null ? '应用更新' : '应用已是最新版本')
                : '发现新版本 ${updates.policy?.latestVersion}',
          ),
          subtitle: Text(
            updates.error ??
                (updates.availability == AppUpdateAvailability.required
                    ? '需更新后才能使用在线版；本地数据仍可离线使用。'
                    : updates.policy?.releaseNotes ??
                          '仅检查 Android 更新，不会上传本地养殖数据。'),
          ),
          trailing: updates.checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: updates.availability == AppUpdateAvailability.none
                      ? () => updates.check(manual: true)
                      : updates.openDownload,
                  child: Text(
                    updates.availability == AppUpdateAvailability.none
                        ? '检查更新'
                        : '去更新',
                  ),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('使用指南'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('使用指南')),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (_, _) => HelpContent(content: controller.content),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _InstalledAppVersion extends StatefulWidget {
  const _InstalledAppVersion();

  @override
  State<_InstalledAppVersion> createState() => _InstalledAppVersionState();
}

class _InstalledAppVersionState extends State<_InstalledAppVersion> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _info,
    builder: (context, snapshot) {
      final info = snapshot.data;
      return ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('当前 App 版本'),
        subtitle: Text(
          info != null
              ? '${info.version}${info.buildNumber.isEmpty ? '' : ' (${info.buildNumber})'}'
              : snapshot.hasError
              ? '暂时无法读取版本'
              : '读取中…',
        ),
      );
    },
  );
}

class _RequiredUpdateCard extends StatelessWidget {
  const _RequiredUpdateCard({required this.updates, required this.useOffline});
  final AppUpdateController updates;
  final Future<void> Function() useOffline;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '在线版需要更新至 ${updates.policy?.minimumVersion}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          const Text('当前版本仍可使用全部本地记录、备份和离线功能。'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              FilledButton(
                onPressed: updates.openDownload,
                child: const Text('立即更新'),
              ),
              TextButton(
                onPressed: () {
                  useOffline();
                },
                child: const Text('使用离线版'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class HelpContent extends StatelessWidget {
  const HelpContent({super.key, required this.content});
  final PublicContent content;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(content.title, style: Theme.of(context).textTheme.titleLarge),
      Text(content.summary),
      for (final step in content.steps)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle_outline),
          title: Text(step.title),
          subtitle: Text(step.body),
        ),
    ],
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller});
  final OnlineController controller;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController(),
      _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _register = false;
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await widget.controller.login(
      _username.text,
      _password.text,
      register: _register,
    );
    if (!mounted) return;
    _password.clear();
    if (widget.controller.user != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Scaffold(
        appBar: AppBar(title: Text(_register ? '创建账号' : '登录')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              children: [
                const Text('登录仅用于签到，蚁群、记录和照片不会上传。'),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _username,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    helperText: '3–32 位字母、数字或下划线',
                  ),
                  validator: (v) =>
                      RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch((v ?? '').trim())
                      ? null
                      : '请检查用户名格式',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    helperText: '8–64 位',
                  ),
                  validator: (v) =>
                      v != null && v.runes.length >= 8 && v.runes.length <= 64
                      ? null
                      : '密码需为 8–64 位',
                ),
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      controller.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: controller.busy || !controller.enabled
                      ? null
                      : _submit,
                  child: Text(
                    controller.busy
                        ? '处理中…'
                        : _register
                        ? '注册并登录'
                        : '登录',
                  ),
                ),
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () => setState(() => _register = !_register),
                  child: Text(_register ? '已有账号，去登录' : '没有账号，去注册'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
