# Bot Memory System

This document details the memory systems used by bots in the twin stick shooter game.

## Memory Overview

The twin stick shooter implements two complementary memory systems:

1. **AIBlackboardComponent**: Short-term memory for immediate decision-making
2. **AIMemory**: Long-term memory for tracking entities and threats over time

Together, these systems allow bots to maintain awareness of the game state and make informed decisions.

## AIBlackboardComponent

The AIBlackboardComponent serves as short-term memory, storing key-value pairs that represent the bot's current knowledge.

```csharp
public unsafe struct AIBlackboardComponent : IDisposable
{
    public DynamicAssetRef<AIBlackboardInitializer> Initializer;
    private QHashMap<string, BlackboardValue> Values;
    
    // Value manipulation methods
    public void Set<T>(string key, T value) where T : struct { /* Implementation */ }
    public T Get<T>(string key) where T : struct { /* Implementation */ }
    public T GetOrDefault<T>(string key, T defaultValue = default) where T : struct { /* Implementation */ }
    public bool Has(string key) { /* Implementation */ }
    public void Remove(string key) { /* Implementation */ }
    public void Clear() { /* Implementation */ }
    
    // Memory management
    public void Initialize(Frame frame) { /* Implementation */ }
    public void Free(Frame frame) { /* Implementation */ }
    public void Dispose() { /* Implementation */ }
}
```

Key features:
- Stores any struct type (e.g., EntityRef, FP, FPVector2)
- Provides type-safe access to values
- Initializes with default values from an AIBlackboardInitializer asset

### BlackboardValue

```csharp
public unsafe struct BlackboardValue
{
    public BlackboardValueType Type;
    private byte* Data;
    private int Size;
    
    // Value type enum
    public enum BlackboardValueType
    {
        Unknown,
        Boolean,
        Integer,
        FP,
        Vector2,
        Vector3,
        Quaternion,
        EntityRef,
        AssetRef,
        String
        // Other supported types...
    }
    
    // Type-specific methods
    public void SetValue<T>(Frame frame, T value) where T : struct { /* Implementation */ }
    public T GetValue<T>() where T : struct { /* Implementation */ }
    public void Free(Frame frame) { /* Implementation */ }
}
```

The BlackboardValue struct stores type information and a pointer to the actual data.

### AIBlackboardInitializer

```csharp
[CreateAssetMenu(menuName = "Quantum/AI/BlackboardInitializer")]
public class AIBlackboardInitializer : AssetObject
{
    [Serializable]
    public struct InitializerEntry
    {
        public string Key;
        public BlackboardEntryType Type;
        public string StringValue;
        public int IntValue;
        public float FloatValue;
        public bool BoolValue;
        public AssetRef AssetRefValue;
    }
    
    public InitializerEntry[] Entries;
    
    public static void InitializeBlackboard(Frame frame, AIBlackboardComponent* blackboard, AIBlackboardInitializer initializer)
    {
        foreach (var entry in initializer.Entries)
        {
            switch (entry.Type)
            {
                case BlackboardEntryType.Boolean:
                    blackboard->Set(entry.Key, entry.BoolValue);
                    break;
                case BlackboardEntryType.Integer:
                    blackboard->Set(entry.Key, entry.IntValue);
                    break;
                case BlackboardEntryType.FP:
                    blackboard->Set(entry.Key, FPMath.FloatToFP(entry.FloatValue));
                    break;
                // Other types...
            }
        }
    }
}
```

The AIBlackboardInitializer asset defines default values for the blackboard, allowing designers to configure bot behavior without code changes.

## AIMemory

The AIMemory component serves as long-term memory for tracking entities and threats over time.

