# Weapons System in Quantum Simple FPS

This document explains the implementation of the Weapons System in the Quantum Simple FPS sample project, covering weapon management, firing mechanics, and damage handling.

## Weapon Components

The weapons system is built on these components defined in the Quantum DSL:

```qtn
component Weapons
{
    array<asset_ref<EntityPrototype>>[4] WeaponPrototypes;

    LayerMask HitMask;
    FP        WeaponSwitchTime;

    [ExcludeFromPrototype]
    byte      CurrentWeaponId;
    [ExcludeFromPrototype]
    byte      PendingWeaponId;
    [ExcludeFromPrototype]
    FP        FireCooldown;
    [ExcludeFromPrototype]
    FP        ReloadCooldown;
    [ExcludeFromPrototype]
    FP        SwitchCooldown;

    [ExcludeFromPrototype]
    array<EntityRef>[4] WeaponRefs;
}

component Weapon
{
    bool      IsAutomatic;
    int       ClipAmmo;
    int       MaxClipAmmo;
    int       RemainingAmmo;
    int       MaxRemainingAmmo;
    FP        ReloadTime;

    FP        Damage;
    int       FireRate;
    int       ProjectilesPerShot;
    FP        Dispersion;
    FP        MaxHitDistance;

    [ExcludeFromPrototype]
    bool      IsCollected;
    [ExcludeFromPrototype]
    bool      IsReloading;
}
```

Additionally, these signals and events provide communication between simulation and view:

```qtn
signal SwitchWeapon(EntityRef playerEntity, byte weaponId);

event WeaponFired
{
    byte WeaponId;
    EntityRef PlayerEntity;
    bool JustPressed;
    bool IsEmpty;
}

event FireProjectile
{
    byte WeaponId;
    EntityRef PlayerEntity;
    FPVector3 TargetPosition;
    FPVector3 HitNormal;
}

event WeaponSwitchStarted
{
    byte WeaponId;
    EntityRef PlayerEntity;
}

event WeaponReloadStarted
{
    byte WeaponId;
    EntityRef PlayerEntity;
}

synced event DamageInflicted
{
    local player_ref Player;
    bool IsFatal;
    bool IsCritical;
}
```

## Weapons Component Extensions

The `Weapons` component has extensions to simplify access to key state:

```csharp
namespace Quantum
{
    public unsafe partial struct Weapons
    {
        public bool      IsBusy        => IsFiring || IsReloading || IsSwitching;
        public bool      IsFiring      => FireCooldown > 0;
        public bool      IsReloading   => ReloadCooldown > 0;
        public bool      IsSwitching   => SwitchCooldown > 0;
        public EntityRef CurrentWeapon => WeaponRefs[CurrentWeaponId];
    }
}
```

The `Weapon` component also has utility methods:

```csharp
namespace Quantum
{
    public partial struct Weapon
    {
        public bool HasAmmo => ClipAmmo > 0 || RemainingAmmo > 0;

        public bool CanReload()
        {
            if (IsCollected == false)
                return false;

            if (ClipAmmo >= MaxClipAmmo)
                return false;

            return RemainingAmmo > 0;
        }

        public void Reload()
        {
            int reloadAmmo = MaxClipAmmo - ClipAmmo;
            reloadAmmo = Math.Min(reloadAmmo, RemainingAmmo);

            ClipAmmo += reloadAmmo;
            RemainingAmmo -= reloadAmmo;
        }

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
    }
}
```

## Weapons System Implementation

The `WeaponsSystem` handles weapon switching, reloading, and firing:

```csharp
namespace Quantum
{
    [Preserve]
    public unsafe class WeaponsSystem : SystemMainThreadFilter<WeaponsSystem.Filter>,
        ISignalOnComponentAdded<Weapons>, ISignalOnComponentRemoved<Weapons>,
        ISignalSwitchWeapon
    {
        private const ushort _headShapeUserTag = 1;
        private const ushort _limbShapeUserTag = 2;

        public override void Update(Frame frame, ref Filter filter)
        {
            if (filter.Health->IsAlive == false)
                return;
            if (filter.Player->PlayerRef.IsValid == false)
                return;

            var input = frame.GetPlayerInput(filter.Player->PlayerRef);
            var currentWeapon = frame.Unsafe.GetPointer<Weapon>(filter.Weapons->CurrentWeapon);

            UpdateWeaponSwitch(frame, ref filter);
            UpdateReload(frame, ref filter, currentWeapon);

            filter.Weapons->FireCooldown -= frame.DeltaTime;

            if (input->Weapon >= 1)
            {
                TryStartWeaponSwitch(frame, ref filter, (byte)(input->Weapon - 1));
            }

            if (input->Fire.IsDown)
            {
                TryFire(frame, ref filter, currentWeapon, input->Fire.WasPressed);

                // Cancel after-spawn immortality when player starts shooting
                filter.Health->StopImmortality();
            }

            if (input->Reload.IsDown || currentWeapon->ClipAmmo <= 0)
            {
                TryStartReload(frame, ref filter, currentWeapon);
            }
        }

        private void TryStartWeaponSwitch(Frame frame, ref Filter filter, byte weaponId)
        {
            if (weaponId == filter.Weapons->PendingWeaponId)
                return;

            var weaponRef = filter.Weapons->WeaponRefs[weaponId];
            if (weaponRef.IsValid == false)
                return;

            var weapon = frame.Unsafe.GetPointer<Weapon>(weaponRef);
            if (weapon->IsCollected == false)
                return;

            filter.Weapons->PendingWeaponId = weaponId;
            filter.Weapons->SwitchCooldown = filter.Weapons->WeaponSwitchTime;

            // Stop reload
            filter.Weapons->ReloadCooldown = 0;

            frame.Events.WeaponSwitchStarted(weaponId, filter.Entity);
        }

        private void UpdateWeaponSwitch(Frame frame, ref Filter filter)
        {
            filter.Weapons->SwitchCooldown -= frame.DeltaTime;

            // Switch already completed
            if (filter.Weapons->PendingWeaponId == filter.Weapons->CurrentWeaponId)
                return;

            // Switching too quickly
            if (filter.Weapons->SwitchCooldown > filter.Weapons->WeaponSwitchTime * FP._0_50)
                return;

            // In the middle of the switch we already switch the current weapon
            // but player won't be able to shoot until the switch cooldown expires
            filter.Weapons->CurrentWeaponId = filter.Weapons->PendingWeaponId;
        }

        private void TryStartReload(Frame frame, ref Filter filter, Weapon* weapon)
        {
            if (filter.Weapons->IsBusy)
                return;
            if (weapon->CanReload() == false)
                return;

            filter.Weapons->ReloadCooldown = weapon->ReloadTime;

            frame.Events.WeaponReloadStarted(filter.Weapons->CurrentWeaponId, filter.Entity);
        }

        private void UpdateReload(Frame frame, ref Filter filter, Weapon* weapon)
        {
            if (filter.Weapons->IsReloading == false)
                return;

            filter.Weapons->ReloadCooldown -= frame.DeltaTime;

            if (filter.Weapons->IsReloading == false)
            {
                weapon->Reload();

                // Add small prepare time after reload
                filter.Weapons->FireCooldown = FP._0_25;
            }
        }

        private void TryFire(Frame frame, ref Filter filter, Weapon* weapon, bool justPressed)
        {
            if (filter.Weapons->IsBusy)
                return;
            if (weapon->IsCollected == false)
                return;
            if (justPressed == false && weapon->IsAutomatic == false)
                return;

            filter.Weapons->FireCooldown = (FP)60 / weapon->FireRate;

            if (weapon->ClipAmmo <= 0)
            {
                frame.Events.WeaponFired(filter.Weapons->CurrentWeaponId, filter.Entity, justPressed, true);
                return;
            }

            frame.Events.WeaponFired(filter.Weapons->CurrentWeaponId, filter.Entity, justPressed, false);

            var firePosition = filter.KCC->Data.TargetPosition + filter.Player->CameraOffset * FPVector3.Up;
            var fireRotation = FPQuaternion.LookRotation(filter.KCC->Data.LookDirection);

            DamageData damageData = default;

            for (int i = 0; i < weapon->ProjectilesPerShot; i++)
            {
                var projectileRotation = fireRotation;

                if (weapon->Dispersion > 0)
                {
                    // We use unit sphere on purpose -> non-uniform distribution (more projectiles in the center)
                    var dispersionRotation = FPQuaternion.Euler(RandomInsideUnitCircleNonUniform(frame).XYO * weapon->Dispersion);
                    projectileRotation = fireRotation * dispersionRotation;
                }

                FireProjectile(frame, ref filter, firePosition, projectileRotation * FPVector3.Forward, weapon->MaxHitDistance, weapon->Damage, ref damageData);
            }

            if (damageData.TotalDamage > 0)
            {
                frame.Events.DamageInflicted(filter.Player->PlayerRef, damageData.IsFatal, damageData.IsCritical);
            }

            weapon->ClipAmmo--;
        }

        private void FireProjectile(Frame frame, ref Filter filter, FPVector3 fromPosition, FPVector3 direction, FP maxDistance, FP damage, ref DamageData damageData)
        {
            // Use default layer mask + add lag compensation proxy layer mask based on PlayerRef
            var hitMask = filter.Weapons->HitMask;
            hitMask.BitMask |= LagCompensationUtility.GetProxyCollisionLayerMask(filter.Player->PlayerRef);

            var options = QueryOptions.HitAll | QueryOptions.ComputeDetailedInfo;
            var nullableHit = frame.Physics3D.Raycast(fromPosition, direction, maxDistance, hitMask, options);

            if (nullableHit.HasValue == false)
            {
                // No surface was hit, show projectile visual flying to dummy distant point
                var distantPoint = fromPosition + direction * maxDistance;
                frame.Events.FireProjectile(filter.Weapons->CurrentWeaponId, filter.Entity, distantPoint, FPVector3.Zero);
                return;
            }

            Hit3D hit = nullableHit.Value;

            if (frame.Unsafe.TryGetPointer(hit.Entity, out LagCompensationProxy* lagCompensationProxy))
            {
                // Lag compensation proxy was hit, switching hit entity to its origin entity
                hit.SetHitEntity(lagCompensationProxy->Target);
            }

            // When hitting dynamic colliders (players), hit normal is set to zero and hit impact won't be shown
            var hitNormal = hit.IsDynamic ? FPVector3.Zero : hit.Normal;
            frame.Events.FireProjectile(filter.Weapons->CurrentWeaponId, filter.Entity, hit.Point, hitNormal);

            if (frame.Unsafe.TryGetPointer(hit.Entity, out Health* health) == false)
                return;

            // Hitting different shapes on player body can result in different damage multipliers
            #pragma warning disable 0618
            if (hit.ShapeUserTag == _headShapeUserTag)
            {
                damage *= FP._2;
                damageData.IsCritical = true;
            }
            else if (hit.ShapeUserTag == _limbShapeUserTag)
            {
                damage *= FP._0_50;
            }
            #pragma warning restore 0618

            // At the end of gameplay the damage is doubled
            if (frame.GetSingleton<Gameplay>().IsDoubleDamageActive)
            {
                damage *= 2;
            }

            FP damageDone = health->ApplyDamage(damage);
            if (damageDone > 0)
            {
                damageData.TotalDamage += damageDone;

                if (health->IsAlive == false && frame.Unsafe.TryGetPointer(hit.Entity, out Player* victim))
                {
                    frame.Signals.PlayerKilled(filter.Player->PlayerRef, victim->PlayerRef, filter.Weapons->CurrentWeaponId, false);
                    damageData.IsFatal = true;
                }

                frame.Events.DamageReceived(hit.Entity, hit.Point, hit.Normal);
            }
        }

        void ISignalOnComponentAdded<Weapons>.OnAdded(Frame frame, EntityRef entity, Weapons* component)
        {
            // Prepare player weapons
            for (int i = 0; i < component->WeaponPrototypes.Length; i++)
            {
                var prototype = component->WeaponPrototypes[i];
                if (prototype.IsValid == false)
                    continue;

                component->WeaponRefs[i] = frame.Create(prototype);
            }

            // First weapon is automatically collected
            var currentWeapon = frame.Unsafe.GetPointer<Weapon>(component->CurrentWeapon);
            currentWeapon->IsCollected = true;
        }

        void ISignalOnComponentRemoved<Weapons>.OnRemoved(Frame frame, EntityRef entity, Weapons* component)
        {
            // Destroy player weapons
            for (int i = 0; i < component->WeaponRefs.Length; i++)
            {
                frame.Destroy(component->WeaponRefs[i]);
            }
        }

        void ISignalSwitchWeapon.SwitchWeapon(Frame frame, EntityRef playerEntity, byte weaponId)
        {
            var filter = new Filter
            {
                Entity = playerEntity,
                Weapons = frame.Unsafe.GetPointer<Weapons>(playerEntity),
            };

            TryStartWeaponSwitch(frame, ref filter, weaponId);
        }

        private static FPVector2 RandomInsideUnitCircleNonUniform(Frame frame)
        {
            FP radius = frame.RNG->Next();
            FP angle  = frame.RNG->Next() * 2 * FP.Pi;

            return new FPVector2(radius * FPMath.Cos(angle), radius * FPMath.Sin(angle));
        }

        public struct Filter
        {
            public EntityRef Entity;
            public Player*   Player;
            public Weapons*  Weapons;
            public Health*   Health;
            public KCC*      KCC;
        }

        private struct DamageData
        {
            public FP TotalDamage;
            public bool IsCritical;
            public bool IsFatal;
        }
    }
}
```

