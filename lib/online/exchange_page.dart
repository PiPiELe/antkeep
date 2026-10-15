import 'dart:async';
import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/species_picker.dart';
import 'online_api.dart';
import 'online_controller.dart';
import 'online_widgets.dart';

const exchangeNotice = '不涉及真实交易，交易请走官方平台，请勿直接转账。';
const exchangeCategories = {'ANT': '蚂蚁', 'ITEM': '物品', 'OTHER': '其他'};
const exchangeStates = {
  'PENDING': '待审核',
  'APPROVED': '已通过',
  'REJECTED': '已驳回',
  'REMOVED': '已撤下',
};

class ExchangePage extends StatefulWidget {
  const ExchangePage({super.key, required this.controller, this.mine = false});
  final OnlineController controller;
  final bool mine;
  @override
  State<ExchangePage> createState() => _ExchangePageState();
}

class _ExchangePageState extends State<ExchangePage> {
  List<Map<String, dynamic>> listings = [], mine = [];
  int page = 1, total = 0, request = 0;
  bool loading = false;
  bool tableView = false;
  String category = '';
  final search = TextEditingController();
  Timer? searchTimer;
  String? error;
  String? accountId;
  bool wasOnline = false;

  @override
  void initState() {
    super.initState();
    accountId = widget.controller.user?.id;
    wasOnline = widget.controller.enabled;
    widget.controller.addListener(_onAccountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    searchTimer?.cancel();
    search.dispose();
    widget.controller.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    final next = widget.controller.user?.id;
    final online = widget.controller.enabled;
    if (next == accountId && online == wasOnline) return;
    accountId = next;
    wasOnline = online;
    ++request;
    setState(() {
      listings = [];
      mine = [];
      page = 1;
      total = 0;
      error = null;
      loading = false;
    });
    if (widget.controller.enabled) _load();
  }

  Future<void> _load() async {
    if (!mounted || !widget.controller.enabled) return;
    final revision = ++request;
    final owner = widget.controller.user?.id;
    if (widget.mine && owner == null) {
      setState(() {
        loading = false;
        error = null;
        mine = [];
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = widget.mine
          ? null
          : await widget.controller.exchangeListings(
              page,
              query: search.text.trim(),
              category: category,
            );
      final own = widget.mine
          ? await widget.controller.myExchangeListings()
          : null;
      if (!mounted ||
          revision != request ||
          owner != widget.controller.user?.id) {
        return;
      }
      setState(() {
        if (data != null) {
          listings = (data['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          total = (data['total'] as num).toInt();
        }
        if (own != null) mine = own;
      });
    } catch (e) {
      if (mounted && revision == request) {
        setState(() => error = e is ApiFailure ? e.message : '加载失败，请重试。');
      }
    } finally {
      if (mounted && revision == request) setState(() => loading = false);
    }
  }

  void _filterChanged() {
    setState(() => page = 1);
    _load();
  }

  void _searchChanged(String _) {
    searchTimer?.cancel();
    searchTimer = Timer(const Duration(milliseconds: 350), _filterChanged);
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤下售卖信息？'),
        content: Text('“${item['title']}”撤下后不会继续公开展示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤下'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.removeExchangeListing(item['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiFailure ? e.message : '撤下失败，请重试。');
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final online = widget.controller.enabled;
      final user = widget.controller.user;
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.mine ? '我的发布' : '交易所'),
          actions: [
            IconButton(
              onPressed: online && !loading ? _load : null,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$exchangeNotice\n',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: '仅展示用户发布并经后台审核的售卖信息。蚁记不提供下单、支付或担保服务。',
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: 13, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!online)
                  Text('请在设置中切换到在线版后查看${widget.mine ? '我的发布' : '交易所'}。')
                else ...[
                  if (!widget.mine) ...[
                    TextField(
                      controller: search,
                      onChanged: _searchChanged,
                      onSubmitted: (_) {
                        searchTimer?.cancel();
                        _filterChanged();
                      },
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: '模糊搜索',
                        hintText: '搜索标题、蚂蚁品种、说明或城市',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          onPressed: () {
                            search.clear();
                            searchTimer?.cancel();
                            _filterChanged();
                          },
                          icon: const Icon(Icons.clear),
                          tooltip: '清空搜索',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: '商品种类'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('全部种类')),
                        DropdownMenuItem(value: 'ANT', child: Text('蚂蚁')),
                        DropdownMenuItem(value: 'ITEM', child: Text('物品')),
                        DropdownMenuItem(value: 'OTHER', child: Text('其他')),
                      ],
                      onChanged: (value) {
                        category = value ?? '';
                        _filterChanged();
                      },
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.grid_view),
                          label: Text('卡片'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.view_list),
                          label: Text('列表'),
                        ),
                      ],
                      selected: {tableView},
                      onSelectionChanged: (value) =>
                          setState(() => tableView = value.first),
                    ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (widget.mine) ...[
                    const SizedBox(height: 20),
                    if (user == null) ...[
                      const Text('登录后可发布售卖信息，并查看审核结果。'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                LoginPage(controller: widget.controller),
                          ),
                        ),
                        child: const Text('登录 / 注册'),
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final sent = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ExchangeSubmitPage(
                                  controller: widget.controller,
                                ),
                              ),
                            );
                            if (sent == true && mounted) await _load();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('发布售卖信息'),
                        ),
                      ),
                      if (!loading && mine.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('还没有发布售卖信息。'),
                        ),
                      if (tableView && mine.isNotEmpty)
                        _listingTable(mine, own: true)
                      else
                        ...mine.map((item) => _listingCard(item, own: true)),
                    ],
                  ] else ...[
                    const SizedBox(height: 20),
                    Text('交易信息', style: Theme.of(context).textTheme.titleLarge),
                    if (!loading && listings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('暂无已审核的售卖信息。'),
                      ),
                    if (tableView && listings.isNotEmpty)
                      _listingTable(listings)
                    else
                      ...listings.map((item) => _listingCard(item)),
                    if (total > 20)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: page > 1
                                ? () {
                                    setState(() => page--);
                                    _load();
                                  }
                                : null,
                            child: const Text('上一页'),
                          ),
                          Text('$page / ${(total + 19) ~/ 20}'),
                          TextButton(
                            onPressed: page * 20 < total
                                ? () {
                                    setState(() => page++);
                                    _load();
                                  }
                                : null,
                            child: const Text('下一页'),
                          ),
                        ],
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _listingCard(Map<String, dynamic> item, {bool own = false}) {
    final state = exchangeStates[item['status']] ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final image = Container(
              key: ValueKey('exchange-image-${item['id']}'),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 32,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 4),
                    Text('商品图片', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            );
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['title'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (own) Text(state),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_kind(item)}  ·  ¥${item['priceYuan']}  ·  ${item['region']}',
                ),
                const SizedBox(height: 8),
                Text(item['description'] as String),
                const SizedBox(height: 8),
                Text(
                  '发布者：${item['seller']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (own && item['reviewNote'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('审核备注：${item['reviewNote']}'),
                  ),
                if (own && item['status'] != 'REMOVED')
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _remove(item),
                      child: const Text('撤下'),
                    ),
                  ),
              ],
            );
            final imageSize = constraints.maxWidth < 520 ? 108.0 : 136.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                SizedBox(width: imageSize, height: imageSize, child: image),
              ],
            );
          },
        ),
      ),
    );
  }

  String _kind(Map<String, dynamic> item) {
    final label = exchangeCategories[item['category']] ?? '其他';
    final species = item['species'] as String?;
    return species == null ? label : '$label / $species';
  }

  Widget _listingTable(List<Map<String, dynamic>> items, {bool own = false}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                showCheckboxColumn: false,
                horizontalMargin: compact ? 8 : 24,
                columnSpacing: compact ? 8 : 24,
                headingRowHeight: compact ? 44 : 56,
                dataRowMinHeight: compact ? 52 : 48,
                dataRowMaxHeight: compact ? 52 : 64,
                columns: [
                  const DataColumn(label: Text('商品')),
                  const DataColumn(label: Text('商品种类')),
                  const DataColumn(label: Text('标价'), numeric: true),
                  const DataColumn(label: Text('城市')),
                  if (own) const DataColumn(label: Text('状态')),
                ],
                rows: items.map((item) {
                  final status = exchangeStates[item['status']] ?? '';
                  return DataRow(
                    onSelectChanged: (_) => _showDetail(item, own: own),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: compact ? 104 : 180,
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item['title'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: compact ? 108 : 160,
                          child: Text(
                            _kind(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text('¥${item['priceYuan']}')),
                      DataCell(Text(item['region'] as String)),
                      if (own) DataCell(Text(status)),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      );

  void _showDetail(Map<String, dynamic> item, {required bool own}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] as String,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text('商品种类：${_kind(item)}'),
                Text('标价：¥${item['priceYuan']}'),
                Text('城市：${item['region']}'),
                Text('发布者：${item['seller']}'),
                const SizedBox(height: 12),
                Text(item['description'] as String),
                if (own && item['reviewNote'] != null) ...[
                  const SizedBox(height: 12),
                  Text('审核备注：${item['reviewNote']}'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExchangeSubmitPage extends StatefulWidget {
  const ExchangeSubmitPage({
    super.key,
    required this.controller,
    this.locateCity,
    this.cityOptions,
  });
  final OnlineController controller;
  final Future<String> Function()? locateCity;
  final Future<Map<String, List<String>>>? cityOptions;
  @override
  State<ExchangeSubmitPage> createState() => _ExchangeSubmitPageState();
}

class _ExchangeSubmitPageState extends State<ExchangeSubmitPage> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      species = TextEditingController(),
      price = TextEditingController(),
      region = TextEditingController(),
      description = TextEditingController();
  bool saving = false;
  bool locating = false;
  String category = 'ANT';
  bool manualSpecies = false;
  bool manualCity = false;
  String? selectedProvince;
  String? selectedCity;
  late final Future<Map<String, List<String>>> provinceCities;
  String? error;

  @override
  void initState() {
    super.initState();
    provinceCities =
        widget.cityOptions ??
        rootBundle
            .loadString('assets/regions/china_province_cities.json')
            .then(
              (value) => (jsonDecode(value) as Map<String, dynamic>).map(
                (province, cities) => MapEntry(
                  province,
                  (cities as List<dynamic>).cast<String>(),
                ),
              ),
            );
  }

  @override
  void dispose() {
    for (final c in [title, species, price, region, description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String> _deviceCity() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('手机定位服务未开启，请开启后重试，或手填城市。');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('定位权限已关闭，请在系统设置中开启，或手填城市。');
    }
    if (permission == LocationPermission.denied) {
      throw StateError('未获得定位权限，仍可手填城市。');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
    final places = await Geocoding(locale: const Locale('zh', 'CN'))
        .placemarkFromCoordinates(position.latitude, position.longitude)
        .timeout(const Duration(seconds: 15));
    if (places.isEmpty) throw StateError('未能识别城市，请手填城市。');
    final place = places.first;
    final province = place.administrativeArea?.trim() ?? '';
    final city = place.locality?.trim() ?? '';
    if (city.isEmpty) throw StateError('未能识别到市级位置，请手填城市。');
    return province.isEmpty || province == city ? city : '$province · $city';
  }

  Future<void> _pickSpecies() async {
    final selected = await pickSpecies(context);
    if (selected != null && mounted) setState(() => species.text = selected);
  }

  Future<void> _locate() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      final city = await (widget.locateCity?.call() ?? _deviceCity());
      if (!mounted) return;
      setState(() => locating = false);
      final use = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('使用定位城市？'),
          content: Text('$city\n\n仅用于填写售卖信息的城市，坐标不会提交。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('使用此城市'),
            ),
          ],
        ),
      );
      if (use == true && mounted) {
        setState(() {
          manualCity = true;
          region.text = city;
        });
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message.toString())));
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('定位超时，请重试，或手填城市。')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法识别城市，请手填城市。')));
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _submit() async {
    if (!form.currentState!.validate() || saving) return;
    if (region.text.trim().isEmpty) {
      setState(() => error = '请选择或手填城市。');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.submitExchangeListing({
        'title': title.text.trim(),
        'category': category,
        if (category == 'ANT') 'species': species.text.trim(),
        'priceYuan': double.parse(price.text.trim()),
        'region': region.text.trim(),
        'description': description.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiFailure ? e.message : '提交失败，请重试。');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('发布售卖信息')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    exchangeNotice,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('提交后由后台审核，通过后才会公开展示。请勿填写收款账号或要求私下转账。'),
              const SizedBox(height: 16),
              _field(title, '标题', 80),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: '商品种类'),
                items: const [
                  DropdownMenuItem(value: 'ANT', child: Text('蚂蚁')),
                  DropdownMenuItem(value: 'ITEM', child: Text('物品')),
                  DropdownMenuItem(value: 'OTHER', child: Text('其他')),
                ],
                onChanged: (value) => setState(() => category = value ?? 'ANT'),
              ),
              if (category == 'ANT') ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: species,
                    maxLength: 80,
                    readOnly: !manualSpecies,
                    onTap: manualSpecies ? null : _pickSpecies,
                    decoration: InputDecoration(
                      labelText: '蚂蚁品种',
                      hintText: manualSpecies ? '手动填写品种' : '点击选择或搜索品种',
                      suffixIcon: manualSpecies
                          ? null
                          : const Icon(Icons.search),
                    ),
                    validator: (value) =>
                        value?.trim().isEmpty ?? true ? '请填写蚂蚁品种' : null,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => manualSpecies = !manualSpecies),
                    child: Text(manualSpecies ? '从品种库选择' : '未收录？手动填写'),
                  ),
                ),
              ],
              TextFormField(
                controller: price,
                decoration: const InputDecoration(labelText: '标价（元）'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  final amount = double.tryParse(text);
                  return RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(text) &&
                          amount != null &&
                          amount <= 99999999.99
                      ? null
                      : '请输入有效标价，最多两位小数。';
                },
              ),
              const SizedBox(height: 8),
              Text('城市（精确到市）', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('省市选择')),
                  ButtonSegment(value: true, label: Text('手填城市')),
                ],
                selected: {manualCity},
                onSelectionChanged: (value) =>
                    setState(() => manualCity = value.first),
              ),
              const SizedBox(height: 12),
              if (manualCity)
                _field(region, '城市', 80)
              else
                FutureBuilder<Map<String, List<String>>>(
                  future: provinceCities,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('省市选项暂不可用，可切换为手填城市。');
                    }
                    final places = snapshot.data;
                    if (places == null) return const Text('正在加载省市选项…');
                    final cities = places[selectedProvince] ?? const <String>[];
                    return Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedProvince,
                          decoration: const InputDecoration(
                            labelText: '省份 / 直辖市',
                          ),
                          items: places.keys
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() {
                            selectedProvince = value;
                            selectedCity = null;
                            region.clear();
                          }),
                          validator: (value) => value == null ? '请选择省份' : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(selectedProvince),
                          initialValue: selectedCity,
                          decoration: const InputDecoration(
                            labelText: '城市 / 地级区域',
                          ),
                          items: cities
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                          onChanged: cities.isEmpty
                              ? null
                              : (value) => setState(() {
                                  selectedCity = value;
                                  region.text = selectedProvince == value
                                      ? value ?? ''
                                      : '$selectedProvince · $value';
                                }),
                          validator: (value) =>
                              value == null ? '请选择城市，或切换为手填' : null,
                        ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: locating ? null : _locate,
                icon: locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(locating ? '定位中…' : '获取定位填写城市'),
              ),
              Text(
                '仅在点击后获取定位；售卖信息只提交城市，不提交坐标。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _field(description, '说明', 1000, lines: 5),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: saving ? null : _submit,
                child: Text(saving ? '提交中…' : '提交审核'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label,
    int max, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLength: max,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
      validator: (v) => (v?.trim().isEmpty ?? true) ? '请填写$label' : null,
    ),
  );
}
