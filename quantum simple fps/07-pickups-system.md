# Pickups System in Quantum Simple FPS

This document explains the implementation of the Pickups System in the Quantum Simple FPS sample project, covering item collection mechanics, weapon pickups, and health restoration.

## Pickup Components

The pickups system is built on these components defined in the Quantum DSL:

```qtn
component Pickup
{
    PickupSettings Settings;
    FP PickupCooldown;

    [ExcludeFromPrototype]
    FP Cooldown;
}

union PickupSettings
{
    HealthPickup Health;
    WeaponPickup Weapon;
}

struct HealthPickup
{
    FP Heal;
}

struct WeaponPickup
{
    Byte WeaponID;
    int RefillAmmo;
}
```

These components define two types of pickups:
1. **Health Pickups**: Restore a specific amount of health
2. **Weapon Pickups**: Provide a weapon or refill ammo for an existing weapon

Pickups also use standard Quantum components:
- `Transform3D`: Position and rotation in the world
- `PhysicsCollider3D`: For collision detection
- `Trigger3D`: To detect when a player enters the pickup area

## Pickup System Implementation

The `PickupSystem` handles the logic for interacting with pickups:

```csharp
namespace Quantum
{
    [Preserve]
    public unsafe class PickupSystem : SystemMainThreadFilter<PickupSystem.Filter>
    {
        public override void Update(Frame frame, ref Filter filter)
        {
            filter.Pickup->Cooldown -= frame.DeltaTime;

            if (filter.Pickup->Cooldown <= 0)
            {
                if (filter.Trigger->OverlapCount > 0)
                {
                    EntityRef overlapEntity = filter.Trigger->GetOverlappingEntity(0);
                    
                    // Process weapon pickups
                    if (filter.Pickup->Settings.IsWeapon)
                    {
                        ProcessWeaponPickup(frame, filter.Entity, overlapEntity, filter.Pickup);
                    }
                    // Process health pickups
                    else if (filter.Pickup->Settings.IsHealth)
                    {
                        ProcessHealthPickup(frame, filter.Entity, overlapEntity, filter.Pickup);
                    }
                }
            }
        }

        private void ProcessWeaponPickup(Frame frame, EntityRef pickupEntity, EntityRef playerEntity, Pickup* pickup)
        {
            if (frame.Unsafe.TryGetPointer<Weapons>(playerEntity, out var weapons))
            {
                var weaponPickup = pickup->Settings.Weapon;
                var weaponRef = weapons->WeaponRefs[weaponPickup.WeaponID];
                
                if (frame.Unsafe.TryGetPointer<Weapon>(weaponRef, out var weapon))
                {
                    if (weapon->CollectOrRefill(weaponPickup.RefillAmmo))
                    {
                        // If player doesn't have this weapon selected, switch to it
                        if (weapons->CurrentWeaponId != weaponPickup.WeaponID)
                        {
                            frame.Signals.SwitchWeapon(playerEntity, weaponPickup.WeaponID);
                        }
                        
                        // Apply pickup cooldown
                        pickup->Cooldown = pickup->PickupCooldown;
                        
                        // Trigger pickup event
                        frame.Events.WeaponPickedUp(pickupEntity, playerEntity);
                    }
                }
            }
        }

        private void ProcessHealthPickup(Frame frame, EntityRef pickupEntity, EntityRef playerEntity, Pickup* pickup)
        {
            if (frame.Unsafe.TryGetPointer<Health>(playerEntity, out var health))
            {
                var healthPickup = pickup->Settings.Health;
                
                if (health->AddHealth(healthPickup.Heal))
                {
                    // Apply pickup cooldown
                    pickup->Cooldown = pickup->PickupCooldown;
                    
                    // Trigger pickup event
                    frame.Events.HealthPickedUp(pickupEntity, playerEntity);
                }
            }
        }

        public struct Filter
        {
            public EntityRef Entity;
            public Pickup*  Pickup;
            public PhysicsCollider3D* Collider;
            public Trigger3D* Trigger;
        }
    }
}
```

