# Quantum Systems

## Introduction

Systems are the entry points for all gameplay logic in Quantum. They are implemented as normal C# classes but must adhere to specific restrictions to comply with the predict/rollback model:

1. **Must be stateless**: No mutable fields should be declared in systems. All mutable game data must be declared in `.qtn` files, which becomes part of the rollbackable game state inside the `Frame` class.

2. **Must be deterministic**: Systems must implement and/or use only deterministic libraries and algorithms. Quantum provides libraries for fixed point math, vector math, physics, random number generation, path finding, etc.

## System Types

There are several base system classes you can inherit from:

### SystemMainThread

```csharp
namespace Quantum {
  using Photon.Deterministic;
  using UnityEngine.Scripting;

  [Preserve]
  public unsafe class MySystem : SystemMainThread {
    public override void Update(Frame frame) {
      // Your game logic here
    }
  }
}
```

- Has `OnInit` and `Update` callbacks
- Update is executed once per system
- When iterating through entities and their components, you must create your own filters
- Can be used to subscribe and react to Quantum signals

### SystemMainThreadFilter<Filter>

```csharp
namespace Quantum {
  using Photon.Deterministic;
  using UnityEngine.Scripting;

  [Preserve]
  public unsafe class MyFilterSystem : SystemMainThreadFilter<MyFilterSystem.Filter> {
    public override void Update(Frame frame, ref Filter filter) {
      // Your game logic for this specific entity
    }

    public struct Filter {
      public EntityRef Entity;
      // Add component pointers here
    }
  }
}
```

- Similar to `SystemMainThread`
- Takes a filter that defines component layout
- `Update` is called once for every entity that has all components defined in the Filter

### SystemSignalsOnly

```csharp
namespace Quantum {
  using Photon.Deterministic;
  using UnityEngine.Scripting;

  [Preserve]
  public unsafe class MySignalSystem : SystemSignalsOnly {
    // Signal handlers here
  }
}
```

- Does *not* provide an `Update` callback
- Commonly used only for reacting to Quantum signals
- Has reduced overhead as it doesn't have task scheduling

### SystemBase

- For advanced uses only
- Used for scheduling parallel jobs into the task graph
- Not covered in the basic manual

## Core Systems

Quantum SDK includes all *Core* systems in the default `SystemsConfig`:

| System | Description |
| --- | --- |
| `Core.CullingSystem2D()` | Culls entities with a `Transform2D` component in predicted frames |
| `Core.CullingSystem3D()` | Culls entities with a `Transform3D` component in predicted frames |
| `Core.PhysicsSystem2D()` | Runs physics on entities with a `Transform2D` AND a `PhysicsCollider2D` component |
| `Core.PhysicsSystem3D()` | Runs physics on entities with a `Transform3D` AND a `PhysicsCollider3D` component |
| `Core.NavigationSystem()` | Used for all NavMesh related components |
| `Core.EntityPrototypeSystem()` | Creates, Materializes and Initializes `EntityPrototypes` |
| `Core.PlayerConnectedSystem()` | Triggers `ISignalOnPlayerConnected` and `ISignalOnPlayerDisconnected` signals |
| `Core.DebugCommand.CreateSystem()` | Used by the state inspector to send data to instantiate/remove/modify entities on the fly (Editor only) |

All systems are included by default for convenience. Core systems can be selectively added/removed based on the game's requirements; e.g., only keep the `PhysicsSystem2D` or `PhysicsSystem3D` based on what the game needs.

## Creating Systems in Unity

You can create Quantum systems using script templates in Unity's right-click menu:

![System Templates](/docs/img/quantum/v3/manual/quantum-system-templates.png)

## System API

Main callbacks that can be overridden in a System class:

- `OnInit(Frame frame)`: Executed only once when the game starts. Commonly used to set up initial game data.
- `Update(Frame frame)`: Used to advance the game state.
- `OnDisabled(Frame frame)` and `OnEnabled(Frame frame)`: Called when a system is directly disabled/enabled or when a parent system state is toggled.
- `UseCulling`: Defines if the System should exclude culled entities.

