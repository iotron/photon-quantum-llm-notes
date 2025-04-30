# Quantum Karts Boost System

This document details the boost system in Quantum Karts, explaining how temporary speed enhancements are implemented, configured, and integrated with other game systems.

## Core Components

The boost system consists of several interrelated components:

### KartBoost Component

The `KartBoost` component is the central element that handles boost application and timing:

```qtn
component KartBoost {
    [ExcludeFromPrototype] AssetRef<BoostConfig> CurrentBoost;
    [ExcludeFromPrototype] FP TimeRemaining;
}
```

Implementation:

```csharp
public unsafe partial struct KartBoost
{
    public void Update(Frame f)
    {
        if (TimeRemaining <= 0)
        {
            return;
        }

        TimeRemaining -= f.DeltaTime;

        if (TimeRemaining <= 0)
        {
            CurrentBoost = null;
        }
    }

    public void StartBoost(Frame f, AssetRef<BoostConfig> config, EntityRef kartEntity)
    {
        BoostConfig boost = f.FindAsset(config);
        CurrentBoost = config;
        TimeRemaining = boost.Duration;

        f.Events.OnBoostStart(kartEntity, this);
    }

    public void Interrupt()
    {
        CurrentBoost = null;
        TimeRemaining = 0;
    }
}
```

### BoostConfig Asset

The `BoostConfig` asset defines the properties of each boost type:

```csharp
public unsafe partial class BoostConfig : AssetObject
{
    public FP Duration;
    public FP AccelerationBonus;
    public FP MaxSpeedBonus;
    
    public Color ExhaustColor;
}
```

Key properties:
- **Duration**: How long the boost lasts
- **AccelerationBonus**: Additional acceleration applied during boost
- **MaxSpeedBonus**: Increase to maximum speed during boost
- **ExhaustColor**: Visual color for exhaust particles

### DriftBoost Component

The `DriftBoost` component integrates drifting with the boost system:

```qtn
component DriftBoost {
    [ExcludeFromPrototype] FP DriftTime;
    [ExcludeFromPrototype] byte BoostLevel;
    [ExcludeFromPrototype] FP BoostVisualFeedback;
    [ExcludeFromPrototype] array<FP>[3] BoostThresholds;
    [ExcludeFromPrototype] array<AssetRef<BoostConfig>>[3] BoostConfigs;
}
```

This tracks drift time and awards different boost levels based on drift duration.

## Boost System Implementation

The boost system is updated through the `BoostSystem` class:

```csharp
public unsafe class BoostSystem : SystemMainThreadFilter<BoostSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public KartBoost* KartBoost;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        filter.KartBoost->Update(frame);
    }
}
```

## Integration with Kart Physics

The boost system is integrated with the kart physics through two key methods in the `Kart` component:

### 1. Acceleration Modification

```csharp
public FP GetAcceleration(Frame frame, EntityRef entity)
{
    KartStats stats = frame.FindAsset(StatsAsset);
    FP bonus = 0;

    if (frame.Unsafe.TryGetPointer(entity, out KartBoost* kartBoost) && kartBoost->CurrentBoost != null)
    {
        BoostConfig config = frame.FindAsset(kartBoost->CurrentBoost);
        bonus += config.AccelerationBonus;
    }

    return stats.acceleration.Evaluate(GetNormalizedSpeed(frame)) * SurfaceSpeedMultiplier + bonus;
}
```

### 2. Max Speed Modification

```csharp
public FP GetMaxSpeed(Frame frame, EntityRef entity)
{
    KartStats stats = frame.FindAsset(StatsAsset);
    FP bonus = 0;

    if (frame.Unsafe.TryGetPointer(entity, out KartBoost* kartBoost) && kartBoost->CurrentBoost != null)
    {
        BoostConfig config = frame.FindAsset(kartBoost->CurrentBoost);
        bonus += config.MaxSpeedBonus;
    }

    return stats.maxSpeed * SurfaceSpeedMultiplier + bonus;
}
```

These methods are called during the kart's physics update to modify acceleration and top speed when a boost is active.

## Boost Sources

There are multiple ways for a kart to receive a boost:

### 1. Drift Boosts

Drift boosts are awarded based on drift duration through the `DriftBoost` component:

```csharp
public unsafe partial struct DriftBoost
{
    public void Update(Frame frame, KartSystem.Filter filter)
    {
        Drifting* drifting = filter.Drifting;
        
        // When drifting, accumulate time and check for boost level upgrades
        if (drifting->IsDrifting)
        {
            DriftTime += frame.DeltaTime;
            
            // Check for boost level upgrades
            for (byte i = 0; i < BoostThresholds.Length; i++)
            {
                if (DriftTime >= BoostThresholds.GetPointer(i)->Value && i > BoostLevel)
                {
                    BoostLevel = i;
                    BoostVisualFeedback = FP._1;
                    frame.Events.DriftBoostCharged(filter.Entity, BoostLevel);
                }
            }
            
            // Fade visual feedback
            if (BoostVisualFeedback > 0)
            {
                BoostVisualFeedback -= frame.DeltaTime * 2;
            }
        }
        // When drifting ends, apply the boost if eligible
        else if (DriftTime > 0)
        {
            if (BoostLevel > 0 && frame.Unsafe.TryGetPointer(filter.Entity, out KartBoost* boost))
            {
                boost->StartBoost(frame, BoostConfigs.GetPointer(BoostLevel - 1)->Value, filter.Entity);
                frame.Events.DriftBoostApplied(filter.Entity, BoostLevel);
            }
            
            // Reset values
            DriftTime = 0;
            BoostLevel = 0;
            BoostVisualFeedback = 0;
        }
    }
}
```

This system:
1. Tracks drift time
2. Updates boost level when thresholds are crossed
3. Applies the appropriate boost when drifting ends
4. Sends events for visual feedback

### 2. Weapon Boosts

The `WeaponBoost` class implements a boost weapon that can be collected and used:

```csharp
public class WeaponBoost : WeaponAsset
{
    public BoostConfig BoostConfig;
    
    public override void Activate(Frame f, EntityRef sourceKartEntity)
    {
        if (f.Unsafe.TryGetPointer(sourceKartEntity, out KartBoost* boost))
        {
            boost->StartBoost(f, f.FindAsset<BoostConfig>(BoostConfig.Id), sourceKartEntity);
        }
    }
    
    public override bool AIShouldUse(Frame f, EntityRef aiKartEntity)
    {
        // AI logic for when to use boost weapon
        if (!f.Unsafe.TryGetPointer(aiKartEntity, out Kart* kart)) { return false; }
        
        // Use boost if not at max speed
        return kart->GetNormalizedSpeed(f) < FP._0_90;
    }
}
```

### 3. Track Boost Pads

Boost pads on the track can apply boosts through trigger collisions:

```csharp
public unsafe class BoostPadSystem : SystemSignalsOnly, ISignalOnTriggerEnter3D
{
    public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
    {
        // Check if the collider is a boost pad
        if (!f.Unsafe.TryGetPointer(info.Other, out BoostPad* boostPad)) { return; }
        
        // Check if the entity is a kart
        if (!f.Unsafe.TryGetPointer(info.Entity, out KartBoost* kartBoost)) { return; }
        
        // Apply the boost
        kartBoost->StartBoost(f, boostPad->BoostConfig, info.Entity);
        
        // Trigger visual effect
        f.Events.OnBoostPadHit(info.Entity, info.Other);
    }
}
```

## Visual Feedback

The boost system provides visual feedback through several events:

```csharp
// In KartBoost.StartBoost
f.Events.OnBoostStart(kartEntity, this);

// In DriftBoost.Update
f.Events.DriftBoostCharged(filter.Entity, BoostLevel);
f.Events.DriftBoostApplied(filter.Entity, BoostLevel);

// In BoostPadSystem
f.Events.OnBoostPadHit(info.Entity, info.Other);
```

These events are handled on the Unity side to show:
1. **Exhaust Effects**: Colored flames from the kart's exhaust
2. **Speed Lines**: Camera effect indicating increased speed
3. **Particle Effects**: Trails and sparks showing boost activation

Example Unity handler:

```csharp
public class BoostVisualController : MonoBehaviour
{
    [SerializeField] private ParticleSystem exhaustEffect;
    [SerializeField] private AudioSource boostSound;
    
    private QuantumCallback<EventOnBoostStart> boostStartCallback;
    
    private void OnEnable()
    {
        boostStartCallback = QuantumCallback.Subscribe<EventOnBoostStart>(this, OnBoostStart);
    }
    
    private void OnDisable()
    {
        if (boostStartCallback != null)
        {
            boostStartCallback.Dispose();
            boostStartCallback = null;
        }
    }
    
    private void OnBoostStart(EventOnBoostStart evt)
    {
        if (EntityRef != evt.Entity) { return; }
        
        // Get boost config
        var boostConfig = QuantumRunner.Default.Game.FindAsset<BoostConfig>(evt.KartBoost.CurrentBoost);
        
        // Set exhaust color
        var main = exhaustEffect.main;
        main.startColor = boostConfig.ExhaustColor;
        
        // Play effects
        exhaustEffect.Play();
        boostSound.Play();
    }
}
```