```csharp
public unsafe struct AIMemory
{
    public QListShort MemoryEntries;
    
    // Memory entry management
    public AIMemoryEntry* AddTemporaryMemory(Frame frame, EMemoryType type, FP duration)
    {
        // Create a new memory entry with an expiration time
        AIMemoryEntry entry = AIMemoryEntry.CreateTemporaryEntry(frame, type, frame.DeltaTime * frame.Number + duration);
        
        // Add to the list
        var list = frame.ResolveList(MemoryEntries);
        list.Add(frame, entry);
        
        // Return a pointer to the added entry
        return list.GetPointer(list.Count - 1);
    }
    
    public AIMemoryEntry* AddInfiniteMemory(Frame frame, EMemoryType type)
    {
        // Create a new memory entry with no expiration
        AIMemoryEntry entry = AIMemoryEntry.CreateInfiniteEntry(frame, type);
        
        // Add to the list
        var list = frame.ResolveList(MemoryEntries);
        list.Add(frame, entry);
        
        // Return a pointer to the added entry
        return list.GetPointer(list.Count - 1);
    }
    
    // Memory cleanup
    public void Cleanup(Frame frame)
    {
        // Remove expired memory entries
        var list = frame.ResolveList(MemoryEntries);
        FP currentTime = frame.DeltaTime * frame.Number;
        
        for (int i = list.Count - 1; i >= 0; i--)
        {
            if (list[i].IsExpired(currentTime))
            {
                list.RemoveAt(frame, i);
            }
        }
    }
}
```

Key features:
- Stores memory entries with optional expiration times
- Supports different types of memory (e.g., avoidance, targeting)
- Provides cleanup of expired memories

### AIMemoryEntry

```csharp
public unsafe struct AIMemoryEntry
{
    public FP ExpirationTime;
    public MemoryData Data;
    
    public static AIMemoryEntry CreateTemporaryEntry(Frame frame, EMemoryType type, FP expirationTime)
    {
        AIMemoryEntry entry = new AIMemoryEntry();
        entry.ExpirationTime = expirationTime;
        
        // Allocate appropriate memory data based on type
        switch (type)
        {
            case EMemoryType.AreaAvoidance:
                entry.Data.AreaAvoidance = frame.AllocateMemoryData<MemoryDataAreaAvoidance>();
                entry.Data.Field = MemoryData.AREAAVOIDANCE;
                break;
            case EMemoryType.LineAvoidance:
                entry.Data.LineAvoidance = frame.AllocateMemoryData<MemoryDataLineAvoidance>();
                entry.Data.Field = MemoryData.LINEAVOIDANCE;
                break;
            // Other memory types...
        }
        
        return entry;
    }
    
    public static AIMemoryEntry CreateInfiniteEntry(Frame frame, EMemoryType type)
    {
        // Similar to CreateTemporaryEntry but with FP.MaxValue as expiration time
    }
    
    public bool IsExpired(FP currentTime)
    {
        return currentTime > ExpirationTime;
    }
    
    public bool IsAvailable(Frame frame)
    {
        // Check if the memory entry is still valid
        if (Data.Field == MemoryData.AREAAVOIDANCE)
        {
            return frame.Exists(Data.AreaAvoidance->Entity);
        }
        else if (Data.Field == MemoryData.LINEAVOIDANCE)
        {
            return frame.Exists(Data.LineAvoidance->Entity);
        }
        
        return false;
    }
}
```

The AIMemoryEntry struct represents a single memory entry, with an expiration time and type-specific data.

### Memory Data Types

```csharp
public enum EMemoryType
{
    AreaAvoidance,
    LineAvoidance,
    // Other memory types...
}

public unsafe struct MemoryData
{
    public const int AREAAVOIDANCE = 0;
    public const int LINEAVOIDANCE = 1;
    // Other field constants...
    
    public int Field;
    
    // Union of memory data types
    public MemoryDataAreaAvoidance* AreaAvoidance;
    public MemoryDataLineAvoidance* LineAvoidance;
    // Other memory data pointers...
}

public unsafe struct MemoryDataAreaAvoidance
{
    public EntityRef Entity;
    public FP RunDistance;
    public FP Weight;
    
    public void SetData(EntityRef entity, FP runDistance, FP weight = FP._1)
    {
        Entity = entity;
        RunDistance = runDistance;
        Weight = weight;
    }
}

public unsafe struct MemoryDataLineAvoidance
{
    public EntityRef Entity;
    public FPVector2 Direction;
    public FP Weight;
    
    public void SetData(EntityRef entity, FPVector2 direction, FP weight = FP._1)
    {
        Entity = entity;
        Direction = direction;
        Weight = weight;
    }
}
```

