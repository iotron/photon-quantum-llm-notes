# Weapons and Combat in Quantum Platform Shooter 2D

This document explains the implementation of the Weapons and Combat systems in the Platform Shooter 2D sample project, covering weapons, bullets, and damage handling.

## Weapon Components

The weapon system is built on these components defined in the Quantum DSL:

```qtn
// Weapon.qtn
struct Weapon
{
    Boolean IsRecharging;
    Int32 CurrentAmmo;
    FrameTimer FireRateTimer;
    FrameTimer DelayToStartRechargeTimer;
    FrameTimer RechargeRate;
    FP ChargeTime;
    asset_ref<WeaponData> WeaponData;
}

component WeaponInventory
{
    Int32 CurrentWeaponIndex;
    array<Weapon>[2] Weapons;
}

event OnWeaponShoot
{
    entity_ref Character;
}
```

## Bullet Components

The bullet system is built on these components:

```qtn
// Bullet.qtn
component BulletFields
{
    entity_ref Source;
    FPVector2 Direction;
    asset_ref<BulletData> BulletData;
}

event OnBulletDestroyed
{
    Int32 BulletRefHashCode;
    entity_ref Owner;
    nothashed FPVector2 BulletPosition;
    nothashed FPVector2 BulletDirection;
    asset_ref<BulletData> BulletData;
}
```

## Weapon System Implementation

The `WeaponSystem` handles weapon firing, recharging, and ammunition management:

```csharp
namespace Quantum
{
  using Photon.Deterministic;
  using UnityEngine.Scripting;

  [Preserve]
  public unsafe class WeaponSystem : SystemMainThreadFilter<WeaponSystem.Filter>, ISignalOnCharacterRespawn
  {
    public struct Filter
    {
      public EntityRef Entity;
      public PlayerLink* PlayerLink;
      public Status* Status;
      public WeaponInventory* WeaponInventory;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
      if (filter.Status->IsDead) return;

      UpdateWeaponRecharge(frame, ref filter);
      UpdateWeaponFire(frame, ref filter);
    }

    private void UpdateWeaponRecharge(Frame frame, ref Filter filter)
    {
      var currentWeaponIndex = filter.WeaponInventory->CurrentWeaponIndex;
      var currentWeapon = filter.WeaponInventory->Weapons.GetPointer(currentWeaponIndex);

      var weaponData = frame.FindAsset(currentWeapon->WeaponData);
      if (currentWeapon->DelayToStartRechargeTimer.IsRunning(frame) == false
          && currentWeapon->RechargeRate.IsRunning(frame) == false
          && currentWeapon->CurrentAmmo < weaponData.MaxAmmo)
      {
        currentWeapon->RechargeRate = FrameTimer.FromSeconds(frame, weaponData.RechargeTimer / (FP)weaponData.MaxAmmo);
        currentWeapon->CurrentAmmo++;

        if (currentWeapon->CurrentAmmo == weaponData.MaxAmmo)
        {
          currentWeapon->IsRecharging = false;
        }
      }
    }

    private void UpdateWeaponFire(Frame frame, ref Filter filter)
    {
      var currentWeaponIndex = filter.WeaponInventory->CurrentWeaponIndex;
      var currentWeapon = filter.WeaponInventory->Weapons.GetPointer(currentWeaponIndex);
      var weaponData = frame.FindAsset(currentWeapon->WeaponData);

      QuantumDemoInputPlatformer2D input = *frame.GetPlayerInput(filter.PlayerLink->Player);
      if (input.Fire)
      {
        // Checks if the weapon is ready to fire
        if (currentWeapon->FireRateTimer.IsRunning(frame) == false 
            && !currentWeapon->IsRecharging 
            && currentWeapon->CurrentAmmo > 0)
        {
          SpawnBullet(frame, filter.Entity, currentWeapon, input.AimDirection);
          currentWeapon->FireRateTimer = FrameTimer.FromSeconds(frame, FP._1 / weaponData.FireRate);
          currentWeapon->ChargeTime = FP._0;
        }
      }
    }

    private static void SpawnBullet(Frame frame, EntityRef character, Weapon* weapon, FPVector2 direction)
    {
      // Reduce ammo count
      weapon->CurrentAmmo -= 1;
      if (weapon->CurrentAmmo == 0)
      {
        weapon->IsRecharging = true;
      }

      var weaponData = frame.FindAsset(weapon->WeaponData);
      var bulletData = frame.FindAsset(weaponData.BulletData);
      var prototypeAsset = frame.FindAsset(bulletData.BulletPrototype);

      // Create the bullet entity
      var bullet = frame.Create(prototypeAsset);
      var bulletFields = frame.Unsafe.GetPointer<BulletFields>(bullet);
      var bulletTransform = frame.Unsafe.GetPointer<Transform2D>(bullet);
      
      // Configure bullet properties
      var characterTransform = frame.Unsafe.GetPointer<Transform2D>(character);
      var fireSpotWorldOffset = WeaponHelper.GetFireSpotWorldOffset(frame.FindAsset(weapon->WeaponData), direction);
      bulletTransform->Position = characterTransform->Position + fireSpotWorldOffset;
      bulletFields->Direction = direction * weaponData.ShootForce;
      bulletFields->Source = character;
      bulletFields->BulletData = bulletData;

      // Restart recharge timer
      weapon->DelayToStartRechargeTimer = FrameTimer.FromSeconds(frame, weaponData.TimeToRecharge);
      
      // Trigger view event
      frame.Events.OnWeaponShoot(character);
    }

    public void OnCharacterRespawn(Frame frame, EntityRef character)
    {
      // Reset weapon state on respawn
      WeaponInventory* weaponInventory = frame.Unsafe.GetPointer<WeaponInventory>(character);

      for (var i = 0; i < weaponInventory->Weapons.Length; i++)
      {
        var weapon = weaponInventory->Weapons.GetPointer(i);
        var weaponData = frame.FindAsset(weapon->WeaponData);

        weapon->IsRecharging = false;
        weapon->CurrentAmmo = weaponData.MaxAmmo;
        weapon->FireRateTimer = FrameTimer.FromFrames(frame, 0);
        weapon->DelayToStartRechargeTimer = FrameTimer.FromFrames(frame, 0);
        weapon->RechargeRate = FrameTimer.FromFrames(frame, 0);
      }
    }
  }
}
```

