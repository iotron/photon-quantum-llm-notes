# AI Blackboard System

This document details the implementation of the AI Blackboard system in the Photon Quantum Bot SDK.

## Overview

The Blackboard system serves as a shared memory for AI agents, allowing them to store and retrieve data during execution. It's a crucial component that enables communication between different AI systems and provides a central repository for agent knowledge.

## Core Components

### AIBlackboardComponent

The `AIBlackboardComponent` is attached to entities that need to use a blackboard:

```csharp
public unsafe partial struct AIBlackboardComponent : IComponent
{
    // Reference to the blackboard definition
    public AssetRef<AIBlackboard> Board;
    
    // Runtime key-value storage
    public BlackboardMemory* Memory;
    
    // Initialize the blackboard
    public void Init(Frame frame, AIBlackboard blackboardAsset);
    
    // Free memory when component is removed
    public void Free(Frame frame);
    
    // Set and get values of different types
    public void SetBool(Frame frame, int keyId, bool value);
    public bool GetBool(Frame frame, int keyId);
    
    public void SetInt(Frame frame, int keyId, int value);
    public int GetInt(Frame frame, int keyId);
    
    public void SetFP(Frame frame, int keyId, FP value);
    public FP GetFP(Frame frame, int keyId);
    
    public void SetEntity(Frame frame, int keyId, EntityRef value);
    public EntityRef GetEntity(Frame frame, int keyId);
    
    public void SetVector2(Frame frame, int keyId, FPVector2 value);
    public FPVector2 GetVector2(Frame frame, int keyId);
    
    public void SetVector3(Frame frame, int keyId, FPVector3 value);
    public FPVector3 GetVector3(Frame frame, int keyId);
}
```

### AIBlackboard

`AIBlackboard` is an asset that defines the structure of a blackboard:

```csharp
public class AIBlackboard : AssetObject
{
    // List of keys defined in this blackboard
    public List<BlackboardKey> Keys;
    
    // Initialize a blackboard component with this definition
    public void Initialize(Frame frame, AIBlackboardComponent* component);
    
    // Get key ID by name
    public int GetKeyId(string keyName);
}
```

### BlackboardKey

`BlackboardKey` defines a single data entry in the blackboard:

```csharp
public class BlackboardKey
{
    // Name of the key for reference
    public string KeyName;
    
    // Data type stored in this key
    public BlackboardKeyType KeyType;
    
    // Default values for different types
    public bool DefaultBool;
    public int DefaultInt;
    public FP DefaultFP;
    public EntityRef DefaultEntity;
    public FPVector2 DefaultVector2;
    public FPVector3 DefaultVector3;
}
```

### BlackboardMemory

`BlackboardMemory` is the runtime storage for blackboard data:

```csharp
public unsafe struct BlackboardMemory
{
    // Arrays for different data types
    public bool* BoolValues;
    public int* IntValues;
    public FP* FPValues;
    public EntityRef* EntityValues;
    public FPVector2* Vector2Values;
    public FPVector3* Vector3Values;
    
    // Number of keys of each type
    public int BoolCount;
    public int IntCount;
    public int FPCount;
    public int EntityCount;
    public int Vector2Count;
    public int Vector3Count;
}
```

## Execution Flow

### Initialization

The `BotSDKSystem` handles the initialization of blackboard components:

```csharp
public void OnAdded(Frame frame, EntityRef entity, AIBlackboardComponent* component)
{
    if(component->Board != null)
    {
        var blackboardAsset = frame.FindAsset<AIBlackboard>(component->Board.Id);
        blackboardAsset.Initialize(frame, component);
    }
}
```

The initialization process:

```csharp
public void Initialize(Frame frame, AIBlackboardComponent* component)
{
    // Count keys of each type
    int boolCount = 0, intCount = 0, fpCount = 0;
    int entityCount = 0, vector2Count = 0, vector3Count = 0;
    
    foreach (var key in Keys)
    {
        switch (key.KeyType)
        {
            case BlackboardKeyType.Bool: boolCount++; break;
            case BlackboardKeyType.Int: intCount++; break;
            case BlackboardKeyType.FP: fpCount++; break;
            case BlackboardKeyType.Entity: entityCount++; break;
            case BlackboardKeyType.Vector2: vector2Count++; break;
            case BlackboardKeyType.Vector3: vector3Count++; break;
        }
    }
    
    // Allocate memory
    component->Memory = frame.AllocateMemory<BlackboardMemory>(1);
    component->Memory->BoolCount = boolCount;
    component->Memory->IntCount = intCount;
    // ... and so on for other types
    
    if (boolCount > 0)
        component->Memory->BoolValues = frame.AllocateMemory<bool>(boolCount);
    // ... and so on for other types
    
    // Initialize with default values
    int boolIdx = 0, intIdx = 0, fpIdx = 0;
    int entityIdx = 0, vector2Idx = 0, vector3Idx = 0;
    
    foreach (var key in Keys)
    {
        switch (key.KeyType)
        {
            case BlackboardKeyType.Bool:
                component->Memory->BoolValues[boolIdx++] = key.DefaultBool;
                break;
            // ... and so on for other types
        }
    }
}
```

### Usage

Setting and getting values:

```csharp
// Setting a value
public void SetBool(Frame frame, int keyId, bool value)
{
    if (keyId >= 0 && keyId < Memory->BoolCount)
        Memory->BoolValues[keyId] = value;
}

// Getting a value
public bool GetBool(Frame frame, int keyId)
{
    if (keyId >= 0 && keyId < Memory->BoolCount)
        return Memory->BoolValues[keyId];
    return default;
}
```

## Example Usage

