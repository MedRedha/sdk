// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:core' hide MapEntry;
import 'package:kernel/ast.dart';
import '../kernel/body_builder.dart';
import '../builder/builder.dart';
import '../problems.dart';

/// Represents the nullability modifiers encountered while parsing the types.
///
/// The syntactic nullability needs to be interpreted, that is, built, into the
/// semantic nullability used on [DartType]s of Kernel.
enum SyntacticNullability {
  /// Used when the type is declared with '?' suffix after it.
  nullable,

  /// Used when the type is declared in an opted-out library.
  legacy,

  /// Used when the type is declared without any nullability suffixes.
  omitted,
}

class NullabilityBuilder {
  final SyntacticNullability _syntacticNullability;

  const NullabilityBuilder.nullable()
      : _syntacticNullability = SyntacticNullability.nullable;

  const NullabilityBuilder.legacy()
      : _syntacticNullability = SyntacticNullability.legacy;

  const NullabilityBuilder.omitted()
      : _syntacticNullability = SyntacticNullability.omitted;

  /// Used temporarily in the places that need proper handling of NNBD features.
  ///
  /// Over time the uses of [NullabilityBuilder.pendingImplementation] should be
  /// eliminated, and the constructor should be eventually removed.  Currently,
  /// it redirects to [NullabilityBuilder.legacy] as a conservative safety
  /// measure for the pre-NNBD code and as a visible reminder of the feature
  /// implementation being in progress in the NNBD code.
  // TODO(38286): Remove this constructor.
  const NullabilityBuilder.pendingImplementation() : this.legacy();

  Nullability build(LibraryBuilder libraryBuilder, {Nullability ifOmitted}) {
    // TODO(dmitryas): Ensure that either ifOmitted is set or libraryBuilder is
    // provided;
    //assert(libraryBuilder != null || ifOmitted != null);
    ifOmitted ??= (libraryBuilder == null ? Nullability.legacy : null);

    ifOmitted ??= libraryBuilder.isNonNullableByDefault
        ? Nullability.nonNullable
        : Nullability.legacy;
    switch (_syntacticNullability) {
      case SyntacticNullability.legacy:
        return Nullability.legacy;
      case SyntacticNullability.nullable:
        return Nullability.nullable;
      case SyntacticNullability.omitted:
        return ifOmitted;
    }
    return unhandled("$_syntacticNullability", "buildNullability",
        TreeNode.noOffset, noLocation);
  }

  void writeNullabilityOn(StringBuffer sb) {
    switch (_syntacticNullability) {
      case SyntacticNullability.legacy:
        sb.write("*");
        return;
      case SyntacticNullability.nullable:
        sb.write("?");
        return;
      case SyntacticNullability.omitted:
        // Do nothing.
        return;
    }
    unhandled("$_syntacticNullability", "writeNullabilityOn", TreeNode.noOffset,
        noLocation);
  }
}
