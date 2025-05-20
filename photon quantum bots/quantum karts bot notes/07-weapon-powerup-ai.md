# Weapon and Powerup AI Logic

## Overview

AI drivers in Quantum Karts need to make strategic decisions about when to use weapons and powerups. This document explores how the AI evaluates and uses weapons, and how this system integrates with the overall AI decision-making process.

## Weapon System Components

### KartWeapons Component

The `KartWeapons` component manages a kart's current weapon state:

```csharp
// Derived from usage in code
public unsafe partial struct KartWeapons
{
    public AssetRef<Weapon> HeldWeapon;
    
    public void UseWeapon(Frame frame, KartSystem.Filter filter)
    {
        // Logic for using the current weapon
    }
}
```

### Weapon Asset

Weapons are likely defined as assets with various properties and behaviors:

```csharp
// Conceptual structure based on usage
public class Weapon : AssetObject
{
    // Configuration parameters for the weapon
    
    public bool AIShouldUse(Frame frame, EntityRef entity)
    {
        // Decision logic for when AI should use this weapon
        // Different for each weapon type
        return ShouldUseNow(frame, entity);
    }
}
```

## AI Weapon Usage

The AI's decision to use weapons is handled in the `AIDriver.Update` method:

```csharp
// In AIDriver.Update
if (frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
{
    LastWeaponTime += frame.DeltaTime;

    if (weapons->HeldWeapon != default
        && LastWeaponTime > FP._0_50
        && frame.FindAsset(weapons->HeldWeapon).AIShouldUse(frame, filter.Entity))
    {
        input.Powerup = true;
    }
}
```

This code shows three conditions for weapon usage:
1. The AI has a weapon (`weapons->HeldWeapon != default`)
2. Enough time has passed since the last weapon use (`LastWeaponTime > FP._0_50`)
3. The weapon's `AIShouldUse` method returns true

## Weapon-Specific AI Logic

Each weapon type likely has its own AI usage logic in the `AIShouldUse` method:

### Offensive Weapons (e.g., Missiles)

```csharp
// Example implementation for a missile weapon
public override bool AIShouldUse(Frame frame, EntityRef entity)
{
    // Check if there's a kart in front within firing range
    if (frame.Unsafe.TryGetPointer<Transform3D>(entity, out var transform))
    {
        // Find target karts in front
        EntityRef targetKart = FindTargetInFront(frame, transform->Position, transform->Forward);
        return targetKart != default;
    }
    return false;
}
```

### Defensive Weapons (e.g., Shields)

```csharp
// Example implementation for a shield weapon
public override bool AIShouldUse(Frame frame, EntityRef entity)
{
    // Check if there's a kart close behind that might attack
    if (frame.Unsafe.TryGetPointer<Transform3D>(entity, out var transform) &&
        frame.Unsafe.TryGetPointer<RaceProgress>(entity, out var progress))
    {
        bool threatBehind = CheckForThreatBehind(frame, entity, transform->Position);
        return threatBehind;
    }
    return false;
}
```

### Speed Boosts

```csharp
// Example implementation for a speed boost
public override bool AIShouldUse(Frame frame, EntityRef entity)
{
    // Use boost on straightaways
    if (frame.Unsafe.TryGetPointer<Kart>(entity, out var kart))
    {
        // Check if on a straightaway by comparing current and next checkpoint angles
        if (frame.Unsafe.TryGetPointer<AIDriver>(entity, out var ai))
        {
            FPVector3 toWaypoint = ai->TargetLocation - kart->Transform->Position;
            FPVector3 toNextWaypoint = ai->NextTargetLocation - kart->Transform->Position;
            FP turnAngle = FPVector3.Angle(toWaypoint, toNextWaypoint);
            
            // Use boost if the turn angle is small (straightaway)
            return turnAngle < FP._10;
        }
    }
    return false;
}
```

## Integration with Race Positioning

The AI might also consider race position when deciding to use weapons:

```csharp
// Example of position-aware weapon usage
public bool AIShouldUse(Frame frame, EntityRef entity)
{
    if (frame.Unsafe.TryGetPointer<RaceProgress>(entity, out var progress))
    {
        // Use offensive weapons more aggressively when behind
        if (progress->Position > 3) {
            return true; // More likely to use when behind
        }
        // Use defensive weapons when in leading positions
        else if (progress->Position <= 3) {
            // Check if there are threats nearby
            return CheckForNearbyThreats(frame, entity);
        }
    }
    return false;
}
```

## Cooldown Management

The AI implements a simple cooldown system to prevent rapid weapon usage:

```csharp
LastWeaponTime += frame.DeltaTime;

if (weapons->HeldWeapon != default && LastWeaponTime > FP._0_50 && ...)
{
    input.Powerup = true;
}
```

This ensures weapons are used at reasonable intervals.

## Weapon Acquisition

The code we've seen doesn't show how weapons are acquired, but it would likely involve trigger collisions with pickup items on the track. The AI doesn't need special logic for pickups—the physical kart simply collides with them.

## Strategic Considerations

More advanced AI weapon systems might incorporate:

1. **Target Selection**: Choosing the optimal target when multiple options exist
2. **Predictive Aiming**: Leading targets based on their velocity
3. **Defensive Timing**: Using defensive items just before being hit
4. **Weapon Holding**: Saving valuable weapons for strategic moments
5. **Race Context**: Using different strategies based on race progress (early race, mid-race, final lap)

## Implementation Best Practices

1. **Adaptive Usage**: Adjust weapon usage strategies based on AI difficulty level
2. **Balanced Aggression**: Ensure AI doesn't spam weapons or hold them for too long
3. **Realistic Decisions**: Make AI weapon usage mimic human decision patterns
4. **Performance**: Keep weapon decision logic lightweight
5. **Determinism**: Ensure all decisions are deterministic for network synchronization

## Sample Implementation

```csharp
// Example of a complete weapon system integration

// In Weapon base class
public abstract class Weapon : AssetObject 
{
    public virtual bool AIShouldUse(Frame frame, EntityRef entity) 
    {
        return false; // Default implementation
    }
}

// Missile implementation
public class MissileWeapon : Weapon 
{
    public override bool AIShouldUse(Frame frame, EntityRef entity) 
    {
        // Get AI settings to factor in difficulty
        AIDriver* ai = frame.Unsafe.GetPointer<AIDriver>(entity);
        AIDriverSettings settings = frame.FindAsset(ai->SettingsRef);
        
        // More aggressive usage with higher difficulty
        FP useChance = FP._0_30 + settings.Difficulty * FP._0_30;
        
        // Find target in front
        EntityRef target = FindTargetInFront(frame, entity);
        
        if (target != default) {
            // Random factor to prevent predictable usage
            return frame.RNG->NextFP(0, 1) < useChance;
        }
        
        return false;
    }
}

// In AIDriver update
if (weapons->HeldWeapon != default && LastWeaponTime > FP._0_50) 
{
    var weapon = frame.FindAsset(weapons->HeldWeapon);
    
    // Get chance based on weapon type and game state
    if (weapon.AIShouldUse(frame, filter.Entity)) 
    {
        input.Powerup = true;
        LastWeaponTime = 0; // Reset cooldown
    }
}
```

This provides a flexible system where different weapon types can implement their own AI usage logic, while sharing the common cooldown and input mechanism.
