import 'package:db_context_lib/db_context_lib.dart';

class Transaction {
  const Transaction._();
}

const Transaction transaction = Transaction._();

abstract class Transactional<CONNECTION> {
  DbContext<CONNECTION> get db;
}
