# Race Progression and Checkpoint System for AI

## Overview

The race progression and checkpoint system is a critical component for AI navigation in Quantum Karts. It allows bots to understand their position on the track, navigate between checkpoints, and make decisions based on the track layout. This document explains how the checkpoint system works and how it integrates with the AI.

## Key Components

### 1. RaceTrack Component

The `RaceTrack` component manages the overall track structure:

```csharp
// Conceptual structure based on the code seen
public unsafe partial struct RaceTrack
{
    public QList<EntityRef> Checkpoints;
    public sbyte TotalLaps;
    
    public QList<EntityRef> GetCheckpoints(Frame frame) 
    {
        return frame.ResolveList(Checkpoints);
    }
    
    public EntityRef GetCheckpointEntity(Frame frame, int index)
    {
        var checkpoints = GetCheckpoints(frame);
        return checkpoints[index % checkpoints.Count];
    }
    
    public FPVector3 GetCheckpointTargetPosition(Frame frame, int checkpointIndex, FP difficulty)
    {
        EntityRef checkpoint = GetCheckpointEntity(frame, checkpointIndex);
        Transform3D* transform = frame.Unsafe.GetPointer<Transform3D>(checkpoint);
        
        // Use difficulty to adjust target position (more difficult = better racing line)
        // This calculation would vary based on checkpoint layout
        
        return transform->Position + CalculateOptimalOffset(difficulty);
    }
    
    public void GetStartPosition(Frame frame, int driverIndex, out FPVector3 position, out FPQuaternion rotation)
    {
        // Calculate starting grid position based on driver index
        // This places karts in appropriate starting positions
    }
}
```

### 2. Checkpoint Component

The `Checkpoint` component represents individual checkpoints on the track:

```csharp
// Derived from usage in code
public unsafe partial struct Checkpoint
{
    public sbyte Index;
    public bool Finish;
}
```

### 3. RaceProgress Component

The `RaceProgress` component tracks each kart's progress around the track:

```csharp
public unsafe partial struct RaceProgress
{
    public sbyte TargetCheckpointIndex;
    public sbyte CurrentLap;
    public sbyte TotalLaps;
    public bool Finished;
    public QList<FP> LapTimes;
    public FP LapTimer;
    public sbyte Position;
    public FP FinishTime;
    public FP DistanceToCheckpoint;
    public bool LastWrongWay;
    
    // Methods
    public void Initialize(sbyte totalLaps);
    public void StartRace();
    public FP GetFinishTime();
    public void Update(Frame frame, KartSystem.Filter filter);
    public void SetRacePosition(sbyte position);
    public void UpdateDistanceToCheckpoint(Frame f, EntityRef entity, RaceTrack* raceTrack);
    public bool CheckpointReached(Frame frame, Checkpoint* checkpoint, EntityRef entity, out bool lap);
}
```

## AI Navigation Using Checkpoints

### Target Acquisition

The AI driver uses the checkpoint system to determine where to steer:

```csharp
public void UpdateTarget(Frame frame, EntityRef entity)
{
    RaceTrack* raceTrack = frame.Unsafe.GetPointerSingleton<RaceTrack>();
    RaceProgress* raceProgress = frame.Unsafe.GetPointer<RaceProgress>(entity);
    AIDriverSettings settings = frame.FindAsset(SettingsRef);

    // Get current target position
    TargetLocation = raceTrack->GetCheckpointTargetPosition(
        frame, 
        raceProgress->TargetCheckpointIndex, 
        settings.Difficulty
    );

    // Calculate next checkpoint index
    int nextIndex = raceProgress->TargetCheckpointIndex + 1;
    if (nextIndex >= raceTrack->GetCheckpoints(frame).Count) {
        nextIndex = 0;
    }

    // Get next target position for predictive steering
    NextTargetLocation = raceTrack->GetCheckpointTargetPosition(
        frame, 
        nextIndex, 
        settings.Difficulty
    );
}
```

### Checkpoint Transitions

When an AI passes through a checkpoint, its target is updated:

```csharp
// In RaceSystem.OnTriggerEnter3D
if (playerProgress->CheckpointReached(f, checkpoint, info.Entity, out bool lapCompleted))
{
    if (f.Unsafe.TryGetPointer(info.Entity, out AIDriver* drivingAI))
    {
        drivingAI->UpdateTarget(f, info.Entity);
    }
}
```

