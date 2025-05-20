# Performance Optimization

This document details the performance optimization techniques used in the twin stick shooter bot system.

## Optimization Overview

The twin stick shooter bot system is designed to support multiple bots while maintaining high performance. Key optimization areas include:

1. **Efficient data structures**: Using memory-efficient data structures and components
2. **Selective updates**: Using varied update rates for different systems
3. **Entity filtering**: Processing only relevant entities
4. **Spatial partitioning**: Using spatial awareness to reduce computation
5. **Component reuse**: Reusing components and systems from the player system
6. **Memory management**: Careful allocation and deallocation of memory

## Efficient Data Structures

### Component Design

Bot components are designed to minimize memory usage:

```csharp
// Memory-efficient Bot component
public unsafe struct Bot
{
    public Input Input;
    public DynamicAssetRef<NavMeshAgentConfig> NavMeshAgentConfig;
    public AssetRef BlackboardInitializer;
    public AssetRef HFSMRoot;
    public DynamicAssetRef<AIConfig> AIConfig;
    public bool IsActive;
    
    // Usage statistics for profiling (optional)
    public int MovementUpdates;
    public int PathfindingUpdates;
    public int SensorUpdates;
    public int HFSMUpdates;
}

// Memory-efficient Input component
public unsafe struct Input
{
    public FPVector2 MoveDirection;
    public FPVector2 AimDirection;
    public bool Attack;
    public bool SpecialAttack;
    public bool Jump;
    public bool Dash;
}

// Memory-efficient AISteering component
public unsafe struct AISteering
{
    public FPVector2 CurrentDirection;
    public FP LerpFactor;
    public FP MainSteeringWeight;
    public SteeringData MainSteeringData;
    public FP EvasionTimer;
    public FP MaxEvasionDuration;
    public int EvasionDirection;
    public FPVector2 EvasionDirectionVector;
}
```

These components use minimal memory and avoid redundant data.

### Smart Data Structures

The bot system uses specialized data structures for efficiency:

```csharp
// Efficient AIMemory implementation
public unsafe struct AIMemory
{
    public QListShort MemoryEntries; // Using QListShort for minimal memory footprint
    
    // Memory entry management
    public AIMemoryEntry* AddTemporaryMemory(Frame frame, EMemoryType type, FP duration)
    {
        AIMemoryEntry entry = AIMemoryEntry.CreateTemporaryEntry(frame, type, frame.DeltaTime * frame.Number + duration);
        
        // Use frame.ResolveList for efficient list access
        var list = frame.ResolveList(MemoryEntries);
        list.Add(frame, entry);
        
        return list.GetPointer(list.Count - 1);
    }
    
    public void Cleanup(Frame frame)
    {
        // Use frame.ResolveList for efficient list access
        var list = frame.ResolveList(MemoryEntries);
        FP currentTime = frame.DeltaTime * frame.Number;
        
        // Iterate backwards for efficient removal
        for (int i = list.Count - 1; i >= 0; i--)
        {
            if (list[i].IsExpired(currentTime))
            {
                list.RemoveAt(frame, i);
            }
        }
    }
}

// Efficient memory entry with union types
public unsafe struct AIMemoryEntry
{
    public FP ExpirationTime;
    public MemoryData Data; // Union type to save memory
    
    // Other fields...
}

// Memory data using a union type to minimize memory usage
public unsafe struct MemoryData
{
    public const int AREAAVOIDANCE = 0;
    public const int LINEAVOIDANCE = 1;
    
    public int Field;
    
    // Union of memory data types
    public MemoryDataAreaAvoidance* AreaAvoidance;
    public MemoryDataLineAvoidance* LineAvoidance;
}
```

These data structures minimize memory usage and optimize access patterns.

## Selective Updates

### Variable Update Rates

Different bot systems update at different rates to balance responsiveness and performance:

