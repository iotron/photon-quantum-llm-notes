# Networking and Determinism

This document details how the bot system in the twin stick shooter game integrates with Photon Quantum's deterministic networking.

## Deterministic Bot Behavior

The twin stick shooter uses Photon Quantum as its networking solution, which requires all simulation code to be deterministic. The bot system is designed to maintain perfect determinism across all clients:

1. All random number generation uses Quantum's deterministic RNG
2. All physics and math operations use fixed-point arithmetic
3. All bot decisions derive solely from the deterministic game state
4. No Unity-specific or host-dependent code is used in the simulation layer

## Random Number Generation

Random decisions, such as evasion direction or attack selection, use Quantum's deterministic RNG:

```csharp
// Example of deterministic RNG in the bot system
public class RandomizedDecision : HFSMDecision
{
    public FP Probability = FP._0_5;
    
    public override bool Decide(Frame frame, EntityRef entity)
    {
        // Use frame.RNG for all random number generation
        // Never use Unity's Random.Range or similar
        return frame.RNG->Next() < Probability;
    }
}

// Example of random direction selection
private void DefineEvasionDirection(Frame frame, Transform2D* agentTransform, FPVector2 dirToTarget)
{
    EvasionTimer = MaxEvasionDuration;
    
    // Use frame.RNG for deterministic randomness
    int randomDir = frame.RNG->NextInclusive(-1, 1);
    
    if (randomDir < 0)
    {
        EvasionDirectionVector = agentTransform->Left;
        EvasionDirection = -1;
    }
    else if (randomDir > 0)
    {
        EvasionDirectionVector = agentTransform->Right;
        EvasionDirection = 1;
    }
    else
    {
        EvasionDirectionVector = default;
        EvasionDirection = 0;
    }
}
```

## Time-Based Operations

For time-based operations, the bot system uses Quantum's frame number and delta time:

```csharp
// Example of time-based cooldown
public class CooldownManager : SystemMainThread
{
    public override void Update(Frame f)
    {
        var bots = f.Filter<Bot, AIBlackboardComponent>();
        while (bots.NextUnsafe(out EntityRef entity, out Bot* bot, out AIBlackboardComponent* blackboard))
        {
            if (bot->IsActive == false)
                continue;
            
            // Use f.DeltaTime instead of Time.deltaTime
            if (blackboard->Has("SpecialAttackCooldown"))
            {
                FP cooldown = blackboard->Get<FP>("SpecialAttackCooldown");
                cooldown -= f.DeltaTime;
                
                if (cooldown <= 0)
                {
                    blackboard->Remove("SpecialAttackCooldown");
                }
                else
                {
                    blackboard->Set("SpecialAttackCooldown", cooldown);
                }
            }
        }
    }
}

// Example of using frame number for deterministic timing
private bool ShouldUpdateSensor(Frame frame, string sensorName, FP updateInterval)
{
    // Create a deterministic update pattern based on frame number
    return frame.Number % FP.FloorToInt(updateInterval / frame.DeltaTime) == 0;
}
```

## Networked Input System

Bot inputs are processed through the same input system as player inputs:

```csharp
public class InputSystem : SystemMainThread
{
    public override void Update(Frame f)
    {
        // Process player inputs first
        for (int i = 0; i < f.PlayerCount; i++)
        {
            PlayerRef playerRef = i;
            
            // Get player input from the network
            Input input = default;
            if (f.GetPlayerInput(playerRef, out Quantum.Input networkInput))
            {
                input = networkInput.Input;
            }
            
            // Apply input to all player entities
            var playerEntities = f.Filter<PlayerLink, Transform2D>();
            while (playerEntities.Next(out EntityRef entity, out PlayerLink playerLink, out Transform2D transform))
            {
                if (playerLink.PlayerRef == playerRef)
                {
                    // This entity belongs to this player
                    ApplyInput(f, entity, input);
                }
            }
        }
        
        // Process bot inputs
        var botEntities = f.Filter<Bot, Transform2D>();
        while (botEntities.Next(out EntityRef entity, out Bot bot, out Transform2D transform))
        {
            if (bot.IsActive == false)
                continue;
            
            // Use the bot's Input, which is set by the AI system
            ApplyInput(f, entity, bot.Input);
        }
    }
    
    private void ApplyInput(Frame f, EntityRef entity, Input input)
    {
        // Apply movement input
        if (f.Has<KCC>(entity))
        {
            KCC* kcc = f.Unsafe.GetPointer<KCC>(entity);
            kcc->Move(input.MoveDirection);
        }
        
        // Apply rotation input
        if (f.Has<Transform2D>(entity))
        {
            Transform2D* transform = f.Unsafe.GetPointer<Transform2D>(entity);
            if (input.AimDirection != default)
            {
                transform->Rotation = FPMath.Atan2(input.AimDirection.Y, input.AimDirection.X);
                transform->Up = input.AimDirection;
            }
        }
        
        // Apply attack input
        if (input.Attack)
        {
            f.Signals.OnAttackInput(entity);
        }
        
        // Apply special attack input
        if (input.SpecialAttack)
        {
            f.Signals.OnSpecialAttackInput(entity);
        }
        
        // Apply other inputs
        // ...
    }
}
```