Key aspects of the weapons system:
1. Uses a filter to process only entities with Player, Weapons, Health, and KCC components
2. Handles weapon initialization when a Weapons component is added
3. Manages weapon state (switching, reloading, firing)
4. Implements raycast-based shooting with hit detection
5. Applies damage to hit entities
6. Supports shotgun-like multiple projectiles with dispersion
7. Implements different damage multipliers for different body parts
8. Integrates with lag compensation for fair hit detection

## Weapon Pickup System

Weapons can be collected through the `PickupSystem`:

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
                    
                    if (frame.Unsafe.TryGetPointer<Weapons>(overlapEntity, out var weapons))
                    {
                        if (filter.Pickup->Settings.IsWeapon)
                        {
                            var weaponPickup = filter.Pickup->Settings.Weapon;
                            var weaponRef = weapons->WeaponRefs[weaponPickup.WeaponID];
                            
                            if (frame.Unsafe.TryGetPointer<Weapon>(weaponRef, out var weapon))
                            {
                                if (weapon->CollectOrRefill(weaponPickup.RefillAmmo))
                                {
                                    // If player doesn't have this weapon selected, switch to it
                                    if (weapons->CurrentWeaponId != weaponPickup.WeaponID)
                                    {
                                        frame.Signals.SwitchWeapon(overlapEntity, weaponPickup.WeaponID);
                                    }
                                    
                                    // Apply pickup cooldown
                                    filter.Pickup->Cooldown = filter.Pickup->PickupCooldown;
                                    
                                    // Trigger pickup event
                                    frame.Events.WeaponPickedUp(filter.Entity, overlapEntity);
                                }
                            }
                        }
                        else if (filter.Pickup->Settings.IsHealth)
                        {
                            var healthPickup = filter.Pickup->Settings.Health;
                            
                            if (frame.Unsafe.TryGetPointer<Health>(overlapEntity, out var health))
                            {
                                if (health->AddHealth(healthPickup.Heal))
                                {
                                    // Apply pickup cooldown
                                    filter.Pickup->Cooldown = filter.Pickup->PickupCooldown;
                                    
                                    // Trigger pickup event
                                    frame.Events.HealthPickedUp(filter.Entity, overlapEntity);
                                }
                            }
                        }
                    }
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

