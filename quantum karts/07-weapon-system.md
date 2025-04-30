# Quantum Karts Weapon System

This document details the weapon system in Quantum Karts, explaining how weapons are acquired, stored, and used by players to gain advantages during races.

## Core Components

The weapon system consists of several interconnected components:

### KartWeapons Component

The `KartWeapons` component is attached to karts to manage their current weapon:

```qtn
component KartWeapons {
    [ExcludeFromPrototype] AssetRef<WeaponAsset> HeldWeapon;
    [ExcludeFromPrototype] byte RemainingUses;
}
```

Implementation:

```csharp
public unsafe partial struct KartWeapons
{
    public void GiveWeapon(Frame f, EntityRef entity, AssetRef<WeaponAsset> weaponAsset)
    {
        if (HeldWeapon != null)
        {
            // don't replace weapons
            return;
        }

        HeldWeapon = weaponAsset;
        RemainingUses = f.FindAsset(HeldWeapon).Uses;

        f.Events.WeaponCollected(entity, this);
    }

    public void UseWeapon(Frame f, KartSystem.Filter filter)
    {
        if (HeldWeapon == null)
        {
            return;
        }

        f.FindAsset(HeldWeapon).Activate(f, filter.Entity);

        if (--RemainingUses <= 0)
        {
            RemoveWeapon();
        }

        f.Events.WeaponUsed(filter.Entity, this);
    }

    public void RemoveWeapon()
    {
        HeldWeapon = null;
    }
}
```

### WeaponAsset Base Class

The `WeaponAsset` class is the base for all weapon types:

```csharp
public abstract partial class WeaponAsset : AssetObject
{
    [Header("Unity")]
    public Sprite WeaponSprite;
    public string WeaponName;

    /// <summary>
    /// How many times weapon can be used in total
    /// </summary>
    [Header("Quantum")]
    public byte Uses = 1;

    /// <summary>
    /// Activates the weapon
    /// </summary>
    /// <param name="f">Game frame</param>
    /// <param name="sourceKartEntity">Kart entity which used the weapon</param>
    public abstract void Activate(Frame f, EntityRef sourceKartEntity);

    /// <summary>
    /// Contains weapon specific AI behaviour
    /// </summary>
    /// <param name="f">Game frame</param>
    /// <param name="aiKartEntity">AI kart entity</param>
    /// <returns>Whether or not the AI driver should activate the weapon this frame</returns>
    public abstract bool AIShouldUse(Frame f, EntityRef aiKartEntity);
}
```

### WeaponPickup Component

The `WeaponPickup` component is attached to item boxes on the track:

```qtn
component WeaponPickup {
    [ExcludeFromPrototype] FP RespawnTimer;
    [ExcludeFromPrototype] bool Active;
    AssetRef<WeaponSelection> WeaponSelectionAsset;
}
```

Implementation:

```csharp
public unsafe partial struct WeaponPickup
{
    public void Collect(Frame f, EntityRef kartEntity)
    {
        if (!Active) { return; }
        
        // Check if kart can receive weapon
        if (!f.Unsafe.TryGetPointer(kartEntity, out KartWeapons* weapons)) { return; }
        if (weapons->HeldWeapon != null) { return; }
        
        // Get weapon selection asset
        var weaponSelection = f.FindAsset(WeaponSelectionAsset);
        
        // Select a weapon based on kart position
        AssetRef<WeaponAsset> selectedWeapon = SelectWeapon(f, kartEntity, weaponSelection);
        
        // Give weapon to kart
        weapons->GiveWeapon(f, kartEntity, selectedWeapon);
        
        // Deactivate pickup and start respawn timer
        Active = false;
        RespawnTimer = weaponSelection.RespawnTime;
        
        // Send event
        f.Events.WeaponPickupCollected(kartEntity);
    }
    
    private AssetRef<WeaponAsset> SelectWeapon(Frame f, EntityRef kartEntity, WeaponSelection selection)
    {
        // Get kart's race position
        sbyte position = sbyte.MaxValue;
        if (f.Unsafe.TryGetPointer(kartEntity, out RaceProgress* progress))
        {
            position = progress->CurrentPosition;
        }
        
        // Select weapon based on position
        if (position <= 3)
        {
            // Front positions get defensive weapons
            return selection.GetWeaponFromCategory(f, WeaponCategory.Defensive);
        }
        else if (position >= 6)
        {
            // Back positions get catch-up weapons
            return selection.GetWeaponFromCategory(f, WeaponCategory.CatchUp);
        }
        else
        {
            // Middle positions get balanced weapons
            return selection.GetWeaponFromCategory(f, WeaponCategory.Balanced);
        }
    }
    
    public void Update(Frame f)
    {
        if (!Active && RespawnTimer > 0)
        {
            RespawnTimer -= f.DeltaTime;
            
            if (RespawnTimer <= 0)
            {
                Active = true;
                f.Events.WeaponPickupRespawned(f.FindEntityRef(this));
            }
        }
    }
}
```

