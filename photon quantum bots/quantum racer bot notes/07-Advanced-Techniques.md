# Advanced Techniques and Best Practices for Quantum Bots

This document covers advanced techniques and best practices for implementing bots in Photon Quantum racing games, based on the Quantum Racer project architecture.

## Advanced Bot Behaviors

### Dynamic Path Generation

While the standard bot implementation follows pre-recorded racelines, more advanced systems can dynamically generate paths:

```csharp
public void GenerateDynamicPath(Frame f, EntityRef botEntity, FPVector2 currentPosition, FPVector2 targetPosition) {
    // Create a temporary raceline
    var tempRaceline = new List<RacelineEntry>();
    
    // Find obstacles in the way
    List<Collider2D> obstacles = new List<Collider2D>();
    f.PhysicsScene2D.OverlapBox(
        currentPosition, 
        new FPVector2(50, 50), 
        0, 
        obstacles);
    
    // Generate waypoints avoiding obstacles
    var pathfinder = new AStarPathfinder();
    var waypoints = pathfinder.FindPath(currentPosition, targetPosition, obstacles);
    
    // Convert waypoints to raceline entries
    foreach (var waypoint in waypoints) {
        tempRaceline.Add(new RacelineEntry {
            Position = waypoint,
            DesiredSpeed = 5 // Default speed
        });
    }
    
    // Apply speed adjustments based on turns
    OptimizePathSpeeds(tempRaceline);
    
    // Store the dynamic path
    if (f.Unsafe.TryGetPointer<Bot>(botEntity, out var bot)) {
        // Replace or supplement the standard raceline with this dynamic path
        // Implementation depends on how you want to integrate this feature
    }
}

private void OptimizePathSpeeds(List<RacelineEntry> path) {
    // Calculate optimal speeds based on turn angles
    for (int i = 1; i < path.Count - 1; i++) {
        var prev = path[i-1].Position;
        var curr = path[i].Position;
        var next = path[i+1].Position;
        
        var inDirection = (curr - prev).Normalized;
        var outDirection = (next - curr).Normalized;
        
        // Calculate dot product to find turn sharpness
        var dot = FPVector2.Dot(inDirection, outDirection);
        
        // Adjust speed based on turn sharpness
        // Lower dot product = sharper turn = lower speed
        var speedFactor = FPMath.Lerp(FP._0_30, FP._1_00, dot);
        path[i].DesiredSpeed *= speedFactor;
    }
}
```

### Adaptive Racing Style

Implement bots that adapt their racing style based on race conditions:

```csharp
public unsafe class AdaptiveBotSystem : SystemMainThread {
    public override void Update(Frame f) {
        f.Foreach((EntityRef entity, ref Bot bot, ref Racer racer) => {
            // Skip if not initialized
            if (!bot.Config.IsValid) return;
            
            var botConfig = f.FindAsset(bot.Config);
            
            // Adapt based on race position
            if (racer.Position <= 3) {
                // Leading or near front - be defensive
                bot.RacingStyle = RacingStyle.Defensive;
                botConfig.OverlapDistance = 4; // Wider berth when overtaking
                botConfig.RacelineSpeedFactor = FP._0_95; // Slightly conservative
            }
            else if (racer.Position >= f.PlayerCount + 3) {
                // Far behind - be aggressive
                bot.RacingStyle = RacingStyle.Aggressive;
                botConfig.OverlapDistance = 2; // Tighter overtaking
                botConfig.RacelineSpeedFactor = FP._1_05; // Push harder
            }
            else {
                // Mid-pack - balanced approach
                bot.RacingStyle = RacingStyle.Balanced;
                botConfig.OverlapDistance = 3; // Default overtaking
                botConfig.RacelineSpeedFactor = FP._1_00; // Standard speed
            }
            
            // Adapt based on lap number
            var lapProgress = (FP)racer.LapData.Laps / f.RuntimeConfig.TotalLaps;
            if (lapProgress > FP._0_75) {
                // Final laps - more aggressive
                botConfig.RacelineSpeedFactor += FP._0_05;
            }
        });
    }
}
```

### Terrain-Aware Bot Behavior

