# Quantum DSL (Domain Specific Language)

Quantum provides a Domain Specific Language (DSL) for defining game state components, signals, events, and other elements in a clean, declarative way. This document explains how to use the Quantum DSL and how it integrates with the rest of the framework.

## Overview

The Quantum DSL is used to define:

- Components
- Signals
- Events
- Global variables
- Input structures

DSL files use the `.qtn` extension and are compiled into C# code during the build process.

## Basic Syntax

### Components

Components define the data structures that can be attached to entities. They are defined using the `component` keyword:

```
component Transform2D {
    FPVector2 Position;
    FP Rotation;
    FPVector2 Scale;
}

component Health {
    FP Current;
    FP Max;
}
```

### Signals

Signals define communication channels between systems. They are defined using the `signal` keyword:

```
signal OnDamaged(EntityRef entity, FP amount);

signal OnLevelCompleted();
```

### Events

Events define messages sent from the simulation to the Unity side (view). They are defined using the `event` keyword:

```
event PlayerTookDamage {
    EntityRef Player;
    FP Amount;
    FPVector3 HitPoint;
}

event ItemCollected {
    EntityRef Item;
    EntityRef Collector;
}
```

### Global Variables

Global variables are defined at the file level, outside of any other structure:

```
global {
    EntityRef CurrentLevel;
    FP GameTime;
    int PlayerCount;
}
```

### Input Structure

The input structure defines what player input data is synchronized. It's defined using the `input` keyword:

```
input {
    FPVector2 MoveDirection;
    FPVector2 LookRotation;
    bool Jump;
    bool Fire;
    bool Sprint;
}
```

## Example DSL Files

### Common.qtn

```
component PlayerLink {
    PlayerRef PlayerRef;
}

component Health {
    FP Current;
    FP Max;
    bool IsDead;
}

signal OnPlayerFell(EntityRef entity);

global {
    FP GameTime;
    AssetRef<EntityPrototype> DefaultPlayerPrototype;
}

event PlayerDied {
    EntityRef Player;
    PlayerRef PlayerRef;
}

event PlayerRespawned {
    EntityRef Player;
    PlayerRef PlayerRef;
    FPVector3 Position;
}
```

### Input.qtn

```
input {
    FPVector2 MoveDirection;
    FPVector2 LookRotation;
    bool Jump;
    bool Fire;
    bool Sprint;
}

event Jumped {
    EntityRef Entity;
}

event Landed {
    EntityRef Entity;
}
```

## Using DSL-Generated Code

Once compiled, DSL files generate C# code that can be used throughout your project:

### Components

Components are generated as unmanaged structs that implement `IComponent`:

```csharp
// From PlayerLink DSL definition
public unsafe struct PlayerLink : IComponent
{
    public PlayerRef PlayerRef;
}

// Adding component to an entity
var playerLink = frame.AddComponent<PlayerLink>(entity);
playerLink->PlayerRef = playerRef;
```

### Signals

Signals are generated as interfaces that systems can implement:

```csharp
// From OnPlayerFell signal definition
public interface ISignalOnPlayerFell : ISignal
{
    void OnPlayerFell(Frame frame, EntityRef entity);
}

// Implementing the signal
public class RespawnSystem : SystemBase, ISignalOnPlayerFell
{
    public void OnPlayerFell(Frame frame, EntityRef entity)
    {
        // Handle player falling
    }
}

// Triggering the signal
frame.Signals.PlayerFell(entity);
```

### Events

Events are generated as classes that can be triggered from the simulation and received in Unity:

```csharp
// From Jumped event definition
public unsafe class EventJumped : EventBase
{
    public EntityRef Entity;
}

// Triggering the event
frame.Events.Jumped(entity);

// Subscribing to the event in Unity
QuantumEvent.Subscribe<EventJumped>(this, OnJumped);

private void OnJumped(EventJumped jumpEvent)
{
    // Play jump sound or animation
}
```

### Global Variables

Global variables are accessible through the `frame.Global` property:

```csharp
// Access a global variable
var gameTime = frame.Global->GameTime;

// Modify a global variable
frame.Global->GameTime += frame.DeltaTime;
```

### Input Structure

The input structure is accessible through the `frame.GetPlayerInput` method:

```csharp
// Get player input
var input = frame.GetPlayerInput(playerRef);

// Access input values
var moveDirection = input->MoveDirection;
var isJumping = input->Jump;
```

## DSL Compilation Process

The Quantum DSL compilation process works as follows:

1. DSL files (`.qtn`) are parsed by the Quantum compiler
2. C# code is generated for each DSL element
3. The generated code is included in the Quantum.Simulation assembly
4. At runtime, the generated code is fully integrated with the rest of the framework

## Best Practices

- Keep DSL files organized by functionality (e.g., player.qtn, weapons.qtn)
- Use DSL for all components, signals, and events to maintain consistency
- Prefer DSL-defined components over manually written ones
- Leverage the type safety and error checking provided by the DSL compiler
- Group related components, signals, and events in the same file

## Limitations

- DSL files cannot contain implementation logic, only definitions
- Some complex types may not be directly usable in DSL
- Custom serialization must be handled separately

The Quantum DSL provides a clean, declarative way to define key elements of your game's simulation state, helping to maintain a clear separation between data and behavior in your Quantum project.
