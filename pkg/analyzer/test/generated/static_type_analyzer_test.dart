// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/inheritance_manager3.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/static_type_analyzer.dart';
import 'package:analyzer/src/generated/testing/ast_test_factory.dart';
import 'package:analyzer/src/generated/testing/element_factory.dart';
import 'package:analyzer/src/generated/testing/token_factory.dart';
import 'package:analyzer/src/source/source_resource.dart';
import 'package:analyzer/src/test_utilities/resource_provider_mixin.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'resolver_test_case.dart';
import 'test_analysis_context.dart';
import 'test_support.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SetLiteralsTest);
    defineReflectiveTests(StaticTypeAnalyzerTest);
    defineReflectiveTests(StaticTypeAnalyzer2Test);
    defineReflectiveTests(StaticTypeAnalyzer3Test);
    defineReflectiveTests(StaticTypeAnalyzerWithSetLiteralsTest);
  });
}

/// Wrapper around the test package's `fail` function.
///
/// Unlike the test package's `fail` function, this function is not annotated
/// with @alwaysThrows, so we can call it at the top of a test method without
/// causing the rest of the method to be flagged as dead code.
void _fail(String message) {
  fail(message);
}

@reflectiveTest
class SetLiteralsTest extends StaticTypeAnalyzer2TestShared {
  test_emptySetLiteral_parameter_typed() async {
    String code = r'''
main() {
  useSet({});
}
void useSet(Set<int> s) {
}
''';
    await resolveTestUnit(code);
    expectExpressionType('{}', 'Set<int>');
  }
}

/**
 * Like [StaticTypeAnalyzerTest], but as end-to-end tests.
 */
@reflectiveTest
class StaticTypeAnalyzer2Test extends StaticTypeAnalyzer2TestShared {
  test_FunctionExpressionInvocation_block() async {
    String code = r'''
main() {
  var foo = (() { return 1; })();
}
''';
    await resolveTestUnit(code);
    expectInitializerType('foo', 'int');
  }

  test_FunctionExpressionInvocation_curried() async {
    String code = r'''
typedef int F();
F f() => null;
main() {
  var foo = f()();
}
''';
    await resolveTestUnit(code);
    expectInitializerType('foo', 'int');
  }

  test_FunctionExpressionInvocation_expression() async {
    String code = r'''
main() {
  var foo = (() => 1)();
}
''';
    await resolveTestUnit(code);
    expectInitializerType('foo', 'int');
  }

  test_MethodInvocation_nameType_localVariable() async {
    String code = r"""
typedef Foo();
main() {
  Foo foo;
  foo();
}
""";
    await resolveTestUnit(code);
    // "foo" should be resolved to the "Foo" type
    expectIdentifierType("foo();", new TypeMatcher<FunctionType>());
  }

  test_MethodInvocation_nameType_parameter_FunctionTypeAlias() async {
    String code = r"""
typedef Foo();
main(Foo foo) {
  foo();
}
""";
    await resolveTestUnit(code);
    // "foo" should be resolved to the "Foo" type
    expectIdentifierType("foo();", new TypeMatcher<FunctionType>());
  }

  test_MethodInvocation_nameType_parameter_propagatedType() async {
    String code = r"""
typedef Foo();
main(p) {
  if (p is Foo) {
    p();
  }
}
""";
    await resolveTestUnit(code);
    expectIdentifierType("p()", 'dynamic Function()');
  }

  test_staticMethods_classTypeParameters() async {
    String code = r'''
class C<T> {
  static void m() => null;
}
main() {
  print(C.m);
}
''';
    await resolveTestUnit(code);
    expectFunctionType('m);', 'void Function()');
  }

  test_staticMethods_classTypeParameters_genericMethod() async {
    String code = r'''
class C<T> {
  static void m<S>(S s) {
    void f<U>(S s, U u) {}
    print(f);
  }
}
main() {
  print(C.m);
}
''';
    await resolveTestUnit(code);
    // C - m
    TypeParameterType typeS;
    {
      FunctionTypeImpl type = expectFunctionType('m);', 'void Function<S>(S)',
          elementTypeParams: '[S]',
          typeFormals: '[S]',
          identifierType: 'void Function<S>(S)');

      typeS = type.typeFormals[0].type;
      type = type.instantiate([DynamicTypeImpl.instance]);
      expect(type.toString(), 'void Function(dynamic)');
      expect(type.typeParameters.toString(), '[S]');
      expect(type.typeArguments, [DynamicTypeImpl.instance]);
      expect(type.typeFormals, isEmpty);
    }
    // C - m - f
    {
      FunctionTypeImpl type = expectFunctionType(
          'f);', 'void Function<U>(S, U)',
          elementTypeParams: '[U]',
          typeParams: '[S]',
          typeArgs: '[S]',
          typeFormals: '[U]',
          identifierType: 'void Function<U>(S, U)');

      type = type.instantiate([DynamicTypeImpl.instance]);
      expect(type.toString(), 'void Function(S, dynamic)');
      expect(type.typeParameters.toString(), '[S, U]');
      expect(type.typeArguments, [typeS, DynamicTypeImpl.instance]);
      expect(type.typeFormals, isEmpty);
    }
  }
}

/**
 * End-to-end tests of the static type analyzer that use the new driver.
 */
@reflectiveTest
class StaticTypeAnalyzer3Test extends StaticTypeAnalyzer2TestShared {
  test_emptyMapLiteral_initializer_var() async {
    String code = r'''
main() {
  var v = {};
}
''';
    await resolveTestUnit(code);
    expectExpressionType('{}', 'Map<dynamic, dynamic>');
  }

  test_emptyMapLiteral_parameter_typed() async {
    String code = r'''
main() {
  useMap({});
}
void useMap(Map<int, int> m) {
}
''';
    await resolveTestUnit(code);
    expectExpressionType('{}', 'Map<int, int>');
  }
}

@reflectiveTest
class StaticTypeAnalyzerTest extends EngineTestCase with ResourceProviderMixin {
  /**
   * The error listener to which errors will be reported.
   */
  GatheringErrorListener _listener;

  /**
   * The resolver visitor used to create the analyzer.
   */
  ResolverVisitor _visitor;

  /**
   * The analyzer being used to analyze the test cases.
   */
  StaticTypeAnalyzer _analyzer;

  /**
   * The type provider used to access the types.
   */
  TypeProvider _typeProvider;

  /**
   * The type system used to analyze the test cases.
   */
  TypeSystem get _typeSystem => _visitor.typeSystem;

