# AIDriver Component Implementation

## Overview

The `AIDriver` component is the core of the bot implementation in Quantum Karts. It's responsible for determining the steering, acceleration, drifting, and weapon usage for AI-controlled karts. The component is designed to be deterministic, ensuring that AI behavior is identical across all clients.

## Component Structure

The `AIDriver` component is defined in two files:

1. `AIDriver.qtn` - The Quantum component definition
2. `AIDriver.cs` - The implementation of the component's behavior

### AIDriver.qtn Definition

```csharp
component AIDriver {
    sbyte AIIndex;
    FPVector3 TargetLocation;
    FPVector3 NextTargetLocation;
    asset_ref<AIDriverSettings> SettingsRef;
    FP StationaryTime;
    FP LastWeaponTime;
}
```

This defines the data structure of the component with:
- `AIIndex`: Unique identifier for the AI driver
- `TargetLocation`: Current waypoint the AI is targeting
- `NextTargetLocation`: Next waypoint for predictive steering
- `SettingsRef`: Reference to the AIDriverSettings asset that controls behavior
- `StationaryTime`: Time the AI has been stationary (for detecting when stuck)
- `LastWeaponTime`: Time since last weapon usage (for cooldown)

## Core Functions

### Update Method

The `Update` method is called each frame and is responsible for generating the input for the AI driver:

```csharp
public void Update(Frame frame, KartSystem.Filter filter, ref Input input)
{
    AIDriverSettings settings = frame.FindAsset(SettingsRef);

    // Calculate distances to current and next waypoints
    FP distance = FPVector3.Distance(TargetLocation, filter.Transform3D->Position);
    FP distanceNext = FPVector3.Distance(TargetLocation, NextTargetLocation);
    FP predictionAmount = FPMath.InverseLerp(distance, distanceNext, settings.PredictionRange);

    // Create vectors to current and next waypoints
    FPVector3 toWaypoint = TargetLocation - filter.Transform3D->Position;
    FPVector3 toNextWaypoint = NextTargetLocation - filter.Transform3D->Position;

    // Ignore height differences for steering calculations
    FPVector3 flatVelocity = filter.Kart->Velocity;
    flatVelocity.Y = 0;
    toWaypoint.Y = 0;
    toNextWaypoint.Y = 0;

    // Handle being stuck
    StationaryTime = flatVelocity.SqrMagnitude < FP._7 ? StationaryTime + frame.DeltaTime : 0;
    if (StationaryTime > 5) {
        input.Respawn = true;
        StationaryTime = 0;
    }

    // Weapon usage logic
    if (frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons)) {
        LastWeaponTime += frame.DeltaTime;
        if (weapons->HeldWeapon != default && LastWeaponTime > FP._0_50 
            && frame.FindAsset(weapons->HeldWeapon).AIShouldUse(frame, filter.Entity)) {
            input.Powerup = true;
        }
    }

    // Calculate steering direction based on current and next waypoints
    FPVector3 targetDirection = FPVector3.Lerp(toWaypoint, toNextWaypoint, predictionAmount).Normalized;
    FP turnAngle = FPVector3.Angle(toWaypoint, toNextWaypoint);
    FP signedAngle = FPVector3.SignedAngle(targetDirection, flatVelocity, FPVector3.Up);
    FP desiredDirection = FPMath.Sign(signedAngle);

    // Drift management
    if (frame.Unsafe.TryGetPointer(filter.Entity, out Drifting* drifting)) {
        bool shouldStartDrift = turnAngle >= settings.DriftingAngle && !drifting->IsDrifting;
        bool shouldEndDrift = turnAngle < settings.DriftingStopAngle && drifting->IsDrifting;
        input.Drift = !drifting->IsDrifting && shouldStartDrift || drifting->IsDrifting && shouldEndDrift;
    }

    // Apply steering based on angle to target
    FP steeringStrength = settings.SteeringCurve.Evaluate(FPMath.Abs(signedAngle));
    input.Direction = new FPVector2(FPMath.Clamp(-desiredDirection * steeringStrength, -1, 1), 1);
}
```

### UpdateTarget Method

The `UpdateTarget` method updates the AI's target waypoints:

```csharp
public void UpdateTarget(Frame frame, EntityRef entity)
{
    RaceTrack* raceTrack = frame.Unsafe.GetPointerSingleton<RaceTrack>();
    RaceProgress* raceProgress = frame.Unsafe.GetPointer<RaceProgress>(entity);
    AIDriverSettings settings = frame.FindAsset(SettingsRef);

    // Get current target position
    TargetLocation = raceTrack->GetCheckpointTargetPosition(frame, raceProgress->TargetCheckpointIndex, settings.Difficulty);

    // Calculate next checkpoint index
    int nextIndex = raceProgress->TargetCheckpointIndex + 1;
    if (nextIndex >= raceTrack->GetCheckpoints(frame).Count) {
        nextIndex = 0;
    }

    // Get next target position
    NextTargetLocation = raceTrack->GetCheckpointTargetPosition(frame, nextIndex, settings.Difficulty);
}
```

## Key Behaviors

### Predictive Steering

The AI uses a combination of the current target waypoint and the next waypoint to smooth out its driving path. The `predictionAmount` determines how much the AI looks ahead, which is controlled by the `PredictionRange` parameter in the settings.

### Drift Management

The AI decides when to start and stop drifting based on the angle between the current and next waypoints:
- Starts drifting when the turn angle exceeds `DriftingAngle`
- Stops drifting when the turn angle falls below `DriftingStopAngle`

### Stationery Detection and Recovery

The AI monitors its velocity and accumulates a timer when it's not moving. If this timer exceeds 5 seconds, it triggers a respawn to recover from being stuck.

### Weapon Usage

The AI has a simple weapon usage strategy that:
1. Maintains a cooldown timer between weapon uses
2. Checks if the current weapon should be used via the `AIShouldUse` method
3. Activates the weapon when conditions are met

## Integration with KartSystem

The `AIDriver.Update` method is called from the `KartSystem.Update` method when an entity has an `AIDriver` component:

```csharp
if (frame.Unsafe.TryGetPointer(filter.Entity, out AIDriver* ai))
{
    ai->Update(frame, filter, ref input);
}
```

This allows the AI to generate inputs that are processed by the same systems that handle player inputs, ensuring consistent behavior between AI and players.
