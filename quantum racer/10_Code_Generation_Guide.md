# Quantum Racer 2.5D Code Generation Guide

This guide provides reference patterns for generating code for the Quantum Racer 2.5D game using an LLM. The examples below illustrate the proper structure and syntax for key components of the game.

## Creating a New Modifier

```csharp
// New modifier that applies a speed boost for a limited time
using Photon.Deterministic;
using System;

namespace Quantum 
{
    [Serializable]
    public unsafe class TimedBoostModifier : RacerModifier
    {
        public FP BoostDuration = 3;      // Duration in seconds
        public FP AccelMultiplier = 2;     // Acceleration multiplier
        public FP MaxSpeedMultiplier = 2;  // Speed multiplier
        
        protected override void InnerUpdate(Frame f, ref RacerSystem.Filter filter)
        {
            if (filter.Vehicle->ModifierValues.BoostTimer <= 0)
            {
                // First application - set timer
                filter.Vehicle->ModifierValues.BoostTimer = BoostDuration;
            }
            
            // Apply boost effects
            filter.Vehicle->ModifierValues.AccelMultiplier = AccelMultiplier;
            filter.Vehicle->ModifierValues.MaxSpeedMultiplier = MaxSpeedMultiplier;
            
            // Decrease timer
            filter.Vehicle->ModifierValues.BoostTimer -= f.DeltaTime;
            
            // Remove modifier when timer expires
            if (filter.Vehicle->ModifierValues.BoostTimer <= 0)
            {
                filter.Vehicle->Modifier = default;
            }
        }
    }
}
```

## Creating a New Vehicle Config

```csharp
// Assets/QuantumUser/Resources/Racer/CarSpecs/SuperCarConfig.asset
using Photon.Deterministic;
using UnityEngine;

namespace Quantum 
{
    [CreateAssetMenu(menuName = "Quantum/Racer/Vehicle/SuperCar Config")]
    public class SuperCarConfig : RacerConfig
    {
        private void OnValidate()
        {
            // Set specific vehicle characteristics
            CarName = "Super Car";
            Acceleration = 20;
            Mass = 1.5f;
            Braking = 8;
            GroundDrag = 0.8f;
            MaxSpeed = 12;
            RotationSpeed = 12;
            LeanBuff = 6;
            FrictionCoeficient = 1.8f;
            ThrottleFrictionReductor = 0.4f;
            InitialEnergy = 15;
            
            // Create steering response curve
            if (SteeringResponseCurve == null || SteeringResponseCurve.Points.Length == 0)
            {
                SteeringResponseCurve = new FPAnimationCurve(new [] {
                    new FPAnimationCurve.KeyFrame(0, 1),
                    new FPAnimationCurve.KeyFrame(5, 0.75f),
                    new FPAnimationCurve.KeyFrame(10, 0.5f),
                    new FPAnimationCurve.KeyFrame(15, 0.25f)
                });
            }
        }
    }
}
```

## Adding a New Track Feature

```csharp
// New teleporter system that moves vehicles to a target position
using Photon.Deterministic;
using UnityEngine.Scripting;

namespace Quantum
{
    [Preserve]
    public unsafe class TeleporterSystem : SystemMainThreadFilter<TeleporterSystem.Filter>, 
        ISignalOnTriggerEnter2D
    {
        public struct Filter
        {
            public EntityRef Entity;
            public Teleporter* Teleporter;
            public Transform2D* Transform;
        }
        
        public override void Update(Frame f, ref Filter filter)
        {
            // Optional: Teleporter effects/animations
            filter.Teleporter->EffectTimer += f.DeltaTime;
            if (filter.Teleporter->EffectTimer > filter.Teleporter->EffectInterval)
            {
                filter.Teleporter->EffectTimer = FP._0;
                // Trigger effect here
            }
        }
        
        public void OnTriggerEnter2D(Frame f, TriggerInfo2D info)
        {
            // Check if trigger is a teleporter
            if (f.Unsafe.TryGetPointer(info.Static, out Teleporter* teleporter))
            {
                // Check if entering entity is a racer
                if (f.Unsafe.TryGetPointer(info.Entity, out Racer* racer) &&
                    f.Unsafe.TryGetPointer(info.Entity, out Transform2D* transform) &&
                    f.Unsafe.TryGetPointer(info.Entity, out PhysicsBody2D* body))
                {
                    // Don't teleport finished racers
                    if (racer->Finished) return;
                    
                    // Get destination coordinates
                    var destination = teleporter->Destination;
                    
                    // Store original velocity
                    var velocity = body->Velocity;
                    var speed = velocity.Magnitude;
                    
                    // Momentarily make body kinematic to prevent physics issues
                    body->IsKinematic = true;
                    
                    // Teleport the entity
                    transform->Teleport(f, destination.Position);
                    transform->Rotation = destination.Rotation;
                    
                    // Apply exit velocity in the correct direction
                    body->IsKinematic = false;
                    body->Velocity = transform->Up * speed * teleporter->SpeedMultiplier;
                    
                    // Trigger teleport event
                    f.Events.Teleport(info.Entity, destination.Position);
                }
            }
        }
    }
    
    // Component definition in .qtn file
    /*
    component Teleporter {
        FPTransform2D Destination;
        FP SpeedMultiplier;
        [ExcludeFromPrototype] FP EffectTimer;
        FP EffectInterval;
    }
    
    event Teleport {
        EntityRef Entity;
        FPVector2 Destination;
    }
    */
}
```

