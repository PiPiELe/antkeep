String chineseDate(DateTime value, {bool includeYear = true}) =>
    '${includeYear ? '${value.year}年' : ''}${value.month}月${value.day}日';

String chineseServerDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? '日期未知' : chineseDate(date);
}
