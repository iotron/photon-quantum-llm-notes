# Quantum Karts Drifting System

This document explains the drifting mechanics in Quantum Karts, covering how drift initiation, physics, and control work to create the core skill-based gameplay of kart racing.

## Drifting Component

The drifting system starts with the `Drifting` component defined in `Drifting.qtn`:

```qtn
component Drifting {
    [ExcludeFromPrototype] sbyte Direction;
    [ExcludeFromPrototype] FP SideAcceleration;
    [ExcludeFromPrototype] FP ForwardFactor;
    [ExcludeFromPrototype] FP MaxSteeringOffset;
    [ExcludeFromPrototype] FP MinimumSpeed;
    [ExcludeFromPrototype] FP MinSidewaysSpeedSqr;
    [ExcludeFromPrototype] FP MaxAirTime;
    [ExcludeFromPrototype] FP MaxNoSteerTime;
    [ExcludeFromPrototype] FP MaxOppositeSteerTime;
}
```

Key properties:
- **Direction**: The direction of drift (-1 for left, 0 for none, 1 for right)
- **SideAcceleration**: The force applied perpendicular to the kart's direction
- **ForwardFactor**: Balance between sideways and forward motion during drift
- **MaxSteeringOffset**: How much drift affects steering angle
- **MinimumSpeed**: Speed required to initiate a drift
- **MinSidewaysSpeedSqr**: Minimum sideways speed to maintain drift
- **MaxAirTime**: Maximum time in air before drift is canceled
- **MaxNoSteerTime**: How long without steering before drift ends
- **MaxOppositeSteerTime**: How long with opposite steering before drift ends

## Implementation 

The drifting mechanics are implemented in the `Drifting.cs` file:

```csharp
public unsafe partial struct Drifting
{
    public bool IsDrifting => Direction != 0;

    public void Update(Frame frame, KartSystem.Filter filter)
    {
        Kart* kart = filter.Kart;
        Transform3D* transform = filter.Transform3D;
        
        // Determine the intended drift direction from steering input
        int desiredDirection = FPMath.RoundToInt(FPMath.Sign(filter.KartInput->Steering));

        // Start, maintain, or end drift based on conditions
        if (CanStartDrift(filter.KartInput, kart, desiredDirection))
        {
            Direction = desiredDirection;
        }
        else if (IsDrifting && ShouldEndDrift(filter.KartInput, kart))
        {
            Direction = 0;
        }

        // Calculate drift acceleration direction by blending side and forward vectors
        FPVector3 accelerationDirection = FPVector3.Lerp(transform->Right * -Direction, transform->Forward, ForwardFactor);

        // Apply steering offset from drifting
        filter.KartInput->SteeringOffset = MaxSteeringOffset * Direction;

        // Apply side force when drifting is active
        if (IsDrifting)
        {
            kart->ExternalForce += accelerationDirection * SideAcceleration * filter.KartInput->Throttle;
        }
    }

    private bool CanStartDrift(KartInput* kartInput, Kart* kart, int desiredDirection)
    {
        // Don't start if already drifting in this direction
        if (desiredDirection == Direction) { return false; }

        // Drift button must be pressed
        if (!kartInput->Drifting.WasPressed) { return false; }

        // Can't drift if in air too long
        if (kart->AirTime > MaxAirTime) { return false; }

        // Need minimum speed to drift
        if (kart->Velocity.SqrMagnitude < MinimumSpeed * MinimumSpeed) { return false; }

        // Need to actually be steering
        if (FPMath.Abs(kartInput->Steering) < FP._0_05) { return false; }

        // Can't drift on offroad surfaces
        if (kart->IsOffroad) { return false; }

        return true;
    }

    private bool ShouldEndDrift(KartInput* kartInput, Kart* kart)
    {
        // End drift on offroad surfaces
        if (kart->IsOffroad) { return true; }

        // End drift when drift button is pressed again
        if (kartInput->Drifting.WasPressed) { return true; }

        // End drift if in air too long
        if (kart->AirTime > MaxAirTime) { return true; }

        // End drift if speed drops too low
        if (kart->Velocity.SqrMagnitude < MinimumSpeed * MinimumSpeed) { return true; }

        // End drift if not enough sideways motion and no steering input for too long
        if (kart->SidewaysSpeedSqr < MinSidewaysSpeedSqr && kartInput->NoSteeringTime > MaxNoSteerTime)
        {
            return true;
        }

        // End drift if steering in opposite direction for too long
        if (FPMath.Sign(kartInput->Steering) != Direction && kartInput->SameSteeringTime > MaxOppositeSteerTime)
        {
            return true;
        }

        return false;
    }
}
```

