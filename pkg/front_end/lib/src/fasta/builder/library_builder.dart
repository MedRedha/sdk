// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.library_builder;

import 'package:kernel/ast.dart' show Library;

import '../combinator.dart' show Combinator;

import '../problems.dart' show internalProblem, unsupported;

import '../export.dart' show Export;

import '../loader.dart' show Loader;

import '../messages.dart'
    show
        FormattedMessage,
        LocatedMessage,
        Message,
        templateInternalProblemConstructorNotFound,
        templateInternalProblemNotFoundIn,
        templateInternalProblemPrivateConstructorAccess;

import '../severity.dart' show Severity;

import 'builder.dart'
    show
        ClassBuilder,
        Builder,
        FieldBuilder,
        ModifierBuilder,
        NameIterator,
        NullabilityBuilder,
        PrefixBuilder,
        Scope,
        ScopeBuilder,
        TypeBuilder;

import 'declaration.dart';

abstract class LibraryBuilder extends ModifierBuilder {
  final Scope scope;

  final Scope exportScope;

  final ScopeBuilder scopeBuilder;

  final ScopeBuilder exportScopeBuilder;

  final List<Export> exporters = <Export>[];

  LibraryBuilder partOfLibrary;

  bool mayImplementRestrictedTypes = false;

  LibraryBuilder(Uri fileUri, this.scope, this.exportScope)
      : scopeBuilder = new ScopeBuilder(scope),
        exportScopeBuilder = new ScopeBuilder(exportScope),
        super(null, -1, fileUri);

  bool get isSynthetic => false;

  // Deliberately unrelated return type to statically detect more accidental
  // use until Builder.target is fully retired.
  UnrelatedTarget get target => unsupported(
      "LibraryBuilder.target is deprecated. "
      "Use LibraryBuilder.library instead.",
      charOffset,
      fileUri);

  /// Set the langauge version to a specific non-null major and minor version.
  ///
  /// If the language version has previously been explicitly set set (i.e. with
  /// [explicit] set to true), any subsequent call (explicit or not) should be
  /// ignored.
  /// Multiple calls with [explicit] set to false should be allowed though.
  ///
  /// The main idea is that the .packages file specifies a default language
  /// version, but that the library can have source code that specifies another
  /// one which should be supported, but specifying several in code should not
  /// change anything.
  ///
  /// [offset] and [length] refers to the offset and length of the source code
  /// specifying the language version.
  void setLanguageVersion(int major, int minor,
      {int offset: 0, int length, bool explicit});

  @override
  Builder get parent => null;

  bool get isPart => false;

  @override
  String get debugName => "LibraryBuilder";

  Loader get loader;

  @override
  int get modifiers => 0;

  /// Returns the [Library] built by this builder.
  Library get library;

  Uri get uri;

  Iterator<Builder> get iterator {
    return new LibraryLocalDeclarationIterator(this);
  }

  NameIterator get nameIterator {
    return new LibraryLocalDeclarationNameIterator(this);
  }

  Builder addBuilder(String name, Builder declaration, int charOffset);

  void addExporter(
      LibraryBuilder exporter, List<Combinator> combinators, int charOffset) {
    exporters.add(new Export(exporter, this, combinators, charOffset));
  }

  /// Add a problem with a severity determined by the severity of the message.
  ///
  /// If [fileUri] is null, it defaults to `this.fileUri`.
  ///
  /// See `Loader.addMessage` for an explanation of the
  /// arguments passed to this method.
  FormattedMessage addProblem(
      Message message, int charOffset, int length, Uri fileUri,
      {bool wasHandled: false,
      List<LocatedMessage> context,
      Severity severity,
      bool problemOnLibrary: false}) {
    fileUri ??= this.fileUri;

    return loader.addProblem(message, charOffset, length, fileUri,
        wasHandled: wasHandled,
        context: context,
        severity: severity,
        problemOnLibrary: true);
  }

  /// Returns true if the export scope was modified.
  bool addToExportScope(String name, Builder member, [int charOffset = -1]) {
    if (name.startsWith("_")) return false;
    if (member is PrefixBuilder) return false;
    Map<String, Builder> map =
        member.isSetter ? exportScope.setters : exportScope.local;
    Builder existing = map[name];
    if (existing == member) return false;
    if (existing != null) {
      Builder result = computeAmbiguousDeclaration(
          name, existing, member, charOffset,
          isExport: true);
      map[name] = result;
      return result != existing;
    } else {
      map[name] = member;
    }
    return true;
  }

  void addToScope(String name, Builder member, int charOffset, bool isImport);

  Builder computeAmbiguousDeclaration(
      String name, Builder declaration, Builder other, int charOffset,
      {bool isExport: false, bool isImport: false});

