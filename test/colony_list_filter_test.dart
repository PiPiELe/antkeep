import 'package:antkeep/domain/colony_list_filter.dart';
import 'package:antkeep/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026);
  final colony = Colony(
    id: 'one',
    name: '一号群',
    species: '红足穴猛蚁',
    createdAt: now,
    updatedAt: now,
  );

  test('combined filters use current workers and due status', () {
    const filter = ColonyListFilter(
      scale: ColonyScale.medium,
      species: '红足穴猛蚁',
      todo: ColonyTodoFilter.due,
    );
    expect(filter.activeCount, 3);
    expect(filter.matches(colony, 235, true), isTrue);
    expect(filter.matches(colony, 20, true), isFalse);
    expect(filter.matches(colony, 235, false), isFalse);
    expect(filter.matches(colony, null, true), isFalse);
    expect(
      const ColonyListFilter(todo: ColonyTodoFilter.none)
          .matches(colony, 235, false),
      isTrue,
    );
  });

  test('worker sorting keeps unknown counts last', () {
    const descending = ColonyListFilter(
      workerOrder: ColonyWorkerOrder.descending,
    );
    const ascending = ColonyListFilter(
      workerOrder: ColonyWorkerOrder.ascending,
    );
    expect(descending.compareWorkers(235, 128), lessThan(0));
    expect(ascending.compareWorkers(235, 128), greaterThan(0));
    expect(descending.compareWorkers(null, 128), greaterThan(0));
    expect(ascending.compareWorkers(null, 128), greaterThan(0));
    expect(ascending.compareWorkers(null, null), 0);
  });

  test('nest type and new queen filters use colony profile values', () {
    final newQueen = Colony(
      id: 'queen',
      name: '新后群',
      nestType: '试管巢',
      initialWorkerCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    const filter = ColonyListFilter(
      nestType: '试管巢',
      newQueen: ColonyNewQueenFilter.newQueen,
    );
    expect(filter.activeCount, 2);
    expect(filter.matches(newQueen, 20, false), isTrue);
    expect(filter.matches(colony, 20, false), isFalse);
    expect(
      const ColonyListFilter(newQueen: ColonyNewQueenFilter.other)
          .matches(newQueen, 20, false),
      isFalse,
    );
  });
}