## Adding a New Game Mode

```csharp
// Checkpoint Race mode - race to complete all checkpoints in any order
using Photon.Deterministic;
using UnityEngine.Scripting;

namespace Quantum
{
    [Preserve]
    public unsafe class CheckpointRaceSystem : SystemMainThread
    {
        public override void OnInit(Frame f)
        {
            // Initialize the race
            f.GetOrAddSingleton<CheckpointRaceManager>();
            var raceConfig = f.FindAsset<CheckpointRaceConfig>(f.RuntimeConfig.CheckpointRaceConfig);
            
            if (f.Unsafe.TryGetPointerSingleton<CheckpointRaceManager>(out var manager))
            {
                // Initialize checkpoint list
                manager->RemainingCheckpoints = f.AllocateList<EntityRef>();
                manager->PlayerCheckpoints = f.AllocateMap<PlayerRef, byte>();
                manager->RaceTime = raceConfig.StartCountdown;
                manager->State = RaceState.Start;
                
                // Populate checkpoint list
                var checkpoints = f.Filter<Transform2D, CheckpointRaceTarget>();
                while (checkpoints.NextUnsafe(out var entity, out _, out _))
                {
                    var list = f.ResolveList(manager->RemainingCheckpoints);
                    list.Add(entity);
                }
            }
        }
        
        public override void Update(Frame f)
        {
            if (f.Unsafe.TryGetPointerSingleton<CheckpointRaceManager>(out var manager))
            {
                switch (manager->State)
                {
                    case RaceState.Start:
                        // Countdown timer
                        manager->RaceTime -= f.DeltaTime;
                        if (manager->RaceTime <= 0)
                        {
                            manager->State = RaceState.Running;
                            manager->RaceTime = 0;
                            FillWithBots(f);
                        }
                        break;
                        
                    case RaceState.Running:
                        // Update race timer
                        manager->RaceTime += f.DeltaTime;
                        
                        // Check if all checkpoints have been collected
                        if (manager->FinishedCount >= f.PlayerCount)
                        {
                            manager->State = RaceState.Finished;
                        }
                        break;
                        
                    case RaceState.Finished:
                        // Race complete
                        break;
                }
            }
        }
        
        // Helper methods omitted
    }
    
    // Component definitions in .qtn file
    /*
    singleton component CheckpointRaceManager {
        list<EntityRef> RemainingCheckpoints;
        map<PlayerRef, byte> PlayerCheckpoints;
        FP RaceTime;
        RaceState State;
        int FinishedCount;
    }
    
    component CheckpointRaceTarget {
        byte CheckpointID;
        bool Collected;
    }
    */
}
```

## Creating Custom Player Controls