These types define the structure of different memory data:
- MemoryDataAreaAvoidance: Used for avoiding areas (e.g., enemy attacks, dangerous zones)
- MemoryDataLineAvoidance: Used for avoiding linear threats (e.g., projectiles)

## Memory System Integration

### Integration with Sensors

Sensors use both memory systems to store information:

```csharp
// Example of a sensor updating the blackboard
public override void Execute(Frame frame, EntityRef entity)
{
    AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
    blackboard->Set("TargetEntity", targetEntity);
    blackboard->Set("TargetVisible", true);
}

// Example of a sensor adding a memory entry
public override void Execute(Frame frame, EntityRef entity)
{
    AIMemory* aiMemory = frame.Unsafe.GetPointer<AIMemory>(entity);
    AIMemoryEntry* memoryEntry = aiMemory->AddTemporaryMemory(frame, EMemoryType.AreaAvoidance, FP._5);
    memoryEntry->Data.AreaAvoidance->SetData(threatEntity, runDistance: FP._3);
}
```

### Integration with HFSM

The HFSM uses the blackboard to read sensor data and make decisions:

```csharp
public override bool Decide(Frame frame, EntityRef entity)
{
    AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
    return blackboard->GetOrDefault<bool>("TargetVisible");
}
```

### Integration with Steering

The steering system uses memory entries for avoidance:

```csharp
public FPVector2 GetDesiredDirection(Frame frame, EntityRef agent)
{
    FPVector2 desiredDirection = ProcessSteeringEntry(frame, agent, MainSteeringData);
    
    AIMemory* aiMemory = frame.Unsafe.GetPointer<AIMemory>(agent);
    var memoryEntries = frame.ResolveList(aiMemory->MemoryEntries);
    for (int i = 0; i < memoryEntries.Count; i++)
    {
        if (memoryEntries[i].IsAvailable(frame) == true)
        {
            desiredDirection += ProcessAvoidanceFromMemory(frame, agent, memoryEntries.GetPointer(i));
        }
    }
    
    return desiredDirection.Normalized;
}
```

## Memory System Lifecycle

### Initialization

Memory systems are initialized during bot creation:

```csharp
public static void Botify(Frame frame, EntityRef entity)
{
    // Initialize blackboard
    frame.Add<AIBlackboardComponent>(entity, out var blackboardComponent);
    var blackboardInitializer = frame.FindAsset<AIBlackboardInitializer>(bot->BlackboardInitializer.Id);
    AIBlackboardInitializer.InitializeBlackboard(frame, blackboardComponent, blackboardInitializer);
    
    // Initialize memory
    frame.Add<AIMemory>(entity);
}
```

### Update

Memory systems are updated throughout the bot's lifecycle:

1. Sensors update the blackboard with new information
2. Sensors add memory entries for threats and other entities
3. The AIMemory system cleans up expired entries
4. The HFSM reads from the blackboard to make decisions
5. The steering system reads from memory entries for avoidance

### Cleanup

Memory systems are cleaned up when the bot is removed:

```csharp
public static void Debotify(Frame frame, EntityRef entity)
{
    frame.Unsafe.GetPointer<AIBlackboardComponent>(entity)->Free(frame);
    frame.Remove<AIBlackboardComponent>(entity);
    
    frame.Remove<AIMemory>(entity);
}
```

## Performance Considerations

The memory systems are designed with performance in mind:

1. **Blackboard**:
   - Uses a hash map for efficient key-value lookup
   - Stores values directly when possible, using pointers for larger structs
   - Avoids string allocations by using string constants

2. **AIMemory**:
   - Uses a list for efficient iteration
   - Automatically cleans up expired entries
   - Uses union types to minimize memory usage
   - Leverages Quantum's memory management for allocation

These optimizations allow the bot to maintain comprehensive memory of the game state without impacting performance too heavily.
