// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_COMPILER_AOT_PRECOMPILER_H_
#define RUNTIME_VM_COMPILER_AOT_PRECOMPILER_H_

#include "vm/allocation.h"
#include "vm/compiler/assembler/assembler.h"
#include "vm/hash_map.h"
#include "vm/hash_table.h"
#include "vm/object.h"
#include "vm/symbols.h"

namespace dart {

// Forward declarations.
class Class;
class Error;
class Field;
class Function;
class GrowableObjectArray;
class RawError;
class SequenceNode;
class String;
class ParsedJSONObject;
class ParsedJSONArray;
class Precompiler;
class FlowGraph;
class PrecompilerEntryPointsPrinter;

class SymbolKeyValueTrait {
 public:
  // Typedefs needed for the DirectChainedHashMap template.
  typedef const String* Key;
  typedef const String* Value;
  typedef const String* Pair;

  static Key KeyOf(Pair kv) { return kv; }

  static Value ValueOf(Pair kv) { return kv; }

  static inline intptr_t Hashcode(Key key) { return key->Hash(); }

  static inline bool IsKeyEqual(Pair pair, Key key) {
    return pair->raw() == key->raw();
  }
};

typedef DirectChainedHashMap<SymbolKeyValueTrait> SymbolSet;

class UnlinkedCallKeyValueTrait {
 public:
  // Typedefs needed for the DirectChainedHashMap template.
  typedef const UnlinkedCall* Key;
  typedef const UnlinkedCall* Value;
  typedef const UnlinkedCall* Pair;

  static Key KeyOf(Pair kv) { return kv; }

  static Value ValueOf(Pair kv) { return kv; }

  static inline intptr_t Hashcode(Key key) {
    return String::Handle(key->target_name()).Hash();
  }

  static inline bool IsKeyEqual(Pair pair, Key key) {
    return (pair->target_name() == key->target_name()) &&
           (pair->args_descriptor() == key->args_descriptor());
  }
};

typedef DirectChainedHashMap<UnlinkedCallKeyValueTrait> UnlinkedCallSet;

// Traits for the HashTable template.
struct FunctionKeyTraits {
  static uint32_t Hash(const Object& key) { return Function::Cast(key).Hash(); }
  static const char* Name() { return "FunctionKeyTraits"; }
  static bool IsMatch(const Object& x, const Object& y) {
    return x.raw() == y.raw();
  }
  static bool ReportStats() { return false; }
};

typedef UnorderedHashSet<FunctionKeyTraits> FunctionSet;

class FieldKeyValueTrait {
 public:
  // Typedefs needed for the DirectChainedHashMap template.
  typedef const Field* Key;
  typedef const Field* Value;
  typedef const Field* Pair;

  static Key KeyOf(Pair kv) { return kv; }

  static Value ValueOf(Pair kv) { return kv; }

  static inline intptr_t Hashcode(Key key) {
    // We are using pointer hash for objects originating from Kernel because
    // Fasta currently does not assign any position information to them.
    if (key->kernel_offset() > 0) {
      return key->kernel_offset();
    } else {
      return key->token_pos().value();
    }
  }

  static inline bool IsKeyEqual(Pair pair, Key key) {
    return pair->raw() == key->raw();
  }
};

typedef DirectChainedHashMap<FieldKeyValueTrait> FieldSet;

class ClassKeyValueTrait {
 public:
  // Typedefs needed for the DirectChainedHashMap template.
  typedef const Class* Key;
  typedef const Class* Value;
  typedef const Class* Pair;

  static Key KeyOf(Pair kv) { return kv; }

  static Value ValueOf(Pair kv) { return kv; }

  static inline intptr_t Hashcode(Key key) { return key->token_pos().value(); }

  static inline bool IsKeyEqual(Pair pair, Key key) {
    return pair->raw() == key->raw();
  }
};

typedef DirectChainedHashMap<ClassKeyValueTrait> ClassSet;

class AbstractTypeKeyValueTrait {
 public:
  // Typedefs needed for the DirectChainedHashMap template.
  typedef const AbstractType* Key;
  typedef const AbstractType* Value;
  typedef const AbstractType* Pair;

  static Key KeyOf(Pair kv) { return kv; }

  static Value ValueOf(Pair kv) { return kv; }

  static inline intptr_t Hashcode(Key key) { return key->Hash(); }

  static inline bool IsKeyEqual(Pair pair, Key key) {
    return pair->raw() == key->raw();
  }
};

typedef DirectChainedHashMap<AbstractTypeKeyValueTrait> AbstractTypeSet;

class TypeArgumentsKeyValueTrait {
 public:
  // Typedefs needed for the DirectChainedHashMap template.
  typedef const TypeArguments* Key;
  typedef const TypeArguments* Value;
  typedef const TypeArguments* Pair;