```csharp
// Sensor with configurable tick rate
public abstract class Sensor : AssetObject
{
    public FP TickRate = FP._0_20; // Default 5 times per second
    
    public abstract void Execute(Frame frame, EntityRef entity);
    
    protected FP GetTickTimer(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        string timerKey = $"SensorTickTimer{GetType().Name}";
        
        if (!blackboard->Has(timerKey))
        {
            blackboard->Set(timerKey, FP._0);
        }
        
        return blackboard->Get<FP>(timerKey);
    }
    
    protected void ResetTickTimer(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        string timerKey = $"SensorTickTimer{GetType().Name}";
        
        blackboard->Set(timerKey, TickRate);
    }
    
    protected void DecrementTickTimer(Frame frame, EntityRef entity, FP deltaTime)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        string timerKey = $"SensorTickTimer{GetType().Name}";
        
        FP currentTimer = blackboard->Get<FP>(timerKey);
        blackboard->Set(timerKey, currentTimer - deltaTime);
    }
}

// Sensor implementation with staggered updates
public class SensorEyes : Sensor
{
    public override void Execute(Frame frame, EntityRef entity)
    {
        var tickTimer = GetTickTimer(frame, entity);
        if (tickTimer <= 0)
        {
            ResetTickTimer(frame, entity);
            
            // Sensor logic...
        }
        else
        {
            DecrementTickTimer(frame, entity, frame.DeltaTime);
        }
    }
}
```

### Staggered Updates

Bot updates are staggered to distribute computational load:

```csharp
public class BotUpdateStaggerer : SystemMainThread
{
    public override void OnInit(Frame frame)
    {
        // Assign update groups to bots
        var bots = frame.Filter<Bot>();
        int groupIndex = 0;
        
        while (bots.Next(out EntityRef entity, out Bot bot))
        {
            if (frame.Has<AIBlackboardComponent>(entity))
            {
                var blackboard = frame.Get<AIBlackboardComponent>(entity);
                blackboard.Set("UpdateGroup", groupIndex % 3); // Divide bots into 3 update groups
                groupIndex++;
            }
        }
    }
    
    public override void Update(Frame frame)
    {
        // Determine which update group should run this frame
        int currentGroup = (int)(frame.Number % 3);
        
        // Notify systems which update group is active
        frame.Global->GetCustomInt32("CurrentBotUpdateGroup") = currentGroup;
    }
}

// System that uses staggered updates
public class StaggeredBotSystem : SystemMainThread
{
    public override void Update(Frame frame)
    {
        // Get current update group
        int currentGroup = frame.Global->GetCustomInt32("CurrentBotUpdateGroup");
        
        // Only process bots in the current update group
        var bots = frame.Filter<Bot, AIBlackboardComponent>();
        while (bots.Next(out EntityRef entity, out Bot bot, out AIBlackboardComponent blackboard))
        {
            if (bot.IsActive == false)
                continue;
            
            int botGroup = blackboard.GetOrDefault<int>("UpdateGroup");
            if (botGroup != currentGroup)
                continue;
            
            // Process bot...
        }
    }
}
```

## Entity Filtering

### Efficient Filtering

The bot system uses efficient entity filtering to process only relevant entities:

```csharp
// Using SystemMainThreadFilter for efficient entity filtering
public unsafe class AISystem : SystemMainThreadFilter<AISystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform2D* Transform;
        public Bot* Bot;
        public Health* Health;
        public AISteering* AISteering;
    }
    
    public override void Update(Frame frame, ref Filter filter)
    {
        // Early return for inactive or dead bots
        if (filter.Bot->IsActive == false || filter.Health->IsDead == true)
            return;
        
        // Bot processing...
    }
}
```

### Component-Based Filtering

The bot system uses component-based filtering to skip irrelevant entities:

```csharp
// System that only processes bots with pathfinding capabilities
public class BotPathfindingSystem : SystemMainThreadFilter<BotPathfindingSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Bot* Bot;
        public Transform2D* Transform;
        public NavMeshPathfinder* Pathfinder;
        public NavMeshSteeringAgent* SteeringAgent;
    }
    
    public override void Update(Frame frame, ref Filter filter)
    {
        if (filter.Bot->IsActive == false)
            return;
        
        // Process pathfinding...
    }
}
```

## Spatial Partitioning

### Target Filtering by Distance

The bot system uses spatial awareness to filter potential targets:

```csharp
public class SensorEyes : Sensor
{
    public FP DetectionRange = FP._10;
    
    public override void Execute(Frame frame, EntityRef entity)
    {
        var tickTimer = GetTickTimer(frame, entity);
        if (tickTimer <= 0)
        {
            ResetTickTimer(frame, entity);
            
            // Get bot position
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            FPVector2 botPosition = transform->Position;
            
            // Create a query for potential targets
            FP maxRangeSquared = DetectionRange * DetectionRange;
            
            // Use efficient spatial query
            var spatialQuery = frame.Physics2D.SpatialQuery(botPosition, DetectionRange);
            while (spatialQuery.HasNext)
            {
                EntityRef potentialTarget = spatialQuery.Next();
                
                if (!frame.Has<Character>(potentialTarget) || !frame.Has<TeamInfo>(potentialTarget))
                    continue;
                
                // Get character position
                FPVector2 targetPosition = frame.Get<Transform2D>(potentialTarget).Position;
                
                // Calculate distance squared (avoids square root)
                FP distanceSquared = FPVector2.DistanceSquared(botPosition, targetPosition);
                if (distanceSquared > maxRangeSquared)
                    continue;
                
                // Process target...
            }
        }
        else
        {
            DecrementTickTimer(frame, entity, frame.DeltaTime);
        }
    }
}
```

### Area-Based Targeting

The bot system uses area-based targeting to efficiently find targets:

```csharp
// System that updates bot target awareness based on areas
public class BotTargetAreaSystem : SystemMainThread
{
    // Constants for area divisions
    private const int AREA_DIVISIONS_X = 4;
    private const int AREA_DIVISIONS_Y = 4;
    private const int TOTAL_AREAS = AREA_DIVISIONS_X * AREA_DIVISIONS_Y;
    
    // Array to store potential targets in each area
    private QList[] _areaTargets = new QList[TOTAL_AREAS];
    
    public override void OnInit(Frame frame)
    {
        // Initialize area target lists
        for (int i = 0; i < TOTAL_AREAS; i++)
        {
            _areaTargets[i] = frame.AllocateList<EntityRef>();
        }
    }
    
    public override void Update(Frame frame)
    {
        // Clear previous area assignments
        for (int i = 0; i < TOTAL_AREAS; i++)
        {
            frame.ResolveList(_areaTargets[i]).Clear(frame);
        }
        
        // Get map dimensions
        FP mapWidth = frame.Global->MapDimensions.X;
        FP mapHeight = frame.Global->MapDimensions.Y;
        
        // Assign targets to areas
        var characters = frame.Filter<Character, Transform2D, TeamInfo>();
        while (characters.Next(out EntityRef entity, out Character character, out Transform2D transform, out TeamInfo teamInfo))
        {
            // Calculate area index
            int areaX = FP.FloorToInt(transform.Position.X / mapWidth * AREA_DIVISIONS_X);
            int areaY = FP.FloorToInt(transform.Position.Y / mapHeight * AREA_DIVISIONS_Y);
            
            // Clamp to valid range
            areaX = Math.Clamp(areaX, 0, AREA_DIVISIONS_X - 1);
            areaY = Math.Clamp(areaY, 0, AREA_DIVISIONS_Y - 1);
            
            // Add to area list
            int areaIndex = areaY * AREA_DIVISIONS_X + areaX;
            frame.ResolveList(_areaTargets[areaIndex]).Add(frame, entity);
        }
        
        // Update bots with area awareness
        var bots = frame.Filter<Bot, Transform2D, AIBlackboardComponent>();
        while (bots.Next(out EntityRef entity, out Bot bot, out Transform2D transform, out AIBlackboardComponent blackboard))
        {
            if (bot.IsActive == false)
                continue;
            
            // Calculate bot's area
            int areaX = FP.FloorToInt(transform.Position.X / mapWidth * AREA_DIVISIONS_X);
            int areaY = FP.FloorToInt(transform.Position.Y / mapHeight * AREA_DIVISIONS_Y);
            
            // Clamp to valid range
            areaX = Math.Clamp(areaX, 0, AREA_DIVISIONS_X - 1);
            areaY = Math.Clamp(areaY, 0, AREA_DIVISIONS_Y - 1);
            
            // Store area info in blackboard
            blackboard.Set("AreaX", areaX);
            blackboard.Set("AreaY", areaY);
            blackboard.Set("AreaIndex", areaY * AREA_DIVISIONS_X + areaX);
        }
    }
    
    // Get potential targets for a specific area
    public QList GetPotentialTargets(Frame frame, int areaIndex)
    {
        return _areaTargets[areaIndex];
    }
    
    // Get potential targets for a bot, including neighboring areas
    public List<EntityRef> GetBotPotentialTargets(Frame frame, EntityRef botEntity)
    {
        List<EntityRef> potentialTargets = new List<EntityRef>();
        
        if (!frame.Has<AIBlackboardComponent>(botEntity))
            return potentialTargets;
        
        // Get bot's area
        var blackboard = frame.Get<AIBlackboardComponent>(botEntity);
        int areaX = blackboard.GetOrDefault<int>("AreaX");
        int areaY = blackboard.GetOrDefault<int>("AreaY");
        
        // Add targets from bot's area and neighboring areas
        for (int y = Math.Max(0, areaY - 1); y <= Math.Min(AREA_DIVISIONS_Y - 1, areaY + 1); y++)
        {
            for (int x = Math.Max(0, areaX - 1); x <= Math.Min(AREA_DIVISIONS_X - 1, areaX + 1); x++)
            {
                int neighborAreaIndex = y * AREA_DIVISIONS_X + x;
                var targets = frame.ResolveList(_areaTargets[neighborAreaIndex]);
                
                for (int i = 0; i < targets.Count; i++)
                {
                    potentialTargets.Add(targets[i]);
                }
            }
        }
        
        return potentialTargets;
    }
}
```