Make bots adjust to different track surfaces:

```csharp
public void UpdateBot(Frame f, ref BotSystem.Filter filter) {
    // Get current surface info
    var position = filter.Transform->Position;
    SurfaceType surface = GetSurfaceTypeAtPosition(f, position);
    
    // Adjust behavior based on surface
    switch (surface) {
        case SurfaceType.Ice:
            // Be cautious on ice
            MaxBrakingDistance *= FP._2_00;
            SlowdownFactor *= FP._0_80;
            break;
            
        case SurfaceType.Dirt:
            // Reduced speed on dirt
            MaxSpeed *= FP._0_85;
            break;
            
        case SurfaceType.Boost:
            // Can go faster on boost pads
            MaxSpeed *= FP._1_20;
            break;
    }
    
    // Continue with standard bot update...
}

private SurfaceType GetSurfaceTypeAtPosition(Frame f, FPVector2 position) {
    // Query physics system for surface type
    // Implementation depends on how surfaces are defined in your game
    return SurfaceType.Default;
}
```

## Performance Optimization Techniques

### Hierarchical Bot Updates

Implement different update frequencies for different aspects of bot behavior:

```csharp
public unsafe class HierarchicalBotSystem : SystemMainThread {
    public override void Update(Frame f) {
        // Every frame: Basic movement and collision avoidance
        f.Foreach((EntityRef entity, ref Bot bot) => {
            UpdateBasicBehavior(f, entity, ref bot);
        });
        
        // Every 3 frames: Raceline following and speed optimization
        if (f.Number % 3 == 0) {
            f.Foreach((EntityRef entity, ref Bot bot) => {
                UpdateRacelineBehavior(f, entity, ref bot);
            });
        }
        
        // Every 15 frames: Strategic decisions
        if (f.Number % 15 == 0) {
            f.Foreach((EntityRef entity, ref Bot bot) => {
                UpdateStrategicBehavior(f, entity, ref bot);
            });
        }
    }
    
    private void UpdateBasicBehavior(Frame f, EntityRef entity, ref Bot bot) {
        // High-frequency updates:
        // - Basic steering
        // - Collision avoidance
        // - Input application
    }
    
    private void UpdateRacelineBehavior(Frame f, EntityRef entity, ref Bot bot) {
        // Medium-frequency updates:
        // - Raceline following
        // - Speed profile adjustments
        // - Look-ahead calculations
    }
    
    private void UpdateStrategicBehavior(Frame f, EntityRef entity, ref Bot bot) {
        // Low-frequency updates:
        // - Racing style adjustments
        // - Overtaking strategy
        // - Pit stop decisions (if applicable)
    }
}
```

### Spatial Partitioning for Efficient Queries

Implement spatial partitioning for more efficient bot queries:

```csharp
public unsafe class SpatialBotManager : SystemMainThread {
    // Simple grid partitioning
    private Dictionary<Int2, List<EntityRef>> _spatialGrid = new Dictionary<Int2, List<EntityRef>>();
    private FP _cellSize = 20;
    
    public override void Update(Frame f) {
        // Clear grid
        _spatialGrid.Clear();
        
        // Populate grid with bots
        f.Foreach((EntityRef entity, ref Bot bot, ref Transform2D transform) => {
            var cellX = (transform.Position.X / _cellSize).AsInt;
            var cellY = (transform.Position.Y / _cellSize).AsInt;
            var cellKey = new Int2(cellX, cellY);
            
            if (!_spatialGrid.ContainsKey(cellKey)) {
                _spatialGrid[cellKey] = new List<EntityRef>();
            }
            
            _spatialGrid[cellKey].Add(entity);
        });
        
        // Use grid for efficient queries
        f.Foreach((EntityRef entity, ref Bot bot, ref Transform2D transform) => {
            // Get nearby entities efficiently
            var nearby = GetNearbyEntities(f, transform.Position, 30);
            
            // Process interactions with nearby entities only
            foreach (var nearbyEntity in nearby) {
                if (nearbyEntity == entity) continue;
                
                // Handle interactions...
            }
        });
    }
    
    private List<EntityRef> GetNearbyEntities(Frame f, FPVector2 position, FP radius) {
        var result = new List<EntityRef>();
        var radiusCells = (radius / _cellSize).AsInt + 1;
        
        var centerCellX = (position.X / _cellSize).AsInt;
        var centerCellY = (position.Y / _cellSize).AsInt;
        
        // Query grid cells in radius
        for (int x = centerCellX - radiusCells; x <= centerCellX + radiusCells; x++) {
            for (int y = centerCellY - radiusCells; y <= centerCellY + radiusCells; y++) {
                var cellKey = new Int2(x, y);
                
                if (_spatialGrid.TryGetValue(cellKey, out var entitiesInCell)) {
                    result.AddRange(entitiesInCell);
                }
            }
        }
        
        return result;
    }
}
```

