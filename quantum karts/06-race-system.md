# Quantum Karts Race System

This document explains the race system in Quantum Karts, covering track definition, checkpoints, race state management, and position tracking that form the core gameplay loop.

## Core Components

The race system consists of several interrelated components:

### Race Component

The `Race` component is the central singleton that manages race state:

```qtn
component Race
{
    [ExcludeFromPrototype] RaceState CurrentRaceState;
    [ExcludeFromPrototype] FrameTimer StateTimer;
    [ExcludeFromPrototype] FP CountdownTime;
    [ExcludeFromPrototype] byte SpawnedAIDrivers;
    [ExcludeFromPrototype] byte PositionCalcInterval;
}
```

### RaceTrack Component

The `RaceTrack` component defines the track layout and checkpoints:

```qtn
component RaceTrack
{
    [ExcludeFromPrototype] byte TotalLaps;
    [ExcludeFromPrototype] list<EntityRef> Checkpoints;
    [ExcludeFromPrototype] array<FPVector3>[16] StartPositions;
    [ExcludeFromPrototype] array<FPQuaternion>[16] StartRotations;
}
```

### Checkpoint Component

The `Checkpoint` component marks important track positions:

```qtn
component Checkpoint
{
    [ExcludeFromPrototype] byte Index;
    [ExcludeFromPrototype] AssetRef<CheckpointConfig> Config;
}
```

### RaceProgress Component

The `RaceProgress` component tracks each kart's progress in the race:

```qtn
component RaceProgress
{
    [ExcludeFromPrototype] byte CurrentLap;
    [ExcludeFromPrototype] byte TargetCheckpointIndex;
    [ExcludeFromPrototype] sbyte CurrentPosition;
    [ExcludeFromPrototype] FP DistanceToCheckpoint;
    [ExcludeFromPrototype] bool Finished;
    [ExcludeFromPrototype] FP FinishTime;
    [ExcludeFromPrototype] FP LapStartTime;
    [ExcludeFromPrototype] FP BestLapTime;
    [ExcludeFromPrototype] list<FP> LapTimes;
    
    byte TotalLaps;
}
```

## Race State Management

The race progresses through several states managed by the `Race` component:

```csharp
public enum RaceState : byte
{
    None = 0,
    Waiting,    // Players joining and getting ready
    Countdown,  // Counting down to race start
    InProgress, // Race is active
    Finishing,  // First player has finished, others can still finish
    Finished    // Race is over, showing results
}

public unsafe partial struct Race
{
    public void Update(Frame frame)
    {
        if (StateTimer.ExpiredOrNotRunning(frame))
        {
            switch (CurrentRaceState)
            {
                case RaceState.Countdown:
                    ChangeState(frame, RaceState.InProgress);
                    frame.Events.OnRaceStarted();
                    break;

                case RaceState.Finishing:
                    ChangeState(frame, RaceState.Finished);
                    frame.Events.OnRaceFinished();
                    break;
            }
        }
        else if (CurrentRaceState == RaceState.Countdown)
        {
            CountdownTime = StateTimer.RemainingTime(frame).AsFloat;
            frame.Events.OnCountdownUpdated(CountdownTime);
        }
    }

    public void ChangeState(Frame frame, RaceState state)
    {
        if (state == CurrentRaceState) { return; }

        var oldState = CurrentRaceState;
        CurrentRaceState = state;

        frame.Signals.RaceStateChanged(state);
        frame.Events.OnRaceStateChanged(oldState, state);

        switch (state)
        {
            case RaceState.Countdown:
                StateTimer = FrameTimer.FromSeconds(frame, frame.RuntimeConfig.CountdownTime);
                CountdownTime = frame.RuntimeConfig.CountdownTime;
                break;

            case RaceState.Finishing:
                StateTimer = FrameTimer.FromSeconds(frame, frame.RuntimeConfig.FinishingTime);
                break;
        }
    }
    
    public bool AllPlayersReady(Frame frame)
    {
        int readyCount = 0;
        int playerCount = 0;

        foreach (var (entity, playerLink) in frame.Unsafe.GetComponentBlockIterator<PlayerLink>())
        {
            playerCount++;
            
            if (playerLink->Ready)
            {
                readyCount++;
            }
        }

        return readyCount == playerCount && playerCount > 0;
    }
}
```