## Component Reuse

### Shared Systems

The bot system reuses components and systems from the player system:

```csharp
// System that processes both player and bot inputs
public class InputSystem : SystemMainThread
{
    public override void Update(Frame frame)
    {
        // Process player inputs
        for (int i = 0; i < frame.PlayerCount; i++)
        {
            PlayerRef playerRef = i;
            
            // Get player input from the network
            Input input = default;
            if (frame.GetPlayerInput(playerRef, out Quantum.Input networkInput))
            {
                input = networkInput.Input;
            }
            
            // Apply input to player entities
            var playerEntities = frame.Filter<PlayerLink, Transform2D>();
            while (playerEntities.Next(out EntityRef entity, out PlayerLink playerLink, out Transform2D transform))
            {
                if (playerLink.PlayerRef == playerRef && !frame.Has<Bot>(entity))
                {
                    // This is a player-controlled entity
                    ApplyInput(frame, entity, input);
                }
            }
        }
        
        // Process bot inputs (set by AI system)
        var botEntities = frame.Filter<Bot, Transform2D>();
        while (botEntities.Next(out EntityRef entity, out Bot bot, out Transform2D transform))
        {
            if (bot.IsActive == false)
                continue;
            
            // Apply input
            ApplyInput(frame, entity, bot.Input);
        }
    }
    
    private void ApplyInput(Frame frame, EntityRef entity, Input input)
    {
        // Apply movement input
        if (frame.Has<KCC>(entity))
        {
            KCC* kcc = frame.Unsafe.GetPointer<KCC>(entity);
            kcc->Move(input.MoveDirection);
        }
        
        // Apply rotation input
        if (frame.Has<Transform2D>(entity))
        {
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            if (input.AimDirection != default)
            {
                transform->Rotation = FPMath.Atan2(input.AimDirection.Y, input.AimDirection.X);
                transform->Up = input.AimDirection;
            }
        }
        
        // Apply attack input
        if (input.Attack)
        {
            frame.Signals.OnAttackInput(entity);
        }
        
        // Apply other inputs...
    }
}
```

### Shared Components

Bots and players share the same core components:

```csharp
// KCC component used by both players and bots
public unsafe struct KCC
{
    public FPVector2 Velocity;
    public FP MaxSpeed;
    public FP Acceleration;
    public FP Deceleration;
    public FP RotationSpeed;
    
    public void Move(FPVector2 direction)
    {
        // Process movement...
    }
}

// Health component used by both players and bots
public unsafe struct Health
{
    public FP MaxHealth;
    public FP CurrentHealth;
    public bool IsDead;
    public bool IsImmune;
    public FP ImmuneTime;
}

// Character component used by both players and bots
public unsafe struct Character
{
    public CharacterClass CharacterClass;
    public AssetRef CharacterInfo;
}
```

## Memory Management

### Memory Pooling

The bot system uses memory pooling to avoid allocations:

```csharp
// Memory pool for AIMemoryEntry objects
public class MemoryPool : SystemMainThread
{
    // Pool sizes
    private const int AREA_AVOIDANCE_POOL_SIZE = 100;
    private const int LINE_AVOIDANCE_POOL_SIZE = 50;
    
    // Pools
    private QList _areaAvoidancePool;
    private QList _lineAvoidancePool;
    
    public override void OnInit(Frame frame)
    {
        // Initialize pools
        _areaAvoidancePool = frame.AllocateList<MemoryDataAreaAvoidance>(AREA_AVOIDANCE_POOL_SIZE);
        _lineAvoidancePool = frame.AllocateList<MemoryDataLineAvoidance>(LINE_AVOIDANCE_POOL_SIZE);
        
        // Preallocate pool objects
        for (int i = 0; i < AREA_AVOIDANCE_POOL_SIZE; i++)
        {
            var data = new MemoryDataAreaAvoidance();
            frame.ResolveList(_areaAvoidancePool).Add(frame, data);
        }
        
        for (int i = 0; i < LINE_AVOIDANCE_POOL_SIZE; i++)
        {
            var data = new MemoryDataLineAvoidance();
            frame.ResolveList(_lineAvoidancePool).Add(frame, data);
        }
        
        // Store pool references
        frame.Global->SetCustomRef("AreaAvoidancePool", _areaAvoidancePool);
        frame.Global->SetCustomRef("LineAvoidancePool", _lineAvoidancePool);
    }
    
    // Get object from pool
    public static MemoryDataAreaAvoidance* GetAreaAvoidance(Frame frame)
    {
        var pool = frame.ResolveList(frame.Global->GetCustomRef("AreaAvoidancePool"));
        
        if (pool.Count > 0)
        {
            var lastIndex = pool.Count - 1;
            var data = (MemoryDataAreaAvoidance*)pool.GetPointer(lastIndex);
            pool.RemoveAt(frame, lastIndex);
            return data;
        }
        
        // Pool is empty, allocate new object
        return frame.AllocateMemoryData<MemoryDataAreaAvoidance>();
    }
    
    public static MemoryDataLineAvoidance* GetLineAvoidance(Frame frame)
    {
        var pool = frame.ResolveList(frame.Global->GetCustomRef("LineAvoidancePool"));
        
        if (pool.Count > 0)
        {
            var lastIndex = pool.Count - 1;
            var data = (MemoryDataLineAvoidance*)pool.GetPointer(lastIndex);
            pool.RemoveAt(frame, lastIndex);
            return data;
        }
        
        // Pool is empty, allocate new object
        return frame.AllocateMemoryData<MemoryDataLineAvoidance>();
    }
    
    // Return object to pool
    public static void ReturnAreaAvoidance(Frame frame, MemoryDataAreaAvoidance* data)
    {
        var pool = frame.ResolveList(frame.Global->GetCustomRef("AreaAvoidancePool"));
        pool.Add(frame, *data);
    }
    
    public static void ReturnLineAvoidance(Frame frame, MemoryDataLineAvoidance* data)
    {
        var pool = frame.ResolveList(frame.Global->GetCustomRef("LineAvoidancePool"));
        pool.Add(frame, *data);
    }
}

// Using memory pool in AIMemory
public unsafe struct AIMemory
{
    public QListShort MemoryEntries;
    
    public AIMemoryEntry* AddTemporaryMemory(Frame frame, EMemoryType type, FP duration)
    {
        AIMemoryEntry entry = AIMemoryEntry.CreateTemporaryEntry(frame, type, frame.DeltaTime * frame.Number + duration);
        
        // Use memory pool for data allocation
        switch (type)
        {
            case EMemoryType.AreaAvoidance:
                entry.Data.AreaAvoidance = MemoryPool.GetAreaAvoidance(frame);
                entry.Data.Field = MemoryData.AREAAVOIDANCE;
                break;
            case EMemoryType.LineAvoidance:
                entry.Data.LineAvoidance = MemoryPool.GetLineAvoidance(frame);
                entry.Data.Field = MemoryData.LINEAVOIDANCE;
                break;
        }
        
        var list = frame.ResolveList(MemoryEntries);
        list.Add(frame, entry);
        
        return list.GetPointer(list.Count - 1);
    }
    
    public void Cleanup(Frame frame)
    {
        var list = frame.ResolveList(MemoryEntries);
        FP currentTime = frame.DeltaTime * frame.Number;
        
        for (int i = list.Count - 1; i >= 0; i--)
        {
            if (list[i].IsExpired(currentTime))
            {
                // Return memory to pool before removing entry
                switch (list[i].Data.Field)
                {
                    case MemoryData.AREAAVOIDANCE:
                        MemoryPool.ReturnAreaAvoidance(frame, list[i].Data.AreaAvoidance);
                        break;
                    case MemoryData.LINEAVOIDANCE:
                        MemoryPool.ReturnLineAvoidance(frame, list[i].Data.LineAvoidance);
                        break;
                }
                
                list.RemoveAt(frame, i);
            }
        }
    }
}
```

