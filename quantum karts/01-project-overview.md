# Quantum Karts Project Overview

This document provides a comprehensive overview of the Quantum Karts project, a multiplayer kart racing game built with Photon Quantum 3.0.2. These notes explain the project structure, core systems, and implementation details to help you understand how to create a kart racing game with Quantum's deterministic networking framework.

## Project Structure

Quantum Karts demonstrates a multiplayer kart racing game with the following organization:

### Core Simulation Code (Quantum)
- **Assets/QuantumUser/Simulation/Karts**: Contains all the deterministic simulation code
  - **Kart**: Core kart mechanics (driving, drifting, weapons, etc.)
  - **Gameplay**: Race system, tracks, and game state management
  - **AI**: AI driver implementation
  - **Util**: Utility functions and helpers

### Unity View Code
- **Assets/Scripts**: Contains Unity-side view code
  - **Controllers**: View representations of simulation elements
  - **Managers**: Game state management on the Unity side
  - **Menu**: UI and menu systems
  - **Util**: Unity-specific utility functions

## Key Features Demonstrated

1. **Kart Physics**: Deterministic kart movement system with drifting
2. **Race System**: Track layout, checkpoints, and race progression
3. **Weapons System**: Pickup and use of various game-altering powerups
4. **AI Drivers**: Computer-controlled racers with configurable difficulty
5. **Boost System**: Speed boosts from drifting and pickups
6. **Surface Effects**: Different surface types affecting kart handling

## Architecture Overview

Quantum Karts follows Quantum's core architecture principles:

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
- **Entities**: Dynamic game objects (karts, pickups, weapons)
- **Components**: Data containers attached to entities
- **Systems**: Logic that processes entities with specific components

### Networking Model

The predict/rollback networking model:
- **Prediction**: Each client predicts game state based on local input
- **Rollback**: When actual input arrives, state is corrected if necessary
- **Determinism**: Same input always produces the same output

## Core Systems Overview

### Kart System
```csharp
public unsafe class KartSystem : SystemMainThreadFilter<KartSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform3D* Transform3D;
        public Kart* Kart;
        public Wheels* Wheels;
        public KartInput* KartInput;
        public Drifting* Drifting;
        public RaceProgress* RaceProgress;
        public KartHitReceiver* KartHitReceiver;
    }
    
    public override void Update(Frame frame, ref Filter filter)
    {
        // Core kart update logic
        // ...
        
        filter.RaceProgress->Update(frame, filter);
        filter.KartInput->Update(frame, input);
        filter.Wheels->Update(frame);
        filter.Drifting->Update(frame, filter);
        filter.Kart->Update(frame, filter);
    }
    
    // Player management logic...
}
```

### Race System
```csharp
public unsafe class RaceSystem : SystemMainThread, ISignalOnTriggerEnter3D
{
    public override void Update(Frame frame)
    {
        UpdatePositions(frame);
        frame.Unsafe.GetPointerSingleton<Race>()->Update(frame);
    }
    
    public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
    {
        // Checkpoint and lap completion logic
        // ...
    }
    
    private void UpdatePositions(Frame f)
    {
        // Calculate race positions for all karts
        // ...
    }
}
```

### Input System

The input structure defines the player controls:

```qtn
input
{
    button Drift;
    button Powerup;
    button Respawn;
    byte Encoded;
}
```

This is mapped to Unity input in `LocalInput.cs`:

```csharp
public void PollInput(CallbackPollInput callback)
{
    Quantum.Input input = new Quantum.Input();

    input.Drift = UnityEngine.Input.GetButton("Jump");
    input.Powerup = UnityEngine.Input.GetButton("Fire1");
    input.Respawn = UnityEngine.Input.GetKey(KeyCode.R);

    var x = UnityEngine.Input.GetAxis("Horizontal");
    var y = UnityEngine.Input.GetAxis("Vertical");

    input.Direction = new Vector2(x, y).ToFPVector2();

    callback.SetInput(input, DeterministicInputFlags.Repeatable);
}
```

### AI System

Computer-controlled karts use an AIDriver component:

```csharp
public unsafe partial struct AIDriver
{
    public void Update(Frame frame, KartSystem.Filter filter, ref Input input)
    {
        // Get target checkpoint position
        // Calculate steering direction
        // Handle weapon usage
        // Apply inputs based on race situation
        
        FP steeringStrength = settings.SteeringCurve.Evaluate(FPMath.Abs(signedAngle));
        input.Direction = new FPVector2(FPMath.Clamp(-desiredDirection * steeringStrength, -1, 1), 1);
    }
}
```

## Quantum-Unity Integration

The integration between Quantum and Unity is handled through:
- **VisualKartSpawner**: Creates the visual representation of karts
- **EntityViews**: Connect Unity GameObjects to Quantum entities
- **Event Handlers**: Receive Quantum events for visual effects
- **Input Polling**: Capture Unity input for Quantum simulation

## Key Components

The kart entity consists of several interacting components:

- **Kart**: Handles physics, movement, and surface interactions
- **KartInput**: Processes and applies player input
- **Wheels**: Manages wheel physics and ground detection
- **Drifting**: Controls drift mechanics and related boosts
- **KartWeapons**: Manages weapon pickup and usage
- **RaceProgress**: Tracks race position, laps, and checkpoints

## Race Flow

The race goes through several states managed by the `Race` component:

1. **Waiting**: Players are joining and selecting karts
2. **Countdown**: Race is about to begin
3. **InProgress**: Race is active
4. **Finishing**: First player has finished, giving others time to complete
5. **Finished**: Race is over, showing results

## How To Use These Notes

- Start with the Project Overview to understand the game's architecture
- Explore the Kart Driving System to understand the core mechanics
- Follow other documents based on specific features you're interested in
- Use the code examples as reference when implementing your own kart racing game

The focus is on presenting accurate code examples that can be used as templates for your own Quantum projects.
