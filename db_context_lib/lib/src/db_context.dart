import 'dart:async';

import 'package:logging/logging.dart';
import 'package:resource_pool/resource_pool.dart';

const int _defaultMaxConnectionsInPool = 3;

Logger get _logger => Logger.root;

abstract class ConnectionManager<CONNECTION> {
  Future<CONNECTION> create();

  Future<void> close(CONNECTION connection);

  bool isValid(CONNECTION conn);

  Future<void> beginTransaction(CONNECTION conn);

  Future<void> commitTransaction(CONNECTION conn);

  Future<void> rollbackTransaction(CONNECTION conn);
}

class DbContext<CONNECTION> {
  static const _zoneConnectionKey = "db_context.connection_key";

  final ConnectionManager<CONNECTION> connectionManager;

  late ResourcePool<CONNECTION> _pool;

  DbContext(this.connectionManager, {int maxConnections = _defaultMaxConnectionsInPool}) {
    _pool = ResourcePool<CONNECTION>(maxConnections, create);
  }

  Future<CONNECTION> create() async {
    final connection = await connectionManager.create();
    _logger.fine("connection created: ${connection.hashCode}");
    return connection;
  }

  Future<CONNECTION> open() async {
    var connection = await _pool.get();
    _logger.fine("connection opened: ${connection.hashCode}");

    if (!isValid(connection)) {
      // making sure connection is closed before removal
      try {
        await connectionManager.close(connection);
      } catch(_) {
        //
      }
      await remove(connection);
      connection = await open();
    }

    return connection;
  }

  bool isValid(CONNECTION connection) => connectionManager.isValid(connection);

  Future<void> remove(CONNECTION connection) async {
    _logger.fine("connection removed: ${connection.hashCode}");
    await _pool.remove(connection);
  }

  void close(CONNECTION connection) {
    _logger.fine("connection released: ${connection.hashCode}");
    _pool.release(connection);
  }

  Future<T> executeInReadTransaction<T>(Future<T> Function() block) async {
    final connectionExisted = _resolvedConn != null;
    final connection = connectionExisted ? _resolvedConn! : await open();
    try {
      if (connectionExisted) {
        return await block();
      } else {
        return await runZoned(() async => await block(),
            zoneValues: {_zoneConnectionKey: _ConnectionWrapper(connection)});
      }
    } finally {
      if (!connectionExisted) {
        close(connection!);
      }
    }
  }

  Future<T> executeInWriteTransaction<T>(Future<T> Function() block) async {
    return executeInReadTransaction(() async {
      final transactionExisted = _info!.inTransaction;
      if (!transactionExisted) {
        await connectionManager.beginTransaction(conn!);
        _info!.inTransaction = true;
      }
      try {
        final result = await block();

        if (!transactionExisted) {
          _info!.inTransaction = false;
          await connectionManager.commitTransaction(conn!);
        }

        return result;
      } catch (e) {
        await connectionManager.rollbackTransaction(conn!);
        _info!.inTransaction = false;

        rethrow;
      }
    });
  }

  CONNECTION get conn => _info!.connection;

  // this is needed for internal usage
  CONNECTION? get _resolvedConn => _info?.connection;

  _ConnectionWrapper<CONNECTION>? get _info => Zone.current[_zoneConnectionKey] as _ConnectionWrapper<CONNECTION>?;
}

class _ConnectionWrapper<CONNECTION> {
  final CONNECTION connection;
  bool inTransaction = false;

  _ConnectionWrapper(this.connection);
}
