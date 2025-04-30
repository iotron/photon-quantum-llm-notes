# Quantum DSL (Domain-Specific Language)

## Introduction

Quantum requires components and other runtime game state data types to be declared with its own DSL (domain-specific-language).

Key characteristics:
- Written in text files with `.qtn` extension
- Quantum compiler parses them into an AST (Abstract Syntax Tree)
- Generates partial C# struct definitions for each type
- Definitions can be split across multiple files (compiler merges them)

Benefits of using Quantum DSL:
- Abstracts away complex memory alignment requirements
- Supports Quantum's ECS sparse set memory model
- Required for deterministic predict/rollback simulation
- Eliminates boilerplate code for:
  - Type serialization (snapshots, game saves, killcam replays)
  - Checksumming
  - Debugging functions (printing/dumping frame data)

Creating a new `.qtn` file:
- Using Unity's Project tab context menu: `Create > Quantum > Qtn`
- Or create a file with `.qtn` extension directly

## Components

Components are special structs that can be attached to entities and used for filtering them.

Basic component definition example:

```qtn
component Action
{
  FP Cooldown;
  FP Power;
}
```

These are compiled to regular C# structs with:
- Appropriate code structure
- Marker interface
- ID property
- Other required metadata

### Pre-built Quantum Components

Quantum includes several pre-built components:

- **Transform2D/Transform3D**: position and rotation using Fixed Point (FP) values
- **PhysicsCollider, PhysicsBody, PhysicsCallbacks, PhysicsJoints (2D/3D)**: used by Quantum's stateless physics engines
- **PathFinderAgent, SteeringAgent, AvoidanceAgent, AvoidanceObstacle**: navmesh-based path finding and movement

## Structs

### DSL-Defined Structs

Regular structs can also be defined in the DSL:

```qtn
struct ResourceItem
{
  FP Value;
  FP MaxValue;
  FP RegenRate;
}
```

Features:
- Fields declared in same order but with adjusted memory offsets
- Optimal packing
- Avoids padding
- Can be used as types in other DSL definitions

Example of using a struct within a component:

```qtn
component Resources
{
  ResourceItem Health;
  ResourceItem Strength;
  ResourceItem Mana;
}
```

The generated struct is partial and can be extended in C#.

### C#-Defined Structs

You can also define structs directly in C#, but must manually:
- Define the memory layout using `LayoutKind.Explicit`
- Add a const int `SIZE` containing the struct's byte size
- Implement the `Serialize` function

Example:

```csharp
[StructLayout(LayoutKind.Explicit)]
public struct Foo {
  public const int SIZE = 12; // the size in bytes of all members in bytes.
  
  [FieldOffset(0)]
  public int A;
  
  [FieldOffset(4)]
  public int B;
  
  [FieldOffset(8)]
  public int C;
  
  public static unsafe void Serialize(void* ptr, FrameSerializer serializer)
  {
    var foo = (Foo*)ptr;
    serializer.Stream.Serialize(&foo->A);
    serializer.Stream.Serialize(&foo->B);
    serializer.Stream.Serialize(&foo->C);
  }
}
```

When using C# defined structs in the DSL, you must import them:

```qtn
import struct Foo(12);
```

**Note:** The *import* doesn't support constants in the size; you must specify the exact numerical value each time.

### Components vs. Structs

Components and structs differ in important ways:

Components:
- Contain generated meta-data
- Can be attached directly to entities
- Used to filter entities when traversing game state
- Can be accessed as pointers or value types

## Dynamic Collections

Quantum's custom allocator provides blittable collections for the rollback-able game state:
- Only support blittable types (primitives and DSL-defined types)

For collection management, the Frame API offers 3 methods for each collection type:
- `Frame.AllocateXXX`: Allocates space for the collection on the heap
- `Frame.FreeXXX`: Frees/deallocates the collection's memory
- `Frame.ResolveXXX`: Accesses the collection by resolving the pointer

**Important**: After freeing a collection, it **MUST** be nullified by setting it to `default`. This is required for proper serialization of the game state. Alternatively, you can use the `FreeOnComponentRemoved` attribute on the field.

### Important Notes on Collections

- Several components can reference the same collection instance
- Dynamic collections are stored as references inside components and structs
- Collections **must be** allocated when initialized and freed when no longer needed
- For collections in components, you can:
  - Implement reactive callbacks `ISignalOnAdd<T>` and `ISignalOnRemove<T>` and allocate/free the collections there
  - Use the `[AllocateOnComponentAdded]` and `[FreeOnComponentRemoved]` attributes for automatic handling