### Bot Instancing for Memory Optimization

Use instanced bot configurations to reduce memory usage:

```csharp
// Modified BotSystem to use instanced configs
public unsafe class OptimizedBotSystem : SystemMainThreadFilter<OptimizedBotSystem.Filter> {
    // Shared data for each bot type
    private Dictionary<AssetRefType, BotSharedData> _sharedData = new Dictionary<AssetRefType, BotSharedData>();
    
    public override void Update(Frame f, ref Filter filter) {
        var configRef = filter.Bot->Config;
        
        // Get or create shared data for this bot type
        if (!_sharedData.TryGetValue(configRef.TypeId, out var sharedData)) {
            var botConfig = f.FindAsset(configRef);
            sharedData = new BotSharedData();
            sharedData.Config = botConfig;
            _sharedData[configRef.TypeId] = sharedData;
        }
        
        // Use shared data for bot update
        sharedData.Config.UpdateBot(f, ref filter, sharedData);
    }
    
    public struct Filter {
        public EntityRef Entity;
        public Transform2D* Transform;
        public Bot* Bot;
        public PhysicsBody2D* Body;
        public Racer* Racer;
    }
    
    public class BotSharedData {
        public BotConfig Config;
        // Shared temporary data structures can be stored here
        public List<EntityRef> NearbyEntities = new List<EntityRef>();
        // Other shared data...
    }
}
```

## Visual Debugging Tools

### In-Game Bot Debugging Overlay

Create a debug overlay for bot behavior visualization:

```csharp
// Unity-side debug visualization
public class BotDebugOverlay : MonoBehaviour {
    public bool ShowRacelines = true;
    public bool ShowBotInternals = true;
    public bool ShowPredictions = true;
    
    private QuantumGame _game;
    
    void Start() {
        _game = QuantumRunner.Default.Game;
    }
    
    void OnGUI() {
        if (_game?.Frames?.Predicted == null) return;
        
        var frame = _game.Frames.Predicted;
        
        frame.Foreach((EntityRef entity, ref Bot bot, ref Transform2D transform) => {
            // Convert world position to screen position
            var worldPos = transform.Position.ToUnityVector3();
            var screenPos = Camera.main.WorldToScreenPoint(worldPos);
            
            if (screenPos.z < 0) return; // Behind camera
            
            var pos = new Vector2(screenPos.x, Screen.height - screenPos.y);
            
            if (ShowBotInternals) {
                // Draw bot info
                var botConfig = frame.FindAsset(bot.Config);
                var racerInfo = frame.Has<Racer>(entity) ? frame.Get<Racer>(entity) : default;
                
                GUI.Label(new Rect(pos.x, pos.y, 200, 100), 
                    $"Speed: {bot.CurrentSpeed:F1}/{bot.MaxSpeed:F1}\n" +
                    $"RL Index: {bot.RacelineIndex}\n" +
                    $"Position: {racerInfo.Position}");
            }
            
            if (ShowPredictions && botConfig.Debug) {
                // Draw bot's predicted path
                var raceline = frame.FindAsset(bot.Raceline);
                if (raceline != null && raceline.Raceline != null) {
                    var currentIdx = bot.RacelineIndex;
                    var pointsToDraw = 10;
                    
                    for (int i = 0; i < pointsToDraw; i++) {
                        var idx = (currentIdx + i) % raceline.Raceline.Count;
                        var point = raceline.Raceline[idx].Position.ToUnityVector3();
                        var screenPoint = Camera.main.WorldToScreenPoint(point);
                        
                        if (screenPoint.z < 0) continue; // Behind camera
                        
                        var ptPos = new Vector2(screenPoint.x, Screen.height - screenPoint.y);
                        var size = 10 - i; // Smaller as points get further
                        
                        // Color based on speed
                        var speed = raceline.Raceline[idx].DesiredSpeed;
                        var maxSpeed = botConfig.MaxSpeed;
                        var speedRatio = speed / maxSpeed;
                        Color color = Color.Lerp(Color.red, Color.green, speedRatio.AsFloat);
                        
                        GUI.color = color;
                        GUI.DrawTexture(new Rect(ptPos.x - size/2, ptPos.y - size/2, size, size), 
                            Texture2D.whiteTexture);
                    }
                    
                    GUI.color = Color.white;
                }
            }
        });
    }
}
```