  void fail_visitFunctionExpressionInvocation() {
    _fail("Not yet tested");
    _listener.assertNoErrors();
  }

  void fail_visitMethodInvocation() {
    _fail("Not yet tested");
    _listener.assertNoErrors();
  }

  void fail_visitSimpleIdentifier() {
    _fail("Not yet tested");
    _listener.assertNoErrors();
  }

  @override
  void setUp() {
    super.setUp();
    _listener = new GatheringErrorListener();
    _analyzer = _createAnalyzer();
  }

  void test_flatten_derived() {
    // class Derived<T> extends Future<T> { ... }
    ClassElementImpl derivedClass =
        ElementFactory.classElement2('Derived', ['T']);
    derivedClass.supertype = _typeProvider.futureType
        .instantiate([derivedClass.typeParameters[0].type]);
    InterfaceType intType = _typeProvider.intType;
    DartType dynamicType = _typeProvider.dynamicType;
    InterfaceType derivedIntType = derivedClass.type.instantiate([intType]);
    // flatten(Derived) = dynamic
    InterfaceType derivedDynamicType =
        derivedClass.type.instantiate([dynamicType]);
    expect(_flatten(derivedDynamicType), dynamicType);
    // flatten(Derived<int>) = int
    expect(_flatten(derivedIntType), intType);
    // flatten(Derived<Derived>) = Derived
    expect(_flatten(derivedClass.type.instantiate([derivedDynamicType])),
        derivedDynamicType);
    // flatten(Derived<Derived<int>>) = Derived<int>
    expect(_flatten(derivedClass.type.instantiate([derivedIntType])),
        derivedIntType);
  }

  void test_flatten_inhibit_recursion() {
    // class A extends B
    // class B extends A
    ClassElementImpl classA = ElementFactory.classElement2('A', []);
    ClassElementImpl classB = ElementFactory.classElement2('B', []);
    classA.supertype = classB.type;
    classB.supertype = classA.type;
    // flatten(A) = A and flatten(B) = B, since neither class contains Future
    // in its class hierarchy.  Even though there is a loop in the class
    // hierarchy, flatten() should terminate.
    expect(_flatten(classA.type), classA.type);
    expect(_flatten(classB.type), classB.type);
  }

  void test_flatten_related_derived_types() {
    InterfaceType intType = _typeProvider.intType;
    InterfaceType numType = _typeProvider.numType;
    // class Derived<T> extends Future<T>
    ClassElementImpl derivedClass =
        ElementFactory.classElement2('Derived', ['T']);
    derivedClass.supertype = _typeProvider.futureType
        .instantiate([derivedClass.typeParameters[0].type]);
    InterfaceType derivedType = derivedClass.type;
    // class A extends Derived<int> implements Derived<num> { ... }
    ClassElementImpl classA =
        ElementFactory.classElement('A', derivedType.instantiate([intType]));
    classA.interfaces = <InterfaceType>[
      derivedType.instantiate([numType])
    ];
    // class B extends Future<num> implements Future<int> { ... }
    ClassElementImpl classB =
        ElementFactory.classElement('B', derivedType.instantiate([numType]));
    classB.interfaces = <InterfaceType>[
      derivedType.instantiate([intType])
    ];
    // flatten(A) = flatten(B) = int, since int is more specific than num.
    // The code in flatten() that inhibits infinite recursion shouldn't be
    // fooled by the fact that Derived appears twice in the type hierarchy.
    expect(_flatten(classA.type), intType);
    expect(_flatten(classB.type), intType);
  }

  void test_flatten_related_types() {
    InterfaceType futureType = _typeProvider.futureType;
    InterfaceType intType = _typeProvider.intType;
    InterfaceType numType = _typeProvider.numType;
    // class A extends Future<int> implements Future<num> { ... }
    ClassElementImpl classA =
        ElementFactory.classElement('A', futureType.instantiate([intType]));
    classA.interfaces = <InterfaceType>[
      futureType.instantiate([numType])
    ];
    // class B extends Future<num> implements Future<int> { ... }
    ClassElementImpl classB =
        ElementFactory.classElement('B', futureType.instantiate([numType]));
    classB.interfaces = <InterfaceType>[
      futureType.instantiate([intType])
    ];
    // flatten(A) = flatten(B) = int, since int is more specific than num.
    expect(_flatten(classA.type), intType);
    expect(_flatten(classB.type), intType);
  }

  void test_flatten_simple() {
    InterfaceType intType = _typeProvider.intType;
    DartType dynamicType = _typeProvider.dynamicType;
    InterfaceType futureDynamicType = _typeProvider.futureDynamicType;
    InterfaceType futureIntType =
        _typeProvider.futureType.instantiate([intType]);
    InterfaceType futureFutureDynamicType =
        _typeProvider.futureType.instantiate([futureDynamicType]);
    InterfaceType futureFutureIntType =
        _typeProvider.futureType.instantiate([futureIntType]);
    // flatten(int) = int
    expect(_flatten(intType), intType);
    // flatten(dynamic) = dynamic
    expect(_flatten(dynamicType), dynamicType);
    // flatten(Future) = dynamic
    expect(_flatten(futureDynamicType), dynamicType);
    // flatten(Future<int>) = int
    expect(_flatten(futureIntType), intType);
    // flatten(Future<Future>) = Future<dynamic>
    expect(_flatten(futureFutureDynamicType), futureDynamicType);
    // flatten(Future<Future<int>>) = Future<int>
    expect(_flatten(futureFutureIntType), futureIntType);
  }

  void test_flatten_unrelated_types() {
    InterfaceType futureType = _typeProvider.futureType;
    InterfaceType intType = _typeProvider.intType;
    InterfaceType stringType = _typeProvider.stringType;
    // class A extends Future<int> implements Future<String> { ... }
    ClassElementImpl classA =
        ElementFactory.classElement('A', futureType.instantiate([intType]));
    classA.interfaces = <InterfaceType>[
      futureType.instantiate([stringType])
    ];
    // class B extends Future<String> implements Future<int> { ... }
    ClassElementImpl classB =
        ElementFactory.classElement('B', futureType.instantiate([stringType]));
    classB.interfaces = <InterfaceType>[
      futureType.instantiate([intType])
    ];
    // flatten(A) = A and flatten(B) = B, since neither string nor int is more
    // specific than the other.
    expect(_flatten(classA.type), classA.type);
    expect(_flatten(classB.type), classB.type);
  }

  void test_visitAdjacentStrings() {
    // "a" "b"
    Expression node = AstTestFactory.adjacentStrings(
        [_resolvedString("a"), _resolvedString("b")]);
    expect(_analyze(node), same(_typeProvider.stringType));
    _listener.assertNoErrors();
  }