### Smart Memory Management

The bot system uses smart memory management to minimize allocations:

```csharp
// Efficient blackboard implementation
public unsafe struct AIBlackboardComponent : IDisposable
{
    private QHashMap<string, BlackboardValue> Values;
    
    public void Set<T>(string key, T value) where T : struct
    {
        if (Values.Pointer == null)
        {
            Values = QHashMap<string, BlackboardValue>.Create();
        }
        
        BlackboardValue blackboardValue;
        
        if (Values.TryGetValue(key, out blackboardValue))
        {
            // Update existing value
            blackboardValue.SetValue(frame, value);
        }
        else
        {
            // Create new value
            blackboardValue = new BlackboardValue();
            blackboardValue.SetValue(frame, value);
            Values.Add(key, blackboardValue);
        }
    }
    
    public void Remove(string key)
    {
        if (Values.Pointer == null)
            return;
        
        BlackboardValue value;
        if (Values.TryGetValue(key, out value))
        {
            // Free the value's memory
            value.Free(frame);
            
            // Remove from dictionary
            Values.Remove(key);
        }
    }
    
    public void Clear()
    {
        if (Values.Pointer == null)
            return;
        
        // Free memory for all values
        foreach (var pair in Values)
        {
            pair.Value.Free(frame);
        }
        
        // Clear dictionary
        Values.Clear();
    }
    
    public void Dispose()
    {
        Clear();
        
        if (Values.Pointer != null)
        {
            QHashMap<string, BlackboardValue>.Free(ref Values);
        }
    }
}
```

## Path Optimization

### Simplified Pathfinding

The bot system uses optimized pathfinding:

```csharp
// Efficient pathfinding for bots
public class BotPathfindingOptimizer : SystemMainThread
{
    // Optimization flags
    private const int MAX_WAYPOINTS = 8;
    private const FP PATH_SIMPLIFICATION_TOLERANCE = FP._0_5;
    
    public override void Update(Frame frame)
    {
        var pathfinders = frame.Filter<NavMeshPathfinder, Bot>();
        while (pathfinders.Next(out EntityRef entity, out NavMeshPathfinder pathfinder, out Bot bot))
        {
            if (bot.IsActive == false || pathfinder.Path.Pointer == null)
                continue;
            
            var path = frame.ResolveList(pathfinder.Path);
            
            // Skip paths that are already simple
            if (path.Count <= 2)
                continue;
            
            // Apply path simplification
            SimplifyPath(frame, entity, pathfinder);
        }
    }
    
    private void SimplifyPath(Frame frame, EntityRef entity, NavMeshPathfinder pathfinder)
    {
        var originalPath = frame.ResolveList(pathfinder.Path);
        
        // Create a new list for the simplified path
        var simplifiedPath = frame.AllocateList<NavMeshPathNode>(originalPath.Count);
        
        // Add the first point
        simplifiedPath.Add(frame, originalPath[0]);
        
        // Apply Douglas-Peucker path simplification
        SimplifyPathSegment(frame, originalPath, 0, originalPath.Count - 1, PATH_SIMPLIFICATION_TOLERANCE, simplifiedPath);
        
        // Add the last point
        if (simplifiedPath.Count < 2 || simplifiedPath[simplifiedPath.Count - 1].Position != originalPath[originalPath.Count - 1].Position)
        {
            simplifiedPath.Add(frame, originalPath[originalPath.Count - 1]);
        }
        
        // If the path is still too long, sample it
        if (simplifiedPath.Count > MAX_WAYPOINTS)
        {
            var sampledPath = frame.AllocateList<NavMeshPathNode>(MAX_WAYPOINTS);
            
            // Add the first point
            sampledPath.Add(frame, simplifiedPath[0]);
            
            // Sample intermediate points
            float step = (float)(simplifiedPath.Count - 2) / (MAX_WAYPOINTS - 2);
            for (int i = 1; i < MAX_WAYPOINTS - 1; i++)
            {
                int index = Math.Min(1 + (int)(i * step), simplifiedPath.Count - 2);
                sampledPath.Add(frame, simplifiedPath[index]);
            }
            
            // Add the last point
            sampledPath.Add(frame, simplifiedPath[simplifiedPath.Count - 1]);
            
            // Free the simplified path and use the sampled path
            frame.FreeList(simplifiedPath);
            simplifiedPath = sampledPath;
        }
        
        // Replace the original path with the simplified path
        frame.FreeList(pathfinder.Path);
        pathfinder.Path = simplifiedPath;
    }
    
    private void SimplifyPathSegment(Frame frame, QList originalPath, int startIndex, int endIndex, FP tolerance, QList simplifiedPath)
    {
        if (endIndex <= startIndex + 1)
            return;
        
        FP maxDistanceSquared = FP._0;
        int furthestIndex = startIndex;
        
        FPVector2 startPoint = ((NavMeshPathNode)originalPath[startIndex]).Position;
        FPVector2 endPoint = ((NavMeshPathNode)originalPath[endIndex]).Position;
        
        for (int i = startIndex + 1; i < endIndex; i++)
        {
            FP distanceSquared = PerpendicularDistanceSquared(
                ((NavMeshPathNode)originalPath[i]).Position,
                startPoint,
                endPoint);
            
            if (distanceSquared > maxDistanceSquared)
            {
                maxDistanceSquared = distanceSquared;
                furthestIndex = i;
            }
        }
        
        if (maxDistanceSquared > tolerance * tolerance)
        {
            // Recursively simplify the segments
            SimplifyPathSegment(frame, originalPath, startIndex, furthestIndex, tolerance, simplifiedPath);
            
            simplifiedPath.Add(frame, originalPath[furthestIndex]);
            
            SimplifyPathSegment(frame, originalPath, furthestIndex, endIndex, tolerance, simplifiedPath);
        }
    }
    
    private FP PerpendicularDistanceSquared(FPVector2 point, FPVector2 lineStart, FPVector2 lineEnd)
    {
        FP lineLength = FPVector2.Distance(lineStart, lineEnd);
        if (lineLength == FP._0)
            return FPVector2.DistanceSquared(point, lineStart);
        
        FP t = FPVector2.Dot(point - lineStart, lineEnd - lineStart) / (lineLength * lineLength);
        t = FPMath.Clamp01(t);
        
        FPVector2 projection = lineStart + t * (lineEnd - lineStart);
        return FPVector2.DistanceSquared(point, projection);
    }
}
```

