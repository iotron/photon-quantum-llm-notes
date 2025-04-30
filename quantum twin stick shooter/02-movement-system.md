# Movement System

This document explains the movement implementation in the Quantum Twin Stick Shooter, focusing on how character movement is handled using Quantum's deterministic physics.

## Overview

The movement system in Twin Stick Shooter is built around Quantum's Kinematic Character Controller (KCC) and provides:

1. **Top-down movement**: Direction-based character control
2. **Speed attributes**: Character-specific movement speeds
3. **Movement locking**: During attacks and skills
4. **Stun effects**: Preventing movement during stun duration
5. **Unified handling**: Same system for both player and bot-controlled characters

## Components and Data Structures

The movement system uses several components defined in DSL:

```csharp
// From Movement.qtn
component MovementData
{
    Boolean IsOnAttackMovementLock;
}

// From kcc.qtn
component KCC
{
    asset_ref<KCCSettings> Settings;
    FP MaxSpeed;
    
    // Internal working data for KCC system (not shown)
}
```

## MovementSystem Implementation

The `MovementSystem` handles character movement based on input:

```csharp
[Preserve]
public unsafe class MovementSystem : SystemMainThreadFilter<MovementSystem.Filter>, ISignalOnComponentAdded<KCC>
{
    public struct Filter
    {
        public EntityRef Entity;
        public InputContainer* InputContainer;
        public KCC* KCC;
        public MovementData* MovementData;
    }

    public void OnAdded(Frame frame, EntityRef entity, KCC* component)
    {
        KCCSettings kccSettings = frame.FindAsset<KCCSettings>(component->Settings.Id);
        kccSettings.Init(ref *component);
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Check if movement is currently locked
        FP stun = AttributesHelper.GetCurrentValue(frame, filter.Entity, EAttributeType.Stun);
        if (stun > 0 || filter.MovementData->IsOnAttackMovementLock == true)
        {
            return;
        }

        // Get character speed from attributes system
        FP characterSpeed = AttributesHelper.GetCurrentValue(frame, filter.Entity, EAttributeType.Speed);
        filter.KCC->MaxSpeed = characterSpeed;

        // Compute movement direction based on input and apply to KCC
        KCCSettings kccSettings = frame.FindAsset<KCCSettings>(filter.KCC->Settings.Id);
        KCCMovementData kccMovementData = kccSettings.ComputeRawMovement(frame,
            filter.Entity, filter.InputContainer->Input.MoveDirection.Normalized);
        kccSettings.SteerAndMove(frame, filter.Entity, in kccMovementData);
    }
}
```

## KCC Movement Flow

The KCC (Kinematic Character Controller) handles movement in these steps:

1. **Input processing**: Convert raw input into movement direction
2. **Speed calculation**: Apply character's speed attribute
3. **Physics interaction**: Handle collisions with the environment
4. **Position update**: Update character transform

## Movement Restrictions

Several systems can restrict character movement:

### Attack Movement Lock

During certain attacks or skills, movement is temporarily locked:

```csharp
// In SkillData.cs (simplified)
public virtual EntityRef OnCreate(Frame frame, EntityRef source, SkillData data,
    FPVector2 characterPos, FPVector2 actionVector)
{
    // Lock movement for the duration specified in the skill
    if (MovementLockDuration > 0)
    {
        MovementData* movementData = frame.Unsafe.GetPointer<MovementData>(source);
        movementData->IsOnAttackMovementLock = true;
        
        // Set a timer to unlock movement after duration
        frame.Timer.Set(source, "MovementLock", data.MovementLockDuration,
            () => { 
                if (frame.Exists(source)) {
                    movementData->IsOnAttackMovementLock = false; 
                }
            });
    }
    
    // Rest of skill creation...
}
```

### Stun Effect

The stun attribute temporarily prevents character movement:

```csharp
// Simplified example of applying stun
public static void ApplyStun(Frame frame, EntityRef target, FP duration)
{
    AttributesHelper.ChangeAttribute(
        frame, 
        target, 
        EAttributeType.Stun, 
        EModifierAppliance.Timer, 
        EModifierOperation.Add, 
        FP._1, 
        duration);
}
```

## Rotation System

Character rotation is handled separately from movement:

```csharp
[Preserve]
public unsafe class RotationSystem : SystemMainThreadFilter<RotationSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform2D* Transform;
        public InputContainer* InputContainer;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Check if rotation is locked due to attack
        if (frame.TryGet(filter.Entity, out Skill skill))
        {
            SkillData skillData = frame.FindAsset<SkillData>(skill.SkillData.Id);
            if (skill.TTL < skillData.RotationLockDuration)
            {
                // Rotation is locked during the start of some skills
                return;
            }
        }

        // Rotate character based on aim direction
        FPVector2 aimDirection = filter.InputContainer->Input.AimDirection;
        if (aimDirection.Magnitude > FP._0_10)
        {
            FP targetRotation = FPMath.Atan2(aimDirection.Y, aimDirection.X);
            filter.Transform->Rotation = targetRotation;
        }
    }
}
```

## AI Movement with Context Steering

For AI-controlled characters, movement is driven by Context Steering, which produces input values that feed into the same movement system:

```csharp
// In AISystem.cs (simplified)
private void HandleContextSteering(Frame frame, Filter filter)
{
    // Process the final desired direction using context steering
    FPVector2 desiredDirection = filter.AISteering->GetDesiredDirection(frame, filter.Entity);

    // Smooth the direction change with lerping
    filter.AISteering->CurrentDirection = FPVector2.MoveTowards(
        filter.AISteering->CurrentDirection, 
        desiredDirection,
        frame.DeltaTime * filter.AISteering->LerpFactor);

    // Apply the direction to the Bot's input
    filter.Bot->Input.MoveDirection = filter.AISteering->CurrentDirection;
}
```

The AISteering component calculates movement direction based on multiple factors:

```csharp
// In AISteering class (simplified)
public unsafe FPVector2 GetDesiredDirection(Frame frame, EntityRef entity)
{
    FPVector2 resultingDirection = FPVector2.Zero;
    int validInfluenceCount = 0;
    
    // Consider various steering influences:
    
    // 1. Main navigation path (highest priority)
    if (IsNavMeshSteering && MainSteeringData.SteeringEntryNavMesh->IsValid)
    {
        resultingDirection += MainSteeringData.SteeringEntryNavMesh->Direction * MainSteeringData.SteeringEntryNavMesh->Weight;
        validInfluenceCount++;
    }
    
    // 2. Threat avoidance
    for (int i = 0; i < ThreatSteeringData.SteeringEntries.Length; i++)
    {
        var entry = ThreatSteeringData.SteeringEntries[i];
        if (entry.IsValid)
        {
            resultingDirection += entry.Direction * entry.Weight;
            validInfluenceCount++;
        }
    }
    
    // 3. General avoidance (characters, obstacles, etc.)
    for (int i = 0; i < AvoidanceSteeringData.SteeringEntries.Length; i++)
    {
        var entry = AvoidanceSteeringData.SteeringEntries[i];
        if (entry.IsValid)
        {
            resultingDirection += entry.Direction * entry.Weight;
            validInfluenceCount++;
        }
    }
    
    // Normalize the result if we have valid influences
    if (validInfluenceCount > 0)
    {
        return resultingDirection.Normalized;
    }
    
    return FPVector2.Zero;
}
```

## Important Movement Concepts

### 1. Deterministic Physics

All movement uses Quantum's deterministic physics to ensure consistent behavior across all clients:

- **Fixed Point Math**: All calculations use `FP` types instead of floats
- **Repeatable Results**: Same input always produces the same output
- **Frame-based Updates**: Movement updates happen in discrete simulation frames

### 2. Integration with Attributes System

Character movement speed is determined by the Attributes system:

```csharp
// In MovementSystem.Update
FP characterSpeed = AttributesHelper.GetCurrentValue(frame, filter.Entity, EAttributeType.Speed);
filter.KCC->MaxSpeed = characterSpeed;
```

### 3. Unified Movement Pipeline

Both player-controlled and AI-controlled characters use the same movement system, just with different sources of input:

- **Player Characters**: Input comes from player controls
- **Bot Characters**: Input comes from AI steering calculations
- **Character KCC**: Processes input the same way regardless of source

## Best Practices

1. **Separate Input from Movement**: Keep input collection separate from movement logic
2. **Use AttributesSystem for Stats**: Store movement speeds in the attributes system for flexibility
3. **Context Steering for AI**: Use weighted influence vectors for natural AI movement
4. **Handle Movement Restrictions**: Implement clean systems for restricting movement during skills/stuns
5. **Deterministic Calculations**: Ensure all calculations use fixed-point math and are deterministic

## Implementation Notes

1. The KCC provides collision detection and resolution against the environment
2. Movement and rotation are handled in separate systems for modularity
3. Context steering provides a flexible framework for AI movement decisions
4. The attributes system allows for dynamic adjustment of movement speed
5. All movement calculations are fully deterministic for network consistency