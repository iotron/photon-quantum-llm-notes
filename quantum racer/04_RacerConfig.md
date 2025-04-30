# Racer Config Implementation

The `RacerConfig` class defines the physics and handling characteristics of vehicles in Quantum Racer 2.5D. Each vehicle type has its own configuration with unique handling characteristics.

## Class Definition

```csharp
public unsafe class RacerConfig : AssetObject
{
    // Properties and methods...
}
```

## Physics Properties

```csharp
// Vehicle identification
public string CarName = "car_name";

// Basic movement parameters
public FP Acceleration = 15;
public FP Mass = 2;
public FP Braking = 5;
public FP GroundDrag = 1;
public FP LeanDrag = FP._0_10;
public FP MaxSpeed = 10;

// Steering and handling
public FPAnimationCurve SteeringResponseCurve;
public FP RotationSpeed = 10;
public FP LeanBuff = 5;

// Vertical movement parameters
public FP PitchSpeed = 30;
public FP MaxPitch = 15;
public FP BaseGravity = -10;
public FP PitchGravityBoost = 10;

// Physics tuning
public FP FrictionCoeficient = 2;
public FP ThrottleFrictionReductor = FP._0_50;

// Gameplay parameters
public FP InitialEnergy = 10;
public FP CheckpointDetectionDistance = 12;
```

## Key Methods

### ClampRacerSpeed
Limits the vehicle's speed to the configured maximum speed.

```csharp
public void ClampRacerSpeed(Frame f, ref RacerVelocityClampSystem.Filter filter)
{
    var maxSpeed = MaxSpeed * filter.Vehicle->ModifierValues.MaxSpeedMultiplier;

    var speed = filter.Body->Velocity.Magnitude;
    if (speed > maxSpeed)
    {
        filter.Body->Velocity = filter.Body->Velocity.Normalized * maxSpeed;
    }
}
```

### UpdateRacer
The main update method called each frame to process vehicle movement and state.

```csharp
public void UpdateRacer(Frame f, ref RacerSystem.Filter filter)
{
    // Get input from player or bot
    Input input = default;
    if (f.TryGet(filter.Entity, out RacerPlayerLink link) && link.Player.IsValid)
    {
        input = *f.GetPlayerInput(link.Player);
    }

    if (f.TryGet(filter.Entity, out Bot bot))
    {
        input = bot.Input;
    }

    // Update checkpoint progress
    UpdateCheckpoints(f, ref filter);

    // Disable control if finished
    if (filter.Vehicle->Finished) input = default;

    // Reset modifier values
    filter.Vehicle->ModifierValues.Reset();

    // Handle respawn timer if dead
    if (filter.Vehicle->Energy <= 0)
    {
        if (filter.Vehicle->ResetTimer <= 0)
        {
            f.Signals.Respawn(filter.Entity, filter.Vehicle, true);
        }
        else
        {
            filter.Vehicle->ResetTimer -= f.DeltaTime;
            filter.Body->Velocity = default;
            filter.Body->AngularVelocity = default;
            return;
        }
    }
    
    // Apply modifiers
    var modifier = f.FindAsset(filter.Vehicle->Modifier);
    if (modifier != null)
    {
        modifier.UpdateRacer(f, ref filter);
    }

    // Process vehicle physics
    UpdateSteering(f, ref filter, ref input);
    UpdateFriction(ref filter, ref input);
    
    // Handle jumping/aerial state
    if (UpdateVertical(f, ref filter, ref input)) return;
    
    // Apply acceleration
    UpdateAccel(f, ref filter, ref input);
}
```

## Helper Methods

### UpdateCheckpoints
Tracks checkpoint progress and lap information.

```csharp
private void UpdateCheckpoints(Frame frame, ref RacerSystem.Filter filter)
{
    if (frame.Unsafe.TryGetPointer<Transform2D>(filter.Vehicle->NextCheckpoint, out var checkpointTransform))
    {
        // Update lap timer
        filter.Vehicle->LapData.LapTime += frame.DeltaTime;
        
        // Check if we've reached the checkpoint
        var distance = (checkpointTransform->Position - filter.Transform->Position).Magnitude;
        if (distance < CheckpointDetectionDistance && frame.TryGet<Checkpoint>(filter.Vehicle->NextCheckpoint, out var checkpoint))
        {
            // Move to next checkpoint
            filter.Vehicle->NextCheckpoint = checkpoint.Next;
            filter.Vehicle->LastCheckpointPosition = checkpointTransform->Position;
            filter.Vehicle->LapData.Checkpoints++;

            // Update bot raceline reference
            if (frame.Unsafe.TryGetPointer<Bot>(filter.Entity, out var bot))
            {
                bot->RacingLineReset = checkpoint.RacelineRef;
                bot->RacelineIndexReset = bot->RacelineIndex;
            }
            
            // Handle finish line
            if (checkpoint.Finish)
            {
                // Process lap completion
                filter.Vehicle->LapData.Checkpoints = 0;
                filter.Vehicle->LapData.Laps++;
                filter.Vehicle->LapData.LastLapTime = filter.Vehicle->LapData.LapTime;
                
                // Update best lap time
                if (filter.Vehicle->LapData.LapTime < filter.Vehicle->LapData.BestLap ||
                    filter.Vehicle->LapData.BestLap == 0) 
                    filter.Vehicle->LapData.BestLap = filter.Vehicle->LapData.LapTime;
                
                filter.Vehicle->LapData.LapTime = 0;

                // Update bot raceline for next lap
                if (bot != null)
                {
                    var spawnConfig = frame.FindAsset<SpawnConfig>(frame.Map.UserAsset);
                    var racelineToPick = frame.Global->RngSession.Next(0, spawnConfig.AvailableRacelines.Length);
                    bot->Raceline = spawnConfig.AvailableRacelines[racelineToPick];
                }
                
                // Check if race is finished
                var raceConfig = frame.FindAsset(frame.RuntimeConfig.RaceConfig);
                if (filter.Vehicle->LapData.Laps == raceConfig.Laps)
                {
                    filter.Vehicle->Finished = true;
                    if (frame.Unsafe.TryGetPointerSingleton<RaceManager>(out var manager))
                    {
                        manager->FinishedCount++;
                    }
                }
            }
        }

        // Update total distance for position calculation
        filter.Vehicle->LapData.TotalDistance = filter.Vehicle->LapData.Laps * 100;
        filter.Vehicle->LapData.TotalDistance += filter.Vehicle->LapData.Checkpoints * 10;

        var traveled = (filter.Transform->Position - filter.Vehicle->LastCheckpointPosition);
        var forwardCheckpointDirection = (checkpointTransform->Position - filter.Vehicle->LastCheckpointPosition).Normalized;
        var distanceElapsed = FPVector2.Dot(traveled, forwardCheckpointDirection);
        filter.Vehicle->LapData.TotalDistance += distanceElapsed / 1000;
    }
}
```

