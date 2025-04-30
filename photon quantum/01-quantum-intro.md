# Photon Quantum Introduction

## Overview

Quantum is a high-performance deterministic ECS (Entity Component System) framework for online multiplayer games made with Unity, supporting up to 128 players.

- Uses predict/rollback networking
- Ideal for latency-sensitive games (sports, fighting, FPS)
- Robust with larger latency network connections
- Free for development with scaling pricing model

## Architecture

Quantum decouples:
- Simulation logic (Quantum ECS)
- View/presentation (Unity)
- Network implementation (predict/rollback + transport layer + game server logic)

![Quantum Decoupled Architecture](/docs/img/quantum/v2/getting-started/quantum-intro/quantum-sdk-layers.jpg)

### Core Components
- Server-managed predict/rollback simulation core
- Sparse-set ECS memory model and API
- Deterministic libraries (math, 2D/3D physics, navigation, animation, bots)
- Unity editor integration and tooling
- Built on Photon products (Photon Realtime transport, Photon Server)

## Predict/Rollback Networking

In deterministic systems:
- Game clients exchange only player input
- Simulation runs locally on all clients
- Clients can advance simulation locally using input prediction
- Rollback system handles restoring state and re-simulation when needed

Key concepts:
- Game-agnostic authoritative server component runs on Photon servers
- Synchronizes clocks and manages input latency
- Clients don't wait for slower clients (unlike lockstep networking)
- Server can be extended for matchmaking, player services, etc.

![Quantum Server-Managed predict/Rollback](/docs/img/quantum/v2/getting-started/quantum-intro/quantum-client-server.jpg)

## Entity Component System (ECS)

Quantum uses a high-performance sparse-set ECS model:
- Pointer-based C# code with custom heap allocator
- No C# heap memory allocation at runtime (no garbage)
- Efficient handling of re-simulations from input mispredictions
- Preserves CPU budget for Unity view/rendering code

### Code Generation

Game state is stored in:
- Sparse-set ECS data structures (entities and components)
- Custom heap-allocator (dynamic collections and custom data)
- Stored as blittable memory-aligned C# structs

#### Qtn DSL

Quantum uses a domain-specific language (Qtn) to generate C# code:

```qtn
// Components define reusable game state data groups
component Resources 
{
  Int32 Mana;
  FP Health;
}
```

Generated API provides functions to query and modify game state:

```csharp
var es = frame.Filter<Transform3D, Resources>();

// Sets the entity ref and pointers to the components
while (es.NextUnsafe(out var entity, out var transform, out var resources)) {
  transform->Position += FPVector3.Forward * frame.DeltaTime;
}
```

### Stateless Systems

Game logic is implemented through Systems:
- Stateless pieces of logic
- Execute on game state data
- Organized to process entities with specific components

Example of a system:

```csharp
public unsafe class LogicSystem : SystemMainThread
{
  public override void Update(Frame frame) 
  {
    // customer game logic here 
    // (frame is a reference for the generated game state container).
  }
}
```

## Quantum and Unity Integration

Since Quantum and Unity are decoupled, their communication is well defined:

![Quantum Inputs and Outputs](/docs/img/quantum/v3/getting-started/quantum-intro/quantum-inputs-outputs.jpg)

### Asset Database

Unity's editor and asset pipeline integrate with Quantum through:
- [Assets defined in Quantum](/quantum/current/manual/assets/assets-simulation)
- [Assets created within Unity](/quantum/current/manual/assets/assets-unity) specifically to be shared with Quantum
- Designers can work flexibly with familiar Unity workflows

![Character Classes - Asset Linking](/docs/img/quantum/v3/asset-linking.png)

### Input

[Input](/quantum/current/manual/input) must be defined and is sent to the server and distributed to all game clients every tick. This typically includes:
- Subset of keyboard/controller buttons
- Mouse/controller stick positions required by the game

### Commands

[Commands](/quantum/current/manual/commands) are for occasional actions and only sent when required.

### Events

[Events](/quantum/current/manual/quantum-ecs/game-events) transfer information from the Quantum simulation to the Unity view.

### Full Simulation State

The full simulation state from Quantum is observable from Unity:
- Common cases like synchronizing GameObject transforms to corresponding Quantum Entities are supported out of the box
- See [Entity Prototypes](/quantum/current/manual/entity-prototypes)
- Game-specific data (e.g., character health) can be read directly from the simulation state

## Getting Started

Recommended starting points:
- [Asteroids Tutorial](/quantum/current/tutorials/asteroids/1-overview) - Teaches all necessary basics
- [Complete Course to Quantum 3](/quantum/current/tutorials/video-tutorial) - Video tutorial stream
- [DSL Documentation](/quantum/current/manual/quantum-ecs/dsl) - Core programming concepts for the simulation
- [Entity Prototypes](/quantum/current/manual/entity-prototypes) - Core design concepts for the view
- [Game Samples](/quantum/current/game-samples/platform-shooter-2d/overview) - Downloadable examples