## Bot Creation and Ownership

Bots can be created on any client through a verified command:

```csharp
// Command for creating a bot (can be called from any client)
public unsafe class CreateBotCommand : QCommand
{
    public FPVector2 Position;
    public byte TeamId;
    public AssetRefBotPrototype BotPrototype;
    public byte DifficultyLevel;
    
    public override void Execute(Frame frame)
    {
        // Create the bot using the specified prototype
        BotPrototype botPrototype = frame.FindAsset<BotPrototype>(BotPrototype.Id);
        EntityRef botEntity = frame.Create(botPrototype);
        
        // Set position and team
        frame.Unsafe.GetPointer<Transform2D>(botEntity)->Position = Position;
        frame.Unsafe.GetPointer<TeamInfo>(botEntity)->Index = TeamId;
        
        // Assign player reference (for input polling)
        // This ensures the bot is handled by a specific client
        PlayerLink* playerLink = frame.Unsafe.GetPointer<PlayerLink>(botEntity);
        
        // Assign to a client (e.g., the command sender or a designated host)
        // This depends on your game's design
        playerLink->PlayerRef = frame.PlayerCount - 1; // Example: assign to last player
        
        // Set difficulty level
        if (frame.Has<AIBlackboardComponent>(botEntity))
        {
            frame.Unsafe.GetPointer<AIBlackboardComponent>(botEntity)->Set("DifficultyLevel", DifficultyLevel);
        }
        
        // Activate the bot
        AISetupHelper.Botify(frame, botEntity);
    }
}
```

## Client-Specific Visualization

While the simulation is deterministic, visualizations can be client-specific:

```csharp
public class BotDebugVisualizer : MonoBehaviour
{
    [Header("Local Visualization Settings")]
    public bool ShowLocalDebugOnly = true;
    public bool ShowPathLines = true;
    public bool ShowSensorRanges = true;
    
    private void OnEnable()
    {
        QuantumCallback.Subscribe(this, (CallbackOnDrawGizmos callback) => OnDrawGizmos(callback.Frame));
    }
    
    private void OnDisable()
    {
        QuantumCallback.Unsubscribe(this);
    }
    
    private void OnDrawGizmos(Frame frame)
    {
        if (frame == null)
            return;
        
        // Check if this client is the local player
        bool isLocalPlayer = true; // Simplified for example
        
        if (ShowLocalDebugOnly && !isLocalPlayer)
            return;
        
        // Draw debug visualizations
        var bots = frame.Filter<Bot, Transform2D>();
        while (bots.Next(out EntityRef entity, out Bot bot, out Transform2D transform))
        {
            if (bot.IsActive == false)
                continue;
            
            Vector3 position = transform.Position.ToUnityVector3();
            
            // Draw path lines
            if (ShowPathLines && frame.Has<NavMeshPathfinder>(entity))
            {
                var pathfinder = frame.Get<NavMeshPathfinder>(entity);
                var path = frame.ResolveList(pathfinder.Path);
                
                if (path.Count > 1)
                {
                    Gizmos.color = Color.blue;
                    
                    Vector3 lastPoint = position;
                    for (int i = 0; i < path.Count; i++)
                    {
                        Vector3 point = path[i].Position.ToUnityVector3();
                        Gizmos.DrawLine(lastPoint, point);
                        lastPoint = point;
                    }
                }
            }
            
            // Draw sensor ranges
            if (ShowSensorRanges && frame.Has<HFSMAgent>(entity))
            {
                var hfsmAgent = frame.Get<HFSMAgent>(entity);
                var aiConfig = frame.FindAsset<AIConfig>(hfsmAgent.Config.Id);
                
                if (aiConfig != null)
                {
                    Gizmos.color = new Color(0.5f, 0.5f, 0.5f, 0.2f);
                    Gizmos.DrawWireSphere(position, aiConfig.SightRange.AsFloat);
                }
            }
        }
    }
}
```