## Boost Types and Configurations

The boost system allows for different boost types through configuration:

### Mini-Boost (Short Drift)
```csharp
// Configuration example
miniBoostConfig.Duration = FP._1;
miniBoostConfig.AccelerationBonus = FP._2;
miniBoostConfig.MaxSpeedBonus = FP._1;
miniBoostConfig.ExhaustColor = new Color(1, 0.5f, 0);
```

### Super-Boost (Long Drift)
```csharp
// Configuration example
superBoostConfig.Duration = FP._3;
superBoostConfig.AccelerationBonus = FP._5;
superBoostConfig.MaxSpeedBonus = FP._3;
superBoostConfig.ExhaustColor = new Color(1, 0, 1);
```

### Pickup Boost
```csharp
// Configuration example
pickupBoostConfig.Duration = FP._5;
pickupBoostConfig.AccelerationBonus = FP._3;
pickupBoostConfig.MaxSpeedBonus = FP._2;
pickupBoostConfig.ExhaustColor = new Color(0, 1, 1);
```

### Boost Pad
```csharp
// Configuration example
boostPadConfig.Duration = FP._2;
boostPadConfig.AccelerationBonus = FP._2;
boostPadConfig.MaxSpeedBonus = FP._2;
boostPadConfig.ExhaustColor = new Color(1, 1, 0);
```

## Boost Stacking Behavior

The boost system handles sequential boosts by interrupting the current boost and starting a new one:

```csharp
public void StartBoost(Frame f, AssetRef<BoostConfig> config, EntityRef kartEntity)
{
    BoostConfig boost = f.FindAsset(config);
    CurrentBoost = config;
    TimeRemaining = boost.Duration;

    f.Events.OnBoostStart(kartEntity, this);
}
```

This simple approach ensures that:
1. Only one boost is active at a time
2. New boosts replace existing ones
3. The most recent boost's properties are applied

## AI Integration

AI drivers can use boosts strategically:

```csharp
public unsafe partial struct AIDriver
{
    // Additional AI weapon usage logic
    private bool ShouldUseBoostWeapon(Frame frame, EntityRef entity)
    {
        if (!frame.Unsafe.TryGetPointer(entity, out Kart* kart)) { return false; }
        
        // Use at start of race
        if (frame.Unsafe.TryGetPointerSingleton(out Race* race) && 
            race->CurrentRaceState == RaceState.Countdown) { return true; }
            
        // Use when not at max speed
        if (kart->GetNormalizedSpeed(frame) < FP._0_75) { return true; }
        
        // Use on straightaways
        if (CurrentTurnAngle < FP._15) { return true; }
        
        return false;
    }
}
```

This allows AI drivers to use boosts in appropriate situations.

## Boost Physics Considerations

When implementing boosts, special care is taken in the physics system:

```csharp
private void LimitVelocity(Frame frame, EntityRef entity)
{
    // No hard clamping so kart doesn't suddenly "hit a wall" when a boost ends
    Velocity = FPVector3.MoveTowards(
        Velocity,
        FPVector3.ClampMagnitude(Velocity, GetMaxSpeed(frame, entity)),
        FP._0_10
    );
}
```

This smooth velocity clamping ensures that:
1. Boosts can exceed normal speed limits
2. When a boost ends, speed decreases gradually
3. The transition feels natural to the player

## Best Practices

1. **Variable Boost Types**: Create different boost configurations for variety
2. **Clear Visual Feedback**: Ensure players understand when boosts are active
3. **Smooth Transitions**: Avoid abrupt speed changes when boosts start/end
4. **Strategic Placement**: Place boost pads at strategic points on tracks
5. **Balance**: Ensure boosts provide meaningful advantages without being overpowered
6. **Compound Systems**: Integrate boosts with other systems like drifting for depth
7. **Deterministic Implementation**: Use Quantum's fixed-point math for consistent network behavior