```csharp
// Custom control scheme that adds boost functionality
using Quantum;
using UnityEngine;

public class CustomControlHandler : MonoBehaviour
{
    // Boost cooldown tracking
    private float _boostCooldown = 0f;
    private float _maxBoostCooldown = 3f;
    private bool _boostReady = true;
    
    // UI reference
    public UnityEngine.UI.Image BoostCooldownUI;
    
    private void Update()
    {
        if (QuantumRunner.Default == null) return;
        
        // Update boost cooldown
        if (_boostCooldown > 0)
        {
            _boostCooldown -= Time.deltaTime;
            if (_boostCooldown <= 0)
            {
                _boostReady = true;
                _boostCooldown = 0;
            }
            
            // Update UI
            if (BoostCooldownUI != null)
            {
                BoostCooldownUI.fillAmount = 1f - (_boostCooldown / _maxBoostCooldown);
            }
        }
        
        // Get input
        var input = new Quantum.Input();
        
        // Standard controls
        input.RacerAccel.Set(UnityEngine.Input.GetKey(KeyCode.W));
        input.RacerBrake.Set(UnityEngine.Input.GetKey(KeyCode.S));
        input.RacerLeft.Set(UnityEngine.Input.GetKey(KeyCode.A));
        input.RacerRight.Set(UnityEngine.Input.GetKey(KeyCode.D));
        input.RacerLeanLeft.Set(UnityEngine.Input.GetKey(KeyCode.J));
        input.RacerLeanRight.Set(UnityEngine.Input.GetKey(KeyCode.L));
        input.RacerPitchUp.Set(UnityEngine.Input.GetKey(KeyCode.I));
        input.RacerPitchDown.Set(UnityEngine.Input.GetKey(KeyCode.K));
        
        // Boost control (space key)
        input.RacerBoost.Set(UnityEngine.Input.GetKey(KeyCode.Space) && _boostReady);
        
        // Trigger boost cooldown when activated
        if (input.RacerBoost.WasPressed)
        {
            _boostReady = false;
            _boostCooldown = _maxBoostCooldown;
        }
        
        // Send input to Quantum
        QuantumRunner.Default.Game.SendInput(input);
    }
}

// Add to .qtn file
/*
input {
    // Existing inputs...
    button RacerBoost;
}
*/

// Processor in RacerConfig.cs
/*
public void UpdateRacer(Frame f, ref RacerSystem.Filter filter)
{
    // Existing code...
    
    // Process boost
    if (input.RacerBoost.WasPressed)
    {
        // Apply boost effects
        filter.Body->AddForce(filter.Transform->Up * BoostForce * filter.Body->Mass);
        filter.Vehicle->BoostActive = true;
        filter.Vehicle->BoostTimer = BoostDuration;
        
        // Trigger effect
        f.Events.BoostActivated(filter.Entity);
    }
    
    // Update boost state
    if (filter.Vehicle->BoostActive)
    {
        filter.Vehicle->BoostTimer -= f.DeltaTime;
        if (filter.Vehicle->BoostTimer <= 0)
        {
            filter.Vehicle->BoostActive = false;
        }
        else
        {
            // Apply continuous boost effects
            filter.Vehicle->ModifierValues.MaxSpeedMultiplier = BoostSpeedMultiplier;
        }
    }
}
*/
```

## Adding a New Event System

