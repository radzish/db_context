library db_context_gen;

import 'package:build/build.dart';
import 'package:db_context_gen/src/transactional_generator.dart';
import 'package:source_gen/source_gen.dart';

Builder transactionalGenerator(BuilderOptions options) =>
    SharedPartBuilder([TransactionalGenerator()], 'transactional_generator');