### Bot Telemetry Recording

Implement telemetry recording for bot performance analysis:

```csharp
// Telemetry recording system
public unsafe class BotTelemetrySystem : SystemMainThread {
    private struct BotTelemetryEntry {
        public int FrameNumber;
        public EntityRef Entity;
        public FPVector2 Position;
        public FP Speed;
        public FP TargetSpeed;
        public int RacelineIndex;
        public FP SteeringAngle;
        public bool IsAccelerating;
        public bool IsBraking;
    }
    
    private List<BotTelemetryEntry> _telemetryBuffer = new List<BotTelemetryEntry>(1000);
    private bool _recordingActive = false;
    private int _frameInterval = 5; // Record every 5 frames
    
    public override void Update(Frame f) {
        if (!_recordingActive) return;
        if (f.Number % _frameInterval != 0) return;
        
        // Record telemetry for each bot
        f.Foreach((EntityRef entity, ref Bot bot, ref Transform2D transform, ref PhysicsBody2D body) => {
            _telemetryBuffer.Add(new BotTelemetryEntry {
                FrameNumber = f.Number,
                Entity = entity,
                Position = transform.Position,
                Speed = body.Velocity.Magnitude,
                TargetSpeed = bot.MaxSpeed,
                RacelineIndex = bot.RacelineIndex,
                SteeringAngle = FPVector2.Angle(transform.Up, body.Velocity),
                IsAccelerating = bot.Input.RacerAccel.IsDown,
                IsBraking = bot.Input.RacerBrake
            });
        });
        
        // If buffer gets too large, dump to file or analyze
        if (_telemetryBuffer.Count >= 1000) {
            AnalyzeTelemetry();
            _telemetryBuffer.Clear();
        }
    }
    
    private void AnalyzeTelemetry() {
        // Group by entity
        var entityGroups = _telemetryBuffer
            .GroupBy(e => e.Entity.GetValueOrDefault().Index)
            .ToDictionary(g => g.Key, g => g.ToList());
        
        foreach (var group in entityGroups) {
            var entityId = group.Key;
            var entries = group.Value;
            
            // Calculate average speed
            var avgSpeed = entries.Average(e => e.Speed.AsFloat);
            
            // Calculate speed consistency (standard deviation)
            var speedVariance = entries
                .Average(e => FPMath.Pow(e.Speed - avgSpeed, 2).AsFloat);
            var speedStdDev = FPMath.Sqrt(speedVariance);
            
            // Calculate raceline adherence
            var racetimeProgress = entries.Last().RacelineIndex - entries.First().RacelineIndex;
            
            // Calculate brake/accelerate ratio
            var brakeTime = entries.Count(e => e.IsBraking);
            var accelTime = entries.Count(e => e.IsAccelerating);
            var brakeAccelRatio = brakeTime / (float)accelTime;
            
            // Log or visualize metrics
            Debug.Log($"Bot {entityId} metrics: " +
                $"Avg Speed: {avgSpeed:F2}, " +
                $"Speed StdDev: {speedStdDev:F2}, " +
                $"Raceline Progress: {racetimeProgress}, " +
                $"Brake/Accel Ratio: {brakeAccelRatio:F2}");
        }
    }
    
    public void StartRecording() {
        _telemetryBuffer.Clear();
        _recordingActive = true;
    }
    
    public void StopRecording() {
        _recordingActive = false;
        AnalyzeTelemetry();
    }
}
```

