# Implementation Guide: Adding Photon Quantum Bots to Racing Games

## Overview

This guide provides a step-by-step approach to implementing Photon Quantum bots in racing games, based on the patterns used in Quantum Karts. The guide focuses on practical implementation details and best practices.

## Step 1: Define the Bot Component Structure

Create a quantum component to store the bot's state:

```csharp
// BotDriver.qtn
component BotDriver {
    // Bot identification
    sbyte BotIndex;
    
    // Navigation data
    FPVector3 CurrentWaypoint;
    FPVector3 NextWaypoint;
    
    // Configuration
    asset_ref<BotSettings> SettingsRef;
    
    // State tracking
    FP StuckTimer;
    FP ActionCooldown;
}
```

## Step 2: Create Bot Settings Asset

Define a settings asset to control bot behavior:

```csharp
// BotSettings.cs
[Serializable]
public unsafe partial class BotSettings : AssetObject
{
    // Navigation parameters
    public FP LookAheadDistance;
    public FP SteeringResponseCurve;
    
    // Behavior parameters
    public FP AggressionLevel;
    public FP DriftThreshold;
    public FP RecoveryThreshold;
    
    // Performance parameters
    public FP MaxSpeed;
    public FP Acceleration;
    
    // Visual customization
    public AssetRef<VehicleVisuals> Appearance;
    public string BotName;
}
```

## Step 3: Implement Bot Decision Logic

Create the core decision-making logic that will run each frame:

```csharp
// BotDriver.cs
public unsafe partial struct BotDriver
{
    public void Update(Frame frame, VehicleSystem.Filter filter, ref Input input)
    {
        // Load settings
        BotSettings settings = frame.FindAsset(SettingsRef);
        
        // Calculate vectors to waypoints
        FPVector3 toCurrentWaypoint = CurrentWaypoint - filter.Transform->Position;
        FPVector3 toNextWaypoint = NextWaypoint - filter.Transform->Position;
        toCurrentWaypoint.Y = 0; // Ignore height differences
        toNextWaypoint.Y = 0;
        
        // Calculate prediction amount based on distance
        FP distanceToCurrent = toCurrentWaypoint.Magnitude;
        FP blendFactor = FPMath.Clamp01(distanceToCurrent / settings.LookAheadDistance);
        
        // Blend between current and next waypoints for smoother cornering
        FPVector3 targetDirection = FPVector3.Lerp(
            toCurrentWaypoint.Normalized,
            toNextWaypoint.Normalized,
            blendFactor
        );
        
        // Determine steering input
        FP angleToTarget = FPVector3.SignedAngle(
            filter.Vehicle->Forward,
            targetDirection,
            FPVector3.Up
        );
        
        // Apply steering response curve
        FP steeringAmount = settings.SteeringResponseCurve.Evaluate(FPMath.Abs(angleToTarget) / FP._180) 
            * FPMath.Sign(angleToTarget);
            
        // Set steering input
        input.Direction.X = FPMath.Clamp(steeringAmount, -FP._1, FP._1);
        
        // Always accelerate (can be made more nuanced)
        input.Direction.Y = FP._1;
        
        // Handle drifting
        FP turnSharpness = FPVector3.Angle(toCurrentWaypoint, toNextWaypoint);
        if (turnSharpness > settings.DriftThreshold && distanceToCurrent < FP._10) {
            input.Drift = true;
        }
        
        // Handle recovery
        UpdateStuckDetection(frame, filter);
        if (StuckTimer > settings.RecoveryThreshold) {
            input.Reset = true;
            StuckTimer = FP._0;
        }
        
        // Handle item usage
        UpdateItemUsage(frame, filter, ref input);
    }
    
    private void UpdateStuckDetection(Frame frame, VehicleSystem.Filter filter)
    {
        // Detect if bot is stuck by checking speed
        FP speedSqr = filter.Vehicle->Velocity.SqrMagnitude;
        if (speedSqr < FP._3) {
            StuckTimer += frame.DeltaTime;
        }
        else {
            StuckTimer = FPMath.Max(FP._0, StuckTimer - frame.DeltaTime);
        }
    }
    
    private void UpdateItemUsage(Frame frame, VehicleSystem.Filter filter, ref Input input)
    {
        // Simple item usage with cooldown
        ActionCooldown = FPMath.Max(FP._0, ActionCooldown - frame.DeltaTime);
        
        if (ActionCooldown <= FP._0 && filter.ItemHolder->HasItem) {
            // Determine if the current item should be used
            if (ShouldUseItem(frame, filter)) {
                input.UseItem = true;
                ActionCooldown = FP._1; // 1-second cooldown
            }
        }
    }
    
    private bool ShouldUseItem(Frame frame, VehicleSystem.Filter filter)
    {
        // Item usage strategy could be implemented here
        // For example, use offensive items when there's a vehicle ahead
        return true; // Simplified for this example
    }
    
    public void UpdateWaypoints(Frame frame, EntityRef entity)
    {
        // Get track and progress components
        Track* track = frame.Unsafe.GetPointerSingleton<Track>();
        Progress* progress = frame.Unsafe.GetPointer<Progress>(entity);
        
        // Get bot settings
        BotSettings settings = frame.FindAsset(SettingsRef);
        
        // Get current waypoint position
        CurrentWaypoint = track->GetWaypointPosition(
            frame, 
            progress->CurrentWaypointIndex, 
            settings.DrivingLine
        );
        
        // Calculate next waypoint index
        int nextIndex = progress->CurrentWaypointIndex + 1;
        if (nextIndex >= track->GetWaypointCount(frame)) {
            nextIndex = 0; // Loop back to start for next lap
        }
        
        // Get next waypoint position
        NextWaypoint = track->GetWaypointPosition(
            frame, 
            nextIndex, 
            settings.DrivingLine
        );
    }
}
```

