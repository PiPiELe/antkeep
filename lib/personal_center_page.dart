import 'dart:async';

import 'package:flutter/material.dart';

import 'account_controller.dart';

class PersonalCenterPage extends StatefulWidget {
  const PersonalCenterPage({super.key, required this.controller});
  final AccountController controller;

  @override
  State<PersonalCenterPage> createState() => _PersonalCenterPageState();
}

class _PersonalCenterPageState extends State<PersonalCenterPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _nickname = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  Timer? _refreshTimer;
  AccountController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh on entry, resume and while open so server-day changes are visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.signedIn) controller.refresh();
    });
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (controller.signedIn) controller.refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (controller.signedIn) controller.refresh();
      _startRefreshTimer();
    } else {
      _refreshTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _username.dispose();
    _password.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await controller.authenticate(
      username: _username.text,
      password: _password.text,
      nickname: _register ? _nickname.text : null,
    );
    if (mounted && controller.signedIn) _password.clear();
  }

  Future<void> _editNickname() async {
    var nickname = controller.account!.nickname;
    final form = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改昵称'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: nickname,
            onChanged: (value) => nickname = value,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(labelText: '昵称'),
            validator: _validateNickname,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, nickname.trim());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null && mounted) await controller.updateNickname(value);
  }

  String? _validateNickname(String? value) =>
      value == null || value.trim().isEmpty || value.trim().runes.length > 24
      ? '请输入 1–24 个字符的昵称'
      : null;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('个人中心'),
        actions: [
          if (controller.signedIn)
            IconButton(
              tooltip: '刷新签到记录',
              onPressed: controller.busy ? null : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!controller.online)
                const Text('个人中心仅在线版可用。请返回设置切换版本。')
              else if (!controller.requestsEnabled)
                const Text('账号与签到暂未开放，敬请期待。')
              else if (!controller.configured)
                const Text('账号服务暂未开放，请稍后再试。')
              else ...[
                if (controller.busy) const LinearProgressIndicator(),
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
                if (controller.signedIn)
                  ..._profile(context)
                else
                  _login(context),
                const SizedBox(height: 24),
                Text(
                  '账号与签到记录保存在服务器，登录同一账号可跨设备查看。蚁群、养殖记录和照片仍只保存在本机。\n关闭 App 后需重新登录。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _login(BuildContext context) => Form(
    key: _form,
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            _register ? '创建蚁记账号' : '欢迎回来',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('登录后，每天签到，记录你的养蚁陪伴。'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _username,
            enabled: !controller.busy,
            autofillHints: const [AutofillHints.username],
            autocorrect: false,
            textInputAction: TextInputAction.next,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: '账号',
              helperText: '4–32 位字母、数字或下划线',
            ),
            validator: (value) =>
                RegExp(r'^[a-zA-Z0-9_]{4,32}$').hasMatch(value?.trim() ?? '')
                ? null
                : '请输入有效账号',
          ),
          if (_register) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _nickname,
              enabled: !controller.busy,
              maxLength: 24,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '昵称'),
              validator: _validateNickname,
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            enabled: !controller.busy,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: [
              _register ? AutofillHints.newPassword : AutofillHints.password,
            ],
            decoration: InputDecoration(
              labelText: '密码',
              helperText: '10–128 个字符',
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) =>
                value != null && value.length >= 10 && value.length <= 128
                ? null
                : '密码需为 10–128 个字符',
            onFieldSubmitted: (_) {
              if (!controller.busy) _submit();
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: controller.busy ? null : _submit,
            child: Text(_register ? '注册并登录' : '登录'),
          ),
          TextButton(
            onPressed: controller.busy
                ? null
                : () => setState(() {
                    _register = !_register;
                    _password.clear();
                  }),
            child: Text(_register ? '已有账号，去登录' : '还没有账号？注册'),
          ),
        ],
      ),
    ),
  );

  List<Widget> _profile(BuildContext context) {
    final account = controller.account!;
    final colors = Theme.of(context).colorScheme;
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          account.nickname,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        subtitle: Text('账号：${account.username}'),
        trailing: IconButton(
          tooltip: '修改昵称',
          onPressed: controller.busy ? null : _editNickname,
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        color: colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('每日签到', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('${account.serverDate} · 北京时间'),
              const SizedBox(height: 20),
              Wrap(
                spacing: 28,
                runSpacing: 12,
                children: [
                  Text(
                    '连续 ${account.streakDays} 天',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '累计 ${account.totalDays} 天',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: controller.busy || account.checkedInToday
                    ? null
                    : controller.checkIn,
                icon: Icon(
                  account.checkedInToday
                      ? Icons.check_circle_outline
                      : Icons.calendar_today_outlined,
                ),
                label: Text(account.checkedInToday ? '今日已签到' : '立即签到'),
              ),
              const SizedBox(height: 8),
              const Text('每天可签到一次，每日 00:00 更新。'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text('最近签到', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      if (account.recentDates.isEmpty)
        const Text('还没有签到记录，从今天开始吧。')
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final date in account.recentDates)
              Chip(label: Text(date), avatar: const Icon(Icons.done, size: 16)),
          ],
        ),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: controller.busy ? null : controller.logout,
        child: const Text('退出登录'),
      ),
    ];
  }
}