## Best Practices

### Bot Configuration Management

1. **Version Bot Configurations**: Use version control for bot configurations to track changes
   ```
   BotConfig_v1.2.3
   ├── BotBasic.asset
   ├── BotMedium.asset
   └── BotAdvanced.asset
   ```

2. **Create Presets for Specific Tracks**: Maintain track-specific configurations
   ```csharp
   public class TrackSpecificBotConfig : BotConfig {
       // Map of track IDs to parameter adjustments
       public Dictionary<string, BotConfigAdjustment> TrackAdjustments;
       
       // Apply track-specific adjustments
       public void ApplyTrackAdjustments(string trackId) {
           if (TrackAdjustments.TryGetValue(trackId, out var adjustment)) {
               MaxSpeed *= adjustment.SpeedFactor;
               OverlapDistance *= adjustment.OverlapFactor;
               // Apply other adjustments...
           }
       }
   }
   ```

3. **Use Scriptable Objects for Inspector-Friendly Editing**:
   ```csharp
   [CreateAssetMenu(fileName = "BotConfig", menuName = "Quantum/Racing/Bot Config")]
   public class BotConfigScriptableObject : ScriptableObject {
       public FP MaxSpeed = 10;
       public FP RacelineSpeedFactor = 1;
       // Other parameters...
       
       // Convert to Quantum asset
       public BotConfig ToQuantumAsset() {
           var config = new BotConfig();
           config.MaxSpeed = MaxSpeed;
           config.RacelineSpeedFactor = RacelineSpeedFactor;
           // Copy other parameters...
           return config;
       }
   }
   ```

### Raceline Creation Guidelines

1. **Create Clean, Consistent Racelines**:
   - Drive at a consistent speed
   - Take smooth racing lines through corners
   - Use a controller for smoother input

2. **Record Multiple Racing Lines**:
   - Record different lines for different difficulty levels
   - Create alternative lines for overtaking
   - Record defensive lines for leading positions

3. **Post-Process Racelines**:
   ```csharp
   public static void SmoothRaceline(List<RacelineEntry> raceline, int smoothingPasses = 3) {
       for (int pass = 0; pass < smoothingPasses; pass++) {
           var originalPositions = raceline.Select(r => r.Position).ToList();
           
           for (int i = 1; i < raceline.Count - 1; i++) {
               // Average position with neighbors
               var prevPos = originalPositions[i-1];
               var nextPos = originalPositions[i+1];
               var avgPos = (prevPos + nextPos) * FP._0_50;
               
               // Blend original with smoothed (80% smooth, 20% original)
               raceline[i].Position = FPVector2.Lerp(raceline[i].Position, avgPos, FP._0_80);
           }
       }
       
       // Recalculate speeds based on turns
       OptimizeRacelineSpeeds(raceline);
   }
   
   public static void OptimizeRacelineSpeeds(List<RacelineEntry> raceline) {
       // First pass: Calculate ideal speeds based on turn angles
       for (int i = 1; i < raceline.Count - 1; i++) {
           var inVec = raceline[i].Position - raceline[i-1].Position;
           var outVec = raceline[i+1].Position - raceline[i].Position;
           
           var turnAngle = FPVector2.Angle(inVec, outVec);
           
           // More speed reduction for sharper turns
           var speedFactor = FPMath.Clamp(1 - (turnAngle / 180) * 2, FP._0_30, FP._1_00);
           raceline[i].DesiredSpeed *= speedFactor;
       }
       
       // Second pass: Smooth speed transitions
       var originalSpeeds = raceline.Select(r => r.DesiredSpeed).ToList();
       for (int i = 1; i < raceline.Count - 1; i++) {
           var prevSpeed = originalSpeeds[i-1];
           var nextSpeed = originalSpeeds[i+1];
           var avgSpeed = (prevSpeed + nextSpeed) * FP._0_50;
           
           // Blend original with smoothed (50% smooth, 50% original)
           raceline[i].DesiredSpeed = FPMath.Min(raceline[i].DesiredSpeed, 
               FPMath.Lerp(raceline[i].DesiredSpeed, avgSpeed, FP._0_50));
       }
   }
   ```

