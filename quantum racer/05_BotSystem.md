# Bot System Implementation

The `BotSystem` and `BotConfig` classes handle the AI implementation for computer-controlled racers in Quantum Racer 2.5D.

## Bot System

The `BotSystem` class is a simple wrapper that processes all bot entities each frame:

```csharp
[Preserve]
public unsafe class BotSystem : SystemMainThreadFilter<BotSystem.Filter> {
    public override void Update(Frame f, ref Filter filter)
    {
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

## Bot Config

The `BotConfig` class contains the AI behavior parameters and update logic for bot-controlled vehicles.

### Configuration Parameters

```csharp
public FP MaxSpeed = 10;
public FPVector2 OverlapRelativeOffset = new FPVector2(0, 0);
public FP OverlapDistance = 3;
public FP CheckpointDetectionDistance = 5;
public FP CheckpointDetectionDotThreshold = FP._0_50;
public bool Debug = true;
public FP RacelineSpeedFactor = 1;
public FP LookAhead = FP._0_50;
public bool SmoothLookAhead = false;
public bool UseDirectionToNext;
public FP RadiansSlowdownThreshold = FP.PiOver4;
public FP SlowdownFactor = FP._0_50;
```

### UpdateBot Method

The main AI update method that handles bot driving behavior:

```csharp
public void UpdateBot(Frame f, ref BotSystem.Filter filter)
{
    // Reset input
    filter.Bot->Input = default;

    // Delay start if needed
    if (filter.Bot->StartTimer > 0)
    {
        filter.Bot->StartTimer -= f.DeltaTime;
        return;
    }

    // Get raceline and checkpoint data
    GetCheckpointData(f, ref filter, out var checkpointPosition, out var referencePosition, 
                      out var directionToFollow, out var maxSpeed, out var directionToNext, 
                      out var referenceSpeed);
    
    var directionToCheckpoint = (checkpointPosition - filter.Transform->Position);

    // Check if we've reached the checkpoint
    var normalizedDirection = directionToCheckpoint.Normalized;
    var passed = FPVector2.Dot(-normalizedDirection, directionToNext) > CheckpointDetectionDotThreshold;
    if (directionToCheckpoint.Magnitude < CheckpointDetectionDistance || passed)
    {
        UpdateCheckpoint(f, ref filter);
        return;
    }

    // Avoid cars ahead
    if (filter.Racer->CarAhead.IsValid)
    {
        var other = f.Get<Transform2D>(filter.Racer->CarAhead);
        var offset = OverlapRelativeOffset;
        if (filter.Entity.Index % 2 == 0) offset.X = -offset.X;
        var desired = other.TransformPoint(offset);
        var avoidDirection = (desired - filter.Transform->Position);
        if (avoidDirection.Magnitude < OverlapDistance) directionToFollow += avoidDirection.Normalized;
    }

    // Calculate steering
    var radians = FPVector2.RadiansSignedSkipNormalize(directionToFollow, filter.Transform->Up);
    var absRadians = FPMath.Abs(radians);

    // Slow down for sharp turns
    if (absRadians > RadiansSlowdownThreshold)
        maxSpeed *= SlowdownFactor;
    
    filter.Bot->MaxSpeed = maxSpeed;
    filter.Bot->CurrentSpeed = filter.Body->Velocity.Magnitude;
    
    // Accelerate or brake based on speed
    if (filter.Body->Velocity.Magnitude < maxSpeed) 
        filter.Bot->Input.RacerAccel.Update(f.Number, true);
    else 
        filter.Bot->Input.RacerBrake = true;
    
    // Visualize debug information
    if (Debug)
    {
        ColorRGBA speedColor = ColorRGBA.Green;
        if (maxSpeed / referenceSpeed <= FP._0_50)
        {
            speedColor = ColorRGBA.Red;
        }
        else if (maxSpeed / referenceSpeed <= FP._0_75)
        {
            speedColor = ColorRGBA.Yellow;
        }
        Draw.Ray(filter.Transform->Position, directionToFollow.Normalized * 5, speedColor);
        Draw.Circle(referencePosition, FP._0_25, ColorRGBA.Red);
    }
    
    // Apply steering if needed
    if (absRadians < FP.EN2) return;

    if (radians < 0) filter.Bot->Input.RacerLeft.Update(f.Number, true);
    if (radians > 0) filter.Bot->Input.RacerRight.Update(f.Number, true);
}
```

### Helper Methods

#### UpdateCheckpoint
Moves to the next raceline checkpoint:

```csharp
private void UpdateCheckpoint(Frame f, ref BotSystem.Filter filter)
{
    var raceline = f.FindAsset(filter.Bot->Raceline);
    filter.Bot->RacelineIndex = (filter.Bot->RacelineIndex + 1) % raceline.Raceline.Count;
}
```

#### GetCheckpointData
Gets the current racing line data for the bot to follow:

```csharp
private void GetCheckpointData(Frame f, ref BotSystem.Filter filter, 
                              out FPVector2 checkpointPosition, 
                              out FPVector2 referencePosition, 
                              out FPVector2 directionToFollow, 
                              out FP maxSpeed,
                              out FPVector2 directionToNext, 
                              out FP referenceSpeed)
{
    // Get raceline data
    var raceline = f.FindAsset(filter.Bot->Raceline);
    var currentCheckpointData = raceline.Raceline[filter.Bot->RacelineIndex];
    checkpointPosition = currentCheckpointData.Position;
    referencePosition = checkpointPosition;

    // Set speed based on configuration
    maxSpeed = MaxSpeed;
    if (currentCheckpointData.DesiredSpeed < maxSpeed)
        maxSpeed = currentCheckpointData.DesiredSpeed;

    referenceSpeed = maxSpeed;

    // Adjust speed based on vehicle handling
    var carConfig = f.FindAsset(filter.Racer->Config);
    FP handlingFactor = 1;
    if (carConfig.RotationSpeed < raceline.ReferenceRotationSpeed)
    {
        handlingFactor = carConfig.RotationSpeed / raceline.ReferenceRotationSpeed;
    }
    // if my car handles worse, be conservative when turning
    maxSpeed *= handlingFactor * RacelineSpeedFactor;

    // Calculate direction to next checkpoint
    var nextIndex = (filter.Bot->RacelineIndex + 1) % raceline.Raceline.Count;
    var next = raceline.Raceline[nextIndex];
    directionToNext = (next.Position - checkpointPosition).Normalized;

    // Look ahead based on current speed
    var distanceBetweenMarks = raceline.DistanceBetweenMarks;
    var readAheadCount = ((filter.Bot->CurrentSpeed * LookAhead) / distanceBetweenMarks);
    if (readAheadCount > 0)
    {
        var actualIndex = (filter.Bot->RacelineIndex + readAheadCount.AsInt) % raceline.Raceline.Count;
        var readAheadPosition = raceline.Raceline[actualIndex].Position;
        if (SmoothLookAhead)
        {
            var distance = (filter.Transform->Position - checkpointPosition).Magnitude;
            var alpha = 1 - distance / distanceBetweenMarks;
            if (readAheadCount > 0)
            {
                alpha += readAheadCount;
                alpha /= (readAheadCount + 1);
            }
            referencePosition = FPVector2.Lerp(checkpointPosition, readAheadPosition, alpha);
        }
        else
        {
            referencePosition = readAheadPosition;
        }
    }

    // Calculate steering direction
    directionToFollow = (referencePosition - filter.Transform->Position).Normalized;
    if (UseDirectionToNext)
        directionToFollow = directionToNext;
}
```

## Racing Line System

Bots navigate using predefined racing lines, which are sequences of points with recommended speeds:

```csharp
[Serializable]
struct RacelineEntry {
    FP DesiredSpeed;
    FPVector2 Position;
}
```

The `CheckpointData` asset contains these racing lines, which bots follow for optimal paths around the track.

## Bot Difficulty Levels

Bots can have different difficulty levels through configuration, controlled via the `BotConfigContainer`:

```csharp
public class BotConfigContainer : AssetObject
{
    public AssetRef<BotConfig>[] Configs;
    public string[] Nicknames;
    public int MaxBots = 10;
    public FP BotStartInterval = 0;
    
    public void GetBot(Frame frame, PlayerRef player, out AssetRef<EntityPrototype> prototype)
    {
        var data = frame.GetPlayerData(player);
        var carIndex = 0;
        if (data != null)
        {
            carIndex = data.PlayerCar;
        }
        else
        {
            carIndex = frame.Global->RngSession.Next(0, 4);
        }
        
        var spawnConfig = frame.FindAsset<SpawnConfig>(frame.Map.UserAsset);
        prototype = spawnConfig.AvailableCars[carIndex];
    }
}
```

## Implementation Notes
- Uses racing lines for optimal pathfinding
- Includes obstacle avoidance for other vehicles
- Adjusts speed based on turn sharpness
- Supports look-ahead behavior for anticipating future turns
- Scales difficulty based on handling capabilities
- Uses debug visualization to help with tuning
