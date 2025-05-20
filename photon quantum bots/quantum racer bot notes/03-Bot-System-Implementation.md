# Bot System Implementation

## BotSystem Overview

The `BotSystem` class is the core simulation system responsible for updating all bot entities in the game. It inherits from `SystemMainThreadFilter<BotSystem.Filter>`, which means it only processes entities that match the specified filter.

```csharp
public unsafe class BotSystem : SystemMainThreadFilter<BotSystem.Filter> {
    public override void Update(Frame f, ref Filter filter) {
        var botConfig = f.FindAsset(filter.Bot->Config);
        botConfig.UpdateBot(f, ref filter);
    }

    public struct Filter {
        public EntityRef Entity;
        public Transform2D* Transform;
        public Bot* Bot;
        public PhysicsBody2D* Body;
        public Racer* Racer;
    }
}
```

Key aspects of this system:
- The filter ensures only entities with Transform2D, Bot, PhysicsBody2D, and Racer components are processed
- Processing is delegated to the bot's configuration asset
- The system uses pointers for performance, accessing the component data directly

## Bot Update Process

The main bot behavior is implemented in the `UpdateBot` method of the `BotConfig` class:

```csharp
public void UpdateBot(Frame f, ref BotSystem.Filter filter) {
    // Reset input state
    filter.Bot->Input = default;

    // Handle start timer
    if (filter.Bot->StartTimer > 0) {
        filter.Bot->StartTimer -= f.DeltaTime;
        return;
    }

    // Get checkpoint and raceline data
    GetCheckpointData(f, ref filter, out var checkpointPosition, out var referencePosition, 
        out var directionToFollow, out var maxSpeed, out var directionToNext, out var referenceSpeed);
    
    // Calculate direction to the checkpoint
    var directionToCheckpoint = (checkpointPosition - filter.Transform->Position);
    var normalizedDirection = directionToCheckpoint.Normalized;
    
    // Check if checkpoint is passed
    var passed = FPVector2.Dot(-normalizedDirection, directionToNext) > CheckpointDetectionDotThreshold;
    if (directionToCheckpoint.Magnitude < CheckpointDetectionDistance || passed) {
        UpdateCheckpoint(f, ref filter);
        return;
    }

    // Handle car avoidance
    if (filter.Racer->CarAhead.IsValid) {
        var other = f.Get<Transform2D>(filter.Racer->CarAhead);
        var offset = OverlapRelativeOffset;
        if (filter.Entity.Index % 2 == 0) offset.X = -offset.X;
        var desired = other.TransformPoint(offset);
        var avoidDirection = (desired - filter.Transform->Position);
        if (avoidDirection.Magnitude < OverlapDistance) directionToFollow += avoidDirection.Normalized;
    }

    // Calculate steering angle
    var radians = FPVector2.RadiansSignedSkipNormalize(directionToFollow, filter.Transform->Up);
    var absRadians = FPMath.Abs(radians);

    // Adjust speed based on turning angle
    if (absRadians > RadiansSlowdownThreshold)
        maxSpeed *= SlowdownFactor;
    
    // Update bot state
    filter.Bot->MaxSpeed = maxSpeed;
    filter.Bot->CurrentSpeed = filter.Body->Velocity.Magnitude;
    
    // Apply acceleration or braking
    if (filter.Body->Velocity.Magnitude < maxSpeed) 
        filter.Bot->Input.RacerAccel.Update(f.Number, true);
    else 
        filter.Bot->Input.RacerBrake = true;
    
    // Draw debug visualizations if enabled
    if (Debug) {
        // Debug visualization code
    }
    
    // Apply steering inputs if needed
    if (absRadians < FP.EN2) return;
    if (radians < 0) filter.Bot->Input.RacerLeft.Update(f.Number, true);
    if (radians > 0) filter.Bot->Input.RacerRight.Update(f.Number, true);
}
```

## Checkpoint Navigation

Bots navigate through checkpoints along the raceline:

```csharp
private void UpdateCheckpoint(Frame f, ref BotSystem.Filter filter) {
    var raceline = f.FindAsset(filter.Bot->Raceline);
    filter.Bot->RacelineIndex = (filter.Bot->RacelineIndex + 1) % raceline.Raceline.Count;
}
```

When a bot passes a checkpoint, its target index is updated to the next point on the raceline.

## Raceline Following Logic

The core of the bot's navigation is in the `GetCheckpointData` method:

```csharp
private void GetCheckpointData(Frame f, ref BotSystem.Filter filter, 
    out FPVector2 checkpointPosition, out FPVector2 referencePosition, 
    out FPVector2 directionToFollow, out FP maxSpeed,
    out FPVector2 directionToNext, out FP referenceSpeed) {
    
    // Get raceline data
    var raceline = f.FindAsset(filter.Bot->Raceline);
    var currentCheckpointData = raceline.Raceline[filter.Bot->RacelineIndex];
    checkpointPosition = currentCheckpointData.Position;
    referencePosition = checkpointPosition;

    // Determine maximum speed
    maxSpeed = MaxSpeed;
    if (currentCheckpointData.DesiredSpeed < maxSpeed)
        maxSpeed = currentCheckpointData.DesiredSpeed;
    referenceSpeed = maxSpeed;

    // Adjust speed based on car handling capabilities
    var carConfig = f.FindAsset(filter.Racer->Config);
    FP handlingFactor = 1;
    if (carConfig.RotationSpeed < raceline.ReferenceRotationSpeed) {
        handlingFactor = carConfig.RotationSpeed / raceline.ReferenceRotationSpeed;
    }
    maxSpeed *= handlingFactor * RacelineSpeedFactor;

    // Calculate direction to next checkpoint
    var nextIndex = (filter.Bot->RacelineIndex + 1) % raceline.Raceline.Count;
    var next = raceline.Raceline[nextIndex];
    directionToNext = (next.Position - checkpointPosition).Normalized;

    // Implement look-ahead behavior
    var distanceBetweenMarks = raceline.DistanceBetweenMarks;
    var readAheadCount = ((filter.Bot->CurrentSpeed * LookAhead) / distanceBetweenMarks);
    if (readAheadCount > 0) {
        var actualIndex = (filter.Bot->RacelineIndex + readAheadCount.AsInt) % raceline.Raceline.Count;
        var readAheadPosition = raceline.Raceline[actualIndex].Position;
        
        // Apply smooth look-ahead if enabled
        if (SmoothLookAhead) {
            var distance = (filter.Transform->Position - checkpointPosition).Magnitude;
            var alpha = 1 - distance / distanceBetweenMarks;
            if (readAheadCount > 0) {
                alpha += readAheadCount;
                alpha /= (readAheadCount + 1);
            }
            referencePosition = FPVector2.Lerp(checkpointPosition, readAheadPosition, alpha);
        }
        else {
            referencePosition = readAheadPosition;
        }
    }

    // Set final direction to follow
    directionToFollow = (referencePosition - filter.Transform->Position).Normalized;
    if (UseDirectionToNext)
        directionToFollow = directionToNext;
}
```

This method determines:
1. The current target checkpoint position
2. The appropriate maximum speed based on the raceline data and car capabilities
3. The look-ahead position based on current speed (allowing bots to anticipate turns)
4. The final direction vector that the bot should follow

## Bot Spawning

Bots are spawned through the `BotConfigContainer`:

```csharp
public void GetBot(Frame f, PlayerRef player, out AssetRef<EntityPrototype> prototype) {
    var prototypeIndex = f.Global->RngSession.Next(0, Prefabs.Length);
    prototype = Prefabs[prototypeIndex];
}
```

When spawning a bot, a random prefab is selected from the available options, allowing for variety in bot vehicles.

## Raceline Recording System

While not part of the bot runtime system, the `RacelineRecorder` component is crucial for creating the racelines that bots follow:

```csharp
public class RacelineRecorder : QuantumEntityViewComponent<RacelineContext> {
    private FPVector2 _lastPos;
    public FP distanceInterval = 4;
    public int StartLap = 2;
    public bool Record = false;

    public override void OnUpdateView() {
        if (Record == false) return;
        var racer = PredictedFrame.Get<Racer>(EntityRef);
        
        if (racer.LapData.Laps + 1 != StartLap) return;
        
        var t = PredictedFrame.Get<Transform2D>(EntityRef);
        var body = PredictedFrame.Get<PhysicsBody2D>(EntityRef);
        var distance = t.Position - _lastPos;
        
        if (distance.Magnitude >= distanceInterval) {
            var checkpoint = new RacelineEntry() {
                Position = t.Position,
                DesiredSpeed = body.Velocity.Magnitude
            };
            
            if (ViewContext.CheckpointData.Raceline == null)
                ViewContext.CheckpointData.Raceline = new List<RacelineEntry>();
                
            ViewContext.CheckpointData.Raceline.Add(checkpoint);
            _lastPos = t.Position;
        }
    }
}
```

During development, this component:
1. Records the position and speed of a human-controlled vehicle
2. Samples at regular distance intervals (typically starting on lap 2 to ensure a clean run)
3. Stores the data in a CheckpointData asset that bots can later use

This approach allows developers to create high-quality racing lines by simply driving the track themselves.