  void test_visitAsExpression() {
    // class A { ... this as B ... }
    // class B extends A {}
    ClassElement superclass = ElementFactory.classElement2("A");
    InterfaceType superclassType = superclass.type;
    ClassElement subclass = ElementFactory.classElement("B", superclassType);
    Expression node = AstTestFactory.asExpression(
        AstTestFactory.thisExpression(), AstTestFactory.typeName(subclass));
    expect(_analyze(node, superclassType), same(subclass.type));
    _listener.assertNoErrors();
  }

  void test_visitAssignmentExpression_compound_lazy() {
    validate(TokenType operator) {
      InterfaceType boolType = _typeProvider.boolType;
      SimpleIdentifier identifier = _resolvedVariable(boolType, "b");
      AssignmentExpression node = AstTestFactory.assignmentExpression(
          identifier, operator, _resolvedBool(true));
      expect(_analyze(node), same(boolType));
      _listener.assertNoErrors();
    }

    validate(TokenType.AMPERSAND_AMPERSAND_EQ);
    validate(TokenType.BAR_BAR_EQ);
  }

  void test_visitAssignmentExpression_simple() {
    // i = 0
    InterfaceType intType = _typeProvider.intType;
    Expression node = AstTestFactory.assignmentExpression(
        _resolvedVariable(intType, "i"), TokenType.EQ, _resolvedInteger(0));
    expect(_analyze(node), same(intType));
    _listener.assertNoErrors();
  }

  void test_visitAwaitExpression_flattened() {
    // await e, where e has type Future<Future<int>>
    InterfaceType intType = _typeProvider.intType;
    InterfaceType futureIntType =
        _typeProvider.futureType.instantiate(<DartType>[intType]);
    InterfaceType futureFutureIntType =
        _typeProvider.futureType.instantiate(<DartType>[futureIntType]);
    Expression node = AstTestFactory.awaitExpression(
        _resolvedVariable(futureFutureIntType, 'e'));
    expect(_analyze(node), same(futureIntType));
    _listener.assertNoErrors();
  }