### UpdatePitch
Handles the pitch control for aerial movement.

```csharp
private void UpdatePitch(Frame frame, ref RacerSystem.Filter filter, ref Input input)
{
    FP pitchSpeed = 0;
    if (input.RacerPitchUp) pitchSpeed -= PitchSpeed;
    if (input.RacerPitchDown) pitchSpeed += PitchSpeed;

    filter.Vehicle->Pitch += pitchSpeed * frame.DeltaTime;
    filter.Vehicle->Pitch = FPMath.Clamp(filter.Vehicle->Pitch, -MaxPitch, MaxPitch);
}
```

### UpdateVertical
Handles jumping and aerial movement.

```csharp
private bool UpdateVertical(Frame frame, ref RacerSystem.Filter filter, ref Input input)
{
    var pitchFactor = -filter.Vehicle->Pitch / MaxPitch;
    var gravity = BaseGravity;
    var wasJumping = filter.Vertical->Position != 0;
    
    if (filter.Vehicle->VerticalSpeed < 0)
        gravity += pitchFactor * PitchGravityBoost;

    filter.Vertical->Position += filter.Vehicle->VerticalSpeed * frame.DeltaTime;
    filter.Vehicle->VerticalSpeed += gravity * frame.DeltaTime;
    
    if (filter.Vertical->Position <= 0)
    {
        filter.Vertical->Position = 0;
        filter.Vehicle->VerticalSpeed = 0;
    }

    if (filter.Vertical->Position != 0)
    {
        UpdatePitch(frame, ref filter, ref input);
        return true;
    }
    else if (wasJumping)
    {
        frame.Events.JumpLand(filter.Entity);
    }

    filter.Vehicle->Pitch = 0;
    return false;
}
```

### UpdateFriction
Applies lateral friction to limit drifting.

```csharp
private void UpdateFriction(ref RacerSystem.Filter filter, ref Input input)
{
    var dot = FPVector2.Dot(filter.Transform->Right, filter.Body->Velocity);
    var friction = FrictionCoeficient * filter.Vehicle->ModifierValues.FrictionMultiplier * filter.Body->Mass;
    filter.Body->AddForce(filter.Transform->Right * -dot * friction);
}
```

### UpdateSteering
Handles steering controls and lean mechanics.

```csharp
private void UpdateSteering(Frame frame, ref RacerSystem.Filter filter, ref Input input)
{
    FP rotationSpeed = 0;
    if (input.RacerLeft.IsDown) rotationSpeed += RotationSpeed;
    if (input.RacerRight.IsDown) rotationSpeed -= RotationSpeed;

    filter.Vehicle->Lean = 0;
    if (input.RacerLeanLeft.IsDown)
    {
        rotationSpeed += LeanBuff;
        filter.Vehicle->Lean += 1;
    }

    if (input.RacerLeanRight.IsDown)
    {
        rotationSpeed -= LeanBuff;
        filter.Vehicle->Lean -= 1;
    }

    // Calibrate with speed (animation curve)
    var mult = SteeringResponseCurve.Evaluate(filter.Body->Velocity.Magnitude);

    if (input.RacerAccel.IsDown) mult *= ThrottleFrictionReductor;
    
    rotationSpeed *= mult;

    filter.Transform->Rotation += rotationSpeed * frame.DeltaTime * FP.Deg2Rad;
}
```

### UpdateAccel
Handles acceleration, braking, and drag.

```csharp
private void UpdateAccel(Frame frame, ref RacerSystem.Filter filter, ref Input input)
{
    var accel = Acceleration * filter.Vehicle->ModifierValues.AccelMultiplier * filter.Body->Mass;
    if (input.RacerAccel.IsDown) filter.Body->AddForce(filter.Transform->Up * accel);
    if (input.RacerBrake.IsDown) filter.Body->AddForce(filter.Transform->Down * Braking);
    
    var drag = GroundDrag;
    if (input.RacerLeanLeft.IsDown || input.RacerLeanRight.IsDown) drag += LeanDrag;

    filter.Body->Velocity -= filter.Body->Velocity * drag * frame.DeltaTime;
}
```

## Implementation Notes
- Uses fixed-point math (FP) for deterministic physics
- Leverages animation curves to tune steering response by speed
- Modular approach with separate physics handling methods
- Supports various vehicle stats through configuration values
- Handles vertical movement for jumps and pitch control
