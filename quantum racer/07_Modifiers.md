# Modifiers System Implementation

Modifiers in Quantum Racer 2.5D are special effects that can be applied to vehicles when they enter trigger zones on the track. Each modifier alters the vehicle's behavior in unique ways.

## Base RacerModifier Class

All modifiers inherit from the abstract `RacerModifier` class:

```csharp
public abstract class RacerModifier : AssetObject
{
    public AssetRef<RacerModifier>[] Children;
    private RacerModifier[] _children;

#if QUANTUM_UNITY
    public UnityEngine.AudioClip ModifierSFX;
#endif
    
    public void UpdateRacer(Frame f, ref RacerSystem.Filter filter)
    {
        InnerUpdate(f, ref filter);
        if (_children != null)
        {
            foreach (var child in _children)
            {
                child.UpdateRacer(f, ref filter);
            }
        }
    }

    public override void Loaded(IResourceManager resourceManager, Native.Allocator allocator)
    {
        if (Children != null && Children.Length > 0)
        {
            _children = new RacerModifier[Children.Length];
            for (int i = 0; i < Children.Length; i++)
            {
                _children[i] = resourceManager.GetAsset(Children[i].Id) as RacerModifier;
            }
        }
    }

    protected abstract void InnerUpdate(Frame f, ref RacerSystem.Filter filter);
}
```

The abstract design allows for:
- Composition of modifiers through the Children array
- Audio SFX for Unity rendering
- Hooks into the core update loop with `InnerUpdate`

## ModifierValues

The `Modifier` struct is used to store active modifier effects:

```csharp
struct Modifier {
    FP AccelMultiplier;
    FP FrictionMultiplier;
    FP MaxSpeedMultiplier;
}
```

This struct has a custom `Reset()` extension method:

```csharp
public static void Reset(ref this Modifier modifier)
{
    modifier.AccelMultiplier = FP._1;
    modifier.FrictionMultiplier = FP._1;
    modifier.MaxSpeedMultiplier = FP._1;
}
```

## Specific Modifier Types

### BoosterModifier

Increases acceleration and maximum speed:

```csharp
[Serializable]
public unsafe class BoosterModifier : RacerModifier
{
    public FP AccelMultiplier = 2;
    public FP MaxSpeedMultiplier = 2;

    protected override void InnerUpdate(Frame f, ref RacerSystem.Filter filter)
    {
        filter.Vehicle->ModifierValues.AccelMultiplier = AccelMultiplier;
        filter.Vehicle->ModifierValues.MaxSpeedMultiplier = MaxSpeedMultiplier;
    }
}
```

### FrictionModifier

Alters the vehicle's friction coefficient:

```csharp
[Serializable]
public unsafe class FrictionModifier : RacerModifier
{
    public FP FrictionMultiplier = 2;

    protected override void InnerUpdate(Frame f, ref RacerSystem.Filter filter)
    {
        filter.Vehicle->ModifierValues.FrictionMultiplier = FrictionMultiplier;
    }
}
```

### JumpPadModifier

Launches the vehicle into the air:

```csharp
[Serializable]
public unsafe class JumpPadModifier : RacerModifier
{
    public FP JumpImpulse = 0;

    protected override void InnerUpdate(Frame f, ref RacerSystem.Filter filter)
    {
        filter.Vehicle->VerticalSpeed = JumpImpulse;
        f.Events.Jump(filter.Entity);
    }
}
```

### HealthModifier

Restores vehicle energy:

```csharp
[Serializable]
public unsafe class HealthModifier : RacerModifier
{
    public FP HealthRestored = 1;

    protected override void InnerUpdate(Frame f, ref RacerSystem.Filter filter)
    {
        var config = f.FindAsset(filter.Vehicle->Config);
        filter.Vehicle->Energy = FPMath.Min(filter.Vehicle->Energy + HealthRestored, config.InitialEnergy);
    }
}
```

### ForceFieldModifier

Applies a directional force to the vehicle:

```csharp
[Serializable]
public unsafe class ForceFieldModifier : RacerModifier
{
    public FPVector2 ForceDirection = FPVector2.Up;
    public FP ForceMagnitude = 20;

    protected override void InnerUpdate(Frame f, ref RacerSystem.Filter filter)
    {
        filter.Body->AddForce(ForceDirection.Normalized * ForceMagnitude * filter.Body->Mass);
    }
}
```

## Modifier Application

Modifiers are applied to vehicles when they enter trigger areas in the game world. This happens in the `RacerSystem.OnTriggerEnter2D` method:

```csharp
public void OnTriggerEnter2D(Frame f, TriggerInfo2D info)
{
    if (info.IsStatic && f.Unsafe.TryGetPointer(info.Entity, out Racer* racer))
    {
        if (racer->Finished) return;
        var modifier = f.FindAsset<RacerModifier>(info.StaticData.Asset);
        if (modifier != null)
        {
            racer->Modifier = modifier.Guid;
        }
        else
        {
            // death
            Death(f, info.Entity, racer);
        }
    }
}
```

And removed when they exit:

```csharp
public void OnTriggerExit2D(Frame f, ExitInfo2D info)
{
    if (info.IsStatic && f.Unsafe.TryGetPointer(info.Entity, out Racer* racer))
    {
        racer->Modifier = default;
    }
}
```

## Available Modifier Assets

The following modifier assets are defined in the project:
- `BoosterPatch`: Provides a speed boost
- `HealthPatch`: Restores vehicle energy
- `JumpPad`: Launches vehicles into the air
- `MagnetPatchNegZ`: Applies force in the negative Z direction
- `MagnetPatchPosX`: Applies force in the positive X direction
- `OilPatch`: Reduces friction
- `RoughtPatch`: Increases friction

## Implementation Notes

- Modifiers can be composed together using the Children array
- Values take effect immediately when entering trigger areas
- Effects are applied every frame until the vehicle leaves the area
- Audio feedback is provided for Unity rendering
- Effects stack multiplicatively with vehicle base stats
- The modifier system is extensible for adding new effect types
