# Quantum Motor Dome Project Overview

This document provides a comprehensive overview of the Quantum Motor Dome project, a multiplayer 3D arena game built with Photon Quantum 3.0.2. These notes explain the project structure, core systems, and implementation details to help you understand how to create a similar arena game with Quantum's deterministic networking framework.

## Project Structure

Quantum Motor Dome demonstrates a multiplayer arena game with the following organization:

### Core Simulation Code (Quantum)
- **Assets/QuantumUser/Simulation/Game**: Contains all the deterministic simulation code
  - **DSL**: Component and state definitions in Quantum DSL
  - **Systems**: Game logic implementation
  - **Filters**: Entity filtering structures

### Unity View Code
- **Assets/Scripts**: Contains Unity-side view code
  - **View Logic**: View representations of simulation elements
  - **UI**: User interface and menu systems
  - **Camera**: Camera control and effects
  - **Effects**: Visual and audio effects

## Game Concept

Quantum Motor Dome is a multiplayer arena game where players control ships that move around a spherical arena. Key features include:

1. **Trail Mechanics**: Each ship leaves a trail behind it
2. **Collision**: Players can collide with other players' trails
3. **Reconnection**: Players can reconnect their trail to score points
4. **Pickups**: Collectible items provide boosts and score bonuses
5. **Spherical Movement**: All gameplay takes place on the surface of a sphere

## Architecture Overview

Quantum Motor Dome follows Quantum's core architecture principles:

### Simulation-View Separation

```
Simulation (Quantum) → Events → View (Unity)
             ↑           ↓
             └─ Input ───┘
```

- **Simulation**: Deterministic game logic running in Quantum
- **View**: Visual representation in Unity
- **Events**: One-way communication from simulation to view
- **Input**: Player commands sent from view to simulation

### ECS Implementation

The game uses Quantum's Entity Component System:
- **Entities**: Dynamic game objects (ships, pickups)
- **Components**: Data containers attached to entities (Ship, PlayerLink)
- **Systems**: Logic that processes entities with specific components (ShipMovementSystem, CollisionSystem)

### Game State Flow

The game transitions through several states managed by the GameStateSystem:

```
Lobby → Pregame → Intro → Countdown → Game → Outro → Postgame
  ↑                                                    |
  └────────────────────────────────────────────────────┘
```

Each state activates specific systems related to that phase of gameplay.

## Core Components

### Ship Component

The Ship component represents the player-controlled vehicle:

```qtn
component Ship
{
	[Header("Runtime Properties")]
	FP BoostAmount;
	int Score;
	list<FPVector3> Segments;
	list<PhysicsQueryRef> SegmentQueries;

	[Header("Movement State")]
	FP SteerAmount;
	bool IsBraking;
	bool IsBoosting;
}
```

Key aspects:
- `BoostAmount`: Current boost energy (0-100)
- `Score`: Player's current score (length of trail)
- `Segments`: List of positions forming the ship's trail
- `SegmentQueries`: Physics queries for collision detection
- Movement state flags for steering, braking, and boosting

### Player Link

The PlayerLink connects ships to players:

```qtn
component PlayerLink
{
	player_ref Player;
}

struct PlayerData
{
	bool ready;
	Int16 points;
}
```

### Global State

The global state manages game-wide information:

```qtn
global
{
	FrameTimer clock;
	dictionary<Int32, PlayerData> playerData;
	
	FrameTimer StateTimer;
    GameState DelayedState;
    
    GameState CurrentState;
    GameState PreviousState;
}
```

## Core Systems

### 1. Game State System

The `GameStateSystem` manages the game flow:

```csharp
unsafe class GameStateSystem : SystemMainThread
{
    static readonly ReadOnlyDictionary<GameState, Type> stateTable =
        new(new Dictionary<GameState, Type>()
        {
            { GameState.Lobby, typeof(IGameState_Lobby) },
            { GameState.Pregame, typeof(IGameState_Pregame) },
            { GameState.Intro, typeof(IGameState_Intro) },
            { GameState.Countdown, typeof(IGameState_Countdown) },
            { GameState.Game, typeof(IGameState_Game) },
            { GameState.Outro, typeof(IGameState_Outro) },
            { GameState.Postgame, typeof(IGameState_Postgame) }
        });
    
    // Implementation details...
    
    public static void SetStateDelayed(Frame f, GameState state, FP delay)
    {
        f.Global->DelayedState = state;
        f.Global->StateTimer = FrameTimer.FromSeconds(f, delay);
    }

    public static void SetState(Frame f, GameState state)
    {
        f.Global->CurrentState = state;
    }
}
```

This system manages state transitions and enables/disables other systems based on the current game state.

### 2. Ship Movement System

The `ShipMovementSystem` handles ship movement and trail mechanics:

```csharp
unsafe class ShipMovementSystem : SystemMainThreadFilter<ShipFilter>, IGameState_Game
{
    public override void Update(Frame f, ref ShipFilter filter)
    {
        // Process player input
        Input* input = f.GetPlayerInput(filter.Link->Player);
        
        // Update ship state based on input
        filter.Player->SteerAmount = FPMath.Clamp(input->steer, -1, 1);
        filter.Player->IsBoosting = input->boost && filter.Player->BoostAmount > 0;
        filter.Player->IsBraking = input->brake;
        
        // Apply steering
        FP steerRate = filter.Player->SteerAmount * spec.steerRate;
        if (filter.Player->IsBraking) steerRate /= 2;
        filter.Transform->Rotation *= FPQuaternion.AngleAxis(steerRate * f.DeltaTime, FPVector3.Up);
        
        // Apply movement
        FP speed = filter.Player->IsBoosting ? spec.speedBoosting : input->brake ? spec.speedBraking : spec.speedNormal;
        
        // Handle boost consumption
        if (filter.Player->IsBoosting)
        {
            filter.Player->BoostAmount -= spec.boostDrain * f.DeltaTime;
            if (filter.Player->BoostAmount < 0) filter.Player->BoostAmount = 0;
        }
        
        // Update position
        filter.Transform->Position += filter.Transform->Forward * speed * f.DeltaTime;
        
        // Orient to sphere surface
        Orient(f, filter.Transform, filter.Player);
        
        // Update trail segments
        // Implementation details...
    }
    
    // Additional methods...
}
```

### 3. Collision Systems

Collision detection is handled by a pair of systems:

```csharp
// Injection system creates physics queries
public unsafe class ShipCollisionInjectionSystem : SystemMainThread, IGameState_Game
{
    public override void Update(Frame f)
    {
        // Create linecast queries between segment points
        // Implementation details...
    }
}

// Retrieval system processes query results
public unsafe class ShipCollisionRetrievalSystem : SystemMainThread, IGameState_Game
{
    public override void Update(Frame f)
    {
        // Process linecast query results
        // Handle collisions between ships and trails
        // Implementation details...
    }
}
```

### 4. Pickup System

The `PickupSystem` manages collectible items:

```csharp
unsafe class PickupSystem<P> : SystemSignalsOnly, ISignalOnTriggerEnter3D, IGameState_Game where P : unmanaged, IComponent
{
    public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
    {
        // Handle pickup collection
        if (!f.TryGet(info.Other, out P pickup)) return;
        if (!f.Unsafe.TryGetPointer(info.Entity, out Ship* ship)) return;
        if (!f.TryGet(info.Entity, out PlayerLink link)) return;

        // Apply pickup effect based on type
        if (pickup is TrailPickup)
        {
            // Increase score
            int oldScore = ship->Score;
            ship->Score += ship->Score > 0 ? 5 : 2;
            f.Events.PlayerScoreChanged(link.Player, oldScore, ship->Score);
        }
        else if (pickup is BoostPickup)
        {
            // Add boost energy
            ship->BoostAmount += f.RuntimeConfig.boostPickupValue;
            if (ship->BoostAmount > 100) ship->BoostAmount = 100;
        }

        // Send event and spawn new pickup
        f.Events.PickupCollected(info.Entity, ComponentTypeId<P>.Id);
        f.Destroy(info.Other);

        if (f.ComponentCount<P>() < SpawnCap(f))
        {
            SpawnPickup(f);
        }
    }
    
    // Implementation details...
}
```