## Step 4: Integrate with Vehicle System

Modify your vehicle system to handle bot-controlled vehicles:

```csharp
// VehicleSystem.cs
public unsafe class VehicleSystem : SystemMainThreadFilter<VehicleSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform3D* Transform;
        public Vehicle* Vehicle;
        public ItemHolder* ItemHolder;
        public Progress* Progress;
    }
    
    public override void Update(Frame frame, ref Filter filter)
    {
        // Start with default input
        Input input = default;
        
        // Skip if race hasn't started
        if (!IsRaceActive(frame)) {
            return;
        }
        
        // Get input based on entity type (bot or player)
        if (frame.Unsafe.TryGetPointer(filter.Entity, out BotDriver* bot))
        {
            // Get input from bot
            bot->Update(frame, filter, ref input);
        }
        else if (frame.Unsafe.TryGetPointer(filter.Entity, out PlayerLink* playerLink))
        {
            // Get input from player
            input = *frame.GetPlayerInput(playerLink->Player);
        }
        
        // Process input for vehicle
        ProcessVehicleInput(frame, ref filter, input);
    }
    
    private void ProcessVehicleInput(Frame frame, ref Filter filter, Input input)
    {
        // Update vehicle physics based on input
        filter.Vehicle->ProcessSteering(input.Direction.X);
        filter.Vehicle->ProcessAcceleration(input.Direction.Y);
        
        // Handle special inputs
        if (input.Drift) {
            filter.Vehicle->StartDrift();
        }
        
        if (input.UseItem && filter.ItemHolder->HasItem) {
            filter.ItemHolder->UseItem(frame, filter.Entity);
        }
        
        if (input.Reset) {
            RequestReset(frame, filter.Entity);
        }
    }
    
    // Methods for bot management
    
    public void SpawnBot(Frame frame, AssetRef<BotSettings> settings = default)
    {
        // If no settings provided, get random settings
        if (settings == default) {
            settings = GetRandomBotSettings(frame);
        }
        
        // Create vehicle entity for bot
        EntityRef botEntity = CreateVehicleEntity(frame, settings);
        
        // Add bot component
        frame.Add<BotDriver>(botEntity);
        
        // Initialize bot
        if (frame.Unsafe.TryGetPointer<BotDriver>(botEntity, out var bot)) {
            bot->SettingsRef = settings;
            bot->UpdateWaypoints(frame, botEntity);
        }
    }
    
    public void ConvertToBot(Frame frame, EntityRef vehicleEntity, AssetRef<BotSettings> settings = default)
    {
        // Add bot component to existing vehicle
        frame.Add<BotDriver>(vehicleEntity);
        
        // Initialize bot
        if (frame.Unsafe.TryGetPointer<BotDriver>(vehicleEntity, out var bot)) {
            bot->SettingsRef = settings ?? GetRandomBotSettings(frame);
            bot->UpdateWaypoints(frame, vehicleEntity);
        }
        
        // Remove player link if exists
        if (frame.Has<PlayerLink>(vehicleEntity)) {
            frame.Remove<PlayerLink>(vehicleEntity);
        }
    }
    
    public void ConvertToPlayer(Frame frame, EntityRef vehicleEntity, PlayerRef player)
    {
        // Remove bot component if exists
        if (frame.Has<BotDriver>(vehicleEntity)) {
            frame.Remove<BotDriver>(vehicleEntity);
        }
        
        // Add player link
        var playerLink = new PlayerLink {
            Player = player
        };
        frame.Add(vehicleEntity, playerLink);
    }
    
    private AssetRef<BotSettings> GetRandomBotSettings(Frame frame)
    {
        // Get race configuration
        var config = frame.FindAsset<RaceConfig>(frame.RuntimeConfig.RaceConfigRef);
        
        // Select random bot settings
        int index = frame.RNG->Next(config.BotProfiles.Length);
        return config.BotProfiles[index];
    }
}
```