### Distance-Based Path Updates

The bot system uses distance-based path updates:

```csharp
// Distance-based path updates for efficiency
public static class NavMeshPathfinderExtensions
{
    public static bool ShouldUpdatePath(this NavMeshPathfinder pathfinder, Frame frame, EntityRef entity, FPVector2 targetPosition)
    {
        // Get current position
        FPVector2 currentPosition = frame.Get<Transform2D>(entity).Position;
        
        // Check if target has moved significantly
        if (pathfinder.LastTargetPosition != default)
        {
            FP targetMovementSquared = FPVector2.DistanceSquared(targetPosition, pathfinder.LastTargetPosition);
            if (targetMovementSquared < pathfinder.PathUpdateThreshold * pathfinder.PathUpdateThreshold)
            {
                // Target hasn't moved enough to warrant a path update
                return false;
            }
        }
        
        // Check if we have a valid path
        bool hasPath = pathfinder.Path.Pointer != null && frame.ResolveList(pathfinder.Path).Count > 0;
        
        // Check if the update timer has expired
        bool timerExpired = pathfinder.PathUpdateTimer <= 0;
        
        // Check if we're at the end of the current path
        bool atPathEnd = false;
        bool pathNeedsUpdate = false;
        
        if (hasPath)
        {
            var path = frame.ResolveList(pathfinder.Path);
            if (path.Count > 0)
            {
                // Get the final waypoint
                FPVector2 finalWaypoint = path[path.Count - 1].Position;
                
                // Check if final waypoint is close to target
                FP waypointToTargetDistanceSquared = FPVector2.DistanceSquared(finalWaypoint, targetPosition);
                if (waypointToTargetDistanceSquared > pathfinder.PathUpdateThreshold * pathfinder.PathUpdateThreshold)
                {
                    // Final waypoint is too far from target, need to update
                    pathNeedsUpdate = true;
                }
                
                // Check if we're close to the final waypoint
                FP distanceSquared = FPVector2.DistanceSquared(currentPosition, finalWaypoint);
                atPathEnd = distanceSquared < pathfinder.StoppingDistance * pathfinder.StoppingDistance;
            }
        }
        
        return !hasPath || timerExpired || atPathEnd || pathNeedsUpdate;
    }
}
```

