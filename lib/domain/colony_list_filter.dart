import 'models.dart';

enum ColonyTodoFilter { all, due, none }

enum ColonyNewQueenFilter { all, newQueen, other }

enum ColonyWorkerOrder { manual, descending, ascending }

class ColonyListFilter {
  const ColonyListFilter({
    this.scale,
    this.species,
    this.nestType,
    this.newQueen = ColonyNewQueenFilter.all,
    this.todo = ColonyTodoFilter.all,
    this.workerOrder = ColonyWorkerOrder.manual,
  });

  final ColonyScale? scale;
  final String? species;
  final String? nestType;
  final ColonyNewQueenFilter newQueen;
  final ColonyTodoFilter todo;
  final ColonyWorkerOrder workerOrder;

  int get activeCount =>
      (scale == null ? 0 : 1) +
      (species == null ? 0 : 1) +
      (nestType == null ? 0 : 1) +
      (newQueen == ColonyNewQueenFilter.all ? 0 : 1) +
      (todo == ColonyTodoFilter.all ? 0 : 1) +
      (workerOrder == ColonyWorkerOrder.manual ? 0 : 1);

  bool matches(Colony colony, int? workers, bool hasDueTasks) {
    if (scale != null && ColonyScale.fromWorkerCount(workers) != scale) {
      return false;
    }
    if (species != null && colony.species?.trim() != species) return false;
    if (nestType != null && colony.nestType?.trim() != nestType) return false;
    if (newQueen == ColonyNewQueenFilter.newQueen && !colony.isNewQueenColony) {
      return false;
    }
    if (newQueen == ColonyNewQueenFilter.other && colony.isNewQueenColony) {
      return false;
    }
    if (todo == ColonyTodoFilter.due && !hasDueTasks) return false;
    if (todo == ColonyTodoFilter.none && hasDueTasks) return false;
    return true;
  }

  int compareWorkers(int? first, int? second) {
    if (first == null) return second == null ? 0 : 1;
    if (second == null) return -1;
    return workerOrder == ColonyWorkerOrder.ascending
        ? first.compareTo(second)
        : second.compareTo(first);
  }
}
