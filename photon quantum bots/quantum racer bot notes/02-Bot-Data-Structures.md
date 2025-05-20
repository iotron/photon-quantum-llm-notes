# Bot Data Structures and Components

## Bot Component

The Bot component is defined in the Quantum simulation and contains the essential data for controlling an AI racer:

```csharp
// Core Bot component structure (derived from prototypes)
public struct Bot {
    public EntityRef RacingLineCheckpoint;  // Reference to current checkpoint
    public EntityRef RacingLineReset;       // Reset position reference
    public AssetRef<BotConfig> Config;      // Reference to bot configuration
    public Input Input;                     // Current input state
    public int NickIndex;                   // Index for bot nickname
    public FP StartTimer;                   // Timer for delayed start
    public int RacelineIndex;               // Current position on raceline
    public int RacelineIndexReset;          // Reset position on raceline
    public AssetRef<CheckpointData> Raceline; // Reference to raceline data
    public FP MaxSpeed;                     // Current maximum speed
    public FP CurrentSpeed;                 // Current actual speed
}
```

The Bot component is tightly integrated with other racing game components:
- `Transform2D`: For positioning
- `PhysicsBody2D`: For physical simulation
- `Racer`: For racing-specific data

## BotConfig Asset

The BotConfig class inherits from AssetObject and contains parameters that define bot behavior:

```csharp
public class BotConfig : AssetObject {
    // Speed and movement parameters
    public FP MaxSpeed = 10;
    public FP RacelineSpeedFactor = 1;
    
    // Navigation parameters
    public FPVector2 OverlapRelativeOffset = new FPVector2(0, 0);
    public FP OverlapDistance = 3;
    public FP CheckpointDetectionDistance = 5;
    public FP CheckpointDetectionDotThreshold = FP._0_50;
    
    // Look-ahead behavior
    public FP LookAhead = FP._0_50;
    public bool SmoothLookAhead = false;
    public bool UseDirectionToNext;
    
    // Turning behavior
    public FP RadiansSlowdownThreshold = FP.PiOver4;
    public FP SlowdownFactor = FP._0_50;
    
    // Debug flag
    public bool Debug = true;
    
    // Bot update method
    public void UpdateBot(Frame f, ref BotSystem.Filter filter);
}
```

The `UpdateBot` method is the core behavior implementation that:
1. Processes checkpoint detection
2. Calculates the desired movement direction
3. Handles car avoidance
4. Sets appropriate inputs for acceleration and steering
5. Optionally, draws debug visualizations

## BotConfigContainer Asset

This container asset allows for managing multiple bot configurations in one place:

```csharp
public class BotConfigContainer : AssetObject {
    // Array of bot configurations
    public AssetRef<BotConfig>[] Configs;
    
    // Array of bot entity prefabs
    public AssetRef<EntityPrototype>[] Prefabs;
    
    // Bot nicknames for UI display
    public string[] Nicknames;
    
    // Bot spawning parameters
    public int MaxBots = 32;
    public FP BotStartInterval = 0;
    
    // Method to select a bot prefab
    public void GetBot(Frame f, PlayerRef player, out AssetRef<EntityPrototype> prototype);
}
```

This container supports spawning different types of bots with varied characteristics and appearances.

## CheckpointData Asset

The raceline that bots follow is defined in the CheckpointData asset:

```csharp
public class CheckpointData : AssetObject {
    // List of points defining the racing line
    public List<RacelineEntry> Raceline;
    
    // Reference rotation speed for the track
    public FP ReferenceRotationSpeed = 120;
    
    // Spatial distance between recorded points
    public FP DistanceBetweenMarks = 4;
}
```

Each `RacelineEntry` contains:
- `Position`: The 2D position on the track
- `DesiredSpeed`: The optimal speed at this position

## RacelineEntry Structure

```csharp
public struct RacelineEntry {
    public FP DesiredSpeed;    // Optimal speed at this point
    public FPVector2 Position; // Position on the track
}
```

These entries are created and recorded using the RacelineRecorder component during development, capturing an optimal racing line that bots will later follow.

## Input Structure

Bots use the same Input structure as players, allowing them to control vehicles through the same interface:

```csharp
public struct Input {
    public Button RacerAccel;     // Acceleration input
    public Button RacerBrake;     // Braking input
    public Button RacerLeft;      // Steering left
    public Button RacerRight;     // Steering right
    public Button RacerLeanLeft;  // Leaning left (for extra turning)
    public Button RacerLeanRight; // Leaning right (for extra turning)
    public Button RacerPitchUp;   // Pitch control for jumps
    public Button RacerPitchDown; // Pitch control for jumps
}
```

This approach ensures that bot-controlled vehicles and player-controlled vehicles use identical control mechanisms, providing fair competition.