### WeaponSelection Asset

The `WeaponSelection` asset defines weapon distribution and probabilities:

```csharp
public partial class WeaponSelection : AssetObject
{
    public FP RespawnTime = 5;
    
    [Header("Defensive Weapons")]
    public List<WeaponProbability> DefensiveWeapons = new();
    
    [Header("Balanced Weapons")]
    public List<WeaponProbability> BalancedWeapons = new();
    
    [Header("Catch-up Weapons")]
    public List<WeaponProbability> CatchUpWeapons = new();
    
    [Serializable]
    public class WeaponProbability
    {
        public AssetRef<WeaponAsset> Weapon;
        public FP Probability;
    }
    
    public AssetRef<WeaponAsset> GetWeaponFromCategory(Frame f, WeaponCategory category)
    {
        List<WeaponProbability> weapons;
        
        switch (category)
        {
            case WeaponCategory.Defensive:
                weapons = DefensiveWeapons;
                break;
            case WeaponCategory.CatchUp:
                weapons = CatchUpWeapons;
                break;
            default:
                weapons = BalancedWeapons;
                break;
        }
        
        // Calculate total probability
        FP totalProb = FP._0;
        foreach (var weapon in weapons)
        {
            totalProb += weapon.Probability;
        }
        
        // Generate random number
        FP rand = f.RNG->NextFP(FP._0, totalProb);
        
        // Select weapon based on probability
        FP currentProb = FP._0;
        foreach (var weapon in weapons)
        {
            currentProb += weapon.Probability;
            
            if (rand <= currentProb)
            {
                return weapon.Weapon;
            }
        }
        
        // Fallback to first weapon
        return weapons[0].Weapon;
    }
}

public enum WeaponCategory
{
    Defensive,
    Balanced,
    CatchUp
}
```

## Weapon Types

Quantum Karts implements several weapon types, all derived from the `WeaponAsset` base class:

### Boost Weapon

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

### Shield Weapon

```csharp
public class WeaponShield : WeaponAsset
{
    public FP Duration = 5;
    
    public override void Activate(Frame f, EntityRef sourceKartEntity)
    {
        // Add shield component with duration
        var shield = new Shield { Duration = Duration };
        f.Add(sourceKartEntity, shield);
        
        f.Events.ShieldActivated(sourceKartEntity, Duration);
    }
    
    public override bool AIShouldUse(Frame f, EntityRef aiKartEntity)
    {
        // Activate shield when an incoming hazard is detected
        if (f.Unsafe.TryGetPointer(aiKartEntity, out KartHitReceiver* receiver))
        {
            return receiver->IncomingHazardDetected;
        }
        
        return false;
    }
}
```

### Hazard Spawner Weapon

