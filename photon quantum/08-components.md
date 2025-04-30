# Quantum Components

## Introduction

Components are special structs that can be attached to entities and used for filtering them (iterating only a subset of active entities based on attached components).

Quantum provides several pre-built components:
- **Transform2D/Transform3D**: Position and rotation using Fixed Point (FP) values
- **PhysicsCollider, PhysicsBody, PhysicsCallbacks, PhysicsJoints (2D/3D)**: Used by Quantum's stateless physics engines
- **PathFinderAgent, SteeringAgent, AvoidanceAgent, AvoidanceObstacle**: NavMesh-based path finding and movement

## Defining Components

Components are defined in the Quantum DSL:

```qtn
component Action
{
    FP Cooldown;
    FP Power;
}
```

Labeling them as components (rather than simple structs) generates the appropriate code structure (marker interface, ID property, etc.). Once compiled, components become available in the Unity Editor for use with Entity Prototypes. In the editor, custom components are named *Entity Component ComponentName*.

## Working with Components

The API for working with components is accessed through the `Frame` class. There are two approaches:
1. Work with copies of components
2. Work with components via pointers

For clarity, the API distinguishes between these approaches:
- Direct access via `Frame` for working with copies
- Access via `Frame.Unsafe` for working with pointers (as this modifies memory directly)

## Component API

### Adding Components

`Add<T>` adds a component to an entity. Each entity can only have one instance of a particular component type. The method returns an `AddResult` enum for debugging:

```csharp
public enum AddResult {
    EntityDoesNotExist     = 0, // The EntityRef passed in is invalid
    ComponentAlreadyExists = 1, // The Entity already has this component attached
    ComponentAdded         = 2  // The component was successfully added to the entity
}
```

### Getting and Setting Components

Once an entity has a component, you can retrieve it with `Get<T>`, which returns a copy of the component value. Since you're working with a copy, you must save modified values using `Set<T>`, which returns a `SetResult`:

```csharp
public enum SetResult {
    EntityDoesNotExist = 0, // The EntityRef passed in is invalid
    ComponentUpdated   = 1, // The component values were successfully updated
    ComponentAdded     = 2  // The Entity did not have this component type yet, so it was added with the new values
}
```

Example of setting a health component value:

```csharp
private void SetHealth(Frame frame, EntityRef entity, FP value){    
    var health = frame.Get<Health>(entity);
    health.Value = value;
    frame.Set(entity, health);
}
```

### Component API Methods Summary

| Method | Return | Additional Info |
| --- | --- | --- |
| Add<T>(EntityRef entityRef) | `AddResult` enum | Allows an invalid `EntityRef` |
| Get<T>(EntityRef entityRef) | A copy of `T` with current values | Does **not** allow an invalid `EntityRef`. Throws an exception if component `T` is not present |
| Set<T>(EntityRef entityRef) | `SetResult` enum | Allows an invalid `EntityRef` |
| Has<T>(EntityRef entityRef) | `true` if entity exists and component is attached | Allows invalid `EntityRef` and component to not exist |
| TryGet<T>(EntityRef entityRef, out T value) | `true` if successful | Allows an invalid `EntityRef` |
| TryGetComponentSet(EntityRef entityRef, out ComponentSet componentSet) | `true` if entity exists and all components in set are attached | Allows an invalid `EntityRef` |
| Remove<T>(EntityRef entityRef) | No return value | Allows an invalid `EntityRef` |

### Unsafe API (Direct Memory Access)

To avoid the overhead of Get/Set operations, `Frame.Unsafe` offers versions that work directly with component memory:

| Method | Return | Additional Info |
| --- | --- | --- |
| GetPointer<T>(EntityRef entityRef) | `T*` | Does NOT allow invalid entity ref. Throws an exception if component `T` is not present |
| TryGetPointer<T>(EntityRef entityRef, out T* value) | `true` if successful | Allows an invalid `EntityRef` |
| AddOrGet<T>(EntityRef entityRef, out <T>* result) | `true` if the entity exists and component is attached/has been attached | Allows an invalid `EntityRef` |

**Note**: Monolithic structs should be avoided and split into multiple structs to prevent `bracket nesting level exceeded maximum` errors when compiling IL2CPP.

## Singleton Components

A *Singleton Component* is a special component type that can only have one instance in the entire game state. This is strictly enforced by Quantum.