## Unity-Quantum Integration

The integration between Quantum and Unity happens primarily through:

1. **EntityView Components**: Create visual representations of Quantum entities
2. **Event Handling**: Process events from Quantum simulation to update visuals
3. **Input Processing**: Capture Unity input and send it to Quantum

Example of the ShipView class:

```csharp
public unsafe class ShipView : MonoBehaviour
{
    // Implementation details...
    
    private void Update()
    {
        // Get ship data from Quantum
        Ship* player = game.Frames.Predicted.Unsafe.GetPointer<Ship>(EntityRef);
        
        // Update visual representation based on simulation data
        // Implementation details...
        
        // Apply visual effects for boosting, steering, etc.
        // Implementation details...
    }
    
    // Event handlers for Quantum events
    void PlayerDataChangedCallback(EventPlayerDataChanged evt)
    {
        // Handle player data changes
        // Implementation details...
    }
    
    void PlayerVulnerableCallback(EventPlayerVulnerable evt)
    {
        // Handle player vulnerability changes
        // Implementation details...
    }
}
```

## Key Game Mechanics

### 1. Spherical Movement

Ships move on the surface of a sphere, with orientation automatically adjusted:

```csharp
public static void Orient(Frame f, Transform3D* tf, Ship* player)
{
    MapMeta mm = f.FindAsset<MapMeta>(f.Map.UserAsset.Id);

    FPVector3 n = mm.mapOrigin - tf->Position;
    tf->Position =
        (tf->Position - mm.mapOrigin).Normalized
        * (mm.mapRadius - spec.radius)
        + mm.mapOrigin;

    tf->Rotation = FPQuaternion.FromToRotation(tf->Up, n) * tf->Rotation;
}
```

### 2. Trail System

Ships leave a trail of segments behind them:

```csharp
Collections.QList<FPVector3> segs = f.ResolveList(filter.Player->Segments);

if (segs.Count < filter.Player->Score)
{
    segs.Add(filter.Transform->Position);
}

// Update segment positions
for (int i = segs.Count - 2; i >= 0; i--)
{
    MoveDistance(f, segs.GetPointer(i), segs.GetPointer(i + 1), spec.segmentDistance, spec.radius);
}
```

### 3. Reconnection Mechanic

Players can reconnect their trail to score points:

```csharp
// Check if this is a self-collision with the head segment
if (i == 0 && hit.Entity == ship.Entity && ship.Player->Score > 20)
{
    // Evaluate alignment quality
    ship.Player->Segments.Resolve(f, out var segs);
    FP dot = FPVector3.Dot(ship.Transform->Forward,
        (segs[1] - segs[0]).Normalized);
        
    if (dot > spec.connectThreshold)
    {
        // Award points based on trail length
        f.Global->playerData.Resolve(f, out var dict);
        dict.TryGetValuePointer(ship.Link->Player, out var pd);
        pd->points += (short)segs.Count;
        
        // Fire events and respawn player
        // Implementation details...
    }
}
```

## Game Configuration

The game is configured through several asset objects, primarily:

### ShipSpec

```csharp
public partial class ShipSpec : AssetObject
{
    public FP radius;
    public FP speedNormal;
    public FP speedBoosting;
    public FP speedBraking;
    public FP steerRate;
    public FP segmentDistance;
    public FP boostDrain;
    [Range(0, 1)] public FP connectThreshold;
    public FP despawnAfterConnectDelay;
}
```

### MapMeta

```csharp
public class MapMeta : AssetObject
{
    public FPVector3 mapOrigin;
    public FP mapRadius;
}
```

## How To Use These Notes

- Start with the Project Overview to understand the game's architecture
- Explore the Ship Movement System to understand the core mechanics
- Follow other documents based on specific features you're interested in
- Use the code examples as reference when implementing your own arena game

The focus is on presenting accurate code examples that can be used as templates for your own Quantum projects.