  static Key KeyOf(Pair kv) { return kv; }

  static Value ValueOf(Pair kv) { return kv; }

  static inline intptr_t Hashcode(Key key) { return key->Hash(); }

  static inline bool IsKeyEqual(Pair pair, Key key) {
    return pair->raw() == key->raw();
  }
};

typedef DirectChainedHashMap<TypeArgumentsKeyValueTrait> TypeArgumentsSet;

class InstanceKeyValueTrait {
 public:
  // Typedefs needed for the DirectChainedHashMap template.
  typedef const Instance* Key;
  typedef const Instance* Value;
  typedef const Instance* Pair;

  static Key KeyOf(Pair kv) { return kv; }

  static Value ValueOf(Pair kv) { return kv; }

  static inline intptr_t Hashcode(Key key) { return key->GetClassId(); }

  static inline bool IsKeyEqual(Pair pair, Key key) {
    return pair->raw() == key->raw();
  }
};

typedef DirectChainedHashMap<InstanceKeyValueTrait> InstanceSet;

class Precompiler : public ValueObject {
 public:
  static RawError* CompileAll();

  static RawError* CompileFunction(Precompiler* precompiler,
                                   Thread* thread,
                                   Zone* zone,
                                   const Function& function);

  static RawFunction* CompileStaticInitializer(const Field& field);

  // Returns true if get:runtimeType is not overloaded by any class.
  bool get_runtime_type_is_unique() const {
    return get_runtime_type_is_unique_;
  }

  compiler::ObjectPoolBuilder* global_object_pool_builder() {
    ASSERT(FLAG_use_bare_instructions);
    return &global_object_pool_builder_;
  }

  void* il_serialization_stream() const { return il_serialization_stream_; }

  static Precompiler* Instance() { return singleton_; }

 private:
  static Precompiler* singleton_;

  explicit Precompiler(Thread* thread);
  ~Precompiler();

  void DoCompileAll();
  void AddRoots();
  void AddAnnotatedRoots();
  void Iterate();

  void AddType(const AbstractType& type);
  void AddTypesOf(const Class& cls);
  void AddTypesOf(const Function& function);
  void AddTypeArguments(const TypeArguments& args);
  void AddCalleesOf(const Function& function, intptr_t gop_offset);
  void AddCalleesOfHelper(const Object& entry,
                          String* temp_selector,
                          Class* temp_cls);
  void AddConstObject(const class Instance& instance);
  void AddClosureCall(const Array& arguments_descriptor);
  void AddField(const Field& field);
  void AddFunction(const Function& function);
  void AddInstantiatedClass(const Class& cls);
  void AddSelector(const String& selector);
  bool IsSent(const String& selector);

  void ProcessFunction(const Function& function);
  void CheckForNewDynamicFunctions();
  void CollectCallbackFields();

  void AttachOptimizedTypeTestingStub();

  void TraceForRetainedFunctions();
  void DropFunctions();
  void DropFields();
  void TraceTypesFromRetainedClasses();
  void DropTypes();
  void DropTypeArguments();
  void DropMetadata();
  void DropLibraryEntries();
  void DropClasses();
  void DropLibraries();

  // Remove the indirection of the CallStaticFunction stub from all static call
  // sites now that Code is available for all call targets. Allows for dropping
  // the static call table from each Code object.
  void BindStaticCalls();
  // Deduplicate the UnlinkedCall objects in all ObjectPools to reduce snapshot
  // size.
  void DedupUnlinkedCalls();

  void Obfuscate();

  void CollectDynamicFunctionNames();

  void PrecompileStaticInitializers();
  void PrecompileConstructors();

  void FinalizeAllClasses();

  void set_il_serialization_stream(void* file) {
    il_serialization_stream_ = file;
  }

  Thread* thread() const { return thread_; }
  Zone* zone() const { return zone_; }
  Isolate* isolate() const { return isolate_; }

  Thread* thread_;
  Zone* zone_;
  Isolate* isolate_;

  bool changed_;
  bool retain_root_library_caches_;
  intptr_t function_count_;
  intptr_t class_count_;
  intptr_t selector_count_;
  intptr_t dropped_function_count_;
  intptr_t dropped_field_count_;
  intptr_t dropped_class_count_;
  intptr_t dropped_typearg_count_;
  intptr_t dropped_type_count_;
  intptr_t dropped_library_count_;

