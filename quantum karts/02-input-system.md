# Quantum Karts Input System

This document details the input system used in the Quantum Karts project, covering how player input is defined, processed, and applied to kart entities within the deterministic simulation.

## Input Definition

The Quantum Karts input structure is defined in `Input.qtn` as follows:

```qtn
input
{
    button Drift;
    button Powerup;
    button Respawn;
    byte Encoded;
}
```

This structure contains:
- **Drift**: Button for initiating/ending drifts
- **Powerup**: Button for using collected weapons
- **Respawn**: Button for manual respawn or ready toggle
- **Encoded**: Compact representation of steering and acceleration (discussed below)

## Unity Input Collection

The Unity-side input is captured in the `LocalInput` class, which subscribes to Quantum's input polling callback:

```csharp
public class LocalInput : MonoBehaviour
{
    private void Start()
    {
        QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
    }

    public void PollInput(CallbackPollInput callback)
    {
        Quantum.Input input = new Quantum.Input();

        // Buttons
        input.Drift = UnityEngine.Input.GetButton("Jump");
        input.Powerup = UnityEngine.Input.GetButton("Fire1");
        input.Respawn = UnityEngine.Input.GetKey(KeyCode.R);

        // Direction (steering and acceleration)
        var x = UnityEngine.Input.GetAxis("Horizontal");
        var y = UnityEngine.Input.GetAxis("Vertical");

        // Convert to Quantum's deterministic FPVector2
        input.Direction = new Vector2(x, y).ToFPVector2();

        // Send input to Quantum simulation
        callback.SetInput(input, DeterministicInputFlags.Repeatable);
    }
}
```

This approach ensures that:
1. Input is captured every frame from Unity's input system
2. Values are converted to deterministic types (FPVector2)
3. Input is sent to the Quantum simulation with the Repeatable flag

## KartInput Component

The input is further processed by the `KartInput` component, which is attached to kart entities:

```qtn
component KartInput {
    [ExcludeFromPrototype] FP Throttle;    
    [ExcludeFromPrototype] FP Steering;    
    [ExcludeFromPrototype] button Drifting;
    [ExcludeFromPrototype] FP PreviousSteering;    
    [ExcludeFromPrototype] bool PreviousDrifting;
    [ExcludeFromPrototype] FP SameSteeringTime;    
    [ExcludeFromPrototype] FP NoSteeringTime;
    [ExcludeFromPrototype] FP DriftingInputTime;    
    [ExcludeFromPrototype] FP SteeringOffset;
}
```

The C# implementation of this component includes methods for processing raw input:

```csharp
public unsafe partial struct KartInput
{
    public void Update(Frame frame, Input input)
    {
        // Store previous frame values
        PreviousSteering = Steering;
        PreviousDrifting = Drifting.IsActive;
        
        // Update current values
        Drifting = input.Drift;
        Throttle = input.Direction.Y;
        Steering = input.Direction.X;
        
        // Calculate timing values for steering and drifting
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
        
        // Track drifting button hold time
        if (Drifting.IsActive)
        {
            DriftingInputTime += frame.DeltaTime;
        }
        else
        {
            DriftingInputTime = 0;
        }
    }

    public FP GetTotalSteering()
    {
        return Steering + SteeringOffset;
    }
}
```

Key aspects of this implementation:
- Tracks input timing for features like drift control
- Manages state transitions (button presses/releases)
- Adds steering offset caused by drifting
- Provides a clean API for other systems to access input state

## AI Input Simulation

For AI-controlled karts, the input is simulated by the `AIDriver` component rather than coming from a player:

```csharp
public unsafe partial struct AIDriver
{
    public void Update(Frame frame, KartSystem.Filter filter, ref Input input)
    {
        AIDriverSettings settings = frame.FindAsset(SettingsRef);
        
        // Calculate target position and direction
        FPVector3 toWaypoint = TargetLocation - filter.Transform3D->Position;
        FPVector3 toNextWaypoint = NextTargetLocation - filter.Transform3D->Position;
        toWaypoint.Y = 0;
        toNextWaypoint.Y = 0;
        
        // Calculate prediction amount based on distance
        FP distance = FPVector3.Distance(TargetLocation, filter.Transform3D->Position);
        FP distanceNext = FPVector3.Distance(TargetLocation, NextTargetLocation);
        FP predictionAmount = FPMath.InverseLerp(distance, distanceNext, settings.PredictionRange);
        
        // Blend current and next waypoint based on prediction
        FPVector3 targetDirection = FPVector3.Lerp(toWaypoint, toNextWaypoint, predictionAmount).Normalized;
        
        // Calculate steering angle
        FP turnAngle = FPVector3.Angle(toWaypoint, toNextWaypoint);
        FP signedAngle = FPVector3.SignedAngle(targetDirection, filter.Kart->Velocity, FPVector3.Up);
        FP desiredDirection = FPMath.Sign(signedAngle);
        
        // Set drift input based on turn sharpness
        if (frame.Unsafe.TryGetPointer(filter.Entity, out Drifting* drifting))
        {
            bool shouldStartDrift = turnAngle >= settings.DriftingAngle && !drifting->IsDrifting;
            bool shouldEndDrift = turnAngle < settings.DriftingStopAngle && drifting->IsDrifting;
            
            input.Drift = !drifting->IsDrifting && shouldStartDrift || drifting->IsDrifting && shouldEndDrift;
        }
        
        // Calculate steering strength based on angle
        FP steeringStrength = settings.SteeringCurve.Evaluate(FPMath.Abs(signedAngle));
        
        // Set final input direction
        input.Direction = new FPVector2(FPMath.Clamp(-desiredDirection * steeringStrength, -1, 1), 1);
        
        // Handle weapon usage
        if (frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
        {
            LastWeaponTime += frame.DeltaTime;
            
            if (weapons->HeldWeapon != default
                && LastWeaponTime > FP._0_50
                && frame.FindAsset(weapons->HeldWeapon).AIShouldUse(frame, filter.Entity))
            {
                input.Powerup = true;
            }
        }
        
        // Handle respawn if stuck
        StationaryTime = filter.Kart->Velocity.SqrMagnitude < FP._7 ? 
            StationaryTime + frame.DeltaTime : 0;
            
        if (StationaryTime > 5)
        {
            input.Respawn = true;
            StationaryTime = 0;
        }
    }
}
```

AI input is designed to:
- Follow racing waypoints on the track
- Use look-ahead for smoother steering
- Determine when to drift based on turn angles
- Decide when to use weapons based on race situation
- Auto-respawn when stuck

## Input Flow Overview

The full input flow in Quantum Karts follows this sequence:

1. **Unity** captures raw input via `LocalInput.PollInput`
2. Input is converted to deterministic types and sent to Quantum
3. **Quantum** processes the input in `KartSystem.Update`
4. `KartInput.Update` transforms raw input into usable values
5. Input values are used by multiple systems:
   - `Kart.Update` for movement and physics
   - `Drifting.Update` for drift mechanics
   - `KartWeapons.UseWeapon` for weapon activation

## Optimization Notes

1. **Button States**: Quantum automatically tracks button state transitions (pressed/released), so Unity code only needs to provide current state
2. **Input Size**: The input structure is kept minimal to reduce network traffic
3. **Encoded Input**: The `Encoded` byte field can be used for even more compact representation of analog input
4. **Prediction**: The `DeterministicInputFlags.Repeatable` flag ensures consistent prediction during network delays

## Implementation Examples

### Starting a Drift Based on Input

```csharp
private bool CanStartDrift(KartInput* kartInput, Kart* kart, int desiredDirection)
{
    if (desiredDirection == Direction) { return false; }
    
    if (!kartInput->Drifting.WasPressed) { return false; }
    
    if (kart->AirTime > MaxAirTime) { return false; }
    
    if (kart->Velocity.SqrMagnitude < MinimumSpeed * MinimumSpeed) { return false; }
    
    if (FPMath.Abs(kartInput->Steering) < FP._0_05) { return false; }
    
    if (kart->IsOffroad) { return false; }
    
    return true;
}
```

### Using a Weapon

```csharp
// In KartSystem.Update
if (input.Powerup.WasPressed && frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
{
    weapons->UseWeapon(frame, filter);
}
```

### Respawn Logic

```csharp
// In KartSystem.Update
if (input.Respawn)
{
    frame.Add<RespawnMover>(filter.Entity);
}
```

## Best Practices

1. **Always use FP types**: Ensure all input processing uses Quantum's fixed-point math
2. **Handle state transitions**: Track when input state changes for one-time events
3. **Decouple input capture**: Keep Unity's input collection separate from simulation logic
4. **Input validation**: Verify input values are within expected ranges
5. **Minimal structure**: Keep the input structure as small as possible for network efficiency
