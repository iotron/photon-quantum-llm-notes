# AI Input System and Deterministic Control

## Overview

The input system is a critical component of the Quantum Karts AI implementation. It ensures that AI decisions result in the same deterministic inputs that human players would generate, allowing both AI and human-controlled karts to share the same underlying systems.

## Input Structure

The input structure in Quantum Karts is defined in `Input.qtn`:

```csharp
input
{
    button Drift;
    button Powerup;
    button Respawn;
    byte Encoded;
}
```

This compact structure includes:
- `Drift`: Button for initiating and ending drifts
- `Powerup`: Button for using held weapons/powerups
- `Respawn`: Button for manual respawn
- `Encoded`: A byte used to encode directional input

## Directional Input

Direction is likely handled through a `FPVector2` that represents:
- X-axis: Steering (-1 for left, 1 for right)
- Y-axis: Acceleration (0 for no acceleration, 1 for full acceleration)

This can be seen in the AI driver's code:

```csharp
input.Direction = new FPVector2(FPMath.Clamp(-desiredDirection * steeringStrength, -1, 1), 1);
```

## AI Input Generation

The `AIDriver` component generates inputs by analyzing the racing environment and making decisions:

```csharp
public void Update(Frame frame, KartSystem.Filter filter, ref Input input)
{
    // [Decision making logic...]
    
    // Example input generation:
    
    // Respawn decision
    if (StationaryTime > 5) {
        input.Respawn = true;
        StationaryTime = 0;
    }
    
    // Weapon usage decision
    if (frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons)) {
        LastWeaponTime += frame.DeltaTime;
        if (weapons->HeldWeapon != default && LastWeaponTime > FP._0_50 
            && frame.FindAsset(weapons->HeldWeapon).AIShouldUse(frame, filter.Entity)) {
            input.Powerup = true;
        }
    }
    
    // Drift decision
    if (frame.Unsafe.TryGetPointer(filter.Entity, out Drifting* drifting)) {
        bool shouldStartDrift = turnAngle >= settings.DriftingAngle && !drifting->IsDrifting;
        bool shouldEndDrift = turnAngle < settings.DriftingStopAngle && drifting->IsDrifting;
        input.Drift = !drifting->IsDrifting && shouldStartDrift || drifting->IsDrifting && shouldEndDrift;
    }
    
    // Steering and acceleration
    FP steeringStrength = settings.SteeringCurve.Evaluate(FPMath.Abs(signedAngle));
    input.Direction = new FPVector2(FPMath.Clamp(-desiredDirection * steeringStrength, -1, 1), 1);
}
```

## Input Processing in KartSystem

The `KartSystem` handles input from both AI and human players in a unified way:

```csharp
public override void Update(Frame frame, ref Filter filter)
{
    Input input = default;
    
    // [Race state checking...]
    
    // Get input from either AI or player
    if (frame.Unsafe.TryGetPointer(filter.Entity, out AIDriver* ai))
    {
        ai->Update(frame, filter, ref input);
    }
    else if (frame.Unsafe.TryGetPointer(filter.Entity, out PlayerLink* playerLink))
    {
        input = *frame.GetPlayerInput(playerLink->Player);
    }
    
    // Process inputs uniformly regardless of source
    if (input.Respawn)
    {
        frame.Add<RespawnMover>(filter.Entity);
    }
    
    if (input.Powerup.WasPressed && 
        frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
    {
        weapons->UseWeapon(frame, filter);
    }
    
    // [Hit processing...]
    
    // Update kart systems with processed input
    filter.KartInput->Update(frame, input);
    filter.Wheels->Update(frame);
    filter.Drifting->Update(frame, filter);
    filter.Kart->Update(frame, filter);
}
```

## KartInput Component

There's likely a `KartInput` component that processes raw input before it's applied to kart physics:

```csharp
// Conceptual implementation based on usage
public unsafe partial struct KartInput
{
    public FPVector2 Direction;
    
    public void Update(Frame frame, Input input)
    {
        // Process raw input into more refined control values
        Direction = input.Direction;
        
        // Additional input processing logic...
    }
}
```

## Deterministic Input Processing

The input system in Quantum Karts is fully deterministic due to:

1. **Fixed-Point Math**: All calculations use Quantum's deterministic fixed-point math.
2. **Frame-Based Timing**: All timing is based on frame numbers and delta time.
3. **Shared Code Path**: Both AI and player inputs go through the same processing code.
4. **No External Randomness**: All random decisions use the frame's deterministic RNG.

## AI-Specific Input Considerations

### 1. Continuous vs. Button Inputs

Unlike human players who press and release buttons, the AI must decide each frame whether a button should be pressed:

```csharp
// Drift button example
input.Drift = !drifting->IsDrifting && shouldStartDrift || drifting->IsDrifting && shouldEndDrift;
```

### 2. Steering Smoothing

The AI's steering uses an animation curve to map angle differences to steering input:

```csharp
FP steeringStrength = settings.SteeringCurve.Evaluate(FPMath.Abs(signedAngle));
```

This allows for more natural steering that mimics human players rather than binary left/right inputs.

### 3. Decision Cooldowns

For actions like weapon usage, the AI implements cooldowns to prevent rapid firing:

```csharp
LastWeaponTime += frame.DeltaTime;
if (weapons->HeldWeapon != default && LastWeaponTime > FP._0_50 && ...) {
    input.Powerup = true;
}
```

## Adapting Input for Different Difficulty Levels

The AI's input generation can be tuned through the AIDriverSettings:

1. **Steering Curve**: Different curves for different difficulty levels
2. **Prediction Range**: Affects how much the AI looks ahead when steering
3. **Drift Thresholds**: Changes when the AI initiates and ends drifts

## Implementation Best Practices

1. **Unified Input Structure**: Using the same input structure for AI and players simplifies code.
2. **Deterministic Decisions**: All AI decisions must be deterministic to maintain sync.
3. **Difficulty Tuning**: Input generation parameters should be tuned for different difficulty levels.
4. **Human-Like Behavior**: Add slight imperfections in AI inputs for more realistic behavior.
5. **Performance Optimization**: Keep input processing lightweight, as it runs for every kart every frame.