Key aspects:
1. Filter selects entities with required components (PlayerLink, Status, WeaponInventory)
2. Handles weapon firing based on player input
3. Manages ammo consumption and recharging
4. Spawns bullet entities when firing
5. Resets weapons on character respawn

## Bullet System Implementation

The `BulletSystem` handles bullet movement, collision detection, and impact effects:

```csharp
namespace Quantum
{
  using Photon.Deterministic;
  using UnityEngine.Scripting;

  [Preserve]
  public unsafe class BulletSystem : SystemMainThreadFilter<BulletSystem.Filter>
  {
    public struct Filter
    {
      public EntityRef Entity;
      public Transform2D* Transform;
      public BulletFields* BulletFields;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
      // Check for collisions first
      if (CheckRaycastCollision(frame, ref filter))
      {
        return;
      }
      
      // Destroy bullet if source entity no longer exists
      if (frame.Exists(filter.BulletFields->Source) == false)
      {
        frame.Destroy(filter.Entity);
        return;
      }
      
      // Update bullet position
      UpdateBulletPosition(frame, ref filter);
      
      // Check if bullet has traveled too far
      CheckBulletDistance(frame, ref filter);
    }

    private void CheckBulletDistance(Frame frame, ref Filter filter)
    {
      var bulletFields = filter.BulletFields;
      var sourcePosition = frame.Unsafe.GetPointer<Transform2D>(bulletFields->Source)->Position;
      var distanceSquared = FPVector2.DistanceSquared(filter.Transform->Position, sourcePosition);
      
      var bulletData = frame.FindAsset(bulletFields->BulletData);
      bool bulletIsTooFar = FPMath.Sqrt(distanceSquared) > bulletData.Range;

      if (bulletIsTooFar)
      {
        // Apply bullet action when range is exceeded
        bulletData.BulletAction(frame, filter.Entity, EntityRef.None);
      }
    }

    private void UpdateBulletPosition(Frame frame, ref Filter filter)
    {
      // Move the bullet based on its direction and delta time
      filter.Transform->Position += filter.BulletFields->Direction * frame.DeltaTime;
    }

    private bool CheckRaycastCollision(Frame frame, ref Filter filter)
    {
      var bulletFields = filter.BulletFields;
      var bulletTransform = filter.Transform;
      
      if (bulletFields->Direction.Magnitude <= FP._0)
      {
        return false;
      }

      // Calculate future position for raycast
      var futurePosition = bulletTransform->Position + bulletFields->Direction * frame.DeltaTime;
      var bulletData = frame.FindAsset(bulletFields->BulletData);

      var futurePositionDistance = FPVector2.DistanceSquared(bulletTransform->Position, futurePosition);
      if (futurePositionDistance <= bulletData.CollisionCheckThreshold)
      {
        return false;
      }

      // Perform raycast to check for collisions
      Physics2D.HitCollection hits = frame.Physics2D.LinecastAll(
        bulletTransform->Position, 
        futurePosition, 
        -1, 
        QueryOptions.HitAll | QueryOptions.ComputeDetailedInfo);
        
      for (int i = 0; i < hits.Count; i++)
      {
        var entity = hits[i].Entity;
        // Check for character hit (avoiding source entity and dead characters)
        if (entity != EntityRef.None && frame.Has<Status>(entity) && entity != bulletFields->Source)
        {
          if (frame.Get<Status>(entity).IsDead)
          {
            continue;
          }

          // Update bullet position to hit point
          bulletTransform->Position = hits[i].Point;

          // Apply bullet action on character hit
          bulletData.BulletAction(frame, filter.Entity, entity);
          return true;
        }

        // Check for environment hit
        if (entity == EntityRef.None)
        {
          bulletTransform->Position = hits[i].Point;

          // Apply bullet action on environment hit
          bulletData.BulletAction(frame, filter.Entity, EntityRef.None);
          return true;
        }
      }
      return false;
    }
  }
}
```