## Drift Boost System

Drifting in Quantum Karts is integrated with the boost system. The `DriftBoost` component extends drifting with boost rewards:

```qtn
component DriftBoost {
    [ExcludeFromPrototype] FP DriftTime;
    [ExcludeFromPrototype] byte BoostLevel;
    [ExcludeFromPrototype] FP BoostVisualFeedback;
    [ExcludeFromPrototype] array<FP>[3] BoostThresholds;
    [ExcludeFromPrototype] array<AssetRef<BoostConfig>>[3] BoostConfigs;
}
```

The implementation tracks drift time and grants boosts when thresholds are met:

```csharp
public unsafe partial struct DriftBoost
{
    public void Update(Frame frame, KartSystem.Filter filter)
    {
        Drifting* drifting = filter.Drifting;
        
        // Only update when actively drifting
        if (drifting->IsDrifting)
        {
            DriftTime += frame.DeltaTime;
            
            // Check for boost level upgrades
            for (byte i = 0; i < BoostThresholds.Length; i++)
            {
                if (DriftTime >= BoostThresholds.GetPointer(i)->Value && i > BoostLevel)
                {
                    BoostLevel = i;
                    BoostVisualFeedback = FP._1;
                    frame.Events.DriftBoostCharged(filter.Entity, BoostLevel);
                }
            }
            
            // Fade visual feedback
            if (BoostVisualFeedback > 0)
            {
                BoostVisualFeedback -= frame.DeltaTime * 2;
            }
        }
        // Apply boost when drifting ends
        else if (DriftTime > 0)
        {
            if (BoostLevel > 0 && frame.Unsafe.TryGetPointer(filter.Entity, out KartBoost* boost))
            {
                boost->StartBoost(frame, BoostConfigs.GetPointer(BoostLevel - 1)->Value, filter.Entity);
                frame.Events.DriftBoostApplied(filter.Entity, BoostLevel);
            }
            
            // Reset values
            DriftTime = 0;
            BoostLevel = 0;
            BoostVisualFeedback = 0;
        }
    }
}
```

The `BoostSystem` ties everything together:

```csharp
public unsafe class BoostSystem : SystemMainThreadFilter<BoostSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public KartBoost* KartBoost;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        filter.KartBoost->Update(frame);
    }
}
```

## Drift-Specific Physics Calculations

Several parts of the kart physics system are modified during drifting:

### 1. Turning Rate Calculation

The `Kart.GetTurningRate` method adjusts turning sensitivity during drifting:

```csharp
public FP GetTurningRate(Frame frame, Drifting* drifting)
{
    KartStats stats = frame.FindAsset(StatsAsset);
    
    // Use maximum turning rate during drift, otherwise use speed-based turning
    return stats.turningRate.Evaluate(drifting->Direction != 0 ? 1 : GetNormalizedSpeed(frame));
}
```

This makes steering more responsive during drifts regardless of speed.

### 2. Steering Offset Application

The `KartInput` component tracks a steering offset that is applied during drifting:

```csharp
// In Drifting.Update
filter.KartInput->SteeringOffset = MaxSteeringOffset * Direction;

// In KartInput
public FP GetTotalSteering()
{
    return Steering + SteeringOffset;
}
```

This causes the kart to automatically steer in the drift direction, requiring counter-steering to balance.

### 3. Side Force Application

During drifting, a continuous side force is applied to maintain the sliding motion:

```csharp
// In Drifting.Update
if (IsDrifting)
{
    kart->ExternalForce += accelerationDirection * SideAcceleration * filter.KartInput->Throttle;
}
```

This creates the characteristic sliding motion while still allowing forward movement.

## Drift Initiation and Control

Drifting follows a specific flow:

1. **Preparation**: Player must be moving above minimum speed
2. **Initiation**: Player presses the drift button while steering left or right
3. **Maintenance**: Player must maintain speed and steering
4. **Control**: Counter-steering controls the drift angle
5. **Boost Building**: Longer drifts charge up larger boosts
6. **Release**: Letting go of drift or pressing it again ends the drift
7. **Boost Application**: If minimum drift time was achieved, a boost is applied

## KartInput Integration

The `KartInput` component tracks input timing that's crucial for drift control:

```csharp
public unsafe partial struct KartInput
{
    public void Update(Frame frame, Input input)
    {
        // Store previous frame values
        PreviousSteering = Steering;
        PreviousDrifting = Drifting.IsActive;
        
        // Update current values from input
        Drifting = input.Drift;
        Throttle = input.Direction.Y;
        Steering = input.Direction.X;
        
        // Calculate steering timing values
        if (FPMath.Abs(Steering) < FP._0_05)
        {
            NoSteeringTime += frame.DeltaTime;
            SameSteeringTime = 0;
        }
        else if (FPMath.Sign(Steering) == FPMath.Sign(PreviousSteering))
        {
            SameSteeringTime += frame.DeltaTime;
            NoSteeringTime = 0;
        }
        else
        {
            SameSteeringTime = 0;
            NoSteeringTime = 0;
        }
        
        // Track drift button hold time
        if (Drifting.IsActive)
        {
            DriftingInputTime += frame.DeltaTime;
        }
        else
        {
            DriftingInputTime = 0;
        }
    }
}
```

These timing values are used to determine when drifts should end based on player control.

## Visual Feedback System

The drifting system provides visual feedback through events:

```csharp
// In DriftBoost.Update
frame.Events.DriftBoostCharged(filter.Entity, BoostLevel);
frame.Events.DriftBoostApplied(filter.Entity, BoostLevel);
```

These events are handled on the Unity side to show:
1. **Drift Sparks**: Visual indicators showing drift direction and intensity
2. **Boost Charge**: Color changes indicating boost level
3. **Boost Effect**: Visual and audio feedback when boost is applied

## AI Drifting

AI drivers can also perform drifts using logic in the `AIDriver` component:

```csharp
public void Update(Frame frame, KartSystem.Filter filter, ref Input input)
{
    // Calculate turn angle between current and next waypoint
    FP turnAngle = FPVector3.Angle(toWaypoint, toNextWaypoint);
    
    if (frame.Unsafe.TryGetPointer(filter.Entity, out Drifting* drifting))
    {
        // Start drift on sharp turns
        bool shouldStartDrift = turnAngle >= settings.DriftingAngle && !drifting->IsDrifting;
        
        // End drift when turn smooths out
        bool shouldEndDrift = turnAngle < settings.DriftingStopAngle && drifting->IsDrifting;
        
        // Trigger drift button press when needed
        input.Drift = !drifting->IsDrifting && shouldStartDrift || drifting->IsDrifting && shouldEndDrift;
    }
}
```

AI drivers use the turn angle between waypoints to determine when to drift, mimicking player behavior.

## Drift Parameters Tuning

The drift system can be tuned through several key parameters:

1. **SideAcceleration**: How strong the sideways sliding force is
2. **ForwardFactor**: Balance between sideways and forward motion (0-1)
3. **MaxSteeringOffset**: How much automatic steering is applied during drift
4. **BoostThresholds**: Time thresholds for mini, medium, and super boosts
5. **MinSidewaysSpeedSqr**: Required sideways motion to maintain drift

These parameters can dramatically change the feel of drifting from arcade to simulation.

## Integration with Surface System

Drifting interacts with the surface system:

```csharp
// In CanStartDrift method
if (kart->IsOffroad) { return false; }

// In ShouldEndDrift method
if (kart->IsOffroad) { return true; }
```

This prevents drifting on off-road surfaces, creating strategic track choices.

## Best Practices

1. **Balanced Drift Control**: Make drifting require skill but not be frustratingly difficult
2. **Clear Visual Feedback**: Ensure players understand drift state and boost levels
3. **Surface Integration**: Use surface properties to create interesting drift opportunities
4. **Boost Rewards**: Scale boost rewards with drift difficulty and duration
5. **Deterministic Physics**: Ensure all drift calculations use Quantum's fixed-point math
6. **Input Buffering**: Track input timing to create responsive controls
7. **Testing**: Thoroughly test drift mechanics across different kart types and surfaces