  compiler::ObjectPoolBuilder global_object_pool_builder_;
  GrowableObjectArray& libraries_;
  const GrowableObjectArray& pending_functions_;
  SymbolSet sent_selectors_;
  FunctionSet enqueued_functions_;
  FieldSet fields_to_retain_;
  FunctionSet functions_to_retain_;
  ClassSet classes_to_retain_;
  TypeArgumentsSet typeargs_to_retain_;
  AbstractTypeSet types_to_retain_;
  InstanceSet consts_to_retain_;
  Error& error_;

  bool get_runtime_type_is_unique_;
  void* il_serialization_stream_;
};

class FunctionsTraits {
 public:
  static const char* Name() { return "FunctionsTraits"; }
  static bool ReportStats() { return false; }

  static bool IsMatch(const Object& a, const Object& b) {
    Zone* zone = Thread::Current()->zone();
    String& a_s = String::Handle(zone);
    String& b_s = String::Handle(zone);
    a_s = a.IsFunction() ? Function::Cast(a).name() : String::Cast(a).raw();
    b_s = b.IsFunction() ? Function::Cast(b).name() : String::Cast(b).raw();
    ASSERT(a_s.IsSymbol() && b_s.IsSymbol());
    return a_s.raw() == b_s.raw();
  }
  static uword Hash(const Object& obj) {
    if (obj.IsFunction()) {
      return String::Handle(Function::Cast(obj).name()).Hash();
    } else {
      ASSERT(String::Cast(obj).IsSymbol());
      return String::Cast(obj).Hash();
    }
  }
  static RawObject* NewKey(const Function& function) { return function.raw(); }
};

typedef UnorderedHashSet<FunctionsTraits> UniqueFunctionsSet;

#if defined(DART_PRECOMPILER) && !defined(TARGET_ARCH_DBC) &&                  \
    !defined(TARGET_ARCH_IA32)
// ObfuscationMap maps Strings to Strings.
class ObfuscationMapTraits {
 public:
  static const char* Name() { return "ObfuscationMapTraits"; }
  static bool ReportStats() { return false; }

  // Only for non-descriptor lookup and table expansion.
  static bool IsMatch(const Object& a, const Object& b) {
    return a.raw() == b.raw();
  }

  static uword Hash(const Object& key) { return String::Cast(key).Hash(); }
};
typedef UnorderedHashMap<ObfuscationMapTraits> ObfuscationMap;

// Obfuscator is a helper class that is responsible for obfuscating
// identifiers when obfuscation is enabled via isolate flags.
//
class Obfuscator : public ValueObject {
 public:
  // Create Obfuscator for the given |thread|, with the given |private_key|.
  // This private key will be used when obfuscating private identifiers
  // (those starting with '_').
  //
  // If obfuscation is enabled constructor will restore obfuscation state
  // from ObjectStore::obfuscation_map()
  //
  // Note: only a single instance of obfuscator should exist at any given
  // moment on the stack because Obfuscator takes ownership of obfuscation
  // map. ObjectStore::obfuscation_map() will only be updated when
  // this Obfuscator is destroyed.
  Obfuscator(Thread* thread, const String& private_key);

  // If obfuscation is enabled - commit accumulated renames to ObjectStore.
  ~Obfuscator();

  // If obfuscation is enabled return a rename for the given |name|,
  // otherwise it is a no-op.
  //
  // Note: |name| *must* be a Symbol.
  //
  // By default renames are aware about mangling scheme used for private names:
  // '_ident@key' and '_ident' will be renamed consistently. If such
  // interpretation is undesirable e.g. it is known that name does not
  // contain a private key suffix or name is not a Dart identifier at all
  // then this function should be called with |atomic| set to true.
  //
  // Note: if obfuscator was created with private_key then all
  // renames *must* be atomic.
  //
  // This method is guaranteed to return the same value for the same
  // input and it always preserves leading '_' even for atomic renames.
  RawString* Rename(const String& name, bool atomic = false) {
    if (state_ == NULL) {
      return name.raw();
    }

    return state_->RenameImpl(name, atomic);
  }

  // Given a constant |instance| of dart:internal.Symbol rename it by updating
  // its |name| field.
  static void ObfuscateSymbolInstance(Thread* thread, const Instance& instance);

  // Given a sequence of obfuscated identifiers deobfuscate it.
  //
  // This method is only used by parser when resolving conditional imports
  // because it needs deobfuscated names to lookup in the environment.
  //
  // Note: this operation is not optimized because is very infrequent.
  static void Deobfuscate(Thread* thread, const GrowableObjectArray& pieces);