Key aspects:
1. Filter selects entities with required components (Transform2D, BulletFields)
2. Updates bullet position based on direction and delta time
3. Uses raycast to detect collisions with characters and environment
4. Checks if bullet has exceeded its maximum range
5. Applies bullet actions through polymorphic behavior

## Bullet Data and Actions

The game uses a polymorphic approach to bullet behavior through the `BulletData` base class:

```csharp
// BulletData.cs (base class)
public abstract class BulletData : AssetObject
{
    public FP Range = 15;
    public FP Damage = 10;
    public FP CollisionCheckThreshold = FP._0_01;
    public AssetRefEntityPrototype BulletPrototype;
    
    // Polymorphic action method
    public abstract void BulletAction(Frame frame, EntityRef bullet, EntityRef targetCharacter);
}

// BulletDataCommon.cs (implementation)
public class BulletDataCommon : BulletData
{
    public override unsafe void BulletAction(Frame frame, EntityRef bullet, EntityRef targetCharacter)
    {
        if (targetCharacter != EntityRef.None)
        {
            // Apply damage to character
            frame.Signals.OnCharacterHit(bullet, targetCharacter, Damage);
        }

        // Trigger view event
        var fields = frame.Get<BulletFields>(bullet);
        var position = frame.Get<Transform2D>(bullet).Position;
        frame.Events.OnBulletDestroyed(
            bullet.GetHashCode(), 
            fields.Source, 
            position, 
            fields.Direction, 
            fields.BulletData);
            
        // Destroy the bullet
        frame.Destroy(bullet);
    }
}

// Other implementations can provide different behaviors
public class BulletDataExplosive : BulletData 
{
    public FP ExplosionRadius = 3;
    
    public override unsafe void BulletAction(Frame frame, EntityRef bullet, EntityRef targetCharacter)
    {
        // Create explosion effect
        // Apply area damage
        // ...
    }
}
```

## Weapon Inventory System

The `WeaponInventorySystem` handles weapon switching:

```csharp
// Simplified WeaponInventorySystem
public unsafe class WeaponInventorySystem : SystemMainThreadFilter<WeaponInventorySystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public PlayerLink* PlayerLink;
        public Status* Status;
        public WeaponInventory* WeaponInventory;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        if (filter.Status->IsDead) return;

        QuantumDemoInputPlatformer2D input = *frame.GetPlayerInput(filter.PlayerLink->Player);
        if (input.Use)
        {
            // Toggle between weapons (0 and 1)
            filter.WeaponInventory->CurrentWeaponIndex = 
                filter.WeaponInventory->CurrentWeaponIndex == 0 ? 1 : 0;
                
            // Trigger view event
            frame.Events.OnWeaponChanged(filter.Entity, filter.WeaponInventory->CurrentWeaponIndex);
        }
    }
}
```

