// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.type_builder_computer;

import 'package:kernel/ast.dart'
    show
        BottomType,
        Class,
        DartType,
        DartTypeVisitor,
        DynamicType,
        FunctionType,
        InterfaceType,
        InvalidType,
        Library,
        NamedType,
        TypeParameter,
        TypeParameterType,
        TypedefType,
        VoidType;

import '../kernel/kernel_builder.dart'
    show
        DynamicTypeBuilder,
        FunctionTypeBuilder,
        ClassBuilder,
        FormalParameterBuilder,
        NamedTypeBuilder,
        TypeVariableBuilder,
        LibraryBuilder,
        NullabilityBuilder,
        TypeBuilder,
        VoidTypeBuilder;

import '../loader.dart' show Loader;

import '../parser.dart' show FormalParameterKind;

class TypeBuilderComputer implements DartTypeVisitor<TypeBuilder> {
  final Loader loader;

  const TypeBuilderComputer(this.loader);

  TypeBuilder defaultDartType(DartType node) {
    throw "Unsupported";
  }

  TypeBuilder visitInvalidType(InvalidType node) {
    throw "Not implemented";
  }

  TypeBuilder visitDynamicType(DynamicType node) {
    // 'dynamic' is always nullable.
    return new NamedTypeBuilder(
        "dynamic", const NullabilityBuilder.nullable(), null)
      ..bind(
          new DynamicTypeBuilder(const DynamicType(), loader.coreLibrary, -1));
  }

  TypeBuilder visitVoidType(VoidType node) {
    // 'void' is always nullable.
    return new NamedTypeBuilder(
        "void", const NullabilityBuilder.nullable(), null)
      ..bind(new VoidTypeBuilder(const VoidType(), loader.coreLibrary, -1));
  }

  TypeBuilder visitBottomType(BottomType node) {
    throw "Not implemented";
  }

  TypeBuilder visitInterfaceType(InterfaceType node) {
    ClassBuilder cls =
        loader.computeClassBuilderFromTargetClass(node.classNode);
    List<TypeBuilder> arguments;
    List<DartType> kernelArguments = node.typeArguments;
    if (kernelArguments.isNotEmpty) {
      arguments = new List<TypeBuilder>(kernelArguments.length);
      for (int i = 0; i < kernelArguments.length; i++) {
        arguments[i] = kernelArguments[i].accept(this);
      }
    }
    // TODO(dmitryas): Compute the nullabilityBuilder field for the result from
    //  the nullability field of 'node'.
    return new NamedTypeBuilder(
        cls.name, const NullabilityBuilder.pendingImplementation(), arguments)
      ..bind(cls);
  }

  @override
  TypeBuilder visitFunctionType(FunctionType node) {
    TypeBuilder returnType = node.returnType.accept(this);
    // We could compute the type variables here. However, the current
    // implementation of [visitTypeParameterType] is sufficient.
    List<TypeVariableBuilder> typeVariables = null;
    List<DartType> positionalParameters = node.positionalParameters;
    List<NamedType> namedParameters = node.namedParameters;
    List<FormalParameterBuilder> formals = new List<FormalParameterBuilder>(
        positionalParameters.length + namedParameters.length);
    for (int i = 0; i < positionalParameters.length; i++) {
      TypeBuilder type = positionalParameters[i].accept(this);
      FormalParameterKind kind = FormalParameterKind.mandatory;
      if (i >= node.requiredParameterCount) {
        kind = FormalParameterKind.optionalPositional;
      }
      formals[i] = new FormalParameterBuilder(null, 0, type, null, null, -1)
        ..kind = kind;
    }
    for (int i = 0; i < namedParameters.length; i++) {
      NamedType parameter = namedParameters[i];
      TypeBuilder type = positionalParameters[i].accept(this);
      formals[i + positionalParameters.length] =
          new FormalParameterBuilder(null, 0, type, parameter.name, null, -1)
            ..kind = FormalParameterKind.optionalNamed;
    }

    return new FunctionTypeBuilder(returnType, typeVariables, formals);
  }

  TypeBuilder visitTypeParameterType(TypeParameterType node) {
    TypeParameter parameter = node.parameter;
    Class kernelClass = parameter.parent;
    Library kernelLibrary = kernelClass.enclosingLibrary;
    LibraryBuilder library = loader.builders[kernelLibrary.importUri];
    // TODO(dmitryas): Compute the nullabilityBuilder field for the result from
    //  the nullability field of 'node'.
    return new NamedTypeBuilder(
        parameter.name, const NullabilityBuilder.pendingImplementation(), null)
      ..bind(new TypeVariableBuilder.fromKernel(parameter, library));
  }

  TypeBuilder visitTypedefType(TypedefType node) {
    throw "Not implemented";
  }
}