## Performance Monitoring

### Bot Performance Metrics

The twin stick shooter includes a performance monitoring system:

```csharp
// Bot performance monitoring
public class BotPerformanceMonitor : SystemMainThread
{
    // Performance metrics
    public class PerformanceMetrics
    {
        public int ActiveBotCount;
        public int PathfindingUpdates;
        public int SensorUpdates;
        public int HFSMUpdates;
        public int SteeringUpdates;
        public float AveragePathLength;
        public float AverageMemoryEntries;
        public float AverageBlackboardEntries;
    }
    
    // Performance history
    private Queue<PerformanceMetrics> _metricsHistory = new Queue<PerformanceMetrics>(60);
    private int _updateFrequency = 60; // Update metrics every 60 frames
    
    public override void Update(Frame frame)
    {
        if (frame.Number % _updateFrequency != 0)
            return;
        
        PerformanceMetrics metrics = new PerformanceMetrics();
        
        // Count active bots
        var bots = frame.Filter<Bot>();
        int activeBotCount = 0;
        int totalPathLength = 0;
        int pathfindingCount = 0;
        int totalMemoryEntries = 0;
        int memoryCount = 0;
        int totalBlackboardEntries = 0;
        int blackboardCount = 0;
        
        while (bots.Next(out EntityRef entity, out Bot bot))
        {
            if (bot.IsActive == false)
                continue;
            
            // Count active bots
            activeBotCount++;
            
            // Collect metrics
            metrics.PathfindingUpdates += bot.PathfindingUpdates;
            metrics.SensorUpdates += bot.SensorUpdates;
            metrics.HFSMUpdates += bot.HFSMUpdates;
            metrics.SteeringUpdates += bot.MovementUpdates;
            
            // Reset bot counters
            bot.PathfindingUpdates = 0;
            bot.SensorUpdates = 0;
            bot.HFSMUpdates = 0;
            bot.MovementUpdates = 0;
            
            // Collect path length data
            if (frame.Has<NavMeshPathfinder>(entity))
            {
                var pathfinder = frame.Get<NavMeshPathfinder>(entity);
                if (pathfinder.Path.Pointer != null)
                {
                    totalPathLength += frame.ResolveList(pathfinder.Path).Count;
                    pathfindingCount++;
                }
            }
            
            // Collect memory data
            if (frame.Has<AIMemory>(entity))
            {
                var aiMemory = frame.Get<AIMemory>(entity);
                if (aiMemory.MemoryEntries.Pointer != null)
                {
                    totalMemoryEntries += frame.ResolveList(aiMemory.MemoryEntries).Count;
                    memoryCount++;
                }
            }
            
            // Collect blackboard data
            if (frame.Has<AIBlackboardComponent>(entity))
            {
                // This is a simplified example as we can't easily access blackboard entry count
                totalBlackboardEntries += 10; // Placeholder
                blackboardCount++;
            }
        }
        
        metrics.ActiveBotCount = activeBotCount;
        metrics.AveragePathLength = pathfindingCount > 0 ? (float)totalPathLength / pathfindingCount : 0;
        metrics.AverageMemoryEntries = memoryCount > 0 ? (float)totalMemoryEntries / memoryCount : 0;
        metrics.AverageBlackboardEntries = blackboardCount > 0 ? (float)totalBlackboardEntries / blackboardCount : 0;
        
        // Add to history
        _metricsHistory.Enqueue(metrics);
        if (_metricsHistory.Count > 60)
        {
            _metricsHistory.Dequeue();
        }
    }
    
    // Get performance metrics
    public PerformanceMetrics GetCurrentMetrics()
    {
        return _metricsHistory.Count > 0 ? _metricsHistory.Last() : new PerformanceMetrics();
    }
    
    // Get performance history
    public PerformanceMetrics[] GetMetricsHistory()
    {
        return _metricsHistory.ToArray();
    }
}
```

These optimization techniques ensure that the twin stick shooter bot system can support multiple bots while maintaining high performance, even on lower-end hardware. By carefully managing memory, updating selectively, and using efficient data structures, the system provides realistic bot behavior without compromising the game's performance.