### Defining a Blackboard

```csharp
// Create a blackboard asset definition
var blackboard = new AIBlackboard();

// Add keys
blackboard.Keys.Add(new BlackboardKey
{
    KeyName = "HasTarget",
    KeyType = BlackboardKeyType.Bool,
    DefaultBool = false
});

blackboard.Keys.Add(new BlackboardKey
{
    KeyName = "TargetEntity",
    KeyType = BlackboardKeyType.Entity,
    DefaultEntity = default
});

blackboard.Keys.Add(new BlackboardKey
{
    KeyName = "TargetPosition",
    KeyType = BlackboardKeyType.Vector2,
    DefaultVector2 = FPVector2.Zero
});
```

### Using Blackboard in AI Code

```csharp
public unsafe partial class FindTargetAction : AIAction
{
    public override void Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Get blackboard component
        var blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        
        // Find a target
        var targets = frame.GetComponentIterator<Target>();
        EntityRef closestTarget = default;
        FP closestDistance = FP.UseableMax;
        
        foreach (var (targetEntity, target) in targets)
        {
            // Calculate distance and find closest
            // ...
            
            if (closestTarget == default || distance < closestDistance)
            {
                closestTarget = targetEntity;
                closestDistance = distance;
            }
        }
        
        // Update blackboard
        if (closestTarget != default)
        {
            // Get key IDs
            int hasTargetId = frame.FindAsset<AIBlackboard>(blackboard->Board.Id).GetKeyId("HasTarget");
            int targetEntityId = frame.FindAsset<AIBlackboard>(blackboard->Board.Id).GetKeyId("TargetEntity");
            int targetPosId = frame.FindAsset<AIBlackboard>(blackboard->Board.Id).GetKeyId("TargetPosition");
            
            // Set values
            blackboard->SetBool(frame, hasTargetId, true);
            blackboard->SetEntity(frame, targetEntityId, closestTarget);
            
            var targetPos = frame.Get<Transform2D>(closestTarget).Position;
            blackboard->SetVector2(frame, targetPosId, targetPos);
            
            return;
        }
        
        // No target found
        int hasTargetId = frame.FindAsset<AIBlackboard>(blackboard->Board.Id).GetKeyId("HasTarget");
        blackboard->SetBool(frame, hasTargetId, false);
    }
}
```

## Accessing Blackboard from Different AI Systems

### From Behavior Trees

```csharp
public unsafe partial class IsTargetInRangeNode : BTLeaf
{
    // Configure distance threshold
    public FP RangeThreshold;
    
    protected override BTStatus OnUpdate(BTParams p, ref AIContext aiContext)
    {
        var frame = p.Frame;
        var entity = p.Entity;
        
        // Get blackboard
        var blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        var boardAsset = frame.FindAsset<AIBlackboard>(blackboard->Board.Id);
        
        // Get key IDs
        int hasTargetId = boardAsset.GetKeyId("HasTarget");
        int targetPosId = boardAsset.GetKeyId("TargetPosition");
        
        // Check if we have a target
        if (!blackboard->GetBool(frame, hasTargetId))
            return BTStatus.Failure;
        
        // Get target position and self position
        FPVector2 targetPos = blackboard->GetVector2(frame, targetPosId);
        FPVector2 selfPos = frame.Get<Transform2D>(entity).Position;
        
        // Check distance
        FP distance = FPVector2.Distance(selfPos, targetPos);
        
        return distance <= RangeThreshold ? BTStatus.Success : BTStatus.Failure;
    }
}
```

### From HFSM

```csharp
public class HasTargetDecision : HFSMDecision
{
    public override unsafe bool Decide(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Get blackboard
        var blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        var boardAsset = frame.FindAsset<AIBlackboard>(blackboard->Board.Id);
        
        // Get key ID
        int hasTargetId = boardAsset.GetKeyId("HasTarget");
        
        // Return blackboard value
        return blackboard->GetBool(frame, hasTargetId);
    }
}
```

### From Utility Theory

```csharp
public class TargetDistanceFunction : AIFunction<FP>
{
    public override unsafe FP Execute(Frame frame, EntityRef entity, ref AIContext aiContext)
    {
        // Get blackboard
        var blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        var boardAsset = frame.FindAsset<AIBlackboard>(blackboard->Board.Id);
        
        // Get key IDs
        int hasTargetId = boardAsset.GetKeyId("HasTarget");
        int targetPosId = boardAsset.GetKeyId("TargetPosition");
        
        // Check if we have a target
        if (!blackboard->GetBool(frame, hasTargetId))
            return FP._0;
        
        // Get target and self positions
        FPVector2 targetPos = blackboard->GetVector2(frame, targetPosId);
        FPVector2 selfPos = frame.Get<Transform2D>(entity).Position;
        
        // Calculate normalized distance (0-1 range)
        FP distance = FPVector2.Distance(selfPos, targetPos);
        return FPMath.Clamp01(distance / 50); // Assuming max range of 50
    }
}
```

## Best Practices

1. **Plan your blackboard structure** - Identify what data needs to be shared between AI systems
2. **Use meaningful key names** - Clear names make the code more readable
3. **Cache key IDs** - Looking up key IDs repeatedly can be inefficient
4. **Minimize data duplication** - Store shared data in the blackboard instead of recomputing
5. **Default values** - Set sensible defaults for all blackboard keys
6. **Organized access** - Consider creating helper functions for related blackboard operations
7. **Validation** - Check that key IDs are valid before accessing blackboard data
8. **Documentation** - Document the purpose of each blackboard key
9. **Debugging** - Use the debugger to inspect blackboard values during runtime