### Bot Behavior Balance

1. **Design Bots for Fun, Not Just Challenge**:
   - Ensure bots make occasional minor mistakes
   - Add personality through different driving styles
   - Allow the player to catch up when too far behind

2. **Design Different Bot Difficulty Levels**:
   - Easy: Slower, predictable bots that follow optimal lines
   - Medium: Moderate speed with occasional overtaking
   - Hard: Fast, aggressive bots that challenge the player

3. **Implement Rubber-Banding for Single-Player**:
   ```csharp
   public unsafe class RubberbandSystem : SystemMainThread {
       // Maximum adjustment factors
       public FP MaxSpeedBoost = FP._1_25;
       public FP MaxSpeedReduction = FP._0_80;
       
       public override void Update(Frame f) {
           // Find local player
           EntityRef playerEntity = EntityRef.None;
           f.Foreach((EntityRef entity, ref RacerPlayerLink link) => {
               if (f.PlayerIsLocal(link.Player)) {
                   playerEntity = entity;
                   return;
               }
           });
           
           if (!playerEntity.IsValid) return;
           
           // Get player position
           var playerRacer = f.Unsafe.GetPointer<Racer>(playerEntity);
           var playerPosition = playerRacer->Position;
           
           // Calculate rubber-banding factor based on player position
           FP rubberFactor;
           
           if (playerPosition <= 2) {
               // Player is in the lead - make bots faster
               FP leadFactor = FP._1_00 + FP._0_05 * (FP._3_00 - playerPosition);
               rubberFactor = FPMath.Min(leadFactor, MaxSpeedBoost);
           } 
           else if (playerPosition >= f.PlayerCount - 1) {
               // Player is far behind - make bots slower
               FP behindFactor = FP._1_00 - FP._0_05 * (playerPosition - (f.PlayerCount - 2));
               rubberFactor = FPMath.Max(behindFactor, MaxSpeedReduction);
           }
           else {
               // Player is in the middle of the pack - normal speed
               rubberFactor = FP._1_00;
           }
           
           // Apply rubber-banding to all bots
           f.Foreach((EntityRef entity, ref Bot bot) => {
               var botConfig = f.FindAsset(bot.Config);
               bot.MaxSpeed = botConfig.MaxSpeed * rubberFactor;
           });
       }
   }
   ```

## Advanced Racing Techniques

### Slip-Streaming (Drafting)

Implement realistic slipstream effects for bots:

```csharp
public void UpdateBot(Frame f, ref BotSystem.Filter filter) {
    // Check for slipstream opportunities
    if (filter.Racer->CarAhead.IsValid) {
        var other = f.Get<Transform2D>(filter.Racer->CarAhead);
        var otherBody = f.Get<PhysicsBody2D>(filter.Racer->CarAhead);
        
        // Calculate relative position
        var toOther = other.Position - filter.Transform->Position;
        var distance = toOther.Magnitude;
        
        // Check if we're behind the other car
        var behindDot = FPVector2.Dot(filter.Transform->Up, toOther.Normalized);
        var alignmentDot = FPVector2.Dot(filter.Transform->Up, other.Up);
        
        if (behindDot > FP._0_70 && alignmentDot > FP._0_80 && distance < 10) {
            // We're in the slipstream - get a speed boost
            var slipstreamFactor = FPMath.Lerp(FP._1_00, FP._1_15, 
                FPMath.Clamp(FP._1_00 - distance / 10, FP._0, FP._1_00));
            
            filter.Bot->MaxSpeed = MaxSpeed * slipstreamFactor;
            
            // If we're gaining significantly on the car ahead, prepare an overtake
            if (filter.Body->Velocity.Magnitude > otherBody.Velocity.Magnitude * FP._1_10) {
                PrepareOvertake(f, ref filter);
            }
        }
    }
    
    // Continue with standard bot update...
}

private void PrepareOvertake(Frame f, ref BotSystem.Filter filter) {
    var other = f.Get<Transform2D>(filter.Racer->CarAhead);
    
    // Decide which side to overtake on
    var lateralOffset = FPVector2.Dot(other.Position - filter.Transform->Position, filter.Transform->Right);
    var overtakeSide = lateralOffset > 0 ? -1 : 1; // Opposite side of current offset
    
    // Apply overtaking behavior
    filter.Bot->OvertakeTimer = 3; // Seconds to maintain overtake behavior
    filter.Bot->OvertakeSide = overtakeSide;
}
```

