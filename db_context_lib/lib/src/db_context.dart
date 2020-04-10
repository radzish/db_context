import 'dart:async';

import 'package:resource_pool/resource_pool.dart';

const int _defaultMaxConnectionsInPool = 3;

abstract class ConnectionManager<CONNECTION> {
  Future<CONNECTION> create();

  bool isValid(CONNECTION conn);

  Future<void> beginTransaction(CONNECTION conn);

  Future<void> commitTransaction(CONNECTION conn);

  Future<void> rollbackTransaction(CONNECTION conn);
}

class DbContext<CONNECTION> {
  static const _zoneConnectionKey = "postgres_driver.connection_key";

  final ConnectionManager<CONNECTION> connectionManager;

  ResourcePool<CONNECTION> _pool;

  DbContext(this.connectionManager, {int maxConnections = _defaultMaxConnectionsInPool}) {
    _pool = ResourcePool<CONNECTION>(maxConnections, () => connectionManager.create());
  }

  Future<CONNECTION> open() async {
    var connection = await _pool.get();
    print("connection opened: ${connection.hashCode}");

    if (!connectionManager.isValid(connection)) {
      await _pool.remove(connection);
      connection = await _pool.get();
    }

    return connection;
  }

  void close(CONNECTION connection) {
    print("connection closing: ${connection.hashCode}");
    _pool.release(connection);
  }

  Future<T> executeInReadTransaction<T>(Future<T> Function() block) async {
    bool connectionExisted = conn != null;
    final connection = connectionExisted ? conn : await open();
    try {
      if (connectionExisted) {
        return await block();
      } else {
        return await runZoned(() async => await block(),
            zoneValues: {_zoneConnectionKey: _ConnectionWrapper(connection)});
      }
    } finally {
      if (!connectionExisted) {
        await close(connection);
      }
    }
  }

  Future<T> executeInWriteTransaction<T>(Future<T> Function() block) async {
    return executeInReadTransaction(() async {
      bool transactionExisted = _info.inTransaction;
      if (!transactionExisted) {
        await connectionManager.beginTransaction(conn);
        _info.inTransaction = true;
      }
      try {
        final result = await block();

        if (!transactionExisted) {
          _info.inTransaction = false;
          await connectionManager.commitTransaction(conn);
        }

        return result;
      } catch (e) {
        await connectionManager.rollbackTransaction(conn);
        _info.inTransaction = false;

        rethrow;
      }
    });
  }

  CONNECTION get conn => _info?.connection;

  _ConnectionWrapper get _info => Zone.current[_zoneConnectionKey] as _ConnectionWrapper;
}

class _ConnectionWrapper<CONNECTION> {
  final CONNECTION connection;
  bool inTransaction = false;

  _ConnectionWrapper(this.connection);
}