Custom *Singleton Components* are defined in the DSL using `singleton component`:

```qtn
singleton component MySingleton {
    FP Foo;
}
```

Singletons inherit from `IComponentSingleton` which inherits from `IComponent`. They can:
- Be attached to any entity
- Be managed with all regular safe & unsafe methods (Get, Set, TryGetPointer, etc.)
- Be added to entity prototypes via the Unity Editor or in code

### Singleton API Methods

In addition to regular component methods, there are special methods for singletons:

| Method | Return | Additional Info |
| --- | --- | --- |
| **Frame API** | | |
| SetSingleton<T>(T component, EntityRef optionalAddTarget = default) | void | Sets a singleton if it doesn't exist. Optional EntityRef specifies which entity to add it to. If none provided, a new entity is created |
| GetSingleton<T>() | T | Throws exception if singleton doesn't exist. No EntityRef needed |
| TryGetSingleton<T>(out T component) | bool | Returns true if singleton exists. No EntityRef needed |
| GetOrAddSingleton<T>(EntityRef optionalAddTarget = default) | T | Gets singleton or creates it if it doesn't exist. Optional EntityRef specifies target entity |
| GetSingletonEntityRef<T>() | EntityRef | Returns entity holding the singleton. Throws if singleton doesn't exist |
| TryGetSingletonEntityRef<T>(out EntityRef entityRef) | bool | Gets entity holding the singleton. Returns false if singleton doesn't exist |
| **Frame.Unsafe API** | | |
| Unsafe.GetPointerSingleton<T>() | T* | Gets singleton pointer. Throws exception if it doesn't exist |
| TryGetPointerSingleton<T>(out T* component) | bool | Gets singleton pointer if it exists |
| GetOrAddSingletonPointer<T>(EntityRef optionalAddTarget = default) | T* | Gets or adds singleton and returns pointer |

## ComponentTypeRef

The `ComponentTypeRef` struct lets you reference a component by its type at runtime, useful for dynamically adding components via polymorphism:

```csharp
// Set in an asset or prototype
ComponentTypeRef componentTypeRef;

var componentIndex = ComponentTypeId.GetComponentIndex(componentTypeRef);

frame.Add(entityRef, componentIndex);
```

## Adding Functionality (Extending Components)

Since components are structs, you can extend them with custom methods by writing a *partial* struct definition in a C# file:

```csharp
namespace Quantum
{
    public partial struct Action
    {
        public void UpdateCooldown(FP deltaTime){
            Cooldown -= deltaTime;
        }
    }
}
```

## Reactive Callbacks

There are two component-specific reactive callbacks:

- `ISignalOnComponentAdd<T>`: Called when a component type T is added to an entity
- `ISignalOnComponentRemove<T>`: Called when a component type T is removed from an entity

These are particularly useful for initializing resources when a component is added and cleaning up when it's removed (e.g., allocating and deallocating a list).

To receive these signals, implement them in a system:

```csharp
public class ResourceManagerSystem : SystemSignalsOnly, 
    ISignalOnComponentAdd<ResourceList>, 
    ISignalOnComponentRemove<ResourceList>
{
    public void OnAdded(Frame frame, EntityRef entity, ResourceList* component)
    {
        // Initialize resources, e.g. allocate a list
        component->Items = frame.AllocateList<ResourceRef>();
    }
    
    public void OnRemoved(Frame frame, EntityRef entity, ResourceList* component)
    {
        // Clean up resources, e.g. free a list
        frame.FreeList(component->Items);
        component->Items = default;
    }
}
```

## Component Iterators

### Single Component Iterators

For iterating through entities with a single component type, `ComponentIterator` (safe) and `ComponentBlockIterator` (unsafe) are best suited:

```csharp
// Safe iterator (working with copies)
foreach (var pair in frame.GetComponentIterator<Transform3D>())
{
    var component = pair.Component;
    component.Position += FPVector3.Forward * frame.DeltaTime;
    frame.Set(pair.Entity, component);
}

// Unsafe iterator (working with pointers)
foreach (var pair in frame.Unsafe.GetComponentBlockIterator<Transform3D>())
{
    pair.Component->Position += FPVector3.Forward * frame.DeltaTime;
}

// Alternative syntax for deconstruction
foreach (var (entityRef, transform) in frame.Unsafe.GetComponentBlockIterator<Transform3D>())
{
    transform->Position += FPVector3.Forward * frame.DeltaTime;
}
```

