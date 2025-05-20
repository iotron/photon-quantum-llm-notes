# Entity Component System in Quantum

Quantum uses an Entity Component System (ECS) architecture for its simulation. This document explains how the ECS is implemented in Quantum and how to work with it.

## Entities

Entities in Quantum are lightweight identifiers represented by the `EntityRef` struct. They are essentially handles that reference a specific entity in the simulation.

Key characteristics:
- Entities are simply IDs, not objects with behavior
- They serve as containers for components
- Created and managed through the `Frame` object

### Creating Entities

```csharp
// Create a new entity
EntityRef entity = frame.Create();

// Create an entity from a prototype
EntityRef entity = frame.Create("PlayerPrototype");

// Destroy an entity
frame.Destroy(entity);
```

## Components

Components in Quantum are structs (value types) that contain only data. They implement the `IComponent` interface and are added to entities.

Key characteristics:
- Pure data containers with no behavior
- Implemented as unmanaged structs for performance
- Defined in Quantum DSL (.qtn files) or as C# structs

### Component Example (Defined in C#)

```csharp
public unsafe struct Movement : IComponent
{
    public FP RotationSpeed;
    public FP JumpForce;
    public FP WalkSpeedMultiplier;
    public Boolean JumpInProgress;
    public Boolean SetLookRotation;
}
```

### Component Example (Defined in Quantum DSL)

```
component PlayerLink {
    PlayerRef PlayerRef;
}
```

### Working with Components

```csharp
// Add a component to an entity
var movement = frame.AddComponent<Movement>(entity);
movement->RotationSpeed = 5;
movement->JumpForce = 10;

// Get a component from an entity
var movement = frame.Get<Movement>(entity);

// Check if entity has a component
if (frame.Has<Movement>(entity)) {
    // Do something
}

// Remove a component
frame.Remove<Movement>(entity);
```

## Systems

Systems in Quantum contain the game logic that processes entities with specific component combinations. They implement behavior by operating on components.

Key characteristics:
- Contain the game logic for specific aspects of gameplay
- Operate on entities with specific component combinations (filters)
- Execute in a deterministic order
- Can be enabled/disabled dynamically

### System Types

Quantum provides several base types for systems:

1. `SystemBase` - Base class for all systems
2. `SystemMainThread` - Systems that run on the main thread
3. `SystemMainThreadFilter<T>` - Systems that run on the main thread with a filter
4. `SystemMultiThreadFilter<T>` - Systems that can run in parallel on multiple threads

### System Example

```csharp
public unsafe class MovementSystem : SystemMainThreadFilter<MovementSystem.Filter>
{
    public struct Filter
    {
        public EntityRef    Entity;
        public PlayerLink*  PlayerLink;
        public Transform3D* Transform;
        public Movement*    Movement;
        public KCC*         KCC;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Implementation of movement logic
        var input = frame.GetPlayerInput(filter.PlayerLink->PlayerRef);
        var moveDirection = CalculateMoveDirection(input);
        filter.KCC->SetInputDirection(moveDirection);
        
        // Handle jumping
        if (input->Jump.WasPressed && filter.KCC->IsGrounded)
        {
            filter.KCC->Jump(FPVector3.Up * filter.Movement->JumpForce);
            filter.Movement->JumpInProgress = true;
            frame.Events.Jumped(filter.Entity);
        }
    }
}
```

### System Registration

Systems are registered in the simulation through either:

1. The `SystemsConfig` asset
2. The `DeterministicSystemSetup` class (programmatically)

```csharp
// In DeterministicSystemSetup.cs
static partial void AddSystemsUser(ICollection<SystemBase> systems, RuntimeConfig gameConfig,
    SimulationConfig simulationConfig, SystemsConfig systemsConfig)
{
    // Add your custom systems here
    systems.Add(new MovementSystem());
}
```

## Signals

Signals in Quantum provide a decoupled way for systems to communicate with each other.

Key characteristics:
- Define interfaces for receiving callbacks
- Allow communication without direct references
- Enable loose coupling between systems

### Signal Example

```csharp
// Define a signal interface
public interface ISignalOnPlayerFell : ISignal
{
    void OnPlayerFell(Frame frame, EntityRef entity);
}

// Implement the signal in a system
public unsafe class RespawnSystem : SystemBase, ISignalOnPlayerFell
{
    public void OnPlayerFell(Frame frame, EntityRef entity)
    {
        // Handle player falling
        RespawnPlayer(frame, entity);
    }
}

// Trigger the signal
frame.Signals.PlayerFell(entity);
```

## Entity Prototypes

Prototypes allow you to define entity templates that can be instantiated at runtime.

Key characteristics:
- Defined as assets in Unity
- Can be instantiated multiple times
- Support hierarchical composition

### Using Prototypes

```csharp
// Create an entity from a prototype
EntityRef entity = frame.Create("PlayerPrototype");

// Create an entity from a prototype at a specific position
var position = new FPVector3(0, 0, 0);
EntityRef entity = frame.Create("PlayerPrototype", position);
```

## Entity Views

Entity Views connect Unity GameObjects to Quantum entities, allowing for visual representation of the simulation.

Key characteristics:
- Implemented through `QuantumEntityView` components
- Map Quantum entities to Unity GameObjects
- Handle interpolation and visual updates

### Entity View Example

```csharp
public class CharacterView : QuantumEntityViewComponent
{
    private Animator _animator;
    
    public override void OnActivate(Frame frame)
    {
        _animator = GetComponent<Animator>();
    }
    
    public override void OnUpdateView()
    {
        var kcc = GetPredictedQuantumComponent<KCC>();
        if (kcc != null)
        {
            _animator.SetBool("IsGrounded", kcc.IsGrounded);
            _animator.SetFloat("Speed", kcc.Data.CharacterVelocity.Magnitude.AsFloat);
        }
    }
}
```

This ECS architecture provides a powerful and efficient framework for building deterministic multiplayer games with Quantum.
