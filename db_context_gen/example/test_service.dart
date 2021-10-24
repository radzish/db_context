import 'package:db_context_lib/db_context_lib.dart';

part 'test_service.g.dart';

class Connection {}

class Model {}

class TestService extends _TestService with _$TestService {
  TestService(DbContext<Connection> db) : super(db);
}

abstract class _TestService implements Transactional<Connection> {
  final DbContext<Connection> db;

  _TestService(this.db);

  Future<void> readableVoidAsyncMethod() async {}

  Future<String> readableStringAsyncMethod() async {
    return "value";
  }

  Future<List<String>> readableListStringAsyncMethod() async {
    return ["value"];
  }

  Future<List<Model>> readableListModelsAsyncMethod() async {
    return [Model()];
  }

  Future<String> readableStringDirectFutureCallMethod() => _futureStringCall();

  Future<String> _futureStringCall() async {
    return "value";
  }

  @transaction
  Future<void> writableAsyncMethod() async {}

  @transaction
  Future<void> writableDirectFutureCallMethod() => _futureVoidCall();

  Future<void> _futureVoidCall() async {}

  Future<void> optionalParamsDefaultValues(String normalParam, {bool lock = true}) async {}

  @transaction
  Future<void> nullableParamsMethod(String? name, {String? description = "11"}) async {}

  Future<String?> nullableReturnMethod() async {}
}