The race lifecycle follows this sequence:
1. **Waiting**: Players connect and select "Ready"
2. **Countdown**: 3-second countdown before race starts
3. **InProgress**: Race is active, karts compete
4. **Finishing**: First player has finished, others have limited time to finish
5. **Finished**: Race is complete, results are shown

## Checkpoint System

The checkpoint system tracks race progress and ensures karts follow the correct path:

```csharp
public unsafe partial struct RaceProgress
{
    public void Initialize(byte totalLaps)
    {
        TotalLaps = totalLaps;
        CurrentLap = 1;
        TargetCheckpointIndex = 0;
        CurrentPosition = -1;
        Finished = false;
    }

    public bool CheckpointReached(Frame frame, Checkpoint* checkpoint, EntityRef kartEntity, out bool lapCompleted)
    {
        lapCompleted = false;

        // Skip if not the target checkpoint
        if (checkpoint->Index != TargetCheckpointIndex)
        {
            return false;
        }

        // Update to next checkpoint
        if (frame.Unsafe.TryGetPointerSingleton(out RaceTrack* track))
        {
            byte nextCheckpoint = (byte)((checkpoint->Index + 1) % track->GetCheckpoints(frame).Count);
            
            // Complete lap if crossing finish line (checkpoint 0)
            if (nextCheckpoint == 0)
            {
                FP lapTime = frame.Time - LapStartTime;
                LapTimes.Add(frame, lapTime);
                
                if (BestLapTime <= 0 || lapTime < BestLapTime)
                {
                    BestLapTime = lapTime;
                }
                
                lapCompleted = true;
                LapStartTime = frame.Time;
                CurrentLap++;
                
                // Check for race finish
                if (CurrentLap > TotalLaps)
                {
                    Finished = true;
                    FinishTime = frame.Time;
                }
            }
            
            TargetCheckpointIndex = nextCheckpoint;
        }
        
        return true;
    }

    public void UpdateDistanceToCheckpoint(Frame frame, EntityRef kart, RaceTrack* track)
    {
        if (Finished) { return; }
        
        // Get the target checkpoint entity
        var checkpoints = track->GetCheckpoints(frame);
        var checkpointEntity = checkpoints[TargetCheckpointIndex];
        
        // Get transform components
        if (frame.Unsafe.TryGetPointer(checkpointEntity, out Transform3D* checkpointTransform) && 
            frame.Unsafe.TryGetPointer(kart, out Transform3D* kartTransform))
        {
            // Calculate distance to checkpoint
            FPVector3 checkpointCenter = checkpointTransform->Position;
            DistanceToCheckpoint = FPVector3.Distance(kartTransform->Position, checkpointCenter);
        }
    }

    public void Update(Frame frame, KartSystem.Filter filter)
    {
        // Update is called every frame on the kart
    }

    public FP GetFinishTime()
    {
        return Finished ? FinishTime : FP._0;
    }

    public void SetRacePosition(sbyte position)
    {
        if (position != CurrentPosition)
        {
            CurrentPosition = position;
        }
    }
}
```

Key aspects of the checkpoint system:
1. Checkpoints must be hit in sequence
2. Crossing the finish line (checkpoint 0) completes a lap
3. Distance to the next checkpoint is used for position calculation
4. Lap times are recorded for each completed lap

## Position Calculation

Race positions are calculated at regular intervals by the `RaceSystem`:

```csharp
private void UpdatePositions(Frame f)
{
    Race* race = f.Unsafe.GetPointerSingleton<Race>();

    if (f.Number % race->PositionCalcInterval != 0) { return; }

    ProgressWrappers.Clear();

    f.Unsafe.TryGetPointerSingleton(out RaceTrack* raceTrack);

    // Collect all racers and update their distance to next checkpoint
    foreach (var pair in f.Unsafe.GetComponentBlockIterator<RaceProgress>())
    {
        pair.Component->UpdateDistanceToCheckpoint(f, pair.Entity, raceTrack);
        ProgressWrappers.Add(new() { RaceProgress = pair.Component, Entity = pair.Entity });
    }

    // Sort racers by progress
    ProgressWrappers.Sort(raceProgressComparer);

    // Assign positions
    for (int i = 0; i < ProgressWrappers.Count; i++)
    {
        ProgressWrappers[i].RaceProgress->SetRacePosition((sbyte)(i + 1));
    }

    f.Events.OnPositionsUpdated();
}
```

The position calculation logic is in the `RaceProgressComparer`:

```csharp
private class RaceProgressComparer : IComparer<ProgressWrapper>
{
    int IComparer<ProgressWrapper>.Compare(ProgressWrapper A, ProgressWrapper B)
    {
        FP aTime = A.RaceProgress->GetFinishTime();
        FP bTime = B.RaceProgress->GetFinishTime();

        // both finished
        if (aTime > 0 && bTime > 0)
            return aTime.CompareTo(bTime);

        // other finished
        if (aTime > 0 != bTime > 0)
            return aTime > 0 ? -1 : 1;

        // negate lap and checkpoint index comparisons because higher better
        int lapResult = A.RaceProgress->CurrentLap.CompareTo(B.RaceProgress->CurrentLap);
        if (lapResult != 0) return -lapResult;

        int checkpointResult = A.RaceProgress->TargetCheckpointIndex.CompareTo(B.RaceProgress->TargetCheckpointIndex);
        if (checkpointResult != 0) return -checkpointResult;

        int distanceResult = A.RaceProgress->DistanceToCheckpoint.CompareTo(B.RaceProgress->DistanceToCheckpoint);
        return distanceResult != 0 ? distanceResult : -1;
    }
}
```

This sorting logic prioritizes:
1. Finished racers (by finish time)
2. Current lap (higher is better)
3. Current checkpoint (higher is better)
4. Distance to next checkpoint (lower is better)

## Checkpoint Detection

Checkpoints are detected using Quantum's trigger system:

```csharp
public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
{
    if (f.Unsafe.TryGetPointer<RaceProgress>(info.Entity, out var playerProgress) == false)
        return;

    if (f.Unsafe.TryGetPointer<Checkpoint>(info.Other, out var checkpoint) == false)
        return;

    Race* race = f.Unsafe.GetPointerSingleton<Race>();
    f.Unsafe.TryGetPointerSingleton<RaceTrack>(out RaceTrack* track);

    bool alreadyFinished = playerProgress->Finished;

    if (playerProgress->CheckpointReached(f, checkpoint, info.Entity, out bool lapCompleted))
    {
        if (f.Unsafe.TryGetPointer(info.Entity, out AIDriver* drivingAI))
        {
            drivingAI->UpdateTarget(f, info.Entity);
        }
    }

    if (alreadyFinished)
    {
        return;
    }

    if (lapCompleted) { f.Events.OnPlayerCompletedLap(info.Entity); }

    if (playerProgress->Finished)
    {
        f.Events.OnPlayerFinished(info.Entity);
        f.Signals.PlayerFinished(info.Entity);
    }

    if (playerProgress->Finished && race->CurrentRaceState == RaceState.InProgress)
    {
        FirstPlayerFinished(f, info.Entity);
    }
}

private void FirstPlayerFinished(Frame f, EntityRef kartEntity)
{
    Race* race = f.Unsafe.GetPointerSingleton<Race>();
    race->ChangeState(f, RaceState.Finishing);
    race->StateTimer = FrameTimer.FromSeconds(f, f.RuntimeConfig.FinishingTime);
    f.Events.OnFirstPlayerFinish(kartEntity);
}
```

This system:
1. Detects when karts pass through checkpoint triggers
2. Updates progress tracking
3. Handles lap completion
4. Manages race completion when the final lap is finished

## Track Definition

Tracks are defined through the `RaceTrack` component, which includes:

```csharp
public unsafe partial struct RaceTrack
{
    public QList<EntityRef> GetCheckpoints(Frame frame)
    {
        return frame.ResolveList(Checkpoints);
    }
    
    public void GetStartPosition(Frame frame, int index, out FPVector3 position, out FPQuaternion rotation)
    {
        index = FPMath.Clamp(index, 0, StartPositions.Length - 1);
        
        position = StartPositions.GetPointer(index)->Value;
        rotation = StartRotations.GetPointer(index)->Value;
    }
    
    public FPVector3 GetCheckpointTargetPosition(Frame frame, int checkpointIndex, int difficultyLevel)
    {
        var checkpoints = GetCheckpoints(frame);
        var checkpoint = checkpoints[checkpointIndex % checkpoints.Count];
        
        if (frame.Unsafe.TryGetPointer(checkpoint, out Transform3D* transform) && 
            frame.Unsafe.TryGetPointer(checkpoint, out Checkpoint* checkpointComp))
        {
            var config = frame.FindAsset(checkpointComp->Config);
            
            // Get position offset based on difficulty
            FPVector3 offset = config.GetAITargetOffset(difficultyLevel);
            
            return transform->Position + transform->TransformDirection(offset);
        }
        
        return FPVector3.Zero;
    }
}
```