```csharp
public class WeaponHazardSpawner : WeaponAsset
{
    public AssetRef<EntityPrototype> HazardPrototype;
    public FP SpawnOffset = 2;
    public bool SpawnBehind = false;
    
    public override void Activate(Frame f, EntityRef sourceKartEntity)
    {
        if (!f.Unsafe.TryGetPointer(sourceKartEntity, out Transform3D* transform))
        {
            return;
        }
        
        // Calculate spawn position
        FPVector3 direction = SpawnBehind ? -transform->Forward : transform->Forward;
        FPVector3 spawnPosition = transform->Position + direction * SpawnOffset;
        
        // Create hazard entity
        EntityRef hazard = f.Create(HazardPrototype);
        
        // Set hazard position and properties
        if (f.Unsafe.TryGetPointer(hazard, out Transform3D* hazardTransform))
        {
            hazardTransform->Position = spawnPosition;
            hazardTransform->Rotation = transform->Rotation;
        }
        
        // Link hazard to the kart that spawned it
        if (f.Unsafe.TryGetPointer(hazard, out Hazard* hazardComp))
        {
            hazardComp->SourceKart = sourceKartEntity;
        }
        
        f.Events.HazardSpawned(sourceKartEntity, hazard);
    }
    
    public override bool AIShouldUse(Frame f, EntityRef aiKartEntity)
    {
        // Use offensive weapons when there's a kart ahead
        if (SpawnBehind)
        {
            // Use defensive weapons when there's a kart behind
            return f.Unsafe.TryGetPointer(aiKartEntity, out AIDriver* driver) && 
                   driver->KartBehindDistance < FP._10;
        }
        else
        {
            return f.Unsafe.TryGetPointer(aiKartEntity, out AIDriver* driver) && 
                   driver->KartAheadDistance < FP._10;
        }
    }
}
```

## Weapon Collection and Usage

The weapon flow consists of several steps:

### 1. Weapon Pickup Collection

Weapons are collected when karts drive through weapon pickup boxes:

```csharp
public unsafe class WeaponPickupSystem : SystemMainThreadFilter<WeaponPickupSystem.Filter>, ISignalOnTriggerEnter3D
{
    public struct Filter
    {
        public EntityRef Entity;
        public WeaponPickup* WeaponPickup;
    }
    
    public override void Update(Frame frame, ref Filter filter)
    {
        // Update pickup respawn timer
        filter.WeaponPickup->Update(frame);
    }
    
    public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
    {
        // Check if trigger is a weapon pickup
        if (!f.Unsafe.TryGetPointer(info.Other, out WeaponPickup* pickup))
        {
            return;
        }
        
        // Try to give weapon to kart
        pickup->Collect(f, info.Entity);
    }
}
```

### 2. Weapon Activation

Weapons are activated when the player presses the weapon button:

```csharp
// In KartSystem.Update
if (input.Powerup.WasPressed && frame.Unsafe.TryGetPointer(filter.Entity, out KartWeapons* weapons))
{
    weapons->UseWeapon(frame, filter);
}
```

### 3. Weapon Effects

Each weapon type implements its own effects through the `Activate` method:

```csharp
// Example from WeaponBoost
public override void Activate(Frame f, EntityRef sourceKartEntity)
{
    if (f.Unsafe.TryGetPointer(sourceKartEntity, out KartBoost* boost))
    {
        boost->StartBoost(f, f.FindAsset<BoostConfig>(BoostConfig.Id), sourceKartEntity);
    }
}
```

## Hazard System

Many weapons create hazards that can affect other karts:

### Hazard Component

```qtn
component Hazard {
    [ExcludeFromPrototype] EntityRef SourceKart;
    [ExcludeFromPrototype] FP Lifetime;
    
    FP MaxLifetime;
    FP Damage;
    bool AffectsSource;
}
```

Implementation:

```csharp
public unsafe partial struct Hazard
{
    public void Update(Frame f)
    {
        Lifetime += f.DeltaTime;
        
        if (Lifetime >= MaxLifetime)
        {
            // Destroy hazard when lifetime expires
            f.Destroy(f.FindEntityRef(this));
        }
    }
    
    public bool CanAffectKart(EntityRef kartEntity)
    {
        // Prevent hazard from affecting its source unless allowed
        return AffectsSource || kartEntity != SourceKart;
    }
}
```

### Hazard System

```csharp
public unsafe class HazardSystem : SystemMainThreadFilter<HazardSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Hazard* Hazard;
    }
    
    public override void Update(Frame frame, ref Filter filter)
    {
        // Update hazard lifetime
        filter.Hazard->Update(frame);
    }
}
```

### Hazard Collision Detection

