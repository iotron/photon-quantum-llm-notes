# Quantum Karts AI System

This document explains the AI driver system in Quantum Karts, covering how computer-controlled karts navigate the track, make racing decisions, and provide challenging opponents for players.

## Core Components

The AI system consists of several interconnected components:

### AIDriver Component

The `AIDriver` component is the central element that controls computer-driven karts:

```qtn
component AIDriver {
    [ExcludeFromPrototype] FP StationaryTime;
    [ExcludeFromPrototype] FP LastWeaponTime;
    [ExcludeFromPrototype] FPVector3 TargetLocation;
    [ExcludeFromPrototype] FPVector3 NextTargetLocation;
    [ExcludeFromPrototype] FP KartAheadDistance;
    [ExcludeFromPrototype] FP KartBehindDistance;
    [ExcludeFromPrototype] byte AIIndex;
    
    asset_ref<AIDriverSettings> SettingsRef;
}
```

### AIDriverSettings Asset

The `AIDriverSettings` asset defines the behavior characteristics of AI drivers:

```csharp
public unsafe partial class AIDriverSettings : AssetObject
{
    [Header("Race Data")]
    public AssetRef<KartStats> KartStats;
    public AssetRef<KartVisuals> KartVisuals;
    
    [Header("AI Behavior")]
    [Range(0, 5)]
    public int Difficulty = 2;
    
    public FP PredictionRange = 5;
    public FP DriftingAngle = 45;
    public FP DriftingStopAngle = 15;
    
    public FPAnimationCurve SteeringCurve;
    
    [Header("Weapon Usage")]
    public FP WeaponUseChance = FP._0_75;
    public FP MinWeaponInterval = 1;
}
```

## AI Driver Implementation

The core AI logic is implemented in the `AIDriver` component's `Update` method:

```csharp
public unsafe partial struct AIDriver
{
    public void Update(Frame frame, KartSystem.Filter filter, ref Input input)
    {
        AIDriverSettings settings = frame.FindAsset(SettingsRef);

        // Calculate distances between current target and next target
        FP distance = FPVector3.Distance(TargetLocation, filter.Transform3D->Position);
        FP distanceNext = FPVector3.Distance(TargetLocation, NextTargetLocation);
        
        // Calculate how much to look ahead based on settings
        FP predictionAmount = FPMath.InverseLerp(distance, distanceNext, settings.PredictionRange);

        // Calculate direction vectors
        FPVector3 toWaypoint = TargetLocation - filter.Transform3D->Position;
        FPVector3 toNextWaypoint = NextTargetLocation - filter.Transform3D->Position;

        // Remove vertical component for 2D steering calculations
        FPVector3 flatVelocity = filter.Kart->Velocity;
        flatVelocity.Y = 0;
        toWaypoint.Y = 0;
        toNextWaypoint.Y = 0;

        // Check if kart is stuck (low speed for too long)
        StationaryTime = flatVelocity.SqrMagnitude < FP._7 ? StationaryTime + frame.DeltaTime : 0;

        if (StationaryTime > 5)
        {
            // Trigger respawn if stuck for too long
            input.Respawn = true;
            StationaryTime = 0;
        }

        // Handle weapon usage
        if (frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
        {
            LastWeaponTime += frame.DeltaTime;

            if (weapons->HeldWeapon != default
                && LastWeaponTime > settings.MinWeaponInterval
                && frame.RNG->NextFP() < settings.WeaponUseChance
                && frame.FindAsset(weapons->HeldWeapon).AIShouldUse(frame, filter.Entity))
            {
                input.Powerup = true;
                LastWeaponTime = 0;
            }
        }

        // Calculate steering target by blending current and next waypoint
        FPVector3 targetDirection = FPVector3.Lerp(toWaypoint, toNextWaypoint, predictionAmount).Normalized;

        // Calculate turn angle and direction
        FP turnAngle = FPVector3.Angle(toWaypoint, toNextWaypoint);
        FP signedAngle = FPVector3.SignedAngle(targetDirection, flatVelocity, FPVector3.Up);
        FP desiredDirection = FPMath.Sign(signedAngle);

        // Handle drifting input
        if (frame.Unsafe.TryGetPointer(filter.Entity, out Drifting* drifting))
        {
            bool shouldStartDrift = turnAngle >= settings.DriftingAngle && !drifting->IsDrifting;
            bool shouldEndDrift = turnAngle < settings.DriftingStopAngle && drifting->IsDrifting;

            input.Drift = !drifting->IsDrifting && shouldStartDrift || drifting->IsDrifting && shouldEndDrift;
        }

        // Calculate steering intensity based on angle
        FP steeringStrength = settings.SteeringCurve.Evaluate(FPMath.Abs(signedAngle));

        // Set final input values
        input.Direction = new FPVector2(FPMath.Clamp(-desiredDirection * steeringStrength, -1, 1), 1);
    }

    public void UpdateTarget(Frame frame, EntityRef entity)
    {
        RaceTrack* raceTrack = frame.Unsafe.GetPointerSingleton<RaceTrack>();
        RaceProgress* raceProgress = frame.Unsafe.GetPointer<RaceProgress>(entity);

        AIDriverSettings settings = frame.FindAsset(SettingsRef);

        // Get current target checkpoint
        TargetLocation = raceTrack->GetCheckpointTargetPosition(frame, raceProgress->TargetCheckpointIndex, settings.Difficulty);

        // Get next checkpoint for look-ahead
        int nextIndex = raceProgress->TargetCheckpointIndex + 1;

        if (nextIndex >= raceTrack->GetCheckpoints(frame).Count)
        {
            nextIndex = 0;
        }

        NextTargetLocation = raceTrack->GetCheckpointTargetPosition(frame, nextIndex, settings.Difficulty);
        
        // Update kart proximity awareness
        UpdateNearbyKarts(frame, entity);
    }
    
    private void UpdateNearbyKarts(Frame frame, EntityRef entity)
    {
        KartAheadDistance = FP.MaxValue;
        KartBehindDistance = FP.MaxValue;
        
        if (!frame.Unsafe.TryGetPointer(entity, out Transform3D* transform))
        {
            return;
        }
        
        // Check all karts to find nearest ahead and behind
        foreach (var (otherEntity, kart) in frame.Unsafe.GetComponentBlockIterator<Kart>())
        {
            if (otherEntity == entity) { continue; }
            
            if (frame.Unsafe.TryGetPointer(otherEntity, out Transform3D* otherTransform) && 
                frame.Unsafe.TryGetPointer(otherEntity, out RaceProgress* otherProgress) &&
                frame.Unsafe.TryGetPointer(entity, out RaceProgress* progress))
            {
                // Get vectors and distance
                FPVector3 toOtherKart = otherTransform->Position - transform->Position;
                FP distance = toOtherKart.Magnitude;
                
                // Check if ahead or behind based on race position
                if (otherProgress->CurrentPosition < progress->CurrentPosition)
                {
                    // Kart is ahead in race
                    KartAheadDistance = FPMath.Min(KartAheadDistance, distance);
                }
                else if (otherProgress->CurrentPosition > progress->CurrentPosition)
                {
                    // Kart is behind in race
                    KartBehindDistance = FPMath.Min(KartBehindDistance, distance);
                }
                else
                {
                    // Same position, use dot product to determine ahead/behind
                    FP dot = FPVector3.Dot(transform->Forward, toOtherKart.Normalized);
                    
                    if (dot > 0)
                    {
                        // Kart is ahead spatially
                        KartAheadDistance = FPMath.Min(KartAheadDistance, distance);
                    }
                    else
                    {
                        // Kart is behind spatially
                        KartBehindDistance = FPMath.Min(KartBehindDistance, distance);
                    }
                }
            }
        }
    }
}
```

## AI Integration with Race System

AI drivers are created and managed by the `KartSystem` class:

```csharp
public unsafe class KartSystem : SystemMainThreadFilter<KartSystem.Filter>, ISignalRaceStateChanged
{
    // Other implementations...
    
    public void RaceStateChanged(Frame frame, RaceState state)
    {
        if (state == RaceState.Waiting)
        {
            SpawnAIDrivers(frame);
            return;
        }

        if (state == RaceState.Countdown && frame.RuntimeConfig.FillWithAI)
        {
            FillWithAI(frame);
            return;
        }
    }
    
    private void ToggleKartEntityAI(Frame frame, EntityRef kartEntity, bool useAI, AssetRef<AIDriverSettings> settings = default)
    {
        if (kartEntity == default) { return; }

        if (useAI)
        {
            AddResult result = frame.Add<AIDriver>(kartEntity);

            if (result != 0)
            {
                AIDriver* drivingAI = frame.Unsafe.GetPointer<AIDriver>(kartEntity);

                if (settings == default)
                {
                    RaceSettings rs = frame.FindAsset(frame.RuntimeConfig.RaceSettings);
                    settings = rs.GetRandomAIConfig(frame);
                }

                drivingAI->SettingsRef = settings;
                drivingAI->UpdateTarget(frame, kartEntity);
            }
        }
        else if (frame.Unsafe.TryGetPointer(kartEntity, out AIDriver* ai))
        {
            frame.Remove<AIDriver>(kartEntity);
        }
    }
    
    private void SpawnAIDriver(Frame frame, AssetRef<AIDriverSettings> driverAsset)
    {
        if (driverAsset == null)
        {
            RaceSettings rs = frame.FindAsset(frame.RuntimeConfig.RaceSettings);
            driverAsset = rs.GetRandomAIConfig(frame);
        }

        var driverData = frame.FindAsset(driverAsset);
        EntityRef kartEntity = SpawnKart(frame, driverData.KartVisuals, driverData.KartStats);
        frame.Add<AIDriver>(kartEntity);

        if (frame.Unsafe.TryGetPointer(kartEntity, out AIDriver* ai) && frame.Unsafe.TryGetPointerSingleton(out Race* race))
        {
            ai->AIIndex = race->SpawnedAIDrivers++;
        }

        ToggleKartEntityAI(frame, kartEntity, true, driverAsset);
    }
    
    private void SpawnAIDrivers(Frame frame)
    {
        RaceSettings rs = frame.FindAsset(frame.RuntimeConfig.RaceSettings);
        byte count = frame.RuntimeConfig.AICount;

        for (int i = 0; i < count; i++)
        {
            SpawnAIDriver(frame, rs.GetRandomAIConfig(frame));
        }
    }
    
    private void FillWithAI(Frame frame)
    {
        int playerCount = frame.ComponentCount<Kart>();
        int missingDrivers = frame.RuntimeConfig.DriverCount - playerCount;

        if (missingDrivers <= 0)
        {
            return;
        }

        RaceSettings rs = frame.FindAsset(frame.RuntimeConfig.RaceSettings);

        for (int i = 0; i < missingDrivers; i++)
        {
            SpawnAIDriver(frame, rs.GetRandomAIConfig(frame));
        }
    }
    
    public void PlayerFinished(Frame f, EntityRef entity)
    {
        // When a player finishes, convert them to AI
        ToggleKartEntityAI(f, entity, true);
    }
}
```

AI drivers are automatically created in several scenarios:
1. When the race starts, based on `AICount` setting
2. To fill empty slots up to `DriverCount` when the race begins
3. When a player disconnects, their kart is taken over by AI
4. When a player finishes the race, their kart is controlled by AI

## Checkpoint Target Positions

The `RaceTrack` component provides target positions for AI drivers based on difficulty:

```csharp
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
```

Each checkpoint defines multiple target positions based on difficulty:

```csharp
public partial class CheckpointConfig : AssetObject
{
    public FPVector3[] TargetOffsets = new FPVector3[6];
    
    public FPVector3 GetAITargetOffset(int difficulty)
    {
        difficulty = FPMath.Clamp(difficulty, 0, 5);
        return TargetOffsets[difficulty];
    }
}
```