- Quantum does **NOT** pre-allocate collections from prototypes unless there is at least one value
- Attempting to free a collection more than once will throw an error and invalidate the heap

### Lists

Lists can be defined in the DSL using:

```qtn
component Targets {
  list<EntityRef> Enemies;
}
```

Core list API methods:
- `Frame.AllocateList<T>()`
- `Frame.FreeList(QListPtr<T> ptr)`
- `Frame.ResolveList(QListPtr<T> ptr)`

Once resolved, a list supports expected operations (Add, Remove, Contains, IndexOf, RemoveAt, [], etc.)

Example of using a list:

```csharp
namespace Quantum
{
  public unsafe class HandleTargets : SystemMainThread, ISignalOnComponentAdded<Targets>, ISignalOnComponentRemoved<Targets>
  {
    public override void Update(Frame frame) 
    {
      foreach (var (entity, component) in frame.GetComponentIterator<Targets>()) { 
        // To use a list, you must first resolve its pointer via the frame
        var list = frame.ResolveList(component.Enemies);

        // Do stuff
      }    
    }

    public void OnAdded(Frame frame, EntityRef entity, Targets* component)
    {
      // allocating a new List (returns the blittable reference type - QListPtr)
        component->Enemies = frame.AllocateList<EntityRef>();
    }
    
    public void OnRemoved(Frame frame, EntityRef entity, Targets* component)
    {
      // A component HAS TO de-allocate all collection it owns from the frame data, otherwise it will lead to a memory leak.
      // receives the list QListPtr reference.
      frame.FreeList(component->Enemies);
      
      // All dynamic collections a component points to HAVE TO be nullified in a component's OnRemoved
      // EVEN IF is only referencing an external one!
      // This is to prevent serialization issues that otherwise lead to a desynchronisation.
      component->Enemies = default;
    }
  }
}
```

### Dictionaries

Dictionaries can be declared in the DSL:

```qtn
component Hazard {
  dictionary<EntityRef, Int32> DamageDealt;
}
```

Core dictionary API methods:
- `Frame.AllocateDictionary<K,V>()`
- `Frame.FreeDictionary(QDictionaryPtr<K,V> ptr)`
- `Frame.ResolveDictionary(QDictionaryPtr<K,V> ptr)`

### HashSet

HashSets can be declared in the DSL:

```qtn
component Nodes {
  hash_set<FP> ProcessedNodes;
}
```

Core HashSet API methods:
- `Frame.AllocateHashSet(QHashSetPtr<T> ptr, int capacity = 8)`
- `Frame.FreeHashSet(QHashSetPtr<T> ptr)`
- `Frame.ResolveHashSet(QHashSetPtr<T> ptr)`

## Enums, Unions and Bitsets

### Enums

Enums define a set of named constant values:

```qtn
enum EDamageType {
    None, Physical, Magic
}

struct StatsEffect {
    EDamageType DamageType;
}
```

- Enums are treated as integer constants starting from 0 by default
- Values can be explicitly assigned
- You can specify an underlying type to reduce memory footprint:

```qtn
enum EModifierOperation : Byte
{
  None = 0,
  Add = 1,
  Subtract = 2
}
```

The `flags` keyword is used to indicate bit flags that can be combined:

```qtn
flags ETeamStatus : Byte
{
  None,
  Winning,
  SafelyWinning,
  LowHealth,
  MidHealth,
  HighHealth,
}
```

Using `flags` also generates utility methods like `IsFlagSet()`, which is more performant than `System.Enum.HasFlag()` as it avoids value type boxing.

### Unions

C-like unions overlay the memory of multiple structs:

```qtn
struct DataA
{
  FPVector2 Foo;
}

struct DataB
{
  FP Bar;
}

union Data
{
  DataA A;
  DataB B;
}
```

Unions can be used in components:

```qtn
component ComponentWithUnion {
  Data ComponentData;
}
```

Usage examples:

```csharp
private void UseWarriorAttack(Frame frame)
{
    var character = frame.Unsafe.GetPointer<Character>(entity);
    character->Data.Warrior->ImpulseDirection = FPVector3.Forward;
}

private void ResetSpellcasterMana(Frame frame)
{
    var character = frame.Unsafe.GetPointer<Character>(entity);
    character->Data.Spellcaster->Mana = FP._10;
}
```