## Weapon View Integration

The Unity-side view code uses event subscriptions to visualize weapon actions:

```csharp
namespace QuantumDemo
{
    public class WeaponView : QuantumMonoBehaviour
    {
        // References
        public WeaponType WeaponType;
        public Transform WeaponModel;
        public ParticleSystem MuzzleFlash;
        public TrailRenderer BulletTrail;
        public AudioSource FireSound;
        public AudioSource EmptySound;
        public AudioSource ReloadSound;
        
        // Internal state
        private bool _isLocal;
        private EntityRef _playerEntity;
        private CharacterView _characterView;
        
        private void OnEnable()
        {
            // Subscribe to weapon events
            QuantumEvent.Subscribe<EventWeaponFired>(this, OnWeaponFired);
            QuantumEvent.Subscribe<EventFireProjectile>(this, OnFireProjectile);
            QuantumEvent.Subscribe<EventWeaponReloadStarted>(this, OnWeaponReloadStarted);
        }
        
        private void OnDisable()
        {
            // Unsubscribe from weapon events
            QuantumEvent.Unsubscribe<EventWeaponFired>(this, OnWeaponFired);
            QuantumEvent.Unsubscribe<EventFireProjectile>(this, OnFireProjectile);
            QuantumEvent.Unsubscribe<EventWeaponReloadStarted>(this, OnWeaponReloadStarted);
        }
        
        public void Initialize(EntityRef playerEntity, CharacterView characterView, bool isLocal)
        {
            _playerEntity = playerEntity;
            _characterView = characterView;
            _isLocal = isLocal;
        }
        
        private void OnWeaponFired(EventWeaponFired e)
        {
            if (e.PlayerEntity != _playerEntity || e.WeaponId != (byte)WeaponType)
                return;
                
            if (e.IsEmpty)
            {
                // Play empty sound
                EmptySound.Play();
            }
            else
            {
                // Play fire sound
                FireSound.Play();
                
                // Play muzzle flash effect
                MuzzleFlash.Play();
            }
        }
        
        private void OnFireProjectile(EventFireProjectile e)
        {
            if (e.PlayerEntity != _playerEntity || e.WeaponId != (byte)WeaponType)
                return;
                
            // Show bullet trail
            var muzzlePosition = MuzzleFlash.transform.position;
            var targetPosition = e.TargetPosition.ToUnityVector3();
            
            var trail = Instantiate(BulletTrail, muzzlePosition, Quaternion.identity);
            
            // Set trail positions
            trail.AddPosition(muzzlePosition);
            trail.transform.position = targetPosition;
            
            // Show impact effect if hit normal is not zero (environment hit)
            if (e.HitNormal != FPVector3.Zero)
            {
                // Create impact effect at hit point
                // using hit normal for rotation
                var rotation = Quaternion.FromToRotation(Vector3.up, e.HitNormal.ToUnityVector3());
                Instantiate(ImpactEffectPrefab, targetPosition, rotation);
            }
        }
        
        private void OnWeaponReloadStarted(EventWeaponReloadStarted e)
        {
            if (e.PlayerEntity != _playerEntity || e.WeaponId != (byte)WeaponType)
                return;
                
            // Play reload sound
            ReloadSound.Play();
        }
    }
}
```