## Synchronization Verification

The twin stick shooter includes tools for verifying that bots behave identically across clients:

```csharp
public class BotSyncVerifier : SystemMainThread
{
    private Dictionary<int, int> _botStateHashCache = new Dictionary<int, int>();
    
    public override void Update(Frame frame)
    {
        if (frame.IsVerified == false)
            return;
        
        // Only run on specific frames to minimize performance impact
        if (frame.Number % 60 != 0)
            return;
        
        var bots = frame.Filter<Bot>();
        while (bots.Next(out EntityRef entity, out Bot bot))
        {
            if (bot.IsActive == false)
                continue;
            
            // Calculate a hash of the bot's state
            int stateHash = CalculateBotStateHash(frame, entity);
            
            // Check if we have a previous hash for this bot
            if (_botStateHashCache.TryGetValue(entity.Id, out int previousHash))
            {
                // Compare hashes
                if (stateHash != previousHash)
                {
                    // Log desync
                    Log.Error($"Bot {entity.Id} state hash mismatch: {previousHash} vs {stateHash}");
                    
                    // Additional debug info
                    DumpBotState(frame, entity);
                }
            }
            
            // Update hash cache
            _botStateHashCache[entity.Id] = stateHash;
        }
        
        // Clean up hashes for deleted bots
        List<int> botsToRemove = new List<int>();
        foreach (var kvp in _botStateHashCache)
        {
            EntityRef entity = new EntityRef { Id = kvp.Key };
            if (!frame.Exists(entity) || !frame.Has<Bot>(entity) || !frame.Get<Bot>(entity).IsActive)
            {
                botsToRemove.Add(kvp.Key);
            }
        }
        
        foreach (int id in botsToRemove)
        {
            _botStateHashCache.Remove(id);
        }
    }
    
    private int CalculateBotStateHash(Frame frame, EntityRef entity)
    {
        int hash = 17;
        
        // Include bot input in the hash
        Bot bot = frame.Get<Bot>(entity);
        hash = hash * 31 + bot.Input.MoveDirection.X.GetHashCode();
        hash = hash * 31 + bot.Input.MoveDirection.Y.GetHashCode();
        hash = hash * 31 + bot.Input.AimDirection.X.GetHashCode();
        hash = hash * 31 + bot.Input.AimDirection.Y.GetHashCode();
        hash = hash * 31 + bot.Input.Attack.GetHashCode();
        hash = hash * 31 + bot.Input.SpecialAttack.GetHashCode();
        
        // Include position and rotation in the hash
        if (frame.Has<Transform2D>(entity))
        {
            Transform2D transform = frame.Get<Transform2D>(entity);
            hash = hash * 31 + transform.Position.X.GetHashCode();
            hash = hash * 31 + transform.Position.Y.GetHashCode();
            hash = hash * 31 + transform.Rotation.GetHashCode();
        }
        
        // Include HFSM state in the hash
        if (frame.Has<HFSMAgent>(entity))
        {
            HFSMAgent agent = frame.Get<HFSMAgent>(entity);
            hash = hash * 31 + agent.CurrentStateEntity.Id.GetHashCode();
        }
        
        return hash;
    }
    
    private void DumpBotState(Frame frame, EntityRef entity)
    {
        // Dump detailed bot state for debugging
        Bot bot = frame.Get<Bot>(entity);
        
        string stateInfo = $"Bot {entity.Id} state:\n";
        
        // Basic info
        stateInfo += $"IsActive: {bot.IsActive}\n";
        
        // Input
        stateInfo += $"Input.MoveDirection: {bot.Input.MoveDirection}\n";
        stateInfo += $"Input.AimDirection: {bot.Input.AimDirection}\n";
        stateInfo += $"Input.Attack: {bot.Input.Attack}\n";
        stateInfo += $"Input.SpecialAttack: {bot.Input.SpecialAttack}\n";
        
        // Transform
        if (frame.Has<Transform2D>(entity))
        {
            Transform2D transform = frame.Get<Transform2D>(entity);
            stateInfo += $"Position: {transform.Position}\n";
            stateInfo += $"Rotation: {transform.Rotation}\n";
        }
        
        // HFSM state
        if (frame.Has<HFSMAgent>(entity))
        {
            HFSMAgent agent = frame.Get<HFSMAgent>(entity);
            
            if (agent.CurrentStateEntity != default)
            {
                var stateComponent = frame.Get<HFSMStateComponent>(agent.CurrentStateEntity);
                stateInfo += $"Current State: {stateComponent.Name}\n";
                stateInfo += $"Time In State: {stateComponent.TimeInState}\n";
            }
            else
            {
                stateInfo += "Current State: None\n";
            }
        }
        
        // Log the state info
        Log.Error(stateInfo);
    }
}
```