This allows for:
1. Optimal racing lines for higher difficulty AI
2. Suboptimal paths for lower difficulty AI
3. Different lines based on kart type and characteristics

## Difficulty Levels

AI difficulty is determined by several factors:

### 1. Steering Curve

The `SteeringCurve` defines how aggressively the AI responds to angles:

```csharp
// Example steering curves
// Low difficulty - gentle, slow response
lowDifficulty.SteeringCurve.AddKey(0, FP._0);
lowDifficulty.SteeringCurve.AddKey(45, FP._0_25);
lowDifficulty.SteeringCurve.AddKey(90, FP._0_50);
lowDifficulty.SteeringCurve.AddKey(180, FP._0_75);

// High difficulty - sharp, responsive steering
highDifficulty.SteeringCurve.AddKey(0, FP._0);
highDifficulty.SteeringCurve.AddKey(20, FP._0_50);
highDifficulty.SteeringCurve.AddKey(45, FP._0_75);
highDifficulty.SteeringCurve.AddKey(90, FP._1);
```

### 2. Prediction Range

How far ahead the AI looks to anticipate turns:

```csharp
// Low difficulty - minimal look-ahead
lowDifficulty.PredictionRange = FP._2;

// High difficulty - extensive look-ahead
highDifficulty.PredictionRange = FP._8;
```

### 3. Drifting Thresholds

When AI drivers initiate and release drifts:

```csharp
// Low difficulty - conservative drifting
lowDifficulty.DriftingAngle = 60;
lowDifficulty.DriftingStopAngle = 30;

// High difficulty - aggressive drifting
highDifficulty.DriftingAngle = 35;
highDifficulty.DriftingStopAngle = 10;
```

### 4. Target Racing Lines

The position on the track that AI drivers aim for:

```csharp
// Low difficulty - safer, wider racing line
lowDifficultyCheckpoint.TargetOffsets[0] = new FPVector3(0, 0, 0);

// High difficulty - optimal racing line
highDifficultyCheckpoint.TargetOffsets[5] = new FPVector3(-1.5f, 0, 0);
```

### 5. Weapon Usage

How often and strategically AI uses weapons:

```csharp
// Low difficulty - random weapon usage
lowDifficulty.WeaponUseChance = FP._0_30;
lowDifficulty.MinWeaponInterval = 4;

// High difficulty - strategic weapon usage
highDifficulty.WeaponUseChance = FP._0_90;
highDifficulty.MinWeaponInterval = 1;
```

## AI Behavior Patterns

AI drivers exhibit several behavior patterns:

### 1. Path Following

The core behavior is following checkpoint targets:

```csharp
// Calculate steering target
FPVector3 targetDirection = FPVector3.Lerp(toWaypoint, toNextWaypoint, predictionAmount).Normalized;

// Calculate steering input
FP signedAngle = FPVector3.SignedAngle(targetDirection, flatVelocity, FPVector3.Up);
FP desiredDirection = FPMath.Sign(signedAngle);
FP steeringStrength = settings.SteeringCurve.Evaluate(FPMath.Abs(signedAngle));

// Set steering input
input.Direction = new FPVector2(FPMath.Clamp(-desiredDirection * steeringStrength, -1, 1), 1);
```

### 2. Stuck Detection and Recovery

AI detects when it's not making progress and triggers respawn:

```csharp
// Check if kart is stuck
StationaryTime = flatVelocity.SqrMagnitude < FP._7 ? StationaryTime + frame.DeltaTime : 0;

if (StationaryTime > 5)
{
    // Trigger respawn
    input.Respawn = true;
    StationaryTime = 0;
}
```

### 3. Drift Control

AI initiates drifts on sharp turns and releases when the angle decreases:

```csharp
if (frame.Unsafe.TryGetPointer(filter.Entity, out Drifting* drifting))
{
    bool shouldStartDrift = turnAngle >= settings.DriftingAngle && !drifting->IsDrifting;
    bool shouldEndDrift = turnAngle < settings.DriftingStopAngle && drifting->IsDrifting;

    input.Drift = !drifting->IsDrifting && shouldStartDrift || drifting->IsDrifting && shouldEndDrift;
}
```