### Dynamic Racing Line Selection

Enable bots to switch between multiple racing lines:

```csharp
public unsafe class DynamicRacelineSystem : SystemMainThread {
    public override void Update(Frame f) {
        f.Foreach((EntityRef entity, ref Bot bot, ref Racer racer) => {
            // Skip if bot doesn't have multiple racelines
            if (!bot.AlternativeRacelines.IsValid) return;
            
            var alternatives = f.FindAsset(bot.AlternativeRacelines);
            if (alternatives == null || alternatives.Racelines.Length == 0) return;
            
            // Evaluate current situation
            var situation = EvaluateRacingSituation(f, entity);
            
            // Select appropriate raceline
            AssetRef<CheckpointData> selectedRaceline = bot.Raceline;
            
            switch (situation) {
                case RacingSituation.Leading:
                    // Use defensive line when leading
                    selectedRaceline = alternatives.Racelines[0];
                    break;
                    
                case RacingSituation.Chasing:
                    // Use aggressive line when chasing
                    selectedRaceline = alternatives.Racelines[1]; 
                    break;
                    
                case RacingSituation.Overtaking:
                    // Use overtaking line
                    selectedRaceline = alternatives.Racelines[2];
                    break;
                    
                case RacingSituation.Normal:
                default:
                    // Use default raceline
                    selectedRaceline = bot.Raceline;
                    break;
            }
            
            // If raceline is changing, handle the transition
            if (selectedRaceline != bot.Raceline) {
                TransitionToNewRaceline(f, entity, ref bot, selectedRaceline);
            }
        });
    }
    
    private RacingSituation EvaluateRacingSituation(Frame f, EntityRef entity) {
        var racer = f.Get<Racer>(entity);
        
        // Leading the race
        if (racer.Position == 1) return RacingSituation.Leading;
        
        // Car close behind
        if (racer.CarBehind.IsValid) {
            var behindTransform = f.Get<Transform2D>(racer.CarBehind);
            var transform = f.Get<Transform2D>(entity);
            
            var distance = (behindTransform.Position - transform.Position).Magnitude;
            if (distance < 15) return RacingSituation.Defensive;
        }
        
        // Car close ahead
        if (racer.CarAhead.IsValid) {
            var aheadTransform = f.Get<Transform2D>(racer.CarAhead);
            var transform = f.Get<Transform2D>(entity);
            
            var distance = (aheadTransform.Position - transform.Position).Magnitude;
            if (distance < 20) return RacingSituation.Overtaking;
            if (distance < 50) return RacingSituation.Chasing;
        }
        
        return RacingSituation.Normal;
    }
    
    private void TransitionToNewRaceline(Frame f, EntityRef entity, ref Bot bot, AssetRef<CheckpointData> newRaceline) {
        // Find closest point on new raceline
        var transform = f.Get<Transform2D>(entity);
        var raceline = f.FindAsset(newRaceline);
        
        int closestIdx = 0;
        FP closestDistance = FP.MaxValue;
        
        for (int i = 0; i < raceline.Raceline.Count; i++) {
            var point = raceline.Raceline[i];
            var distance = (point.Position - transform.Position).Magnitude;
            
            if (distance < closestDistance) {
                closestDistance = distance;
                closestIdx = i;
            }
        }
        
        // Switch to new raceline
        bot.Raceline = newRaceline;
        bot.RacelineIndex = closestIdx;
    }
    
    private enum RacingSituation {
        Normal,
        Leading,
        Chasing,
        Overtaking,
        Defensive
    }
}
```

By implementing these advanced techniques and following the best practices, you can create sophisticated and engaging bot behavior in your Quantum racing game while maintaining good performance and scalability.