## Lag Compensation

The twin stick shooter implements lag compensation for bot reactions:

```csharp
public class BotLagCompensator : SystemMainThread
{
    [Serializable]
    public struct LagSettings
    {
        public FP MinReactionTime;
        public FP MaxReactionTime;
        public FP AimPredictionFactor;
    }
    
    public LagSettings[] DifficultySettings = new LagSettings[]
    {
        // Beginner
        new LagSettings
        {
            MinReactionTime = FP._0_5,
            MaxReactionTime = FP._1_5,
            AimPredictionFactor = FP._0_1
        },
        
        // Easy
        new LagSettings
        {
            MinReactionTime = FP._0_3,
            MaxReactionTime = FP._0_8,
            AimPredictionFactor = FP._0_3
        },
        
        // Medium
        new LagSettings
        {
            MinReactionTime = FP._0_2,
            MaxReactionTime = FP._0_5,
            AimPredictionFactor = FP._0_5
        },
        
        // Hard
        new LagSettings
        {
            MinReactionTime = FP._0_1,
            MaxReactionTime = FP._0_3,
            AimPredictionFactor = FP._0_8
        }
    };
    
    public override void Update(Frame frame)
    {
        var bots = frame.Filter<Bot, AIBlackboardComponent>();
        while (bots.NextUnsafe(out EntityRef entity, out Bot* bot, out AIBlackboardComponent* blackboard))
        {
            if (bot->IsActive == false)
                continue;
            
            // Get difficulty level
            int difficultyLevel = blackboard->GetOrDefault<int>("DifficultyLevel");
            difficultyLevel = Math.Clamp(difficultyLevel, 0, DifficultySettings.Length - 1);
            
            // Update reaction timers
            if (blackboard->Has("TargetDetectedTime"))
            {
                FP targetDetectedTime = blackboard->Get<FP>("TargetDetectedTime");
                FP currentTime = frame.Number * frame.DeltaTime;
                
                // Get reaction time for this difficulty
                LagSettings settings = DifficultySettings[difficultyLevel];
                FP reactionTime = settings.MinReactionTime + 
                    (settings.MaxReactionTime - settings.MinReactionTime) * 
                    frame.RNG->NextFloat(0f, 1f);
                
                // Check if reaction time has passed
                if (currentTime - targetDetectedTime >= reactionTime)
                {
                    // Allow the bot to react
                    blackboard->Set("CanReactToTarget", true);
                    
                    // Apply aim prediction based on difficulty
                    if (blackboard->Has("TargetEntity"))
                    {
                        EntityRef targetEntity = blackboard->Get<EntityRef>("TargetEntity");
                        
                        if (frame.Exists(targetEntity) && frame.Has<KCC>(targetEntity))
                        {
                            // Get target velocity
                            KCC* targetKCC = frame.Unsafe.GetPointer<KCC>(targetEntity);
                            FPVector2 targetVelocity = targetKCC->Velocity;
                            
                            // Get positions
                            Transform2D* botTransform = frame.Unsafe.GetPointer<Transform2D>(entity);
                            Transform2D* targetTransform = frame.Unsafe.GetPointer<Transform2D>(targetEntity);
                            
                            // Calculate distance and time to impact
                            FP distance = FPVector2.Distance(botTransform->Position, targetTransform->Position);
                            FP projectileSpeed = blackboard->GetOrDefault<FP>("ProjectileSpeed", FP._15);
                            FP timeToImpact = distance / projectileSpeed;
                            
                            // Calculate predicted position
                            FPVector2 predictedPosition = targetTransform->Position + 
                                targetVelocity * timeToImpact * settings.AimPredictionFactor;
                            
                            // Store predicted position
                            blackboard->Set("TargetPredictedPosition", predictedPosition);
                        }
                    }
                }
            }
        }
    }
}
```

