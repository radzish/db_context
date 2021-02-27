import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:built_collection/built_collection.dart';
import 'package:code_builder/code_builder.dart' as code;
import 'package:db_context_lib/db_context_lib.dart';
import 'package:source_gen/source_gen.dart';

TypeChecker _transactionalClassChecker = TypeChecker.fromRuntime(Transactional);
TypeChecker _transactionChecker = TypeChecker.fromRuntime(Transaction);
TypeChecker _futureChecker = TypeChecker.fromRuntime(Future);
RegExp _privateClassNameRegexp = RegExp(r"_+([^_]+)");

class TransactionalGenerator extends Generator {
  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) async {
    final transactionalClasses = library.classes.where(_isTransactional).where((cls) => cls.isPrivate);
    if (transactionalClasses.isEmpty) {
      return null;
    }

    return transactionalClasses.map(_generateTransactional).join("\n");
  }

  bool _isTransactional(ClassElement cls) => _transactionalClassChecker.isAssignableFrom(cls);

  String _generateTransactional(ClassElement cls) {
    return _convertToMixin(code.Class(
      (b) => b
        ..name = _generateMixinName(cls.displayName)
        ..types = _buildClassParameters(cls)
        ..extend = code.refer(_buildClassExtends(cls))
        ..methods = _buildTransactionalMethods(cls),
    ).accept(code.DartEmitter()).toString());
  }

  String _buildClassExtends(ClassElement cls) {
    if (cls.typeParameters.isEmpty ||
        cls.typeParameters.length == 1 && cls.typeParameters.first.displayName == "dynamic") {
      return cls.displayName;
    }

    return "${cls.displayName}<${cls.typeParameters.map((param) => param.displayName).join(",")}>";
  }

  ListBuilder<code.Reference> _buildClassParameters(ClassElement cls) {
    return ListBuilder(
      cls.typeParameters.map((param) => code.refer(param.toString())),
    );
  }

  String _generateMixinName(String name) {
    return "_\$${_privateClassNameRegexp.firstMatch(name).group(1)}";
  }

  ListBuilder<code.Parameter> _buildMethodRequiredParams(FunctionTypedElement constructor) {
    return ListBuilder(
      constructor.parameters.where((param) => param.isRequiredPositional).map(_buildMethodParam),
    );
  }

  ListBuilder<code.Parameter> _buildMethodOptionalParams(FunctionTypedElement constructor) {
    return ListBuilder(
      constructor.parameters.where((param) => param.isRequiredNamed || param.isOptional).map(_buildMethodParam),
    );
  }

  code.Parameter _buildMethodParam(ParameterElement param) {
    return code.Parameter((b) => b
      ..name = param.name
      ..type = code.refer(param.type.getDisplayString(withNullability: false))
      ..defaultTo = param.defaultValueCode != null ? code.refer(param.defaultValueCode).code : null
      ..named = param.isNamed);
  }

  Iterable<code.Expression> _buildMethodPositionalParamNames(FunctionTypedElement method) {
    return method.parameters
        .where((param) => param.isPositional)
        .map((param) => code.refer(param.displayName).expression);
  }

  Map<String, code.Expression> _buildMethodNamedParamNames(FunctionTypedElement method) {
    final paramNames = method.parameters.where((param) => param.isNamed).map((param) => param.displayName);
    return {
      for (var param in paramNames) param: code.refer(param).expression,
    };
  }

  ListBuilder<code.Method> _buildTransactionalMethods(ClassElement cls) {
    final suitableMethods =
        cls.methods.where((method) => method.isPublic && !method.isAbstract && !method.isStatic && _isAsync(method));

    return ListBuilder(
      suitableMethods.map(
        (method) => code.Method(
          (b) => b
            ..name = method.name
            ..requiredParameters = _buildMethodRequiredParams(method)
            ..optionalParameters = _buildMethodOptionalParams(method)
            ..returns = _buildMethodReturnType(method)
            ..annotations = ListBuilder([code.refer("override").expression])
            ..modifier = code.MethodModifier.async
            ..body = _buildMethodBody(method),
        ),
      ),
    );
  }

  bool _isAsync(MethodElement method) => _futureChecker.isExactlyType(method.returnType);

  code.Reference _buildMethodReturnType(MethodElement method) {
    return code.refer(method.returnType.displayName);
  }

  code.Code _buildMethodBody(MethodElement method) {
    final isTransaction =
        method.metadata.any((annotation) => _transactionChecker.isExactlyType(annotation.computeConstantValue().type));

    final wrapper = isTransaction ? "executeInWriteTransaction" : "executeInReadTransaction";

    final superCall = code.Method((b) => b
      ..body = code
          .refer("super.${method.displayName}")
          .call(
            _buildMethodPositionalParamNames(method),
            _buildMethodNamedParamNames(method),
          )
          .code).closure;

    final wrapperCall = code.refer('db.$wrapper').call([superCall]).awaited.returned.statement;

    return code.Block((b) => b..statements = ListBuilder([wrapperCall]));
  }

  String _convertToMixin(String classCode) {
    // replace class with mixin keyword
    var result = "mixin ${classCode.substring(5)}";

    // find last "extends" before first {
    final openingBracePosition = result.indexOf("{");
    final extendsPosition = result.substring(0, openingBracePosition).lastIndexOf("extends");

    // replace "extends" with "on"
    result = result.substring(0, extendsPosition) + " on " + result.substring(extendsPosition + "extends".length);

    return result;
  }
}