  void test_visitAwaitExpression_simple() {
    // await e, where e has type Future<int>
    InterfaceType intType = _typeProvider.intType;
    InterfaceType futureIntType =
        _typeProvider.futureType.instantiate(<DartType>[intType]);
    Expression node =
        AstTestFactory.awaitExpression(_resolvedVariable(futureIntType, 'e'));
    expect(_analyze(node), same(intType));
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_equals() {
    // 2 == 3
    Expression node = AstTestFactory.binaryExpression(
        _resolvedInteger(2), TokenType.EQ_EQ, _resolvedInteger(3));
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_ifNull() {
    // 1 ?? 1.5
    Expression node = AstTestFactory.binaryExpression(
        _resolvedInteger(1), TokenType.QUESTION_QUESTION, _resolvedDouble(1.5));
    expect(_analyze(node), _typeProvider.numType);
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_logicalAnd() {
    // false && true
    Expression node = AstTestFactory.binaryExpression(
        AstTestFactory.booleanLiteral(false),
        TokenType.AMPERSAND_AMPERSAND,
        AstTestFactory.booleanLiteral(true));
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_logicalOr() {
    // false || true
    Expression node = AstTestFactory.binaryExpression(
        AstTestFactory.booleanLiteral(false),
        TokenType.BAR_BAR,
        AstTestFactory.booleanLiteral(true));
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_notEquals() {
    // 2 != 3
    Expression node = AstTestFactory.binaryExpression(
        _resolvedInteger(2), TokenType.BANG_EQ, _resolvedInteger(3));
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_plusID() {
    // 1 + 2.0
    BinaryExpression node = AstTestFactory.binaryExpression(
        _resolvedInteger(1), TokenType.PLUS, _resolvedDouble(2.0));
    node.staticElement = getMethod(_typeProvider.numType, "+");
    expect(_analyze(node), same(_typeProvider.doubleType));
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_plusII() {
    // 1 + 2
    BinaryExpression node = AstTestFactory.binaryExpression(
        _resolvedInteger(1), TokenType.PLUS, _resolvedInteger(2));
    node.staticElement = getMethod(_typeProvider.numType, "+");
    expect(_analyze(node), same(_typeProvider.intType));
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_slash() {
    // 2 / 2
    BinaryExpressionImpl node = AstTestFactory.binaryExpression(
        _resolvedInteger(2), TokenType.SLASH, _resolvedInteger(2));
    node.staticElement = getMethod(_typeProvider.numType, "/");
    node.staticInvokeType = node.staticElement.type;
    expect(_analyze(node), _typeProvider.doubleType);
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_star_notSpecial() {
    // class A {
    //   A operator *(double value);
    // }
    // (a as A) * 2.0
    ClassElementImpl classA = ElementFactory.classElement2("A");
    InterfaceType typeA = classA.type;
    MethodElement operator =
        ElementFactory.methodElement("*", typeA, [_typeProvider.doubleType]);
    classA.methods = <MethodElement>[operator];

    var asExpression = AstTestFactory.asExpression(
        AstTestFactory.identifier3("a"), AstTestFactory.typeName(classA));
    asExpression.staticType = typeA;

    BinaryExpressionImpl node = AstTestFactory.binaryExpression(
        asExpression, TokenType.PLUS, _resolvedDouble(2.0));
    node.staticElement = operator;
    node.staticInvokeType = node.staticElement.type;
    expect(_analyze(node), same(typeA));
    _listener.assertNoErrors();
  }

  void test_visitBinaryExpression_starID() {
    // 1 * 2.0
    BinaryExpression node = AstTestFactory.binaryExpression(
        _resolvedInteger(1), TokenType.PLUS, _resolvedDouble(2.0));
    node.staticElement = getMethod(_typeProvider.numType, "*");
    expect(_analyze(node), same(_typeProvider.doubleType));
    _listener.assertNoErrors();
  }

  void test_visitBooleanLiteral_false() {
    // false
    Expression node = AstTestFactory.booleanLiteral(false);
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitBooleanLiteral_true() {
    // true
    Expression node = AstTestFactory.booleanLiteral(true);
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitCascadeExpression() {
    // a..length
    Expression node = AstTestFactory.cascadeExpression(
        _resolvedString("a"), [AstTestFactory.propertyAccess2(null, "length")]);
    expect(_analyze(node), same(_typeProvider.stringType));
    _listener.assertNoErrors();
  }

  void test_visitConditionalExpression_differentTypes() {
    // true ? 1.0 : 0
    Expression node = AstTestFactory.conditionalExpression(
        AstTestFactory.booleanLiteral(true),
        _resolvedDouble(1.0),
        _resolvedInteger(0));
    expect(_analyze(node), _typeProvider.numType);
    _listener.assertNoErrors();
  }

  void test_visitConditionalExpression_sameTypes() {
    // true ? 1 : 0
    Expression node = AstTestFactory.conditionalExpression(
        AstTestFactory.booleanLiteral(true),
        _resolvedInteger(1),
        _resolvedInteger(0));
    expect(_analyze(node), same(_typeProvider.intType));
    _listener.assertNoErrors();
  }

  void test_visitDoubleLiteral() {
    // 4.33
    Expression node = AstTestFactory.doubleLiteral(4.33);
    expect(_analyze(node), same(_typeProvider.doubleType));
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_async_block() {
    // () async {}
    BlockFunctionBody body = AstTestFactory.blockFunctionBody2();
    body.keyword = TokenFactory.tokenFromString('async');
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([]), body);
    DartType resultType = _analyze(node);
    _assertFunctionType(
        _typeProvider.futureDynamicType, null, null, null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_async_expression() {
    // () async => e, where e has type int
    InterfaceType intType = _typeProvider.intType;
    Expression expression = _resolvedVariable(intType, 'e');
    ExpressionFunctionBody body =
        AstTestFactory.expressionFunctionBody(expression);
    body.keyword = TokenFactory.tokenFromString('async');
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([]), body);
    DartType resultType = _analyze(node);
    _assertFunctionType(
        _typeProvider.futureType
            .instantiate(<DartType>[_typeProvider.dynamicType]),
        null,
        null,
        null,
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_async_expression_flatten() {
    // () async => e, where e has type Future<int>
    InterfaceType intType = _typeProvider.intType;
    InterfaceType futureIntType =
        _typeProvider.futureType.instantiate(<DartType>[intType]);
    Expression expression = _resolvedVariable(futureIntType, 'e');
    ExpressionFunctionBody body =
        AstTestFactory.expressionFunctionBody(expression);
    body.keyword = TokenFactory.tokenFromString('async');
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([]), body);
    DartType resultType = _analyze(node);
    _assertFunctionType(
        _typeProvider.futureType
            .instantiate(<DartType>[_typeProvider.dynamicType]),
        null,
        null,
        null,
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_async_expression_flatten_twice() {
    // () async => e, where e has type Future<Future<int>>
    InterfaceType intType = _typeProvider.intType;
    InterfaceType futureIntType =
        _typeProvider.futureType.instantiate(<DartType>[intType]);
    InterfaceType futureFutureIntType =
        _typeProvider.futureType.instantiate(<DartType>[futureIntType]);
    Expression expression = _resolvedVariable(futureFutureIntType, 'e');
    ExpressionFunctionBody body =
        AstTestFactory.expressionFunctionBody(expression);
    body.keyword = TokenFactory.tokenFromString('async');
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([]), body);
    DartType resultType = _analyze(node);
    _assertFunctionType(
        _typeProvider.futureType
            .instantiate(<DartType>[_typeProvider.dynamicType]),
        null,
        null,
        null,
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_generator_async() {
    // () async* {}
    BlockFunctionBody body = AstTestFactory.blockFunctionBody2();
    body.keyword = TokenFactory.tokenFromString('async');
    body.star = TokenFactory.tokenFromType(TokenType.STAR);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([]), body);
    DartType resultType = _analyze(node);
    _assertFunctionType(
        _typeProvider.streamDynamicType, null, null, null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_generator_sync() {
    // () sync* {}
    BlockFunctionBody body = AstTestFactory.blockFunctionBody2();
    body.keyword = TokenFactory.tokenFromString('sync');
    body.star = TokenFactory.tokenFromType(TokenType.STAR);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([]), body);
    DartType resultType = _analyze(node);
    _assertFunctionType(
        _typeProvider.iterableDynamicType, null, null, null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_named_block() {
    // ({p1 : 0, p2 : 0}) {}
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p1 = AstTestFactory.namedFormalParameter(
        AstTestFactory.simpleFormalParameter3("p1"), _resolvedInteger(0));
    _setType(p1, dynamicType);
    FormalParameter p2 = AstTestFactory.namedFormalParameter(
        AstTestFactory.simpleFormalParameter3("p2"), _resolvedInteger(0));
    _setType(p2, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p1, p2]),
        AstTestFactory.blockFunctionBody2());
    _analyze5(p1);
    _analyze5(p2);
    DartType resultType = _analyze(node);
    Map<String, DartType> expectedNamedTypes = new HashMap<String, DartType>();
    expectedNamedTypes["p1"] = dynamicType;
    expectedNamedTypes["p2"] = dynamicType;
    _assertFunctionType(
        dynamicType, null, null, expectedNamedTypes, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_named_expression() {
    // ({p : 0}) -> 0;
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p = AstTestFactory.namedFormalParameter(
        AstTestFactory.simpleFormalParameter3("p"), _resolvedInteger(0));
    _setType(p, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p]),
        AstTestFactory.expressionFunctionBody(_resolvedInteger(0)));
    _analyze5(p);
    DartType resultType = _analyze(node);
    Map<String, DartType> expectedNamedTypes = new HashMap<String, DartType>();
    expectedNamedTypes["p"] = dynamicType;
    _assertFunctionType(
        dynamicType, null, null, expectedNamedTypes, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_normal_block() {
    // (p1, p2) {}
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p1 = AstTestFactory.simpleFormalParameter3("p1");
    _setType(p1, dynamicType);
    FormalParameter p2 = AstTestFactory.simpleFormalParameter3("p2");
    _setType(p2, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p1, p2]),
        AstTestFactory.blockFunctionBody2());
    _analyze5(p1);
    _analyze5(p2);
    DartType resultType = _analyze(node);
    _assertFunctionType(dynamicType, <DartType>[dynamicType, dynamicType], null,
        null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_normal_expression() {
    // (p1, p2) -> 0
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p = AstTestFactory.simpleFormalParameter3("p");
    _setType(p, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p]),
        AstTestFactory.expressionFunctionBody(_resolvedInteger(0)));
    _analyze5(p);
    DartType resultType = _analyze(node);
    _assertFunctionType(
        dynamicType, <DartType>[dynamicType], null, null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_normalAndNamed_block() {
    // (p1, {p2 : 0}) {}
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p1 = AstTestFactory.simpleFormalParameter3("p1");
    _setType(p1, dynamicType);
    FormalParameter p2 = AstTestFactory.namedFormalParameter(
        AstTestFactory.simpleFormalParameter3("p2"), _resolvedInteger(0));
    _setType(p2, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p1, p2]),
        AstTestFactory.blockFunctionBody2());
    _analyze5(p2);
    DartType resultType = _analyze(node);
    Map<String, DartType> expectedNamedTypes = new HashMap<String, DartType>();
    expectedNamedTypes["p2"] = dynamicType;
    _assertFunctionType(dynamicType, <DartType>[dynamicType], null,
        expectedNamedTypes, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_normalAndNamed_expression() {
    // (p1, {p2 : 0}) -> 0
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p1 = AstTestFactory.simpleFormalParameter3("p1");
    _setType(p1, dynamicType);
    FormalParameter p2 = AstTestFactory.namedFormalParameter(
        AstTestFactory.simpleFormalParameter3("p2"), _resolvedInteger(0));
    _setType(p2, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p1, p2]),
        AstTestFactory.expressionFunctionBody(_resolvedInteger(0)));
    _analyze5(p2);
    DartType resultType = _analyze(node);
    Map<String, DartType> expectedNamedTypes = new HashMap<String, DartType>();
    expectedNamedTypes["p2"] = dynamicType;
    _assertFunctionType(dynamicType, <DartType>[dynamicType], null,
        expectedNamedTypes, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_normalAndPositional_block() {
    // (p1, [p2 = 0]) {}
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p1 = AstTestFactory.simpleFormalParameter3("p1");
    _setType(p1, dynamicType);
    FormalParameter p2 = AstTestFactory.positionalFormalParameter(
        AstTestFactory.simpleFormalParameter3("p2"), _resolvedInteger(0));
    _setType(p2, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p1, p2]),
        AstTestFactory.blockFunctionBody2());
    _analyze5(p1);
    _analyze5(p2);
    DartType resultType = _analyze(node);
    _assertFunctionType(dynamicType, <DartType>[dynamicType],
        <DartType>[dynamicType], null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_normalAndPositional_expression() {
    // (p1, [p2 = 0]) -> 0
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p1 = AstTestFactory.simpleFormalParameter3("p1");
    _setType(p1, dynamicType);
    FormalParameter p2 = AstTestFactory.positionalFormalParameter(
        AstTestFactory.simpleFormalParameter3("p2"), _resolvedInteger(0));
    _setType(p2, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p1, p2]),
        AstTestFactory.expressionFunctionBody(_resolvedInteger(0)));
    _analyze5(p1);
    _analyze5(p2);
    DartType resultType = _analyze(node);
    _assertFunctionType(dynamicType, <DartType>[dynamicType],
        <DartType>[dynamicType], null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_positional_block() {
    // ([p1 = 0, p2 = 0]) {}
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p1 = AstTestFactory.positionalFormalParameter(
        AstTestFactory.simpleFormalParameter3("p1"), _resolvedInteger(0));
    _setType(p1, dynamicType);
    FormalParameter p2 = AstTestFactory.positionalFormalParameter(
        AstTestFactory.simpleFormalParameter3("p2"), _resolvedInteger(0));
    _setType(p2, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p1, p2]),
        AstTestFactory.blockFunctionBody2());
    _analyze5(p1);
    _analyze5(p2);
    DartType resultType = _analyze(node);
    _assertFunctionType(dynamicType, null, <DartType>[dynamicType, dynamicType],
        null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitFunctionExpression_positional_expression() {
    // ([p = 0]) -> 0
    DartType dynamicType = _typeProvider.dynamicType;
    FormalParameter p = AstTestFactory.positionalFormalParameter(
        AstTestFactory.simpleFormalParameter3("p"), _resolvedInteger(0));
    _setType(p, dynamicType);
    FunctionExpression node = _resolvedFunctionExpression(
        AstTestFactory.formalParameterList([p]),
        AstTestFactory.expressionFunctionBody(_resolvedInteger(0)));
    _analyze5(p);
    DartType resultType = _analyze(node);
    _assertFunctionType(
        dynamicType, null, <DartType>[dynamicType], null, resultType);
    _listener.assertNoErrors();
  }

  void test_visitInstanceCreationExpression_named() {
    // new C.m()
    ClassElementImpl classElement = ElementFactory.classElement2("C");
    String constructorName = "m";
    ConstructorElementImpl constructor =
        ElementFactory.constructorElement2(classElement, constructorName);
    classElement.constructors = <ConstructorElement>[constructor];
    InstanceCreationExpression node =
        AstTestFactory.instanceCreationExpression2(
            null,
            AstTestFactory.typeName(classElement),
            [AstTestFactory.identifier3(constructorName)]);
    node.staticElement = constructor;
    expect(_analyze(node), same(classElement.type));
    _listener.assertNoErrors();
  }

  void test_visitInstanceCreationExpression_typeParameters() {
    // new C<I>()
    ClassElementImpl elementC = ElementFactory.classElement2("C", ["E"]);
    ClassElementImpl elementI = ElementFactory.classElement2("I");
    ConstructorElementImpl constructor =
        ElementFactory.constructorElement2(elementC, null);
    elementC.constructors = <ConstructorElement>[constructor];
    TypeName typeName =
        AstTestFactory.typeName(elementC, [AstTestFactory.typeName(elementI)]);
    typeName.type = elementC.type.instantiate(<DartType>[elementI.type]);
    InstanceCreationExpression node =
        AstTestFactory.instanceCreationExpression2(null, typeName);
    node.staticElement = constructor;
    InterfaceType interfaceType = _analyze(node) as InterfaceType;
    List<DartType> typeArgs = interfaceType.typeArguments;
    expect(typeArgs.length, 1);
    expect(typeArgs[0], elementI.type);
    _listener.assertNoErrors();
  }

  void test_visitInstanceCreationExpression_unnamed() {
    // new C()
    ClassElementImpl classElement = ElementFactory.classElement2("C");
    ConstructorElementImpl constructor =
        ElementFactory.constructorElement2(classElement, null);
    classElement.constructors = <ConstructorElement>[constructor];
    InstanceCreationExpression node =
        AstTestFactory.instanceCreationExpression2(
            null, AstTestFactory.typeName(classElement));
    node.staticElement = constructor;
    expect(_analyze(node), same(classElement.type));
    _listener.assertNoErrors();
  }

  void test_visitIntegerLiteral() {
    // 42
    Expression node = _resolvedInteger(42);
    expect(_analyze(node), same(_typeProvider.intType));
    _listener.assertNoErrors();
  }

  void test_visitIsExpression_negated() {
    // a is! String
    Expression node = AstTestFactory.isExpression(
        _resolvedString("a"), true, AstTestFactory.typeName4("String"));
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitIsExpression_notNegated() {
    // a is String
    Expression node = AstTestFactory.isExpression(
        _resolvedString("a"), false, AstTestFactory.typeName4("String"));
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitListLiteral_empty() {
    // []
    Expression node = AstTestFactory.listLiteral();
    DartType resultType = _analyze(node);
    _assertType2(
        _typeProvider.listType
            .instantiate(<DartType>[_typeProvider.dynamicType]),
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitListLiteral_nonEmpty() {
    // [0]
    Expression node = AstTestFactory.listLiteral([_resolvedInteger(0)]);
    DartType resultType = _analyze(node);
    _assertType2(
        _typeProvider.listType.instantiate(<DartType>[_typeProvider.intType]),
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitListLiteral_unresolved() {
    // [a] // where 'a' is not resolved
    Identifier identifier = AstTestFactory.identifier3('a');
    Expression node = AstTestFactory.listLiteral([identifier]);
    DartType resultType = _analyze(node);
    _assertType2(
        _typeProvider.listType
            .instantiate(<DartType>[_typeProvider.dynamicType]),
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitListLiteral_unresolved_multiple() {
    // [0, a, 1] // where 'a' is not resolved
    Identifier identifier = AstTestFactory.identifier3('a');
    Expression node = AstTestFactory.listLiteral(
        [_resolvedInteger(0), identifier, _resolvedInteger(1)]);
    DartType resultType = _analyze(node);
    _assertType2(
        _typeProvider.listType.instantiate(<DartType>[_typeProvider.intType]),
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitMapLiteral_empty() {
    // {}
    Expression node = AstTestFactory.setOrMapLiteral(null, null);
    DartType resultType = _analyze(node);
    _assertType2(
        _typeProvider.mapType.instantiate(
            <DartType>[_typeProvider.dynamicType, _typeProvider.dynamicType]),
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitMapLiteral_nonEmpty() {
    // {"k" : 0}
    Expression node = AstTestFactory.setOrMapLiteral(
        null, null, [AstTestFactory.mapLiteralEntry("k", _resolvedInteger(0))]);
    DartType resultType = _analyze(node);
    _assertType2(
        _typeProvider.mapType.instantiate(
            <DartType>[_typeProvider.dynamicType, _typeProvider.intType]),
        resultType);
    _listener.assertNoErrors();
  }

  void test_visitMethodInvocation_then() {
    // then()
    Expression node = AstTestFactory.methodInvocation(null, "then");
    _analyze(node);
    _listener.assertNoErrors();
  }

  void test_visitNamedExpression() {
    // n: a
    Expression node =
        AstTestFactory.namedExpression2("n", _resolvedString("a"));
    expect(_analyze(node), same(_typeProvider.stringType));
    _listener.assertNoErrors();
  }

  void test_visitNullLiteral() {
    // null
    Expression node = AstTestFactory.nullLiteral();
    expect(_analyze(node), same(_typeProvider.nullType));
    _listener.assertNoErrors();
  }

  void test_visitParenthesizedExpression() {
    // (0)
    Expression node =
        AstTestFactory.parenthesizedExpression(_resolvedInteger(0));
    expect(_analyze(node), same(_typeProvider.intType));
    _listener.assertNoErrors();
  }

  void test_visitPostfixExpression_minusMinus() {
    // 0--
    PostfixExpression node = AstTestFactory.postfixExpression(
        _resolvedInteger(0), TokenType.MINUS_MINUS);
    expect(_analyze(node), same(_typeProvider.intType));
    _listener.assertNoErrors();
  }

  void test_visitPostfixExpression_plusPlus() {
    // 0++
    PostfixExpression node = AstTestFactory.postfixExpression(
        _resolvedInteger(0), TokenType.PLUS_PLUS);
    expect(_analyze(node), same(_typeProvider.intType));
    _listener.assertNoErrors();
  }

  void test_visitPrefixedIdentifier_getter() {
    DartType boolType = _typeProvider.boolType;
    PropertyAccessorElementImpl getter =
        ElementFactory.getterElement("b", false, boolType);
    PrefixedIdentifier node = AstTestFactory.identifier5("a", "b");
    node.identifier.staticElement = getter;
    expect(_analyze(node), same(boolType));
    _listener.assertNoErrors();
  }

  void test_visitPrefixedIdentifier_setter() {
    DartType boolType = _typeProvider.boolType;
    FieldElementImpl field =
        ElementFactory.fieldElement("b", false, false, false, boolType);
    PropertyAccessorElement setter = field.setter;
    PrefixedIdentifier node = AstTestFactory.identifier5("a", "b");
    node.identifier.staticElement = setter;
    expect(_analyze(node), same(boolType));
    _listener.assertNoErrors();
  }

  void test_visitPrefixedIdentifier_variable() {
    VariableElementImpl variable = ElementFactory.localVariableElement2("b");
    variable.type = _typeProvider.boolType;
    PrefixedIdentifier node = AstTestFactory.identifier5("a", "b");
    node.identifier.staticElement = variable;
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitPrefixExpression_bang() {
    // !0
    PrefixExpression node =
        AstTestFactory.prefixExpression(TokenType.BANG, _resolvedInteger(0));
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitPrefixExpression_minus() {
    // -0
    PrefixExpression node =
        AstTestFactory.prefixExpression(TokenType.MINUS, _resolvedInteger(0));
    MethodElement minusMethod = getMethod(_typeProvider.numType, "-");
    node.staticElement = minusMethod;
    expect(_analyze(node), _typeProvider.numType);
    _listener.assertNoErrors();
  }

  void test_visitPrefixExpression_minusMinus() {
    // --0
    PrefixExpression node = AstTestFactory.prefixExpression(
        TokenType.MINUS_MINUS, _resolvedInteger(0));
    MethodElement minusMethod = getMethod(_typeProvider.numType, "-");
    node.staticElement = minusMethod;
    expect(_analyze(node), same(_typeProvider.intType));
    _listener.assertNoErrors();
  }

  void test_visitPrefixExpression_not() {
    // !true
    Expression node = AstTestFactory.prefixExpression(
        TokenType.BANG, AstTestFactory.booleanLiteral(true));
    expect(_analyze(node), same(_typeProvider.boolType));
    _listener.assertNoErrors();
  }

  void test_visitPrefixExpression_plusPlus() {
    // ++0
    PrefixExpression node = AstTestFactory.prefixExpression(
        TokenType.PLUS_PLUS, _resolvedInteger(0));
    MethodElement plusMethod = getMethod(_typeProvider.numType, "+");
    node.staticElement = plusMethod;
    expect(_analyze(node), same(_typeProvider.intType));
    _listener.assertNoErrors();
  }

  void test_visitPrefixExpression_tilde() {
    // ~0
    PrefixExpression node =
        AstTestFactory.prefixExpression(TokenType.TILDE, _resolvedInteger(0));
    MethodElement tildeMethod = getMethod(_typeProvider.intType, "~");
    node.staticElement = tildeMethod;
    expect(_analyze(node), _typeProvider.intType);
    _listener.assertNoErrors();
  }

  void test_visitPropertyAccess_static_getter() {
    DartType boolType = _typeProvider.boolType;
    PropertyAccessorElementImpl getter =
        ElementFactory.getterElement("b", false, boolType);
    PropertyAccess node =
        AstTestFactory.propertyAccess2(AstTestFactory.identifier3("a"), "b");
    node.propertyName.staticElement = getter;
    expect(_analyze(node), same(boolType));
    _listener.assertNoErrors();
  }

  void test_visitPropertyAccess_static_setter() {
    DartType boolType = _typeProvider.boolType;
    FieldElementImpl field =
        ElementFactory.fieldElement("b", false, false, false, boolType);
    PropertyAccessorElement setter = field.setter;
    PropertyAccess node =
        AstTestFactory.propertyAccess2(AstTestFactory.identifier3("a"), "b");
    node.propertyName.staticElement = setter;
    expect(_analyze(node), same(boolType));
    _listener.assertNoErrors();
  }

  void test_visitSimpleIdentifier_dynamic() {
    // "dynamic"
    SimpleIdentifier identifier = AstTestFactory.identifier3('dynamic');
    DynamicElementImpl element = DynamicElementImpl.instance;
    identifier.staticElement = element;
    identifier.staticType = _typeProvider.typeType;
    expect(_analyze(identifier), same(_typeProvider.typeType));
    _listener.assertNoErrors();
  }

  void test_visitSimpleStringLiteral() {
    // "a"
    Expression node = _resolvedString("a");
    expect(_analyze(node), same(_typeProvider.stringType));
    _listener.assertNoErrors();
  }

  void test_visitStringInterpolation() {
    // "a${'b'}c"
    Expression node = AstTestFactory.string([
      AstTestFactory.interpolationString("a", "a"),
      AstTestFactory.interpolationExpression(_resolvedString("b")),
      AstTestFactory.interpolationString("c", "c")
    ]);
    expect(_analyze(node), same(_typeProvider.stringType));
    _listener.assertNoErrors();
  }

  void test_visitSuperExpression() {
    // super
    InterfaceType superType = ElementFactory.classElement2("A").type;
    InterfaceType thisType = ElementFactory.classElement("B", superType).type;
    Expression node = AstTestFactory.superExpression();
    expect(_analyze(node, thisType), same(thisType));
    _listener.assertNoErrors();
  }

  void test_visitSymbolLiteral() {
    expect(_analyze(AstTestFactory.symbolLiteral(["a"])),
        same(_typeProvider.symbolType));
  }

  void test_visitThisExpression() {
    // this
    InterfaceType thisType =
        ElementFactory.classElement("B", ElementFactory.classElement2("A").type)
            .type;
    Expression node = AstTestFactory.thisExpression();
    expect(_analyze(node, thisType), same(thisType));
    _listener.assertNoErrors();
  }

  void test_visitThrowExpression_withoutValue() {
    // throw
    Expression node = AstTestFactory.throwExpression();
    expect(_analyze(node), same(_typeProvider.bottomType));
    _listener.assertNoErrors();
  }

  void test_visitThrowExpression_withValue() {
    // throw 0
    Expression node = AstTestFactory.throwExpression2(_resolvedInteger(0));
    expect(_analyze(node), same(_typeProvider.bottomType));
    _listener.assertNoErrors();
  }

  /**
   * Return the type associated with the given [node] after the static type
   * analyzer has computed a type for it. If [thisType] is provided, it is the
   * type of 'this'.
   */
  DartType _analyze(Expression node, [InterfaceType thisType]) {
    _analyzer.thisType = thisType;
    node.accept(_analyzer);
    return node.staticType;
  }

  /**
   * Return the type associated with the given parameter after the static type analyzer has computed
   * a type for it.
   *
   * @param node the parameter with which the type is associated
   * @return the type associated with the parameter
   */
  DartType _analyze5(FormalParameter node) {
    node.accept(_analyzer);
    return (node.identifier.staticElement as ParameterElement).type;
  }

  /**
   * Assert that the actual type is a function type with the expected characteristics.
   *
   * @param expectedReturnType the expected return type of the function
   * @param expectedNormalTypes the expected types of the normal parameters
   * @param expectedOptionalTypes the expected types of the optional parameters
   * @param expectedNamedTypes the expected types of the named parameters
   * @param actualType the type being tested
   */
  void _assertFunctionType(
      DartType expectedReturnType,
      List<DartType> expectedNormalTypes,
      List<DartType> expectedOptionalTypes,
      Map<String, DartType> expectedNamedTypes,
      DartType actualType) {
    FunctionType functionType = actualType;
    List<DartType> normalTypes = functionType.normalParameterTypes;
    if (expectedNormalTypes == null) {
      expect(normalTypes, hasLength(0));
    } else {
      int expectedCount = expectedNormalTypes.length;
      expect(normalTypes, hasLength(expectedCount));
      for (int i = 0; i < expectedCount; i++) {
        expect(normalTypes[i], same(expectedNormalTypes[i]));
      }
    }
    List<DartType> optionalTypes = functionType.optionalParameterTypes;
    if (expectedOptionalTypes == null) {
      expect(optionalTypes, hasLength(0));
    } else {
      int expectedCount = expectedOptionalTypes.length;
      expect(optionalTypes, hasLength(expectedCount));
      for (int i = 0; i < expectedCount; i++) {
        expect(optionalTypes[i], same(expectedOptionalTypes[i]));
      }
    }
    Map<String, DartType> namedTypes = functionType.namedParameterTypes;
    if (expectedNamedTypes == null) {
      expect(namedTypes, hasLength(0));
    } else {
      expect(namedTypes, hasLength(expectedNamedTypes.length));
      expectedNamedTypes.forEach((String name, DartType type) {
        expect(namedTypes[name], same(type));
      });
    }
    expect(functionType.returnType, equals(expectedReturnType));
  }

  void _assertType(
      InterfaceTypeImpl expectedType, InterfaceTypeImpl actualType) {
    expect(actualType.displayName, expectedType.displayName);
    expect(actualType.element, expectedType.element);
    List<DartType> expectedArguments = expectedType.typeArguments;
    int length = expectedArguments.length;
    List<DartType> actualArguments = actualType.typeArguments;
    expect(actualArguments, hasLength(length));
    for (int i = 0; i < length; i++) {
      _assertType2(expectedArguments[i], actualArguments[i]);
    }
  }

  void _assertType2(DartType expectedType, DartType actualType) {
    if (expectedType is InterfaceTypeImpl) {
      _assertType(expectedType, actualType as InterfaceTypeImpl);
    }
    // TODO(brianwilkerson) Compare other kinds of types then make this a shared
    // utility method.
  }

  /**
   * Create the analyzer used by the tests.
   */
  StaticTypeAnalyzer _createAnalyzer() {
    var context = TestAnalysisContext();
    var inheritance = new InheritanceManager3(context.typeSystem);
    Source source = new FileSource(getFile("/lib.dart"));
    CompilationUnitElementImpl definingCompilationUnit =
        new CompilationUnitElementImpl();
    definingCompilationUnit.librarySource =
        definingCompilationUnit.source = source;
    var featureSet = FeatureSet.forTesting();
    LibraryElementImpl definingLibrary = new LibraryElementImpl.forNode(
        context, null, null, featureSet.isEnabled(Feature.non_nullable));
    definingLibrary.definingCompilationUnit = definingCompilationUnit;
    _typeProvider = context.typeProvider;
    _visitor = new ResolverVisitor(
        inheritance, definingLibrary, source, _typeProvider, _listener,
        featureSet: featureSet, nameScope: new LibraryScope(definingLibrary));
    return _visitor.typeAnalyzer;
  }

  DartType _flatten(DartType type) => _typeSystem.flatten(type);

  /**
   * Return a boolean literal with the given [value] that has been resolved to
   * the correct type.
   */
  BooleanLiteral _resolvedBool(bool value) {
    BooleanLiteral literal = AstTestFactory.booleanLiteral(value);
    literal.staticType = _typeProvider.intType;
    return literal;
  }

  /**
   * Return an integer literal that has been resolved to the correct type.
   *
   * @param value the value of the literal
   * @return an integer literal that has been resolved to the correct type
   */
  DoubleLiteral _resolvedDouble(double value) {
    DoubleLiteral literal = AstTestFactory.doubleLiteral(value);
    literal.staticType = _typeProvider.doubleType;
    return literal;
  }

  /**
   * Create a function expression that has an element associated with it, where the element has an
   * incomplete type associated with it (just like the one
   * [ElementBuilder.visitFunctionExpression] would have built if we had
   * run it).
   *
   * @param parameters the parameters to the function
   * @param body the body of the function
   * @return a resolved function expression
   */
  FunctionExpression _resolvedFunctionExpression(
      FormalParameterList parameters, FunctionBody body) {
    List<ParameterElement> parameterElements = new List<ParameterElement>();
    for (FormalParameter parameter in parameters.parameters) {
      ParameterElementImpl element =
          new ParameterElementImpl.forNode(parameter.identifier);
      // ignore: deprecated_member_use_from_same_package
      element.parameterKind = parameter.kind;
      element.type = _typeProvider.dynamicType;
      parameter.identifier.staticElement = element;
      parameterElements.add(element);
    }
    FunctionExpression node =
        AstTestFactory.functionExpression2(parameters, body);
    FunctionElementImpl element = new FunctionElementImpl.forNode(null);
    element.parameters = parameterElements;
    element.type = new FunctionTypeImpl(element);
    (node as FunctionExpressionImpl).declaredElement = element;
    return node;
  }

  /**
   * Return an integer literal that has been resolved to the correct type.
   *
   * @param value the value of the literal
   * @return an integer literal that has been resolved to the correct type
   */
  IntegerLiteral _resolvedInteger(int value) {
    IntegerLiteral literal = AstTestFactory.integer(value);
    literal.staticType = _typeProvider.intType;
    return literal;
  }

  /**
   * Return a string literal that has been resolved to the correct type.
   *
   * @param value the value of the literal
   * @return a string literal that has been resolved to the correct type
   */
  SimpleStringLiteral _resolvedString(String value) {
    SimpleStringLiteral string = AstTestFactory.string2(value);
    string.staticType = _typeProvider.stringType;
    return string;
  }

  /**
   * Return a simple identifier that has been resolved to a variable element with the given type.
   *
   * @param type the type of the variable being represented
   * @param variableName the name of the variable
   * @return a simple identifier that has been resolved to a variable element with the given type
   */
  SimpleIdentifier _resolvedVariable(InterfaceType type, String variableName) {
    SimpleIdentifier identifier = AstTestFactory.identifier3(variableName);
    VariableElementImpl element =
        ElementFactory.localVariableElement(identifier);
    element.type = type;
    identifier.staticElement = element;
    identifier.staticType = type;
    return identifier;
  }

  /**
   * Set the type of the given parameter to the given type.
   *
   * @param parameter the parameter whose type is to be set
   * @param type the new type of the given parameter
   */
  void _setType(FormalParameter parameter, DartType type) {
    SimpleIdentifier identifier = parameter.identifier;
    Element element = identifier.staticElement;
    if (element is! ParameterElement) {
      element = new ParameterElementImpl.forNode(identifier);
      identifier.staticElement = element;
    }
    (element as ParameterElementImpl).type = type;
  }
}

/**
 * End-to-end tests of the static type analyzer that use the new driver and
 * enable the set-literals experiment.
 */
@reflectiveTest
class StaticTypeAnalyzerWithSetLiteralsTest
    extends StaticTypeAnalyzer2TestShared {
  test_emptySetLiteral_inferredFromLinkedHashSet() async {
    String code = r'''
import 'dart:collection';
LinkedHashSet<int> test4() => {};
''';
    await resolveTestUnit(code, noErrors: false);
    expectExpressionType('{}', 'Set<dynamic>');
    await assertErrorsInCode(code, [StrongModeCode.INVALID_CAST_LITERAL_SET]);
  }

  test_emptySetLiteral_initializer_typed_nested() async {
    String code = r'''
Set<Set<int>> ints = {{}};
''';
    await resolveTestUnit(code);
    expectExpressionType('{}', 'Set<int>');
    expectExpressionType('{{}}', 'Set<Set<int>>');
  }
}