## Weapon Switching UI

The weapon switching is visualized using a UI component:

```csharp
namespace QuantumDemo
{
    public class WeaponSwitchUI : QuantumMonoBehaviour
    {
        public GameObject[] WeaponSlots;
        public Text AmmoText;
        
        private EntityRef _playerEntity;
        
        public void Initialize(EntityRef playerEntity)
        {
            _playerEntity = playerEntity;
            
            // Subscribe to weapon switch events
            QuantumEvent.Subscribe<EventWeaponSwitchStarted>(this, OnWeaponSwitchStarted);
        }
        
        public void OnDestroy()
        {
            QuantumEvent.Unsubscribe<EventWeaponSwitchStarted>(this, OnWeaponSwitchStarted);
        }
        
        private void OnWeaponSwitchStarted(EventWeaponSwitchStarted e)
        {
            if (e.PlayerEntity != _playerEntity)
                return;
                
            // Update UI to show the selected weapon
            for (int i = 0; i < WeaponSlots.Length; i++)
            {
                WeaponSlots[i].SetActive(i == e.WeaponId);
            }
        }
        
        public void Update()
        {
            if (!QuantumRunner.Default.Game.TryGetFrameLocal(out var frame))
                return;
                
            if (!frame.TryGet(_playerEntity, out Weapons weapons))
                return;
                
            // Get current weapon
            var currentWeaponRef = weapons.WeaponRefs[weapons.CurrentWeaponId];
            if (!frame.TryGet(currentWeaponRef, out Weapon currentWeapon))
                return;
                
            // Update ammo text
            AmmoText.text = $"{currentWeapon.ClipAmmo} / {currentWeapon.RemainingAmmo}";
        }
    }
}
```

## Best Practices for FPS Weapon Implementation

1. **Weapon state management**: Track cooldowns for firing, reloading, and switching
2. **Raycast-based shooting**: Use raycasts with proper layer masks for hit detection
3. **Lag compensation integration**: Add proxy layer masks for fair hit detection
4. **Damage multipliers for body parts**: Apply different damage based on hit location
5. **Weapon switching logic**: Allow switching only to collected weapons
6. **Event-based feedback**: Use events to communicate with the view layer
7. **Ammo management**: Track clip ammo and reserve ammo separately
8. **Weapon collection system**: Allow players to pick up weapons and ammo
9. **Support for different weapon types**: Automatic/semi-automatic fire modes, dispersion, fire rate
10. **Visual effects**: Muzzle flash, bullet trails, impact effects

These practices ensure consistent weapon behavior across all clients while providing appropriate visual feedback to players. The systems are designed to be deterministic, ensuring that shots hit the same targets for all players regardless of network conditions.