You can check the currently active union type:

```csharp
private bool IsWarrior(CharacterData data)
{
    return data.Field == CharacterData.WARRIOR;
}
```

### Bitset

Bitsets declare fixed-size memory blocks for various purposes (fog-of-war, grid structures, etc.):

```qtn
struct FOWData
{
  bitset[256] Map;
}
```

## Input

Runtime input exchanged between clients is also declared in the DSL:

```qtn
input
{
  FPVector2 Movement;
  button Fire;
}
```

The input struct is polled every tick and sent to the server (when playing online).

For more information, see [Input](/quantum/current/manual/input).

## Signals

Signals are function signatures used for decoupled inter-system communication (publisher/subscriber pattern):

```qtn
signal OnDamage(FP damage, entity_ref entity);
```

This generates an interface that can be implemented by any System:

```csharp
public interface ISignalOnDamage
{
  public void OnDamage(Frame frame, FP damage, EntityRef entity);
}
```

Signals are the only concept allowing direct declaration of pointers in the DSL:

```qtn
signal OnBeforeDamage(FP damage, Resources* resources);
```

## Events

Events communicate what happens in the simulation to the rendering engine/view:

```qtn
event MyEvent{
  int Foo;
}
```

Trigger the event from the simulation:

```csharp
f.Events.MyEvent(2022);
```

Subscribe and consume the event in Unity:

```csharp
QuantumEvent.Subscribe(listener: this, handler: (MyEvent e) => Debug.Log($"MyEvent {e.Foo}"));
```

For more details, see [Frame Events Manual](/quantum/current/manual/quantum-ecs/game-events#frame_events).

## Globals

Define globally accessible variables in the DSL:

```qtn
global {
  // Any type that is valid in the DSL can also be used.
  FP MyGlobalValue;
}
```

Globals are part of the state and fully compatible with the predict-rollback system.

Variables in the global scope are accessible through the Frame API from any place with frame access.

**Note:** Singleton Components are an alternative to global variables (see the Components page in the ECS section).

## Special Types

Quantum provides special types to abstract complex concepts or protect against common mistakes with unmanaged code:

* `player_ref`: Runtime player index (can cast to/from Int32). Useful for storing which player controls an entity.
* `entity_ref`: Abstracts an entity's index and version, protecting from accidentally accessing deprecated data.
* `asset_ref<AssetType>`: Rollback-able reference to a data asset instance from the Quantum asset database.
* `list<T>`, `dictionary<K,T>`: Dynamic collection references stored in Quantum's frame heap. Only support blittable types.
* `array<Type>[size]`: Fixed-sized "arrays" for rollback-able data collections.

### Assets

Assets define data-driven containers that become immutable instances in an indexed database:

```qtn
asset CharacterData; // the CharacterData class is partially defined in a normal C# file by the developer
```

Example using special types:

```qtn
struct SpecialData
{
  player_ref Player;
  entity_ref Character;
  entity_ref AnotherEntity;
  asset_ref<CharacterData> CharacterData;
  array<FP>[10] TenNumbers;
}
```

## Available Types

### Default Types

Pre-imported cross-platform deterministic types:

* Boolean / bool (wrapped in QBoolean)
* Byte
* SByte
* UInt16 / Int16
* UInt32 / Int32
* UInt64 / Int64
* FP
* FPVector2
* FPVector3
* FPMatrix
* FPQuaternion
* PlayerRef / player_ref
* EntityRef / entity_ref
* LayerMask
* NullableFP / FP?
* NullableFPVector2 / FPVector2?
* NullableFPVector3 / FPVector3?
* QString (UTF-16)
* QStringUtf8 (UTF-8)
* Hit
* Hit3D
* Shape2D
* Shape3D
* Joint, DistanceJoint, SpringJoint and HingeJoint

**Note on QStrings**: `N` represents the total size in bytes minus 2 bytes for bookkeeping. For example, `QString<64>` uses 64 bytes for a string with max byte length of 62 bytes (up to 31 UTF-16 characters).

### Manual Import

Types not listed above must be manually imported when used in QTN files.

#### Importing specific types

To import types from other namespaces:

```qtn
import MyInterface;
// or
import MyNameSpace.Utils;
```

For enums:

```qtn
import enum MyEnum(underlying_type);

// Example for Quantum specific enums
import enum Shape3DType(byte);
```

#### Including namespaces

Add `using MyNamespace;` to any QTN file to include the namespace in the generated class.
