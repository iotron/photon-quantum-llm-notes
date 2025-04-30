# Attributes System

This document explains the attributes system in the Quantum Twin Stick Shooter, focusing on how character stats are managed using a flexible and extensible approach.

## Overview

The attributes system in Twin Stick Shooter provides a framework for managing character statistics:

1. **Attribute Types**: Various character stats (health, speed, mana, etc.)
2. **Flexible Modifiers**: Different ways to modify attributes (add, multiply, etc.)
3. **Timed Effects**: Temporary attribute changes with automatic expiration
4. **Stacking Rules**: How multiple modifiers combine
5. **Attribute-Driven Gameplay**: Character behavior based on attribute values

## Core Components

### Attributes Component

```csharp
// From Attributes.qtn
component Attributes
{
    QList<AttributeEntry> Entries;
}

struct AttributeEntry
{
    EAttributeType Type;
    FP BaseValue;
    QList<ModifierEntry> Modifiers;
}

struct ModifierEntry
{
    EModifierAppliance Appliance;
    EModifierOperation Operation;
    FP Value;
    FP Duration;
    FP Timer;
}
```

### Attribute Types

The game defines various attribute types through an enum:

```csharp
// From Attributes.qtn
enum EAttributeType
{
    // Resources
    Health,
    Mana,
    Energy,
    
    // Stats
    Speed,
    Armor,
    Damage,
    AttackSpeed,
    
    // Special states
    Stun,
    Silence,
    
    // System properties
    SkillCooldown,
    RespawnTime
}
```

### Modifier Operations and Applications

```csharp
// From Attributes.qtn
enum EModifierOperation
{
    Add,        // Simple addition
    Multiply,   // Percentage increase
    Override,   // Replace value
    Max,        // Set minimum value
    Min,        // Set maximum value
    Subtract    // Decrease value
}

enum EModifierAppliance
{
    Permanent,  // Never expires
    Timer,      // Active for a duration
    OneTime     // Applied once, then removed
}
```

## AttributesSystem Implementation

The `AttributesSystem` manages updating and processing attribute modifiers:

```csharp
[Preserve]
public unsafe class AttributesSystem : SystemMainThreadFilter<AttributesSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Attributes* Attributes;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Process each attribute entry
        for (int i = 0; i < filter.Attributes->Entries.Length; i++)
        {
            AttributeEntry* entry = &filter.Attributes->Entries[i];
            
            // Process modifiers for this attribute
            ProcessModifiers(frame, entry, frame.DeltaTime);
        }
    }
    
    private void ProcessModifiers(Frame frame, AttributeEntry* entry, FP deltaTime)
    {
        // Update modifier timers
        for (int i = 0; i < entry->Modifiers.Length; i++)
        {
            ModifierEntry* modifier = &entry->Modifiers[i];
            
            // Skip permanent modifiers
            if (modifier->Appliance == EModifierAppliance.Permanent)
                continue;
                
            // Update timer for timed modifiers
            if (modifier->Appliance == EModifierAppliance.Timer)
            {
                modifier->Timer += deltaTime;
                
                // Remove expired modifiers
                if (modifier->Timer >= modifier->Duration)
                {
                    entry->Modifiers.RemoveAt(i);
                    i--;
                }
            }
            // Remove one-time modifiers after they're processed
            else if (modifier->Appliance == EModifierAppliance.OneTime)
            {
                entry->Modifiers.RemoveAt(i);
                i--;
            }
        }
    }
}
```

## AttributesHelper Utility Class

The `AttributesHelper` provides convenient methods for working with attributes:

```csharp
public static unsafe class AttributesHelper
{
    // Get the current value of an attribute
    public static FP GetCurrentValue(Frame frame, EntityRef entity, EAttributeType type)
    {
        if (!frame.Has<Attributes>(entity))
            return 0;
            
        Attributes* attributes = frame.Unsafe.GetPointer<Attributes>(entity);
        
        // Find the attribute entry for this type
        AttributeEntry* entry = GetEntryOrCreate(frame, attributes, type);
        
        // Start with base value
        FP finalValue = entry->BaseValue;
        
        // Apply additive modifiers first
        for (int i = 0; i < entry->Modifiers.Length; i++)
        {
            ModifierEntry* modifier = &entry->Modifiers[i];
            if (modifier->Operation == EModifierOperation.Add)
            {
                finalValue += modifier->Value;
            }
            else if (modifier->Operation == EModifierOperation.Subtract)
            {
                finalValue -= modifier->Value;
            }
        }
        
        // Apply multiplicative modifiers
        FP multiplier = FP._1;
        for (int i = 0; i < entry->Modifiers.Length; i++)
        {
            ModifierEntry* modifier = &entry->Modifiers[i];
            if (modifier->Operation == EModifierOperation.Multiply)
            {
                multiplier += modifier->Value;
            }
        }
        finalValue *= multiplier;
        
        // Apply min/max modifiers
        for (int i = 0; i < entry->Modifiers.Length; i++)
        {
            ModifierEntry* modifier = &entry->Modifiers[i];
            if (modifier->Operation == EModifierOperation.Min)
            {
                finalValue = FPMath.Min(finalValue, modifier->Value);
            }
            else if (modifier->Operation == EModifierOperation.Max)
            {
                finalValue = FPMath.Max(finalValue, modifier->Value);
            }
            else if (modifier->Operation == EModifierOperation.Override)
            {
                finalValue = modifier->Value;
            }
        }
        
        return finalValue;
    }
    
    // Change an attribute by adding a modifier
    public static void ChangeAttribute(
        Frame frame, 
        EntityRef entity, 
        EAttributeType type, 
        EModifierAppliance appliance, 
        EModifierOperation operation, 
        FP value, 
        FP duration = 0)
    {
        if (!frame.Has<Attributes>(entity))
            return;
            
        Attributes* attributes = frame.Unsafe.GetPointer<Attributes>(entity);
        
        // Find or create the attribute entry
        AttributeEntry* entry = GetEntryOrCreate(frame, attributes, type);
        
        // Create new modifier
        ModifierEntry modifier = new ModifierEntry
        {
            Appliance = appliance,
            Operation = operation,
            Value = value,
            Duration = duration,
            Timer = 0
        };
        
        // Add modifier to the attribute
        entry->Modifiers.Add(frame, modifier);
    }
    
    // Set the base value of an attribute
    public static void SetBaseValue(
        Frame frame, 
        EntityRef entity, 
        EAttributeType type, 
        FP value)
    {
        if (!frame.Has<Attributes>(entity))
            return;
            
        Attributes* attributes = frame.Unsafe.GetPointer<Attributes>(entity);
        
        // Find or create the attribute entry
        AttributeEntry* entry = GetEntryOrCreate(frame, attributes, type);
        
        // Set base value
        entry->BaseValue = value;
    }
    
    // Get or create an attribute entry
    private static AttributeEntry* GetEntryOrCreate(
        Frame frame, 
        Attributes* attributes, 
        EAttributeType type)
    {
        // Try to find existing entry
        for (int i = 0; i < attributes->Entries.Length; i++)
        {
            AttributeEntry* entry = &attributes->Entries[i];
            if (entry->Type == type)
            {
                return entry;
            }
        }
        
        // Create new entry if not found
        AttributeEntry newEntry = new AttributeEntry
        {
            Type = type,
            BaseValue = 0,
            Modifiers = new QList<ModifierEntry>(frame.AllocatorHandle, 4)
        };
        
        attributes->Entries.Add(frame, newEntry);
        
        // Return pointer to the newly added entry
        return &attributes->Entries[attributes->Entries.Length - 1];
    }
    
    // Clear all modifiers of a specific type from an attribute
    public static void ClearModifiers(
        Frame frame, 
        EntityRef entity, 
        EAttributeType type)
    {
        if (!frame.Has<Attributes>(entity))
            return;
            
        Attributes* attributes = frame.Unsafe.GetPointer<Attributes>(entity);
        
        // Find the attribute entry for this type
        for (int i = 0; i < attributes->Entries.Length; i++)
        {
            AttributeEntry* entry = &attributes->Entries[i];
            if (entry->Type == type)
            {
                entry->Modifiers.Clear();
                return;
            }
        }
    }
}
```

## Character Attribute Initialization

When a character is created, its attributes are initialized based on its character type:

```csharp
// From CharacterInitializationSystem.cs (simplified)
public static void InitializeAttributes(Frame frame, EntityRef entity, CharacterInfo characterInfo)
{
    // Create attributes component if not exists
    if (!frame.Has<Attributes>(entity))
    {
        frame.Unsafe.AddComponent<Attributes>(entity);
        Attributes* attributes = frame.Unsafe.GetPointer<Attributes>(entity);
        attributes->Entries = new QList<AttributeEntry>(frame.AllocatorHandle, 8);
    }
    
    // Set base attributes from character info
    AttributesHelper.SetBaseValue(frame, entity, EAttributeType.Health, characterInfo.MaxHealth);
    AttributesHelper.SetBaseValue(frame, entity, EAttributeType.Speed, characterInfo.BaseSpeed);
    AttributesHelper.SetBaseValue(frame, entity, EAttributeType.Armor, characterInfo.BaseArmor);
    AttributesHelper.SetBaseValue(frame, entity, EAttributeType.Damage, characterInfo.BaseDamage);
    AttributesHelper.SetBaseValue(frame, entity, EAttributeType.Mana, characterInfo.MaxMana);
    AttributesHelper.SetBaseValue(frame, entity, EAttributeType.Energy, characterInfo.MaxEnergy);
    AttributesHelper.SetBaseValue(frame, entity, EAttributeType.AttackSpeed, characterInfo.BaseAttackSpeed);
    AttributesHelper.SetBaseValue(frame, entity, EAttributeType.SkillCooldown, characterInfo.BaseSkillCooldown);
}
```

## Using Attributes in Game Systems

Various game systems leverage the attributes system:

### Movement System