```csharp
public unsafe class HazardCollisionSystem : SystemSignalsOnly, ISignalOnTriggerEnter3D
{
    public void OnTriggerEnter3D(Frame f, TriggerInfo3D info)
    {
        // Check if collision involves a hazard
        if (!f.Unsafe.TryGetPointer(info.Other, out Hazard* hazard))
        {
            return;
        }
        
        // Check if collision is with a kart
        if (!f.Unsafe.TryGetPointer(info.Entity, out KartHitReceiver* hitReceiver))
        {
            return;
        }
        
        // Check if hazard can affect this kart
        if (!hazard->CanAffectKart(info.Entity))
        {
            return;
        }
        
        // Apply hazard effect
        hitReceiver->ApplyHit(f, info.Entity, hazard->Damage);
        
        // Destroy hazard after hit (if it's a one-time effect)
        f.Destroy(info.Other);
        
        // Send event
        f.Events.HazardHitKart(info.Entity, info.Other);
    }
}
```

## Hit Reception System

Karts use a `KartHitReceiver` component to handle being hit by hazards:

```qtn
component KartHitReceiver {
    [ExcludeFromPrototype] FP HitTimer;
    [ExcludeFromPrototype] FP InvulnerabilityTimer;
    [ExcludeFromPrototype] bool IncomingHazardDetected;
}
```

Implementation:

```csharp
public unsafe partial struct KartHitReceiver
{
    public void Update(Frame frame, KartSystem.Filter filter)
    {
        // Update hit recovery timer
        if (HitTimer > 0)
        {
            HitTimer -= frame.DeltaTime;
        }
        
        // Update invulnerability timer
        if (InvulnerabilityTimer > 0)
        {
            InvulnerabilityTimer -= frame.DeltaTime;
        }
        
        // Reset incoming hazard detection
        IncomingHazardDetected = false;
    }
    
    public void ApplyHit(Frame frame, EntityRef kartEntity, FP damage)
    {
        // Skip if invulnerable
        if (InvulnerabilityTimer > 0)
        {
            return;
        }
        
        // Check for shield protection
        if (frame.Unsafe.TryGetPointer(kartEntity, out Shield* shield))
        {
            // Shield blocks the hit
            frame.Remove<Shield>(kartEntity);
            frame.Events.ShieldBlocked(kartEntity);
            return;
        }
        
        // Apply hit effect
        HitTimer = damage;
        
        // Add brief invulnerability to prevent multiple hits
        InvulnerabilityTimer = FP._1;
        
        // Apply velocity reduction
        if (frame.Unsafe.TryGetPointer(kartEntity, out Kart* kart))
        {
            kart->Velocity *= FP._0_25;
        }
        
        // Send hit event
        frame.Events.KartHit(kartEntity, damage);
    }
}
```

## Shield System

The shield system provides temporary protection against hazards:

```qtn
component Shield {
    [ExcludeFromPrototype] FP Duration;
    [ExcludeFromPrototype] FP RemainingTime;
}
```

Implementation:

```csharp
public unsafe class ShieldSystem : SystemMainThreadFilter<ShieldSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Shield* Shield;
    }
    
    public override void Update(Frame frame, ref Filter filter)
    {
        filter.Shield->RemainingTime += frame.DeltaTime;
        
        if (filter.Shield->RemainingTime >= filter.Shield->Duration)
        {
            frame.Remove<Shield>(filter.Entity);
            frame.Events.ShieldExpired(filter.Entity);
        }
    }
}
```

## Weapon Selection Logic

Weapons are distributed based on race position to create rubber-banding effects:

```csharp
private AssetRef<WeaponAsset> SelectWeapon(Frame f, EntityRef kartEntity, WeaponSelection selection)
{
    // Get kart's race position
    sbyte position = sbyte.MaxValue;
    if (f.Unsafe.TryGetPointer(kartEntity, out RaceProgress* progress))
    {
        position = progress->CurrentPosition;
    }
    
    // Select weapon based on position
    if (position <= 3)
    {
        // Front positions get defensive weapons
        return selection.GetWeaponFromCategory(f, WeaponCategory.Defensive);
    }
    else if (position >= 6)
    {
        // Back positions get catch-up weapons
        return selection.GetWeaponFromCategory(f, WeaponCategory.CatchUp);
    }
    else
    {
        // Middle positions get balanced weapons
        return selection.GetWeaponFromCategory(f, WeaponCategory.Balanced);
    }
}
```

The rubber-banding is further enhanced by weapon category definitions:

- **Defensive Weapons**: Shields, backward projectiles, oil slicks
- **Balanced Weapons**: Speed boosts, standard projectiles
- **Catch-up Weapons**: Super speed boosts, homing projectiles, lightning

