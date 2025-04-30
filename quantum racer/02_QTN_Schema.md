# Quantum Typescripts (.qtn) Schema Reference

Quantum Racer uses QTN (Quantum TypeScript) files to define the core structure of the game's entities, components, and systems. This file documents the schema used in Racer.qtn.

## Player Limit Configuration
```csharp
#pragma max_players 99
```

## Core Components

### RacerPlayerLink Component
Links a player reference to an entity.
```csharp
component RacerPlayerLink {
    PlayerRef Player;
}
```

### Racer Component
The main component for racer vehicles.
```csharp
component Racer {
    AssetRef<RacerConfig> Config;
    [ExcludeFromPrototype] AssetRef<RacerModifier> Modifier;
    [ExcludeFromPrototype] Int16 Lean;
    [ExcludeFromPrototype] FP Pitch;
    [ExcludeFromPrototype] FP VerticalSpeed;
    [ExcludeFromPrototype] Modifier ModifierValues;
    [ExcludeFromPrototype] EntityRef NextCheckpoint;
    [ExcludeFromPrototype] FPVector2 LastCheckpointPosition;
    [ExcludeFromPrototype] LapData LapData;
    FP Energy;
    [ExcludeFromPrototype] FP ResetTimer;
    EntityRef CarAhead;
    EntityRef CarBehind;
    int Position;
    bool Finished;
}
```

### Bot Component
AI bot configuration and state.
```csharp
component Bot {
    EntityRef RacingLineCheckpoint;
    EntityRef RacingLineReset;
    AssetRef<BotConfig> Config;
    Input Input;
    int NickIndex;
    FP StartTimer;
    int RacelineIndex;
    int RacelineIndexReset;
    AssetRef<CheckpointData> Raceline;
    FP MaxSpeed;
    FP CurrentSpeed;
}
```

### Checkpoint Component
Track checkpoints that racers must pass through.
```csharp
component Checkpoint {
    EntityRef Next;
    EntityRef RacelineRef;
    Boolean Finish;
    [ExcludeFromPrototype] FPVector2 DirectionToNext;
}
```

### RaceManager Singleton
Manages the overall race state.
```csharp
singleton component RaceManager {
    EntityRef StartCheckpoint;
    EntityRef StartBotCheckpoint;
    FP RaceTime;
    RaceState State;
    list<EntityRef> Vehicles;
    int FinishedCount;
}
```

## Input Definition
```csharp
input {
    button RacerAccel;
    button RacerBrake;
    button RacerLeft;
    button RacerRight;
    button RacerLeanLeft;
    button RacerLeanRight;
    button RacerPitchUp;
    button RacerPitchDown;
}
```

## Structs

### Modifier
Modifies racer characteristics.
```csharp
struct Modifier {
    FP AccelMultiplier;
    FP FrictionMultiplier;
    FP MaxSpeedMultiplier;
}
```

### LapData
Tracks lap and checkpoint information.
```csharp
struct LapData {
    [ExcludeFromPrototype] Int32 Laps;
    [ExcludeFromPrototype] Int32 Checkpoints;
    [ExcludeFromPrototype] FP TotalDistance;
    [ExcludeFromPrototype] FP LapTime;
    [ExcludeFromPrototype] FP LastLapTime;
    [ExcludeFromPrototype] FP BestLap;
}
```

### RacelineEntry
Racing line guidance for AI bots.
```csharp
[Serializable]
struct RacelineEntry {
    FP DesiredSpeed;
    FPVector2 Position;
}
```

## Enums

### RaceState
Represents the current state of the race.
```csharp
enum RaceState {
    Start, Running, Finished
}
```

## Signals
Trigger special gameplay events.
```csharp
signal Spawn(PlayerRef player, BotConfig botConfig);
signal Respawn(EntityRef entity, Racer* racer, bool revertPosition);
signal Reset(EntityRef entity, Racer* racer);
```

## Events
Notify about specific gameplay events.
```csharp
event Bump {
    EntityRef Entity;
    Int32 Static;
}

event VehicleBump {
    EntityRef Entity;
    EntityRef Other;
    nothashed FPVector2 Point;
}

event Jump {
    EntityRef Entity;
}

event JumpLand {
    EntityRef Entity;
}

event Death {
    EntityRef Entity;
}

event Respawn {
    EntityRef Entity;
}
```

## Usage Notes
- `[ExcludeFromPrototype]` fields are runtime values not serialized in entity prototypes
- `FP` represents fixed-point numbers for deterministic physics
- `EntityRef` is a reference to another entity in the game
- `AssetRef<T>` is a reference to a configured asset