The track definition includes:
1. An ordered list of checkpoint entities
2. Start positions for each kart
3. Target racing lines for AI drivers of different skill levels

## Race Events

The race system communicates with the Unity view through several events:

```csharp
// Race state events
frame.Events.OnRaceStateChanged(oldState, state);
frame.Events.OnRaceStarted();
frame.Events.OnRaceFinished();
frame.Events.OnCountdownUpdated(CountdownTime);

// Player events
frame.Events.OnPlayerCompletedLap(info.Entity);
frame.Events.OnPlayerFinished(info.Entity);
frame.Events.OnFirstPlayerFinish(kartEntity);
frame.Events.OnPositionsUpdated();
```

These events are handled by Unity components to update:
1. UI elements (countdown, position display, lap counter)
2. Camera behavior
3. Music and sound effects
4. Post-race results screen

## Respawn System

The race system includes a respawn mechanism for karts that go off-track or get stuck:

```csharp
public unsafe class RespawnSystem : SystemMainThreadFilter<RespawnSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public RespawnMover* RespawnMover;
        public Transform3D* Transform3D;
        public RaceProgress* RaceProgress;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Find track and get current checkpoint
        if (!frame.Unsafe.TryGetPointerSingleton(out RaceTrack* track))
            return;

        byte checkpointIndex = filter.RaceProgress->TargetCheckpointIndex;
        
        // Get previous checkpoint (for respawn position)
        int prevIndex = checkpointIndex - 1;
        if (prevIndex < 0)
        {
            var checkpoints = track->GetCheckpoints(frame);
            prevIndex = checkpoints.Count - 1;
        }
        
        // Get respawn position and rotation
        FPVector3 respawnPos = FPVector3.Zero;
        FPQuaternion respawnRot = FPQuaternion.Identity;
        
        var checkpoints = track->GetCheckpoints(frame);
        var checkpointEntity = checkpoints[prevIndex];
        
        if (frame.Unsafe.TryGetPointer(checkpointEntity, out Transform3D* checkpointTransform) &&
            frame.Unsafe.TryGetPointer(checkpointEntity, out Checkpoint* checkpoint))
        {
            var config = frame.FindAsset(checkpoint->Config);
            
            // Get respawn transforms
            respawnPos = checkpointTransform->Position + checkpointTransform->TransformDirection(config.RespawnOffset);
            respawnRot = checkpointTransform->Rotation * config.RespawnRotation;
        }
        
        // Apply respawn
        filter.Transform3D->Position = respawnPos;
        filter.Transform3D->Rotation = respawnRot;
        
        // Reset physics
        if (frame.Unsafe.TryGetPointer(filter.Entity, out Kart* kart))
        {
            kart->Velocity = FPVector3.Zero;
            kart->ExternalForce = FPVector3.Zero;
        }
        
        // Add temporary invulnerability
        frame.Add<Invulnerable>(filter.Entity);
        
        // Remove respawn component
        frame.Remove<RespawnMover>(filter.Entity);
        
        // Send event
        frame.Events.OnKartRespawned(filter.Entity);
    }
}
```

This system:
1. Places karts at the last checkpoint they passed
2. Resets physics state
3. Adds temporary invulnerability
4. Can be triggered manually (respawn button) or automatically (stuck detection)

## Track Decoration

While not directly part of the race mechanics, tracks include various decorative and functional elements:

1. **Surfaces**: Different driving surfaces with unique physics properties
2. **Decoration**: Static meshes like trees, barriers, and scenery
3. **Boost Pads**: Special triggers that give karts a temporary boost
4. **Jump Pads**: Launch karts into the air
5. **Hazards**: Moving or static obstacles

These are all synchronized within the Quantum simulation to ensure deterministic behavior.

## Best Practices

1. **Clear Checkpoint Placement**: Position checkpoints to create a clear racing path
2. **Equal Start Positions**: Balance starting positions for fairness
3. **Deterministic Triggers**: Use Quantum's trigger system for consistent checkpoint detection
4. **Regular Position Updates**: Calculate positions at fixed intervals to save performance
5. **Responsive Respawn**: Place respawn points to minimize player frustration
6. **Multiple Race States**: Use distinct states to manage the race lifecycle
7. **Completion Timeout**: Give slower players a chance to finish after the winner