```csharp
// In MovementSystem.cs (simplified)
public override void Update(Frame frame, ref Filter filter)
{
    // Check if movement is currently locked due to stun
    FP stun = AttributesHelper.GetCurrentValue(frame, filter.Entity, EAttributeType.Stun);
    if (stun > 0)
    {
        return;
    }

    // Get character speed from attributes
    FP characterSpeed = AttributesHelper.GetCurrentValue(frame, filter.Entity, EAttributeType.Speed);
    filter.KCC->MaxSpeed = characterSpeed;
    
    // Rest of movement logic...
}
```

### Skill System

```csharp
// In CharacterSkillCreationSystem.cs (simplified)
private void TryCreateSkill(Frame frame, EntityRef entity, FPVector2 position, 
    AssetRef<SkillData> skillDataRef, FPVector2 actionDirection)
{
    SkillData skillData = frame.FindAsset<SkillData>(skillDataRef.Id);
    
    // Check if character has enough resource for skill
    FP currentResourceValue = AttributesHelper.GetCurrentValue(
        frame, entity, skillData.CostType);
        
    if (currentResourceValue < skillData.Cost)
        return;
        
    // Check silence status (prevents skill use)
    FP silenceValue = AttributesHelper.GetCurrentValue(
        frame, entity, EAttributeType.Silence);
        
    if (silenceValue > 0)
        return;
    
    // Rest of skill creation logic...
}
```

### Combat System

```csharp
// In AttackData.cs (simplified)
protected void ApplyDamageToTarget(Frame frame, EntityRef attackEntity, 
    EntityRef target, Attack* attack)
{
    // Skip if target is invalid
    if (!frame.Exists(target) || !frame.Has<Health>(target))
        return;
        
    // Get base damage from attack
    FP baseDamage = Damage;
    
    // Scale damage based on attacker's damage attribute
    if (frame.Exists(attack->Source))
    {
        FP damageMultiplier = AttributesHelper.GetCurrentValue(
            frame, attack->Source, EAttributeType.Damage);
            
        baseDamage *= FP._1 + (damageMultiplier / FP._100);
    }
    
    // Apply damage to target
    HealthSystem.ApplyDamage(frame, target, attack->Source, baseDamage);
}
```

## Character Buffs and Debuffs

Buffs and debuffs use the attributes system:

```csharp
// Speed boost buff implementation (simplified)
public static void ApplySpeedBoost(Frame frame, EntityRef target, FP multiplier, FP duration)
{
    AttributesHelper.ChangeAttribute(
        frame, 
        target, 
        EAttributeType.Speed, 
        EModifierAppliance.Timer, 
        EModifierOperation.Multiply, 
        multiplier, 
        duration);
        
    // Trigger visual effect
    frame.Events.BuffApplied(target, "SpeedBoost");
}

// Stun debuff implementation (simplified)
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
        
    // Trigger visual effect
    frame.Events.DebuffApplied(target, "Stun");
}
```

## Specialized Attribute Implementations

For some specialized attributes, the system provides additional helper functions:

```csharp
// From ImmuneSystem.cs - System that handles immunity frames
public static void SetImmortal(Frame frame, EntityRef entity, FP duration)
{
    if (!frame.Exists(entity) || !frame.Has<Health>(entity))
        return;
        
    Health* health = frame.Unsafe.GetPointer<Health>(entity);
    health->IsImmortal = true;
    
    // Set timer to remove immunity
    frame.Timer.Set(entity, "Immunity", duration, () => {
        if (frame.Exists(entity))
        {
            Health* h = frame.Unsafe.GetPointer<Health>(entity);
            h->IsImmortal = false;
        }
    });
}

// From RespawnSystem.cs - Helper to set respawn time
public static void SetRespawnTime(Frame frame, EntityRef entity)
{
    if (!frame.Exists(entity) || !frame.Has<Respawn>(entity))
        return;
        
    Respawn* respawn = frame.Unsafe.GetPointer<Respawn>(entity);
    respawn->RespawnDelay = AttributesHelper.GetCurrentValue(
        frame, entity, EAttributeType.RespawnTime);
}
```

## Best Practices

1. **Flexible Attribute System**: Design attributes to handle a wide variety of game mechanics
2. **Helper Functions**: Create utility functions to simplify common attribute operations
3. **Timed Modifiers**: Use the timer system for temporary buffs and debuffs
4. **Stacking Rules**: Define clear rules for how multiple modifiers combine
5. **Centralized Access**: Access attributes through helper functions for consistency
6. **Data-Driven Design**: Define base attribute values in character data assets
7. **Type Safety**: Use enums for attribute types to prevent errors

## Implementation Notes

1. The attribute system supports various modifier operations for flexibility
2. Modifiers can be permanent, one-time, or duration-based
3. Modifiers are processed in a specific order: additive → multiplicative → min/max/override
4. The system automatically handles expiration of timed modifiers
5. Helper methods simplify common attribute operations
6. All calculations are deterministic for network consistency
7. The attribute component is dynamically sized, allowing for efficient use of memory