## Step 5: Implement Waypoint System

Create a track system with waypoints that bots can follow:

```csharp
// Track.cs
public unsafe partial struct Track
{
    // List of waypoint entities
    public QList<EntityRef> Waypoints;
    
    public QList<EntityRef> GetWaypoints(Frame frame)
    {
        return frame.ResolveList(Waypoints);
    }
    
    public int GetWaypointCount(Frame frame)
    {
        return GetWaypoints(frame).Count;
    }
    
    public FPVector3 GetWaypointPosition(Frame frame, int waypointIndex, FP drivingLine)
    {
        // Get waypoint entity
        var waypoints = GetWaypoints(frame);
        var waypoint = waypoints[waypointIndex % waypoints.Count];
        
        // Get base position
        Transform3D* waypointTransform = frame.Unsafe.GetPointer<Transform3D>(waypoint);
        FPVector3 basePosition = waypointTransform->Position;
        
        // Apply driving line offset if waypoint has width
        if (frame.Unsafe.TryGetPointer<Waypoint>(waypoint, out var waypointData)) {
            // Adjust position based on driving line parameter
            // -1.0 = far left, 0.0 = center, 1.0 = far right
            FPVector3 rightVector = FPVector3.Cross(waypointTransform->Forward, FPVector3.Up);
            FPVector3 offset = rightVector * drivingLine * waypointData->Width * FP._0_50;
            return basePosition + offset;
        }
        
        return basePosition;
    }
}

// Waypoint.cs
public unsafe partial struct Waypoint
{
    public FP Width;      // Width of the track at this point
    public sbyte Section;  // Track section (for grouping waypoints)
    public bool IsCheckpoint; // Is this a checkpoint for lap counting
}
```

## Step 6: Handle Race Events and Bot Spawning

Implement event handlers for race state changes:

```csharp
// RaceManager.cs
public unsafe class RaceManager : SystemMainThread, 
    ISignalOnPlayerConnected, 
    ISignalOnPlayerDisconnected,
    ISignalRaceStateChanged
{
    public void OnPlayerConnected(Frame frame, PlayerRef player)
    {
        // Find any bot-controlled vehicles that should be taken over by this player
        EntityRef vehicleEntity = FindVehicleForPlayer(frame, player);
        
        if (vehicleEntity != default) {
            // Convert bot to player-controlled
            frame.Unsafe.GetPointer<VehicleSystem>()->ConvertToPlayer(frame, vehicleEntity, player);
        }
        else {
            // Create new vehicle for player
            SpawnPlayerVehicle(frame, player);
        }
    }
    
    public void OnPlayerDisconnected(Frame frame, PlayerRef player)
    {
        // Find player's vehicle
        EntityRef vehicleEntity = FindPlayerVehicle(frame, player);
        
        if (vehicleEntity != default) {
            // Convert to bot-controlled
            frame.Unsafe.GetPointer<VehicleSystem>()->ConvertToBot(frame, vehicleEntity);
        }
    }
    
    public void RaceStateChanged(Frame frame, RaceState newState)
    {
        if (newState == RaceState.Waiting) {
            // Spawn initial bots
            SpawnInitialBots(frame);
        }
        else if (newState == RaceState.Countdown && frame.RuntimeConfig.FillWithBots) {
            // Fill remaining slots with bots
            FillWithBots(frame);
        }
    }
    
    private void SpawnInitialBots(Frame frame)
    {
        var vehicleSystem = frame.Unsafe.GetPointer<VehicleSystem>();
        int botCount = frame.RuntimeConfig.BotCount;
        
        for (int i = 0; i < botCount; i++) {
            vehicleSystem->SpawnBot(frame);
        }
    }
    
    private void FillWithBots(Frame frame)
    {
        int currentVehicles = frame.ComponentCount<Vehicle>();
        int targetVehicles = frame.RuntimeConfig.MaxRacers;
        int missingVehicles = targetVehicles - currentVehicles;
        
        if (missingVehicles <= 0) {
            return;
        }
        
        var vehicleSystem = frame.Unsafe.GetPointer<VehicleSystem>();
        
        for (int i = 0; i < missingVehicles; i++) {
            vehicleSystem->SpawnBot(frame);
        }
    }
}
```

## Step 7: Create Difficulty Profiles

Define multiple difficulty profiles for bots:

```csharp
// In Unity Editor script
public class BotProfileCreator : MonoBehaviour
{
    public void CreateBotProfiles()
    {
        // Create easy bot profile
        var easyBot = ScriptableObject.CreateInstance<BotSettings>();
        easyBot.LookAheadDistance = FP._5;
        easyBot.AggressionLevel = FP._0_25;
        easyBot.DriftThreshold = FP._45; // Less likely to drift
        easyBot.RecoveryThreshold = FP._3; // Recover quickly
        easyBot.MaxSpeed = FP._0_80; // 80% of max speed
        easyBot.BotName = "Rookie";
        AssetDatabase.CreateAsset(easyBot, "Assets/Resources/BotProfiles/EasyBot.asset");
        
        // Create medium bot profile
        var mediumBot = ScriptableObject.CreateInstance<BotSettings>();
        mediumBot.LookAheadDistance = FP._10;
        mediumBot.AggressionLevel = FP._0_50;
        mediumBot.DriftThreshold = FP._35;
        mediumBot.RecoveryThreshold = FP._2;
        mediumBot.MaxSpeed = FP._0_90; // 90% of max speed
        mediumBot.BotName = "Racer";
        AssetDatabase.CreateAsset(mediumBot, "Assets/Resources/BotProfiles/MediumBot.asset");
        
        // Create hard bot profile
        var hardBot = ScriptableObject.CreateInstance<BotSettings>();
        hardBot.LookAheadDistance = FP._15;
        hardBot.AggressionLevel = FP._0_75;
        hardBot.DriftThreshold = FP._25; // More likely to drift
        hardBot.RecoveryThreshold = FP._1_50;
        hardBot.MaxSpeed = FP._0_95; // 95% of max speed
        hardBot.BotName = "Pro";
        AssetDatabase.CreateAsset(hardBot, "Assets/Resources/BotProfiles/HardBot.asset");
    }
}
```

## Step 8: Configure Runtime Settings

Add bot configuration to runtime settings:

```csharp
// RuntimeConfig additions
public partial class RuntimeConfig
{
    public byte BotCount;
    public byte MaxRacers;
    public bool FillWithBots;
    public AssetRef<RaceConfig> RaceConfigRef;
}
```

## Step 9: Add Debug Visualization

Implement debug visualization to help tune bot behavior:

```csharp
// BotDebugSystem.cs
#if UNITY_EDITOR || DEVELOPMENT_BUILD
public unsafe class BotDebugSystem : SystemMainThread
{
    public override void Update(Frame frame)
    {
        if (!frame.RuntimeConfig.EnableBotDebug) {
            return;
        }
        
        foreach (var pair in frame.Unsafe.GetComponentBlockIterator<BotDriver>())
        {
            BotDriver* bot = pair.Component;
            EntityRef entity = pair.Entity;
            
            if (frame.Unsafe.TryGetPointer<Transform3D>(entity, out var transform))
            {
                // Draw line to current waypoint
                Draw.Line(transform->Position, bot->CurrentWaypoint, ColorRGBA.Green);
                
                // Draw line to next waypoint
                Draw.Line(transform->Position, bot->NextWaypoint, ColorRGBA.Blue);
                
                // Draw prediction vector
                BotSettings settings = frame.FindAsset(bot->SettingsRef);
                FPVector3 toCurrentWaypoint = bot->CurrentWaypoint - transform->Position;
                FPVector3 toNextWaypoint = bot->NextWaypoint - transform->Position;
                toCurrentWaypoint.Y = 0;
                toNextWaypoint.Y = 0;
                
                FP distanceToCurrent = toCurrentWaypoint.Magnitude;
                FP blendFactor = FPMath.Clamp01(distanceToCurrent / settings.LookAheadDistance);
                
                FPVector3 targetDirection = FPVector3.Lerp(
                    toCurrentWaypoint.Normalized, 
                    toNextWaypoint.Normalized, 
                    blendFactor
                );
                
                Draw.Line(transform->Position, transform->Position + (targetDirection * FP._5), ColorRGBA.Red);
                
                // Draw bot index and state
                Draw.String(transform->Position + FPVector3.Up * FP._2, $"Bot {bot->BotIndex}", ColorRGBA.White);
            }
        }
    }
}
#endif
```

## Step 10: Performance Optimization

Implement performance optimizations for handling many bots:

```csharp
// Performance optimizations for BotDriver.Update

// 1. Skip detailed updates for distant bots
if (IsOutOfPlayerRange(frame, filter.Entity)) {
    // Use simplified logic for distant bots
    input.Direction = FPVector2.Up; // Just keep going forward
    return;
}

// 2. Use interval-based updates for non-critical systems
if (frame.Number % 5 == bot->BotIndex % 5) {
    // Only update item usage logic every 5 frames
    UpdateItemUsage(frame, filter, ref input);
}

// 3. Share computation results between systems
// Store precalculated data in a singleton component
if (frame.Unsafe.TryGetPointerSingleton<BotSharedData>(out var sharedData)) {
    // Use shared data for common calculations
    if (sharedData->UpdateFrame == frame.Number) {
        // Use precalculated data
    }
}

// 4. Level-of-detail for decision making
FP distanceToPlayer = GetDistanceToClosestPlayer(frame, filter.Entity);
if (distanceToPlayer > FP._100) {
    // Use very basic AI for far-away bots
} else if (distanceToPlayer > FP._50) {
    // Use medium complexity AI
} else {
    // Use full AI for nearby bots
}
```

## Key Best Practices

1. **Deterministic Logic**: Always use deterministic calculations for bot decisions.
2. **Layered Difficulty**: Create multiple difficulty levels through varied settings.
3. **Waypoint System**: Use waypoints for reliable navigation rather than dynamic pathfinding.
4. **Performance Scaling**: Scale AI complexity based on distance or importance.
5. **Easy Configuration**: Make bot behavior easily configurable through assets.
6. **Player Conversion**: Allow seamless conversion between bot and player-controlled vehicles.
7. **Graceful Recovery**: Implement stuck detection and recovery mechanisms.
8. **Testing Tools**: Create visualization tools for debugging and tuning.

## Common Pitfalls to Avoid

1. **Non-Deterministic Decisions**: Avoid using Unity's Random instead of Quantum's RNG.
2. **Over-Correction**: Bots that over-correct steering often oscillate wildly.
3. **Perfect Bots**: Make bots slightly imperfect to create natural-looking behavior.
4. **Ignoring Physics**: Bots should obey the same physics constraints as players.
5. **Complex Pathfinding**: Avoid dynamic pathfinding for racing games; use waypoints instead.
6. **CPU Bottlenecks**: Optimize bot logic, as it runs for each bot every frame.
7. **Rubberbanding**: Be careful with catch-up mechanics that can feel unfair.
