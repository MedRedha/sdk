// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/member.dart';
import 'package:analyzer/src/dart/element/type_algebra.dart';
import 'package:analyzer/src/dart/resolver/resolution_result.dart';
import 'package:analyzer/src/dart/resolver/scope.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/type_system.dart';

class ExtensionMemberResolver {
  final ResolverVisitor _resolver;

  ExtensionMemberResolver(this._resolver);

  DartType get _dynamicType => _typeProvider.dynamicType;

  ErrorReporter get _errorReporter => _resolver.errorReporter;

  Scope get _nameScope => _resolver.nameScope;

  TypeProvider get _typeProvider => _resolver.typeProvider;

  TypeSystem get _typeSystem => _resolver.typeSystem;

  /// Return the most specific extension in the current scope for this [type],
  /// that defines the member with the given [name].
  ///
  /// If no applicable extensions, return [ResolutionResult.none].
  ///
  /// If the match is ambiguous, report an error and return
  /// [ResolutionResult.ambiguous].
  ResolutionResult findExtension(
    DartType type,
    String name,
    Expression target,
  ) {
    var extensions = _getApplicable(type, name);

    if (extensions.isEmpty) {
      return ResolutionResult.none;
    }

    if (extensions.length == 1) {
      return extensions[0].asResolutionResult;
    }

    var extension = _chooseMostSpecific(extensions);
    if (extension != null) {
      return extension.asResolutionResult;
    }

    _errorReporter.reportErrorForNode(
      CompileTimeErrorCode.AMBIGUOUS_EXTENSION_MEMBER_ACCESS,
      target,
      [
        name,
        extensions[0].extension.name,
        extensions[1].extension.name,
      ],
    );
    return ResolutionResult.ambiguous;
  }

  /// Return the member with the [name] (without `=`).
  ///
  /// The [node] is fully resolved, and its type arguments are set.
  ExecutableElement getOverrideMember(
    ExtensionOverride node,
    String name, {
    bool setter = false,
  }) {
    ExtensionElement element = node.extensionName.staticElement;

    ExecutableElement member;
    if (setter) {
      member = element.getSetter(name);
    } else {
      member = element.getGetter(name) ?? element.getMethod(name);
    }

    if (member == null) {
      return null;
    }

    return ExecutableMember.from2(
      member,
      Substitution.fromPairs(
        element.typeParameters,
        node.typeArgumentTypes,
      ),
    );
  }

  /// Perform upward inference for the override.
  void resolveOverride(ExtensionOverride node) {
    var nodeImpl = node as ExtensionOverrideImpl;
    var element = node.staticElement;
    var typeParameters = element.typeParameters;

    if (!_isValidContext(node)) {
      _errorReporter.reportErrorForNode(
        CompileTimeErrorCode.EXTENSION_OVERRIDE_WITHOUT_ACCESS,
        node,
      );
      nodeImpl.staticType = _dynamicType;
    }

    var arguments = node.argumentList.arguments;
    if (arguments.length != 1) {
      _errorReporter.reportErrorForNode(
        CompileTimeErrorCode.INVALID_EXTENSION_ARGUMENT_COUNT,
        node.argumentList,
      );
      nodeImpl.typeArgumentTypes = _listOfDynamic(typeParameters);
      nodeImpl.extendedType = _dynamicType;
      return;
    }

    var receiverExpression = arguments[0];
    var receiverType = receiverExpression.staticType;

    var typeArgumentTypes = _inferTypeArguments(node, receiverType);
    nodeImpl.typeArgumentTypes = typeArgumentTypes;

    var substitution = Substitution.fromPairs(
      typeParameters,
      typeArgumentTypes,
    );

    nodeImpl.extendedType = substitution.substituteType(element.extendedType);

    _checkTypeArgumentsMatchingBounds(
      typeParameters,
      node.typeArguments,
      typeArgumentTypes,
      substitution,
    );

    if (!_typeSystem.isAssignableTo(receiverType, node.extendedType)) {
      _errorReporter.reportErrorForNode(
        CompileTimeErrorCode.EXTENSION_OVERRIDE_ARGUMENT_NOT_ASSIGNABLE,
        receiverExpression,
        [receiverType, node.extendedType],
      );
    }
  }

