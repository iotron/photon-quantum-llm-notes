---
trash_metadata:
  original_path: Components/Components-Overview.md
  deleted_at: 2025-04-29T00:01:50.278Z
---

# Components Architecture in Photon Quantum

## Overview

Components in Quantum are data containers attached to entities. They define the data structure of game objects but do not contain any logic. All logic is implemented in Systems that operate on components.

## Defining Components

Components are defined using Quantum Type Notation (QTN) files. These plain text files use a declarative syntax that is then compiled into C# code.

### Basic Component Definition

Here's a basic component definition from the Platform Shooter 2D project:

```
component PlayerLink
{
    player_ref Player;
}
```

This creates a simple component that links an entity to a player reference.

### Component with Multiple Fields

Components can have multiple fields with different types:

```
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
```

### QTN Data Types

Quantum supports several specialized data types:

- `FP`: Fixed-point numbers for deterministic math
- `FPVector2`, `FPVector3`: Fixed-point vector types
- `Boolean`: Boolean values
- `Int32`: 32-bit integers
- `Byte`: 8-bit unsigned integers
- `String`: String data (use sparingly as it's not fully deterministic)
- `entity_ref`: Reference to another entity
- `asset_ref<T>`: Reference to an asset
- `player_ref`: Reference to a player
- `FrameTimer`: Timer for tracking elapsed time

### Arrays

Components can contain arrays:

```
component WeaponInventory
{
    Int32 CurrentWeaponIndex;
    array<Weapon>[2] Weapons;
}
```

## Accessing Components in Code

### SystemMainThreadFilter

The most common way to process components is through systems with filters:

```csharp
public unsafe class StatusSystem : SystemMainThreadFilter<StatusSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform2D* Transform;
        public Status* Status;
    }
    
    public override void Update(Frame frame, ref Filter filter)
    {
        // Work with filter.Transform and filter.Status
    }
}
```

### Direct Access

Components can also be accessed directly via the Frame:

```csharp
// Get a component (returns a copy)
var status = frame.Get<Status>(entityRef);

// Get a pointer to modify the component
var statusPtr = frame.Unsafe.GetPointer<Status>(entityRef);
statusPtr->CurrentHealth = FP._10;
```

## Creating Entities with Components

Entities with components are typically created from EntityPrototype assets:

```csharp
var characterEntity = frame.Create(prototypeAsset);
```

They can also be created manually and have components added:

```csharp
var entity = frame.Create();
frame.Add<Transform2D>(entity);
frame.Add<Status>(entity);

// Initialize component values
var status = frame.Unsafe.GetPointer<Status>(entity);
status->CurrentHealth = FP._100;
status->IsDead = false;
```

## Component Best Practices

1. **Keep components small and focused**: Each component should represent a distinct aspect of an entity
2. **Use appropriate data types**: Always use `FP` instead of `float`, etc.
3. **Minimize strings**: Avoid string data when possible as it's not deterministic
4. **Use asset references**: For complex data, use asset references instead of embedding data directly
5. **Consider data locality**: Group frequently accessed data together

## Struct vs. Component

In addition to components, QTN allows defining structs that can be included in components:

```
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
```

Use structs when:
- The data is a logical group that belongs together
- You need to reuse the same data structure in multiple components
- You need an array of structured data within a component

## Examples from Platform Shooter 2D

### Movement Data

```
component MovementData
{
    Boolean IsFacingRight;
}
```

### Weapon System

```
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
```

### Bullet Fields

```
component BulletFields
{
    entity_ref Source;
    FPVector2 Direction;
    asset_ref<BulletData> BulletData;
}
```

## Next Steps

Learn more about:
- [[../Systems/Systems-Overview|Systems Implementation]]
- [[../Core-Concepts/02-AssetReferences|Asset References]]
- [[BulletComponent|Bullet Component Details]]
- [[WeaponComponent|Weapon Component Details]]