### Wrong Way Detection

The `RaceProgress` component includes wrong way detection, which helps prevent AI from going in the wrong direction:

```csharp
public bool CheckpointReached(Frame frame, Checkpoint* checkpoint, EntityRef entity, out bool lap)
{
    lap = false;

    bool wrongWay = (checkpoint->Index < TargetCheckpointIndex - 1) ||
                    (checkpoint->Index > TargetCheckpointIndex && !checkpoint->Finish);

    if (wrongWay != LastWrongWay)
    {
        LastWrongWay = wrongWay;
        AlertWrongWay(frame, entity);
    }

    if (wrongWay)
    {
        return false;
    }
    
    // Rest of checkpoint processing...
}
```

## Distance Calculations for Race Positioning

The system calculates each kart's distance to its target checkpoint for accurate race positioning:

```csharp
public void UpdateDistanceToCheckpoint(Frame f, EntityRef entity, RaceTrack* raceTrack)
{
    var checkpoint = raceTrack->GetCheckpointEntity(f, TargetCheckpointIndex);

    Transform3D* targetTransform = f.Unsafe.GetPointer<Transform3D>(checkpoint);
    Transform3D* ownTransform = f.Unsafe.GetPointer<Transform3D>(entity);

    DistanceToCheckpoint = FPVector3.Distance(targetTransform->Position, ownTransform->Position);
}
```

## Race Position Calculations

The `RaceSystem` class handles calculating race positions, which affects the AI's understanding of the race:

```csharp
private void UpdatePositions(Frame f)
{
    Race* race = f.Unsafe.GetPointerSingleton<Race>();

    if (f.Number % race->PositionCalcInterval != 0) { return; }

    ProgressWrappers.Clear();

    f.Unsafe.TryGetPointerSingleton(out RaceTrack* raceTrack);

    foreach (var pair in f.Unsafe.GetComponentBlockIterator<RaceProgress>())
    {
        pair.Component->UpdateDistanceToCheckpoint(f, pair.Entity, raceTrack);
        ProgressWrappers.Add(new() { RaceProgress = pair.Component, Entity = pair.Entity });
    }

    ProgressWrappers.Sort(raceProgressComparer);

    for (int i = 0; i < ProgressWrappers.Count; i++)
    {
        ProgressWrappers[i].RaceProgress->SetRacePosition((sbyte)(i + 1));
    }

    f.Events.OnPositionsUpdated();
}
```

The race position calculation logic prioritizes:
1. Finished karts (by finish time)
2. Current lap
3. Current checkpoint
4. Distance to current checkpoint

## Implications for AI Behavior

The checkpoint system influences AI behavior in several key ways:

1. **Predictive Steering**: AI uses both current and next checkpoints to smooth out racing lines.

2. **Difficulty-Based Positioning**: The `GetCheckpointTargetPosition` method uses the AI difficulty to determine the optimal racing line.

3. **Recovery from Wrong Direction**: Wrong way detection helps AI recover if they get turned around.

4. **Dynamic Target Updates**: As the AI passes checkpoints, its targets are automatically updated.

5. **Adaptive Racing Line**: By using the difficulty parameter, different AI drivers can take different racing lines through the same checkpoints.

## Performance Optimizations

1. **Interval-Based Updates**: Position calculations happen at intervals rather than every frame:
   ```csharp
   if (f.Number % race->PositionCalcInterval != 0) { return; }
   ```

2. **Efficient Distance Calculations**: Distance is calculated directly between transform positions rather than using more complex path calculations.

3. **Deterministic Logic**: All calculations are deterministic using Quantum's fixed-point math, ensuring consistent behavior across all clients.

## Implementation Best Practices

1. **Checkpoint Placement**: Place checkpoints at strategic locations (corners, straights) to guide AI effectively.

2. **Difficulty Tuning**: Adjust how much the difficulty parameter affects racing lines in `GetCheckpointTargetPosition`.

3. **Wrong Way Recovery**: Ensure checkpoints are sequenced correctly to avoid wrong way detection issues.

4. **Predictive Steering Balance**: Tune the AI's `PredictionRange` to balance between current and next checkpoint targeting.