## Deterministic Pathfinding

The bot system uses Quantum's deterministic NavMesh for pathfinding:

```csharp
public class BotPathfindingSystem : SystemMainThread
{
    public override void Update(Frame frame)
    {
        var pathfinders = frame.Filter<NavMeshPathfinder, NavMeshSteeringAgent, Bot>();
        while (pathfinders.Next(out EntityRef entity, out NavMeshPathfinder pathfinder, out NavMeshSteeringAgent steeringAgent, out Bot bot))
        {
            if (bot.IsActive == false)
                continue;
            
            // Check if the agent needs a path update
            if (pathfinder.ShouldUpdatePath(frame, entity))
            {
                // Get target position from blackboard
                if (frame.Has<AIBlackboardComponent>(entity))
                {
                    var blackboard = frame.Get<AIBlackboardComponent>(entity);
                    
                    if (blackboard.Has("TargetPosition"))
                    {
                        FPVector2 targetPosition = blackboard.Get<FPVector2>("TargetPosition");
                        
                        // Request path
                        pathfinder.UpdatePath(frame, entity, targetPosition);
                    }
                }
            }
        }
    }
}

// NavMeshPathfinder extension for deterministic path updates
public static unsafe class NavMeshPathfinderExtensions
{
    public static bool ShouldUpdatePath(this NavMeshPathfinder pathfinder, Frame frame, EntityRef entity)
    {
        // Check if we have a valid path
        bool hasPath = pathfinder.Path.Pointer != null && frame.ResolveList(pathfinder.Path).Count > 0;
        
        // Check if the update timer has expired
        bool timerExpired = pathfinder.PathUpdateTimer <= 0;
        
        // Check if we're at the end of the current path
        bool atPathEnd = false;
        if (hasPath)
        {
            var path = frame.ResolveList(pathfinder.Path);
            if (path.Count > 0)
            {
                // Get the final waypoint
                FPVector2 finalWaypoint = path[path.Count - 1].Position;
                
                // Get current position
                FPVector2 currentPosition = frame.Get<Transform2D>(entity).Position;
                
                // Check if we're close to the final waypoint
                FP distanceSquared = FPVector2.DistanceSquared(currentPosition, finalWaypoint);
                atPathEnd = distanceSquared < pathfinder.StoppingDistance * pathfinder.StoppingDistance;
            }
        }
        
        return !hasPath || timerExpired || atPathEnd;
    }
    
    public static void UpdatePath(this NavMeshPathfinder pathfinder, Frame frame, EntityRef entity, FPVector2 targetPosition)
    {
        // Get current position
        FPVector2 currentPosition = frame.Get<Transform2D>(entity).Position;
        
        // Reset path update timer
        pathfinder.PathUpdateTimer = pathfinder.PathUpdateInterval;
        
        // Calculate path
        frame.Physics3D.NavMesh.CalculatePath(
            currentPosition,
            targetPosition,
            pathfinder.MaxPathLength,
            pathfinder.MaxPathNodes,
            out var path);
        
        // Assign path
        if (path.Length > 0)
        {
            var pathList = frame.AllocateList<NavMeshPathNode>(path.Length);
            for (int i = 0; i < path.Length; i++)
            {
                pathList.Add(frame, path[i]);
            }
            
            pathfinder.Path = pathList;
        }
    }
}
```