### 4. Weapon Usage

AI makes decisions about when to use weapons:

```csharp
if (frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
{
    LastWeaponTime += frame.DeltaTime;

    if (weapons->HeldWeapon != default
        && LastWeaponTime > settings.MinWeaponInterval
        && frame.RNG->NextFP() < settings.WeaponUseChance
        && frame.FindAsset(weapons->HeldWeapon).AIShouldUse(frame, filter.Entity))
    {
        input.Powerup = true;
        LastWeaponTime = 0;
    }
}
```

Each weapon type implements its own AI usage logic:

```csharp
// Example from WeaponBoost
public override bool AIShouldUse(Frame f, EntityRef aiKartEntity)
{
    // Use boost if not at max speed
    if (!f.Unsafe.TryGetPointer(aiKartEntity, out Kart* kart)) { return false; }
    return kart->GetNormalizedSpeed(f) < FP._0_90;
}

// Example from WeaponShield
public override bool AIShouldUse(Frame f, EntityRef aiKartEntity)
{
    // Activate shield when an incoming hazard is detected
    if (f.Unsafe.TryGetPointer(aiKartEntity, out KartHitReceiver* receiver))
    {
        return receiver->IncomingHazardDetected;
    }
    return false;
}

// Example from WeaponHazardSpawner
public override bool AIShouldUse(Frame f, EntityRef aiKartEntity)
{
    // Use offensive weapons when there's a kart ahead
    if (f.Unsafe.TryGetPointer(aiKartEntity, out AIDriver* driver))
    {
        return driver->KartAheadDistance < FP._10;
    }
    return false;
}
```

### 5. Awareness of Other Karts

AI tracks nearby karts for strategic decision making:

```csharp
private void UpdateNearbyKarts(Frame frame, EntityRef entity)
{
    KartAheadDistance = FP.MaxValue;
    KartBehindDistance = FP.MaxValue;
    
    // Implementation details...
    
    // Check all karts to find nearest ahead and behind
    foreach (var (otherEntity, kart) in frame.Unsafe.GetComponentBlockIterator<Kart>())
    {
        if (otherEntity == entity) { continue; }
        
        // Determine if kart is ahead or behind based on race position and spatial positioning
        // Set KartAheadDistance and KartBehindDistance accordingly
    }
}
```

This awareness is used for:
1. Deciding when to use offensive weapons
2. Deciding when to use defensive weapons
3. Potentially adjusting racing lines to block or overtake

## AI Performance Optimization

The AI system is optimized in several ways:

### 1. Filtered Updates

AI is only updated for karts with the required components:

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
}
```

### 2. Target Caching

Target positions are only updated when passing checkpoints:

```csharp
public void UpdateTarget(Frame frame, EntityRef entity)
{
    // Update target positions based on current checkpoint
}

// Called when checkpoint is reached
if (playerProgress->CheckpointReached(f, checkpoint, info.Entity, out bool lapCompleted))
{
    if (f.Unsafe.TryGetPointer(info.Entity, out AIDriver* drivingAI))
    {
        drivingAI->UpdateTarget(f, info.Entity);
    }
}
```

### 3. Limited Complexity

AI uses simple, efficient calculations:
- Direct angle calculations instead of complex path finding
- Fixed waypoints rather than dynamic navigation
- Limited lookahead to next checkpoint only

## Best Practices

1. **Difficulty Scaling**: Create a range of AI difficulties through configuration
2. **Checkpoint Design**: Place checkpoints to create good AI racing lines
3. **Runtime Conversion**: Allow AI to take over for disconnected or finished players
4. **Configurable Behavior**: Use asset-based configuration for different AI personalities
5. **Efficient Implementation**: Optimize AI calculations for performance
6. **Deterministic Logic**: Ensure AI behavior is fully deterministic for network play
7. **Strategic Decisions**: Implement weapon usage based on race situation
8. **Recovery Logic**: Add detection and recovery for stuck situations