**Important**: It is mandatory for any Quantum system to use the attribute `[UnityEngine.Scripting.Preserve]`.

All callbacks include an instance of `Frame`, which is the container for all mutable and static game state data, including entities, physics, navigation, and immutable asset objects.

## Stateless Requirements

Systems must be stateless to comply with Quantum's predict/rollback model. Quantum only guarantees determinism if all mutable game state data is fully contained in the Frame instance.

Valid patterns:
- Creating read-only constants
- Using private methods (that receive all needed data as parameters)

```csharp
namespace Quantum 
{
  public unsafe class MySystem : SystemMainThread
  {
    // This is ok - read-only constant
    private const int _readOnlyData = 10;
    
    // This is NOT ok - mutable field that won't be rolled back
    // Would lead to instant drifts between clients during rollbacks
    private int _mutableData = 10;

    public override void Update(Frame frame)
    {
        // OK: Using a constant to compute something
        var temporaryData = _readOnlyData + 5;

        // NOT OK: Modifying transient data outside the Frame
        _transientData = 5;
    }
  }
}
```

## SystemsConfig

In Quantum 3, system configuration is handled through an asset named `SystemsConfig`. This config is passed into the `RuntimeConfig`, and Quantum automatically instantiates the requested systems.

To guarantee determinism, systems are executed in the order they're inserted in the SystemsConfig. Control the sequence of updates by arranging your custom systems in the desired order.

### Creating a new SystemsConfig

Create a new SystemsConfig by right-clicking in the project window and selecting Quantum > SystemsConfig. The asset has a serialized list of systems that you can manipulate like any normal Unity list.

![Systems Config](/docs/img/quantum/v3/manual/config-files/systems-config.png)

### Activating and Deactivating Systems

All injected systems are active by default, but you can control their status at runtime using methods available in the Frame object:

```csharp
public override void OnInit(Frame frame)
{
  // Deactivates MySystem - no updates or signals will be called
  frame.SystemDisable<MySystem>();

  // (Re)activates MySystem
  frame.SystemEnable<MySystem>();

  // Query if a System is currently enabled
  var enabled = frame.SystemIsEnabled<MySystem>();
}
```

Any System can deactivate and reactivate another System. A common pattern is to have a main controller system that manages the lifecycle of specialized Systems using a state machine (e.g., in-game lobby with countdown, normal gameplay, score state).

To make a system start disabled by default:

```csharp
public override bool StartEnabled => false;
```

### System Groups

Systems can be grouped to enable and disable them together:

1. Select the `SystemsConfig`
2. Add a new system of type `SystemGroup`
3. Append child systems to it

![System Group](/docs/img/quantum/v3/manual/ecs/system-setup-groups.png)

**Note**: The `Frame.SystemEnable<T>()` and `Frame.SystemDisable<T>()` methods identify systems by type. For multiple independent system groups, each group needs its own implementation:

```csharp
namespace Quantum
{
  public class MySystemGroup : SystemMainThreadGroup
  {
    public MySystemGroup(string update, params SystemMainThread[] children) : base(update, children)
    {
    }
  }
}
```

## Entity Lifecycle API

This section covers direct API methods for entity creation and composition. For a data-driven approach, refer to the chapter on entity prototypes.

### Creating Entities

```csharp
// Creates a new entity instance (returns an EntityRef)
var e = frame.Create();
```

### Adding Components

Entities don't have pre-defined components. Add components as needed:

```csharp
// Add a Transform3D component
var t = Transform3D.Create();
frame.Set(e, t);

// Add a PhysicsCollider3D component
var c = PhysicsCollider3D.Create(f, Shape3D.CreateSphere(1));
frame.Set(e, c);
```

### Entity Management

```csharp
// Destroys the entity, including all its components
frame.Destroy(e);

// Checks if an EntityRef is still valid
if (frame.Exists(e)) {
  // Safe to do stuff, Get/Set components, etc.
}
```

### Component Operations

You can check if an entity has specific components and access them:

```csharp
// Check if entity has a Transform3D component
if (frame.Has<Transform3D>(e)) {
  // Get a pointer to the component data
  var t = frame.Unsafe.GetPointer<Transform3D>(e);
  // Modify component data
  t->Position += FPVector3.Forward;
}
```