## Network Bandwidth Optimization

To minimize network bandwidth, the bot system optimizes its state representation:

```csharp
// Compact bot state for efficient networking
public unsafe struct CompactBotState
{
    public byte Flags; // Bit 0: IsActive, Bit 1: IsAttacking, Bit 2: IsUsingSpecialAttack, etc.
    public byte BotType; // Type of bot (for visual representation)
    public FPVector2 Position;
    public FP Rotation;
    
    public static CompactBotState FromBot(Frame frame, EntityRef entity)
    {
        CompactBotState state = new CompactBotState();
        
        Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
        
        // Set flags
        state.Flags = 0;
        if (bot->IsActive) state.Flags |= 0x01;
        if (bot->Input.Attack) state.Flags |= 0x02;
        if (bot->Input.SpecialAttack) state.Flags |= 0x04;
        
        // Set bot type
        state.BotType = 0; // Default type
        if (frame.Has<Character>(entity))
        {
            Character* character = frame.Unsafe.GetPointer<Character>(entity);
            state.BotType = (byte)character->CharacterClass;
        }
        
        // Set position and rotation
        state.Position = transform->Position;
        state.Rotation = transform->Rotation;
        
        return state;
    }
}

// System to optimize bot representation
public class BotNetworkOptimizationSystem : SystemMainThread
{
    public override void OnInit(Frame frame)
    {
        // Register snapshot compression callbacks
        frame.RegisterCompressor<Bot>(CompressBot, DecompressBot);
    }
    
    private unsafe byte[] CompressBot(Bot bot)
    {
        // Compress essential bot state for network transmission
        // This is a simplified example
        byte[] data = new byte[10];
        data[0] = bot.IsActive ? (byte)1 : (byte)0;
        
        // Compress Input
        data[1] = (byte)(bot.Input.Attack ? 0x01 : 0x00);
        data[1] |= (byte)(bot.Input.SpecialAttack ? 0x02 : 0x00);
        
        // Compress MoveDirection (using custom FP encoding)
        EncodeFixedPoint(bot.Input.MoveDirection.X, data, 2);
        EncodeFixedPoint(bot.Input.MoveDirection.Y, data, 4);
        
        // Compress AimDirection (using custom FP encoding)
        EncodeFixedPoint(bot.Input.AimDirection.X, data, 6);
        EncodeFixedPoint(bot.Input.AimDirection.Y, data, 8);
        
        return data;
    }
    
    private unsafe void DecompressBot(byte[] data, Bot* bot)
    {
        // Decompress bot state from network data
        bot->IsActive = data[0] == 1;
        
        // Decompress Input
        bot->Input.Attack = (data[1] & 0x01) != 0;
        bot->Input.SpecialAttack = (data[1] & 0x02) != 0;
        
        // Decompress MoveDirection
        bot->Input.MoveDirection.X = DecodeFixedPoint(data, 2);
        bot->Input.MoveDirection.Y = DecodeFixedPoint(data, 4);
        
        // Decompress AimDirection
        bot->Input.AimDirection.X = DecodeFixedPoint(data, 6);
        bot->Input.AimDirection.Y = DecodeFixedPoint(data, 8);
    }
    
    private void EncodeFixedPoint(FP value, byte[] data, int offset)
    {
        // Custom encoding for FP values to save bandwidth
        // This is a simplified example
        short compressed = (short)(value.AsFloat * 32767);
        data[offset] = (byte)(compressed & 0xFF);
        data[offset + 1] = (byte)((compressed >> 8) & 0xFF);
    }
    
    private FP DecodeFixedPoint(byte[] data, int offset)
    {
        // Custom decoding for FP values
        short compressed = (short)((data[offset + 1] << 8) | data[offset]);
        return FPMath.FloatToFP(compressed / 32767.0f);
    }
}
```

These networking and determinism techniques ensure that bots behave consistently across all clients, even in high-latency network conditions. By leveraging Quantum's deterministic framework, the bot system maintains perfect synchronization while minimizing bandwidth usage and providing responsive behavior.