## AI Weapon Usage

AI drivers make strategic decisions about when to use weapons:

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

Each weapon type implements its own AI usage logic:

```csharp
// Example from WeaponBoost
public override bool AIShouldUse(Frame f, EntityRef aiKartEntity)
{
    // AI logic for when to use boost weapon
    if (!f.Unsafe.TryGetPointer(aiKartEntity, out Kart* kart)) { return false; }
    
    // Use boost if not at max speed
    return kart->GetNormalizedSpeed(f) < FP._0_90;
}

// Example from WeaponShield
public override bool AIShouldUse(Frame f, EntityRef aiKartEntity)
{
    // Activate shield when an incoming hazard is detected
    if (f.Unsafe.TryGetPointer(aiKartEntity, out KartHitReceiver* receiver))
    {
        return receiver->IncomingHazardDetected;
    }
    
    return false;
}
```

## Visual Feedback

The weapon system provides visual feedback through several events:

```csharp
// Weapon collection and use
f.Events.WeaponCollected(entity, this);
f.Events.WeaponUsed(filter.Entity, this);

// Pickup box events
f.Events.WeaponPickupCollected(kartEntity);
f.Events.WeaponPickupRespawned(f.FindEntityRef(this));

// Hazard events
f.Events.HazardSpawned(sourceKartEntity, hazard);
f.Events.HazardHitKart(info.Entity, info.Other);

// Shield events
f.Events.ShieldActivated(sourceKartEntity, Duration);
f.Events.ShieldBlocked(kartEntity);
f.Events.ShieldExpired(filter.Entity);

// Hit events
f.Events.KartHit(kartEntity, damage);
```

Example Unity handler for weapon display:

```csharp
public class WeaponDisplayUI : MonoBehaviour
{
    [SerializeField] private Image weaponIcon;
    [SerializeField] private Text weaponName;
    
    private QuantumCallback<EventWeaponCollected> weaponCollectedCallback;
    private QuantumCallback<EventWeaponUsed> weaponUsedCallback;
    
    private void OnEnable()
    {
        weaponCollectedCallback = QuantumCallback.Subscribe<EventWeaponCollected>(this, OnWeaponCollected);
        weaponUsedCallback = QuantumCallback.Subscribe<EventWeaponUsed>(this, OnWeaponUsed);
    }
    
    private void OnDisable()
    {
        if (weaponCollectedCallback != null)
        {
            weaponCollectedCallback.Dispose();
            weaponCollectedCallback = null;
        }
        
        if (weaponUsedCallback != null)
        {
            weaponUsedCallback.Dispose();
            weaponUsedCallback = null;
        }
    }
    
    private void OnWeaponCollected(EventWeaponCollected evt)
    {
        // Only show for local player
        if (evt.Entity != LocalPlayerManager.Instance.LocalPlayerKartEntity) { return; }
        
        // Get weapon asset
        var weapon = QuantumRunner.Default.Game.FindAsset<WeaponAsset>(evt.Weapons.HeldWeapon);
        
        // Update UI
        weaponIcon.sprite = weapon.WeaponSprite;
        weaponName.text = weapon.WeaponName;
        weaponIcon.gameObject.SetActive(true);
    }
    
    private void OnWeaponUsed(EventWeaponUsed evt)
    {
        // Only handle for local player
        if (evt.Entity != LocalPlayerManager.Instance.LocalPlayerKartEntity) { return; }
        
        // Hide weapon icon if no uses left
        if (evt.Weapons.RemainingUses <= 0)
        {
            weaponIcon.gameObject.SetActive(false);
        }
    }
}
```

## Best Practices

1. **Weapon Balance**: Create a mix of offensive, defensive, and utility weapons
2. **Position-Based Distribution**: Provide stronger catch-up weapons to racers in the back
3. **Clear Visual Feedback**: Ensure players understand what weapons they have and when they're affected
4. **AI Strategy**: Give AI drivers strategic weapon usage behaviors
5. **Feedback Events**: Use events to synchronize visual and audio effects with weapon actions
6. **Weapon Categories**: Group weapons into categories for balanced distribution
7. **Deterministic RNG**: Use Quantum's deterministic random number generator for weapon selection
8. **Invulnerability Periods**: Prevent chain-stunning with brief invulnerability after hits
