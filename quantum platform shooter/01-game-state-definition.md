# Game State Definition in Quantum Platform Shooter 2D

This document explains how the game state is defined in the Platform Shooter 2D sample project using Quantum's Domain-Specific Language (DSL).

## Core Game State Components

The Platform Shooter 2D game uses several `.qtn` files to define its game state. These files describe the components, events, and data structures that make up the core gameplay elements.

### Character State

The character state is defined in `Character.qtn`:

```qtn
component PlayerLink
{
    player_ref Player;
}

component Status
{
    asset_ref<StatusData> StatusData;
    FP CurrentHealth;
    Boolean IsDead;
    FrameTimer RespawnTimer;
    FrameTimer RegenTimer;
    FrameTimer InvincibleTimer;
    FrameTimer DisconnectedTimer;
}

event OnPlayerSelectedCharacter
{
    local player_ref PlayerRef;
}

component MovementData
{
    Boolean IsFacingRight;
}
```

Key components:
- **PlayerLink**: Connects an entity to a player index
- **Status**: Contains health and timers for game mechanics
- **MovementData**: Tracks movement state (facing direction)

### Weapon System

The weapon system is defined in `Weapon.qtn`:

```qtn
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

Key elements:
- **Weapon struct**: Contains weapon state including ammo and timing
- **WeaponInventory**: Component that holds an array of weapons
- **OnWeaponShoot**: Event triggered when a weapon is fired

### Bullet System

The bullet system is defined in `Bullet.qtn`:

```qtn
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

Key elements:
- **BulletFields**: Component containing bullet properties
- **OnBulletDestroyed**: Event triggered when a bullet is destroyed

### Skill System

The skill system is defined in `Skill.qtn`:

```qtn
component SkillFields
{
    FP TimeToActivate;
    entity_ref Source;
    asset_ref<SkillData> SkillData;
}

component SkillInventory
{
    FrameTimer CastRateTimer;
    asset_ref<SkillInventoryData> SkillInventoryData;
}

event OnSkillCasted
{
    entity_ref Skill;
}

event OnSkillActivated
{
    FPVector2 SkillPosition;
}

event OnSkillHitTarget
{
    FPVector2 SkillPosition;
    Int64 SkillDataId;
    entity_ref Target;
}
```

Key elements:
- **SkillFields**: Component containing skill properties
- **SkillInventory**: Holds skills and their cooldowns
- **Events**: Several events for different skill phases (cast, activation, hit)

## Asset References

The game state makes extensive use of `asset_ref<T>` to reference configuration data:

```qtn
asset_ref<StatusData> StatusData;
asset_ref<BulletData> BulletData;
asset_ref<WeaponData> WeaponData;
asset_ref<SkillData> SkillData;
```

These references point to asset classes defined in C# that contain configuration data, such as:

```csharp
// Example from WeaponData.cs
public class WeaponData : AssetObject {
    public string Name;
    public FP FireRate;
    public Int32 MaxAmmo;
    public FP RechargeRate;
    public FP DelayToStartRecharge;
    public AssetRefEntityPrototype BulletPrototype;
    // ...
}
```

## Entity References

The game state uses `entity_ref` to create relationships between entities:

```qtn
entity_ref Source;  // In BulletFields, references the entity that fired the bullet
entity_ref Owner;   // In OnBulletDestroyed, references the bullet's owner
entity_ref Target;  // In OnSkillHitTarget, references the entity hit by a skill
```

## Timers

The Platform Shooter 2D game makes extensive use of `FrameTimer` for time-based mechanics:

```qtn
FrameTimer RespawnTimer;
FrameTimer FireRateTimer;
FrameTimer CastRateTimer;
```

A `FrameTimer` is a Quantum-provided struct that facilitates deterministic timing based on simulation frames rather than real-time seconds.

## Events for View Communication

Events defined in `.qtn` files are used to communicate from simulation to view:

```qtn
event OnWeaponShoot { /* ... */ }
event OnBulletDestroyed { /* ... */ }
event OnSkillCasted { /* ... */ }
```

These events are triggered in the simulation code and can be subscribed to in Unity view code to trigger visual effects, animations, or sounds.

## Best Practices for DSL in Quantum

Based on the Platform Shooter 2D implementation:

1. **Keep components focused**: Each component should have a single responsibility
2. **Use appropriate types**: Use Quantum fixed-point types (`FP`) for all floating-point values to ensure determinism
3. **Leverage FrameTimers**: Use `FrameTimer` for any time-based mechanics
4. **Use asset references**: Store configuration in assets and reference them with `asset_ref<T>`
5. **Define clear events**: Use events to communicate between simulation and view
6. **Use appropriate event modifiers**: Use `nothashed` for position fields in events to prevent minor differences causing duplicate events
7. **Use local/remote modifiers**: Events like `OnPlayerSelectedCharacter` use the `local` modifier to ensure they're only processed on the local player's machine

These practices ensure deterministic behavior across all clients in a networked game.