## Damage System

Damage is handled through signals to promote loose coupling between systems:

```csharp
// In a signal implementation class
public void OnCharacterHit(Frame frame, EntityRef bullet, EntityRef character, FP damage)
{
    // Apply damage to the character
    if (frame.Unsafe.TryGetPointer<Status>(character, out var status))
    {
        // Skip for invincible or dead characters
        if (status->IsDead || status->InvincibleTimer.IsRunning(frame))
        {
            return;
        }

        // Get bullet source
        var bulletFields = frame.Get<BulletFields>(bullet);
        
        // Apply damage
        status->CurrentHealth -= damage;
        status->RegenTimer.Restart(frame, status->StatusData.Asset.RegenStartDelay);
        
        // Check for death
        if (status->CurrentHealth <= FP._0)
        {
            status->IsDead = true;
            status->CurrentHealth = FP._0;
            status->RespawnTimer.Restart(frame, status->StatusData.Asset.RespawnTime);
            
            // Trigger death event
            frame.Events.OnCharacterDied(character, bulletFields.Source);
        }
        else
        {
            // Trigger damage event
            frame.Events.OnCharacterDamaged(character, damage);
        }
    }
}
```

## Weapon View Integration

The Unity-side view code uses event subscriptions to visualize weapon actions:

```csharp
// Simplified WeaponView implementation
public class WeaponView : QuantumEntityViewComponent
{
    // Visual elements
    public ParticleSystem MuzzleFlash;
    public Transform WeaponRoot;
    
    public override void OnActivate(Frame frame)
    {
        // Subscribe to weapon events
        QuantumEvent.Subscribe<EventOnWeaponShoot>(this, OnWeaponShoot);
        QuantumEvent.Subscribe<EventOnWeaponChanged>(this, OnWeaponChanged);
    }
    
    private void OnWeaponShoot(EventOnWeaponShoot e)
    {
        if (e.Character == EntityRef)
        {
            // Play muzzle flash effect
            MuzzleFlash.Play();
            
            // Play sound effect
            SfxController.Instance.PlaySound(SoundType.Shoot);
        }
    }
    
    private void OnWeaponChanged(EventOnWeaponChanged e)
    {
        if (e.Character == EntityRef)
        {
            // Update weapon model
            UpdateWeaponVisuals(e.WeaponIndex);
        }
    }
}
```

## Bullet View Integration

Bullet visualization is handled by dedicated view components:

```csharp
// Simplified BulletFxController
public class BulletFxController : QuantumCallbacks
{
    public GameObject BulletHitPrefab;
    
    public override void OnEnable()
    {
        QuantumEvent.Subscribe<EventOnBulletDestroyed>(this, OnBulletDestroyed);
    }
    
    private void OnBulletDestroyed(EventOnBulletDestroyed e)
    {
        // Create hit effect at bullet position
        var hitEffect = Instantiate(BulletHitPrefab, e.BulletPosition.ToUnityVector3(), Quaternion.identity);
        
        // Set up effect based on bullet type
        ConfigureHitEffect(hitEffect, e.BulletData);
        
        // Play sound effect
        SfxController.Instance.PlaySound(SoundType.BulletHit);
    }
}
```

## Best Practices for Weapons and Combat Implementation

1. **Use polymorphic bullet behavior**: The `BulletData` base class with specific implementations allows for diverse weapon types
2. **Decouple systems with signals**: Damage handling uses signals to avoid tight coupling between bullet and character systems
3. **Use raycasting for collision detection**: Deterministic physics raycasts ensure accurate hit detection
4. **Separate visual effects from simulation**: Events notify the view layer about weapon actions without affecting determinism
5. **Use asset references for configuration**: Weapon and bullet properties are defined in assets for easy tuning
6. **Leverage entity prototypes**: Bullets are spawned from entity prototypes to ensure consistency
7. **Handle resource management**: Ammo and recharge timers use deterministic time tracking with FrameTimer
8. **Use events for significant actions**: Events like OnWeaponShoot and OnBulletDestroyed communicate to the view layer

These practices ensure deterministic combat behavior across all clients while providing visual feedback appropriate to each player's view.