  int finishDeferredLoadTearoffs() => 0;

  int finishForwarders() => 0;

  int finishNativeMethods() => 0;

  int finishPatchMethods() => 0;

  /// Looks up [constructorName] in the class named [className].
  ///
  /// The class is looked up in this library's export scope unless
  /// [bypassLibraryPrivacy] is true, in which case it is looked up in the
  /// library scope of this library.
  ///
  /// It is an error if no such class is found, or if the class doesn't have a
  /// matching constructor (or factory).
  ///
  /// If [constructorName] is null or the empty string, it's assumed to be an
  /// unnamed constructor. it's an error if [constructorName] starts with
  /// `"_"`, and [bypassLibraryPrivacy] is false.
  Builder getConstructor(String className,
      {String constructorName, bool bypassLibraryPrivacy: false}) {
    constructorName ??= "";
    if (constructorName.startsWith("_") && !bypassLibraryPrivacy) {
      return internalProblem(
          templateInternalProblemPrivateConstructorAccess
              .withArguments(constructorName),
          -1,
          null);
    }
    Builder cls = (bypassLibraryPrivacy ? scope : exportScope)
        .lookup(className, -1, null);
    if (cls is ClassBuilder) {
      // TODO(ahe): This code is similar to code in `endNewExpression` in
      // `body_builder.dart`, try to share it.
      Builder constructor =
          cls.findConstructorOrFactory(constructorName, -1, null, this);
      if (constructor == null) {
        // Fall-through to internal error below.
      } else if (constructor.isConstructor) {
        if (!cls.isAbstract) {
          return constructor;
        }
      } else if (constructor.isFactory) {
        return constructor;
      }
    }
    throw internalProblem(
        templateInternalProblemConstructorNotFound.withArguments(
            "$className.$constructorName", uri),
        -1,
        null);
  }

  int finishTypeVariables(ClassBuilder object, TypeBuilder dynamicType) => 0;

  /// This method instantiates type parameters to their bounds in some cases
  /// where they were omitted by the programmer and not provided by the type
  /// inference.  The method returns the number of distinct type variables
  /// that were instantiated in this library.
  int computeDefaultTypes(TypeBuilder dynamicType, TypeBuilder bottomType,
      ClassBuilder objectClass) {
    return 0;
  }

  void becomeCoreLibrary() {
    if (scope.local["dynamic"] == null) {
      addSyntheticDeclarationOfDynamic();
    }
  }

  void addSyntheticDeclarationOfDynamic();

  /// Lookups the member [name] declared in this library.
  ///
  /// If [required] is `true` and no member is found an internal problem is
  /// reported.
  Builder lookupLocalMember(String name, {bool required: false}) {
    Builder builder = scope.local[name];
    if (required && builder == null) {
      internalProblem(
          templateInternalProblemNotFoundIn.withArguments(
              name, fullNameForErrors),
          -1,
          null);
    }
    return builder;
  }

  Builder lookup(String name, int charOffset, Uri fileUri) {
    return scope.lookup(name, charOffset, fileUri);
  }

  /// If this is a patch library, apply its patches to [origin].
  void applyPatches() {
    if (!isPatch) return;
    unsupported("${runtimeType}.applyPatches", -1, fileUri);
  }

  void recordAccess(int charOffset, int length, Uri fileUri) {}

  void buildOutlineExpressions() {}

  List<FieldBuilder> takeImplicitlyTypedFields() => null;

  // TODO(38287): Compute the predicate using the library version instead.
  bool get isNonNullableByDefault => loader.target.enableNonNullable;

  NullabilityBuilder computeNullabilityFromToken(bool markedAsNullable) {
    if (!isNonNullableByDefault) {
      return const NullabilityBuilder.legacy();
    }
    if (markedAsNullable) {
      return const NullabilityBuilder.nullable();
    }
    return const NullabilityBuilder.omitted();
  }
}

class LibraryLocalDeclarationIterator implements Iterator<Builder> {
  final LibraryBuilder library;
  final Iterator<Builder> iterator;

  LibraryLocalDeclarationIterator(this.library)
      : iterator = library.scope.iterator;

  Builder get current => iterator.current;

  bool moveNext() {
    while (iterator.moveNext()) {
      if (current.parent == library) return true;
    }
    return false;
  }
}

class LibraryLocalDeclarationNameIterator implements NameIterator {
  final LibraryBuilder library;
  final NameIterator iterator;

  LibraryLocalDeclarationNameIterator(this.library)
      : iterator = library.scope.nameIterator;

  Builder get current => iterator.current;

  String get name => iterator.name;

  bool moveNext() {
    while (iterator.moveNext()) {
      if (current.parent == library) return true;
    }
    return false;
  }
}