  /// Set the type context for the receiver of the override.
  ///
  /// The context of the invocation that is made through the override does
  /// not affect the type inference of the override and the receiver.
  void setOverrideReceiverContextType(ExtensionOverride node) {
    var element = node.staticElement;
    var typeParameters = element.typeParameters;

    var arguments = node.argumentList.arguments;
    if (arguments.length != 1) {
      return;
    }

    List<DartType> typeArgumentTypes;
    var typeArguments = node.typeArguments;
    if (typeArguments != null) {
      var arguments = typeArguments.arguments;
      if (arguments.length == typeParameters.length) {
        typeArgumentTypes = arguments.map((a) => a.type).toList();
      } else {
        typeArgumentTypes = _listOfDynamic(typeParameters);
      }
    } else {
      typeArgumentTypes = List.filled(
        typeParameters.length,
        UnknownInferredType.instance,
      );
    }

    var extendedForDownward = Substitution.fromPairs(
      typeParameters,
      typeArgumentTypes,
    ).substituteType(element.extendedType);

    var receiver = arguments[0];
    InferenceContext.setType(receiver, extendedForDownward);
  }

  void _checkTypeArgumentsMatchingBounds(
    List<TypeParameterElement> typeParameters,
    TypeArgumentList typeArgumentList,
    List<DartType> typeArgumentTypes,
    Substitution substitution,
  ) {
    if (typeArgumentList != null) {
      for (var i = 0; i < typeArgumentTypes.length; i++) {
        var argType = typeArgumentTypes[i];
        var boundType = typeParameters[i].bound;
        if (boundType != null) {
          boundType = substitution.substituteType(boundType);
          if (!_typeSystem.isSubtypeOf(argType, boundType)) {
            _errorReporter.reportTypeErrorForNode(
              CompileTimeErrorCode.TYPE_ARGUMENT_NOT_MATCHING_BOUNDS,
              typeArgumentList.arguments[i],
              [argType, boundType],
            );
          }
        }
      }
    }
  }

  /// Return the most specific extension or `null` if no single one can be
  /// identified.
  _InstantiatedExtension _chooseMostSpecific(
      List<_InstantiatedExtension> extensions) {
    for (var i = 0; i < extensions.length; i++) {
      var e1 = extensions[i];
      var isMoreSpecific = true;
      for (var j = 0; j < extensions.length; j++) {
        var e2 = extensions[j];
        if (i != j && !_isMoreSpecific(e1, e2)) {
          isMoreSpecific = false;
          break;
        }
      }
      if (isMoreSpecific) {
        return e1;
      }
    }

    // Otherwise fail.
    return null;
  }

  /// Return extensions for the [type] that match the given [name] in the
  /// current scope.
  List<_InstantiatedExtension> _getApplicable(DartType type, String name) {
    var candidates = _getExtensionsWithMember(name);

    var instantiatedExtensions = <_InstantiatedExtension>[];
    for (var candidate in candidates) {
      var typeParameters = candidate.extension.typeParameters;
      var inferrer = GenericInferrer(
        _typeProvider,
        _typeSystem,
        typeParameters,
      );
      inferrer.constrainArgument(
        type,
        candidate.extension.extendedType,
        'extendedType',
      );
      var typeArguments = inferrer.infer(typeParameters, failAtError: true);
      if (typeArguments == null) {
        continue;
      }

      var substitution = Substitution.fromPairs(
        typeParameters,
        typeArguments,
      );
      var extendedType = substitution.substituteType(
        candidate.extension.extendedType,
      );
      if (!_isSubtypeOf(type, extendedType)) {
        continue;
      }

      instantiatedExtensions.add(
        _InstantiatedExtension(candidate, substitution, extendedType),
      );
    }

    return instantiatedExtensions;
  }

  /// Return extensions from the current scope, that define a member with the
  /// given [name].
  List<_CandidateExtension> _getExtensionsWithMember(String name) {
    var candidates = <_CandidateExtension>[];

    /// Add the given [extension] to the list of [candidates] if it defined a
    /// member whose name matches the target [name].
    void checkExtension(ExtensionElement extension) {
      for (var field in extension.fields) {
        if (field.name == name) {
          candidates.add(
            _CandidateExtension(extension, field: field),
          );
          return;
        }
      }
      for (var method in extension.methods) {
        if (method.name == name) {
          candidates.add(
            _CandidateExtension(extension, method: method),
          );
          return;
        }
      }
    }

    for (var extension in _nameScope.extensions) {
      checkExtension(extension);
    }
    return candidates;
  }