```csharp
// Item pickup and use system
using Photon.Deterministic;
using UnityEngine.Scripting;

namespace Quantum
{
    [Preserve]
    public unsafe class ItemSystem : SystemMainThreadFilter<ItemSystem.Filter>, 
        ISignalOnTriggerEnter2D
    {
        public struct Filter
        {
            public EntityRef Entity;
            public ItemHolder* Items;
            public Racer* Racer;
        }
        
        public override void Update(Frame f, ref Filter filter)
        {
            Input input = default;
            
            // Get player input if applicable
            if (f.TryGet(filter.Entity, out RacerPlayerLink link) && link.Player.IsValid)
            {
                input = *f.GetPlayerInput(link.Player);
            }
            
            // Check for item use
            if (input.UseItem.WasPressed && filter.Items->CurrentItem != ItemType.None)
            {
                UseItem(f, filter.Entity, filter.Items, filter.Racer);
            }
            
            // Update item cooldown
            if (filter.Items->ItemCooldown > 0)
            {
                filter.Items->ItemCooldown -= f.DeltaTime;
            }
        }
        
        private void UseItem(Frame f, EntityRef entity, ItemHolder* items, Racer* racer)
        {
            if (items->ItemCooldown > 0) return;
            
            switch (items->CurrentItem)
            {
                case ItemType.SpeedBoost:
                    // Apply speed boost
                    items->ItemCooldown = 5; // 5 second cooldown
                    racer->ModifierValues.AccelMultiplier = 2;
                    racer->ModifierValues.MaxSpeedMultiplier = 2;
                    racer->BoostTimer = 3; // 3 second duration
                    f.Events.ItemUsed(entity, ItemType.SpeedBoost);
                    break;
                    
                case ItemType.Shield:
                    // Apply shield
                    items->ItemCooldown = 10; // 10 second cooldown
                    racer->ShieldActive = true;
                    racer->ShieldTimer = 5; // 5 second duration
                    f.Events.ItemUsed(entity, ItemType.Shield);
                    break;
                    
                case ItemType.Missile:
                    // Fire missile at car ahead
                    if (racer->CarAhead.IsValid)
                    {
                        items->ItemCooldown = 8; // 8 second cooldown
                        FireMissile(f, entity, racer->CarAhead);
                        f.Events.ItemUsed(entity, ItemType.Missile);
                    }
                    break;
            }
            
            // Clear current item
            items->CurrentItem = ItemType.None;
        }
        
        private void FireMissile(Frame f, EntityRef source, EntityRef target)
        {
            // Create missile entity
            var missilePrototype = f.FindAsset<EntityPrototype>("Missile");
            var missile = f.Create(missilePrototype);
            
            // Set missile properties
            if (f.Unsafe.TryGetPointer(missile, out Missile* missileComponent))
            {
                missileComponent->Source = source;
                missileComponent->Target = target;
                missileComponent->Speed = 20; // FP units per second
                missileComponent->Damage = 5;
            }
            
            // Position missile
            if (f.Unsafe.TryGetPointer(missile, out Transform2D* transform) &&
                f.TryGet<Transform2D>(source, out var sourceTransform))
            {
                transform->Position = sourceTransform.Position;
                transform->Rotation = sourceTransform.Rotation;
            }
        }
        
        public void OnTriggerEnter2D(Frame f, TriggerInfo2D info)
        {
            // Check if trigger is an item box
            if (f.Unsafe.TryGetPointer(info.Static, out ItemBox* itemBox))
            {
                // Check if entering entity has an item holder
                if (f.Unsafe.TryGetPointer(info.Entity, out ItemHolder* items) &&
                    items->CurrentItem == ItemType.None &&
                    items->ItemCooldown <= 0)
                {
                    // Random item selection
                    var itemIndex = f.Global->RngSession.Next(0, 3); // 0-2
                    items->CurrentItem = (ItemType)(itemIndex + 1); // Convert to enum (1-3)
                    
                    // Trigger pickup event
                    f.Events.ItemPickup(info.Entity, items->CurrentItem);
                }
            }
        }
    }
    
    // Component definitions in .qtn file
    /*
    enum ItemType {
        None = 0,
        SpeedBoost = 1,
        Shield = 2,
        Missile = 3
    }
    
    component ItemHolder {
        ItemType CurrentItem;
        [ExcludeFromPrototype] FP ItemCooldown;
    }
    
    component ItemBox {
        int ItemBoxID;
        [ExcludeFromPrototype] FP RespawnTimer;
        FP RespawnDelay;
    }
    
    component Missile {
        EntityRef Source;
        EntityRef Target;
        FP Speed;
        FP Damage;
        [ExcludeFromPrototype] FP Lifetime;
    }
    
    // Add to Racer component
    [ExcludeFromPrototype] FP BoostTimer;
    [ExcludeFromPrototype] bool ShieldActive;
    [ExcludeFromPrototype] FP ShieldTimer;
    
    // Add to Input
    button UseItem;
    
    // Events
    event ItemPickup {
        EntityRef Entity;
        ItemType ItemType;
    }
    
    event ItemUsed {
        EntityRef Entity;
        ItemType ItemType;
    }
    */
}
```

## Implementation Notes

When generating code for Quantum Racer 2.5D, remember these key patterns:

1. **Deterministic Physics**: Always use `FP` (fixed point) for numeric values
2. **Component Access**: Use `f.Unsafe.TryGetPointer` for high-performance component access
3. **Updates**: Implement core logic in `Update` methods that take a `Frame` parameter
4. **Serialization**: Mark components with `[ExcludeFromPrototype]` for runtime-only values
5. **Events**: Use Quantum's event system for gameplay events and animations
6. **Networking**: Never mix Unity physics with Quantum deterministic simulation
7. **Signal Interfaces**: Implement signal interfaces like `ISignalOnTriggerEnter2D` for physics events
8. **Systems**: Inherit from appropriate `System` class based on threading needs
9. **Assets**: Reference game configs via `AssetRef<T>` and load with `f.FindAsset()`
10. **AI Control**: Use the Bot components and config for computer-controlled racers