Using `ComponentSet` for checking multiple components:

```csharp
var components = ComponentSet.Create<CharacterController3D, PhysicsBody3D>();
if (frame.Has(e, components)) {
  // Entity has both components
}
```

Removing components:

```csharp
frame.Remove<Transform3D>(e);
```

### The EntityRef Type

Due to Quantum's rollback model, several copies of the game state are kept in separate memory locations. This means any direct pointer is only valid within a single Frame.

`EntityRef` provides a safe reference to entities that works across frames, as long as the entity still exists. It contains:
- Entity index: the entity slot
- Entity version number: used to invalidate old references when an entity is destroyed and its slot reused

### Filters

Quantum doesn't use "entity types." In the sparse-set ECS model, entities are indexes to component collections. Filters are used to create a set of components for systems to work with:

```csharp
public unsafe class MySystem : SystemMainThread
{
    public override void Update(Frame frame)
    {
        var filtered = frame.Filter<Transform3D, PhysicsBody3D>();

        while (filtered.Next(out var e, out var t, out var b)) {
          t.Position += FPVector3.Forward * frame.DeltaTime;
          frame.Set(e, t);
        } 
    }
}
```

For more details on filters, see the Components page.

## Pre-Built Assets and Config Classes

Quantum provides pre-built data assets that are accessible through the Frame object:

- **Map and NavMesh**: Playable area, static physics colliders, navigation meshes, etc.
- **SimulationConfig**: General configuration for physics engine, navmesh system, etc.
- **Default materials and agent configs**: Physics materials, character controllers, navmesh agents, etc.

Accessing Map and NavMesh instances:

```csharp
// Map is the container for several static data, such as navmeshes
Map map = f.Map;
var navmesh = map.NavMeshes["MyNavmesh"];
```

## Signals

Signals provide a publisher/subscriber API for inter-system communication. Example from a DSL file:

```qtn
signal OnDamage(FP damage, entity_ref entity);
```

This generates a trigger signal on the Frame class that any "publisher" System can call:

```csharp
// Any System can trigger the signal without coupling to specific implementations
f.Signals.OnDamage(10, entity)
```

A "subscriber" System implements the generated interface:

```csharp
namespace Quantum
{
  class CallbacksSystem : SystemSignalsOnly, ISignalOnDamage
  {
    public void OnDamage(Frame frame, FP damage, EntityRef entity)
    {
      // Called whenever any other system calls the OnDamage signal
    }
  }
}
```

Signals always include the Frame object as the first parameter.

### Built-in and Generated Signals

Besides explicit DSL-defined signals, Quantum includes pre-built signals (like physics collision callbacks) and auto-generated ones based on entity definitions:

- `ISignalOnPlayerDataSet`: Called when a game client sends a RuntimePlayer instance
- `ISignalOnPlayerConnected`/`ISignalOnPlayerDisconnected`: Player connection events
- `ISignalOnMapChanged`: Called when the map changes
- `ISignalOnEntityCreated`/`ISignalOnEntityDestroyed`: Entity lifecycle events

Additionally, component-specific signals are generated for adding/removing components:

- `ISignalOnComponentAdded<T>`
- `ISignalOnComponentRemoved<T>`

## Best Practices

1. **Maintain Statelessness**: Never store mutable state in System classes - all game state should be in the Frame.

2. **System Organization**: Group related functionality in cohesive systems and order them appropriately in SystemsConfig.

3. **Use Signal Pattern**: For inter-system communication, prefer signals over direct system dependencies.

4. **System Lifecycle Management**: Use system enable/disable methods to control game flow rather than complex conditionals.

5. **Optimize Filters**: Be careful when creating complex filters in performance-critical systems.

6. **Follow Entity Lifecycle**: Always check entity existence before accessing its components, especially with stored EntityRefs.

7. **Minimize Cache Misses**: Group related data accesses together to improve performance.

8. **Deterministic Operations**: Always use Quantum's deterministic libraries for calculations to ensure consistent behavior across clients.