  /// Given the generic [element] element, either return types specified
  /// explicitly in [typeArguments], or infer type arguments from the given
  /// [receiverType].
  ///
  /// If the number of explicit type arguments is different than the number
  /// of extension's type parameters, or inference fails, return `dynamic`
  /// for all type parameters.
  List<DartType> _inferTypeArguments(
    ExtensionOverride node,
    DartType receiverType,
  ) {
    var element = node.staticElement;
    var typeParameters = element.typeParameters;
    if (typeParameters.isEmpty) {
      return const <DartType>[];
    }

    var typeArguments = node.typeArguments;
    if (typeArguments != null) {
      var arguments = typeArguments.arguments;
      if (arguments.length == typeParameters.length) {
        return arguments.map((a) => a.type).toList();
      } else {
        // TODO(scheglov) Report an error.
        return _listOfDynamic(typeParameters);
      }
    } else {
      var inferrer = GenericInferrer(
        _typeProvider,
        _typeSystem,
        typeParameters,
      );
      inferrer.constrainArgument(
        receiverType,
        element.extendedType,
        'extendedType',
      );
      return inferrer.infer(
        typeParameters,
        errorReporter: _errorReporter,
        errorNode: node.extensionName,
      );
    }
  }

  /// Instantiate the extended type of the [extension] to the bounds of the
  /// type formals of the extension.
  DartType _instantiateToBounds(ExtensionElement extension) {
    var typeParameters = extension.typeParameters;
    return Substitution.fromPairs(
      typeParameters,
      _typeSystem.instantiateTypeFormalsToBounds(typeParameters),
    ).substituteType(extension.extendedType);
  }

  /// Return `true` is [e1] is more specific than [e2].
  bool _isMoreSpecific(_InstantiatedExtension e1, _InstantiatedExtension e2) {
    // 1. The latter extension is declared in a platform library, and the
    //    former extension is not.
    // 2. They are both declared in platform libraries, or both declared in
    //    non-platform libraries.
    var e1_isInSdk = e1.extension.library.isInSdk;
    var e2_isInSdk = e2.extension.library.isInSdk;
    if (e1_isInSdk && !e2_isInSdk) {
      return false;
    } else if (!e1_isInSdk && e2_isInSdk) {
      return true;
    }

    var extendedType1 = e1.extendedType;
    var extendedType2 = e2.extendedType;

    // 3. The instantiated type (the type after applying type inference from
    //    the receiver) of T1 is a subtype of the instantiated type of T2,
    //    and either...
    if (!_isSubtypeOf(extendedType1, extendedType2)) {
      return false;
    }

    // 4. ...not vice versa, or...
    if (!_isSubtypeOf(extendedType2, extendedType1)) {
      return true;
    }

    // 5. ...the instantiate-to-bounds type of T1 is a subtype of the
    //    instantiate-to-bounds type of T2 and not vice versa.
    // TODO(scheglov) store instantiated types
    var extendedTypeBound1 = _instantiateToBounds(e1.extension);
    var extendedTypeBound2 = _instantiateToBounds(e2.extension);
    return _isSubtypeOf(extendedTypeBound1, extendedTypeBound2) &&
        !_isSubtypeOf(extendedTypeBound2, extendedTypeBound1);
  }

  /// Ask the type system for a subtype check.
  bool _isSubtypeOf(DartType type1, DartType type2) =>
      _typeSystem.isSubtypeOf(type1, type2);

  List<DartType> _listOfDynamic(List<TypeParameterElement> parameters) {
    return List<DartType>.filled(parameters.length, _dynamicType);
  }

  /// Return `true` if the extension override [node] is being used as a target
  /// of an operation that might be accessing an instance member.
  static bool _isValidContext(ExtensionOverride node) {
    AstNode parent = node.parent;
    return parent is BinaryExpression && parent.leftOperand == node ||
        parent is FunctionExpressionInvocation && parent.function == node ||
        parent is IndexExpression && parent.target == node ||
        parent is MethodInvocation && parent.target == node ||
        parent is PrefixExpression ||
        parent is PropertyAccess && parent.target == node;
  }
}

class _CandidateExtension {
  final ExtensionElement extension;
  final FieldElement field;
  final MethodElement method;

  _CandidateExtension(this.extension, {this.field, this.method})
      : assert(field != null || method != null);
}

class _InstantiatedExtension {
  final _CandidateExtension candidate;
  final MapSubstitution substitution;
  final DartType extendedType;

  _InstantiatedExtension(this.candidate, this.substitution, this.extendedType);

  ResolutionResult get asResolutionResult {
    return ResolutionResult(function: method, property: field);
  }

  ExtensionElement get extension => candidate.extension;

  FieldElement get field {
    if (candidate.field == null) {
      return null;
    }
    return FieldMember.from2(candidate.field, substitution);
  }

  MethodElement get method {
    if (candidate.method == null) {
      return null;
    }
    return MethodMember.from2(candidate.method, substitution);
  }
}