Key aspects of the Pickup System:
1. Processes all entities with Pickup, PhysicsCollider3D, and Trigger3D components
2. Checks if players are overlapping with the pickup's trigger
3. Handles different pickup types through specialized methods
4. Applies cooldown to prevent multiple pickup triggers
5. Sends events to notify the view layer

## Weapon Pickup Handling

Weapon pickups integrate with the Weapons system to provide new weapons or refill ammo:

```csharp
private void ProcessWeaponPickup(Frame frame, EntityRef pickupEntity, EntityRef playerEntity, Pickup* pickup)
{
    if (frame.Unsafe.TryGetPointer<Weapons>(playerEntity, out var weapons))
    {
        var weaponPickup = pickup->Settings.Weapon;
        var weaponRef = weapons->WeaponRefs[weaponPickup.WeaponID];
        
        if (frame.Unsafe.TryGetPointer<Weapon>(weaponRef, out var weapon))
        {
            if (weapon->CollectOrRefill(weaponPickup.RefillAmmo))
            {
                // If player doesn't have this weapon selected, switch to it
                if (weapons->CurrentWeaponId != weaponPickup.WeaponID)
                {
                    frame.Signals.SwitchWeapon(playerEntity, weaponPickup.WeaponID);
                }
                
                // Apply pickup cooldown
                pickup->Cooldown = pickup->PickupCooldown;
                
                // Trigger pickup event
                frame.Events.WeaponPickedUp(pickupEntity, playerEntity);
            }
        }
    }
}
```

The `CollectOrRefill` method in the Weapon component:

```csharp
public bool CollectOrRefill(int refillAmmo)
{
    if (IsCollected && RemainingAmmo >= MaxRemainingAmmo)
        return false;

    if (IsCollected)
    {
        // If the weapon is already collected at least refill the ammo
        RemainingAmmo = Math.Min(RemainingAmmo + refillAmmo, MaxRemainingAmmo);
    }
    else
    {
        // Weapon is already present inside Player prefab,
        // marking it as IsCollected is all that is needed
        IsCollected = true;
    }

    return true;
}
```

This mechanism:
1. Checks if the player already has the weapon
2. If not, marks the weapon as collected
3. If already collected, adds ammo (up to the maximum)
4. Automatically switches to the newly collected weapon
5. Returns false if the player already has full ammo

## Health Pickup Handling

Health pickups integrate with the Health system:

```csharp
private void ProcessHealthPickup(Frame frame, EntityRef pickupEntity, EntityRef playerEntity, Pickup* pickup)
{
    if (frame.Unsafe.TryGetPointer<Health>(playerEntity, out var health))
    {
        var healthPickup = pickup->Settings.Health;
        
        if (health->AddHealth(healthPickup.Heal))
        {
            // Apply pickup cooldown
            pickup->Cooldown = pickup->PickupCooldown;
            
            // Trigger pickup event
            frame.Events.HealthPickedUp(pickupEntity, playerEntity);
        }
    }
}
```

The `AddHealth` method in the Health component:

```csharp
public bool AddHealth(FP health)
{
    if (CurrentHealth <= 0)
        return false;
    if (CurrentHealth >= MaxHealth)
        return false;

    CurrentHealth = FPMath.Min(CurrentHealth + health, MaxHealth);

    return true;
}
```

This mechanism:
1. Checks if the player is alive and not at full health
2. Adds health (up to the maximum)
3. Returns false if the player is dead or already at full health

## Pickup Events

Pickups communicate with the view layer through events:

```qtn
event WeaponPickedUp
{
    EntityRef PickupEntity;
    EntityRef PlayerEntity;
}

event HealthPickedUp
{
    EntityRef PickupEntity;
    EntityRef PlayerEntity;
}
```

## Pickup Respawn System

Some pickups respawn after a cooldown period:

```csharp
namespace Quantum
{
    [Preserve]
    public unsafe class PickupRespawnSystem : SystemMainThreadFilter<PickupRespawnSystem.Filter>
    {
        public override void Update(Frame frame, ref Filter filter)
        {
            if (filter.RespawnSettings->IsActive == false)
                return;
                
            // Update cooldown
            filter.RespawnSettings->CurrentCooldown -= frame.DeltaTime;
            
            if (filter.RespawnSettings->CurrentCooldown <= 0)
            {
                // Reset cooldown
                filter.RespawnSettings->CurrentCooldown = filter.RespawnSettings->RespawnCooldown;
                
                // Activate pickup
                filter.RespawnSettings->IsActive = true;
                
                // Enable collider
                var collider = frame.Unsafe.GetPointer<PhysicsCollider3D>(filter.Entity);
                collider->IsTrigger = true;
                
                // Send event for visual feedback
                frame.Events.PickupRespawned(filter.Entity);
            }
        }
        
        public struct Filter
        {
            public EntityRef Entity;
            public PickupRespawnSettings* RespawnSettings;
        }
    }
}
```

This system:
1. Tracks cooldown for respawning pickups
2. Reactivates pickups when their cooldown expires
3. Triggers events for visual feedback

## Pickup View Integration

The Unity-side view code visualizes pickups and their collection:

```csharp
namespace QuantumDemo
{
    public class PickupView : QuantumEntityViewComponent
    {
        // References
        public GameObject ModelRoot;
        public ParticleSystem CollectEffect;
        public AudioSource CollectSound;
        public float RotationSpeed = 90f;
        public float BobAmount = 0.2f;
        public float BobSpeed = 1f;
        
        // Original position for bob effect
        private Vector3 _startPosition;
        private bool _isActive = true;
        
        private void OnEnable()
        {
            // Subscribe to pickup events
            QuantumEvent.Subscribe<EventWeaponPickedUp>(this, OnWeaponPickedUp);
            QuantumEvent.Subscribe<EventHealthPickedUp>(this, OnHealthPickedUp);
            QuantumEvent.Subscribe<EventPickupRespawned>(this, OnPickupRespawned);
            
            // Store original position
            _startPosition = transform.position;
        }
        
        private void OnDisable()
        {
            // Unsubscribe from pickup events
            QuantumEvent.Unsubscribe<EventWeaponPickedUp>(this, OnWeaponPickedUp);
            QuantumEvent.Unsubscribe<EventHealthPickedUp>(this, OnHealthPickedUp);
            QuantumEvent.Unsubscribe<EventPickupRespawned>(this, OnPickupRespawned);
        }
        
        private void Update()
        {
            if (!_isActive)
                return;
                
            // Rotate the pickup
            ModelRoot.transform.Rotate(0, RotationSpeed * Time.deltaTime, 0);
            
            // Bob up and down
            float yOffset = Mathf.Sin(Time.time * BobSpeed) * BobAmount;
            transform.position = _startPosition + new Vector3(0, yOffset, 0);
        }
        
        private void OnWeaponPickedUp(EventWeaponPickedUp e)
        {
            if (e.PickupEntity != EntityRef)
                return;
                
            PlayPickupEffect();
        }
        
        private void OnHealthPickedUp(EventHealthPickedUp e)
        {
            if (e.PickupEntity != EntityRef)
                return;
                
            PlayPickupEffect();
        }
        
        private void OnPickupRespawned(EventPickupRespawned e)
        {
            if (e.Entity != EntityRef)
                return;
                
            // Reactivate pickup
            _isActive = true;
            ModelRoot.SetActive(true);
        }
        
        private void PlayPickupEffect()
        {
            // Hide the pickup model
            _isActive = false;
            ModelRoot.SetActive(false);
            
            // Play visual and audio effects
            CollectEffect.Play();
            CollectSound.Play();
        }
    }
}
```

Key aspects of the pickup visualization:
1. Rotating and bobbing idle animation
2. Visual and audio effects when collected
3. Reactivation when the pickup respawns
4. Event-based communication with the simulation

## Weapon UI Updates

When a weapon is picked up, the UI is updated:

```csharp
namespace QuantumDemo
{
    public class WeaponUIController : QuantumMonoBehaviour
    {
        // References
        public GameObject[] WeaponSlots;
        
        // The local player's entity
        private EntityRef _playerEntity;
        
        public void Initialize(EntityRef playerEntity)
        {
            _playerEntity = playerEntity;
            
            // Subscribe to weapon pickup event
            QuantumEvent.Subscribe<EventWeaponPickedUp>(this, OnWeaponPickedUp);
        }
        
        private void OnDestroy()
        {
            QuantumEvent.Unsubscribe<EventWeaponPickedUp>(this, OnWeaponPickedUp);
        }
        
        private void OnWeaponPickedUp(EventWeaponPickedUp e)
        {
            if (e.PlayerEntity != _playerEntity)
                return;
                
            UpdateWeaponUI();
        }
        
        private void UpdateWeaponUI()
        {
            if (!QuantumRunner.Default.Game.TryGetFrameLocal(out var frame))
                return;
                
            if (!frame.TryGet(_playerEntity, out Weapons weapons))
                return;
                
            // Update UI for each weapon slot
            for (int i = 0; i < WeaponSlots.Length; i++)
            {
                if (i < weapons.WeaponRefs.Length)
                {
                    var weaponRef = weapons.WeaponRefs[i];
                    if (frame.TryGet(weaponRef, out Weapon weapon))
                    {
                        // Show weapon slot if collected
                        WeaponSlots[i].SetActive(weapon.IsCollected);
                    }
                }
            }
        }
    }
}
```

## Health Bar Updates

When health is picked up, the health bar UI is updated:

```csharp
// In HealthView.OnUpdateView()
if (_isLocalPlayer && HealthBar != null)
{
    HealthBar.value = health.CurrentHealth.AsFloat / health.MaxHealth.AsFloat;
    
    // Fade damage overlay based on health
    if (DamageOverlay != null)
    {
        float targetAlpha = 1.0f - (health.CurrentHealth.AsFloat / health.MaxHealth.AsFloat);
        Color color = DamageOverlay.color;
        color.a = Mathf.Lerp(0.0f, 0.8f, targetAlpha);
        DamageOverlay.color = color;
    }
}
```

## Best Practices for FPS Pickup Implementation

1. **Union-based pickup types**: Use a union to handle different pickup types efficiently
2. **Trigger-based detection**: Use physics triggers for reliable pickup detection
3. **Cooldown mechanism**: Prevent spamming pickup triggers
4. **Conditional pickup logic**: Only apply pickups when they would have an effect
5. **Automatic weapon switching**: Switch to newly collected weapons for better UX
6. **Visual feedback**: Provide clear visual and audio cues for pickups
7. **Respawn system**: Allow pickups to reappear after a cooldown
8. **Event-based view updates**: Use events to notify the view layer about pickups
9. **Floating animation**: Create visually appealing idle animations for pickups
10. **Max health/ammo limits**: Respect maximum values when applying pickups

These practices ensure an engaging pickup system that provides clear feedback to players while maintaining deterministic behavior across all clients. The system effectively integrates with the weapons and health systems to ensure a cohesive gameplay experience.

## Pickup Placement and Level Design

Pickups are strategically placed in the level to encourage specific player behaviors:

1. **Health Pickups**:
   - Placed in areas where players might retreat after taking damage
   - Often positioned near cover or in areas away from high-traffic combat zones
   - Encourage players to move around the map when injured

2. **Weapon Pickups**:
   - More powerful weapons placed in high-risk areas
   - Encourage players to compete for control of strategic locations
   - Create focal points for combat

3. **Respawn Timing**:
   - Important pickups have longer respawn timers to make them more valuable
   - Creates rhythms in gameplay as players anticipate respawns
   - Encourages map control and timing-based strategies

All pickup placements are defined in the map data and instantiated when the level loads. This ensures consistent pickup placement across all clients.

## Balancing Considerations

The pickup system is carefully balanced to enhance gameplay:

1. **Health Restoration Amounts**:
   - Small health packs (25 HP): Common, shorter respawn times
   - Large health packs (50 HP): Rare, longer respawn times
   - Values balanced to make health a valuable resource without making players invincible

2. **Weapon Ammo Distribution**:
   - More powerful weapons receive less ammo per pickup
   - Players must make strategic decisions about when to use powerful weapons
   - Creates interesting risk/reward scenarios

3. **Pickup Distribution**:
   - Even distribution ensures no part of the map is overly advantageous
   - Ensures matches remain dynamic with action across the entire level
   - Prevents "camping" by making resources available in multiple areas

These balancing considerations create a dynamic and engaging FPS experience where pickups play a crucial role in player decision-making and strategy.