## Filters

Filters provide a convenient way to get entities based on a set of components. They can be used with both safe (Get/Set) and unsafe (pointer) code.

### Generic Filters

Create a filter using the `Filter()` API:

```csharp
var filtered = frame.Filter<Transform3D, PhysicsBody3D>();
```

Generic filters can include up to 8 components. You can further refine filters using `without` and `any` ComponentSets:

```csharp
var without = ComponentSet.Create<CharacterController3D>();
var any = ComponentSet.Create<NavMeshPathFinder, NavMeshSteeringAgent>();
var filtered = frame.Filter<Transform3D, PhysicsBody3D>(without, any);
```

A `ComponentSet` can hold up to 8 components. The `without` parameter excludes entities that have any of the specified components, while the `any` parameter ensures entities have at least one of the specified components.

Iterating through a filter using `Next()` provides copies of the components:

```csharp
while (filtered.Next(out var e, out var t, out var b)) {
  t.Position += FPVector3.Forward * frame.DeltaTime;
  frame.Set(e, t);
}
```

**Note**: You must use `Set` to update the entity with the modified component copy.

For direct memory access, use `UnsafeNext()`:

```csharp
while (filtered.UnsafeNext(out var e, out var t, out var b)) {
  t->Position += FPVector3.Forward * frame.DeltaTime;
}
```

### FilterStruct

For more complex filters, define a struct with public fields for each component type:

```csharp
struct PlayerFilter
{
    public EntityRef Entity;           // Required
    public CharacterController3D* KCC; // Component pointer
    public Health* Health;             // Component pointer
    public FP AccumulatedDamage;       // Custom field (ignored by filter)
}
```

A `FilterStruct` can include up to 8 different component pointers. The struct **must** have an `EntityRef` field, and component fields **must** be pointers. Custom fields are ignored by the filter.

Using a `FilterStruct`:

```csharp
var players = f.Unsafe.FilterStruct<PlayerFilter>();
var playerStruct = default(PlayerFilter);

while (players.Next(&playerStruct))
{
    // Do stuff with playerStruct.KCC, playerStruct.Health, etc.
}
```

`FilterStruct` also supports the optional `any` and `without` ComponentSets.

### Note on Count

Filters don't know in advance how many entities they'll iterate over. This is due to how filters work in Sparse-Set ECS:
1. The filter finds which component has the fewest entities associated with it
2. It traverses that set and discards entities that don't have the other queried components

Getting an exact count would require traversing the filter once, which would be inefficient (O(n) operation).

## Component Getter

For getting a specific set of components from a known entity, use `Frame.Unsafe.ComponentGetter` with a filter struct:

```csharp
public unsafe class MySpecificEntitySystem : SystemMainThread
{
    struct MyFilter {
        public EntityRef Entity;     // Required
        public Transform2D* Transform;
        public PhysicsBody2D* Body;
    }

    public override void Update(Frame frame)
    {
        var entity = /* known entity ref */;
        
        var getter = frame.Unsafe.ComponentGetter<MyFilter>();
        var filter = default(MyFilter);
        
        // Fills the filter struct with component pointers
        if (getter.TryGet(entity, ref filter))
        {
            // Do something with filter.Transform, filter.Body
        }
    }
}
```

## Best Practices

1. **Choose the Right Access Pattern**: Use copy-based methods (`Get`/`Set`) for simplicity, and pointer-based methods for performance-critical code.

2. **Handle Dynamic Collections**: When a component contains dynamic collections, implement `ISignalOnComponentAdd<T>` and `ISignalOnComponentRemove<T>` to properly allocate and free memory.

3. **Avoid Monolithic Components**: Split large components into smaller, focused ones to prevent compilation issues and improve ECS efficiency.

4. **Use Singleton Wisely**: Use singleton components for global game state, but be mindful of their limitations (only one instance system-wide).

5. **Optimize Filtering**: Structure your component queries to start with the rarest component type for best performance.

6. **Extend with Methods**: Add behavior to components through partial struct definitions, but keep components primarily data-focused.

7. **Validate EntityRefs**: Always check if an entity exists before trying to access its components, especially when storing EntityRefs between frames.

8. **Component Composition**: Design components to be composable rather than creating specialized components for every case.