  // Serialize renaming map as a malloced array of strings.
  static const char** SerializeMap(Thread* thread);

  void PreventRenaming(const char* name);
  void PreventRenaming(const String& name) { state_->PreventRenaming(name); }

 private:
  // Populate renaming map with names that should have identity renaming.
  // (or in other words: with those names that should not be renamed).
  void InitializeRenamingMap(Isolate* isolate);

  // ObjectStore::obfuscation_map() is an Array with two elements:
  // first element is the last used rename and the second element is
  // renaming map.
  static const intptr_t kSavedStateNameIndex = 0;
  static const intptr_t kSavedStateRenamesIndex = 1;
  static const intptr_t kSavedStateSize = 2;

  static RawArray* GetRenamesFromSavedState(const Array& saved_state) {
    Array& renames = Array::Handle();
    renames ^= saved_state.At(kSavedStateRenamesIndex);
    return renames.raw();
  }

  static RawString* GetNameFromSavedState(const Array& saved_state) {
    String& name = String::Handle();
    name ^= saved_state.At(kSavedStateNameIndex);
    return name.raw();
  }

  class ObfuscationState : public ZoneAllocated {
   public:
    ObfuscationState(Thread* thread,
                     const Array& saved_state,
                     const String& private_key)
        : thread_(thread),
          saved_state_(saved_state),
          renames_(GetRenamesFromSavedState(saved_state)),
          private_key_(private_key),
          string_(String::Handle(thread->zone())),
          renamed_(String::Handle(thread->zone())) {
      memset(name_, 0, sizeof(name_));

      // Restore last used rename.
      string_ = GetNameFromSavedState(saved_state);
      if (!string_.IsNull()) {
        string_.ToUTF8(reinterpret_cast<uint8_t*>(name_), sizeof(name_));
      }
    }

    void SaveState();

    // Return a rename for the given |name|.
    //
    // Note: |name| *must* be a Symbol.
    //
    // By default renames are aware about mangling scheme used for private
    // names: '_ident@key' and '_ident' will be renamed consistently. If such
    // interpretation is undesirable e.g. it is known that name does not
    // contain a private key suffix or name is not a Dart identifier at all
    // then this function should be called with |atomic| set to true.
    //
    // Note: if obfuscator was created with private_key then all
    // renames *must* be atomic.
    //
    // This method is guaranteed to return the same value for the same
    // input.
    RawString* RenameImpl(const String& name, bool atomic);

    // Register an identity (name -> name) mapping in the renaming map.
    //
    // This essentially prevents the given name from being renamed.
    void PreventRenaming(const String& name);
    void PreventRenaming(const char* name);

   private:
    // Build rename for the given |name|.
    //
    // For atomic renames BuildRename just returns the next
    // available rename generated by AtomicRename(...).
    //
    // For non-atomic renames BuildRename ensures that private mangled
    // identifiers (_ident@key) are renamed consistently with non-mangled
    // counterparts (_ident).
    RawString* BuildRename(const String& name, bool atomic);

    // Generate a new rename. If |should_be_private| is set to true
    // then we prefix returned identifier with '_'.
    RawString* NewAtomicRename(bool should_be_private);

    // Update next_ to generate the next free rename.
    void NextName();

    Thread* thread_;

    // Saved obfuscation state (ObjectStore::obfuscation_map())
    const Array& saved_state_;

    // Last used rename. Renames are only using a-zA-Z characters
    // and are generated in order: a, b, ..., z, A, ..., Z, aa, ba, ...
    char name_[100];

    ObfuscationMap renames_;

    const String& private_key_;

    // Temporary handles.
    String& string_;
    String& renamed_;
  };

  // Current obfucation state or NULL if obfuscation is not enabled.
  ObfuscationState* state_;
};
#else
// Minimal do-nothing implementation of an Obfuscator for non-precompiler
// builds.
class Obfuscator {
 public:
  Obfuscator(Thread* thread, const String& private_key) {}
  ~Obfuscator() {}

  RawString* Rename(const String& name, bool atomic = false) {
    return name.raw();
  }

  void PreventRenaming(const String& name) {}
  static void ObfuscateSymbolInstance(Thread* thread,
                                      const Instance& instance) {}

  static void Deobfuscate(Thread* thread, const GrowableObjectArray& pieces) {}
};
#endif  // defined(DART_PRECOMPILER) && !defined(TARGET_ARCH_DBC) &&           \
        // !defined(TARGET_ARCH_IA32)

}  // namespace dart

#endif  // RUNTIME_VM_COMPILER_AOT_PRECOMPILER_H_
