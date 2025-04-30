# Inventory System

This document explains the inventory system in the Quantum Twin Stick Shooter, focusing on how items (especially coins) are collected, stored, and managed.

## Overview

The inventory system in Twin Stick Shooter provides:

1. **Item Collection**: Mechanism for collecting coins and other items
2. **Item Storage**: Data structure for storing collected items
3. **Coin Management**: Central to the Coin Grab game mode
4. **Dropping Items**: On character death
5. **Item Effects**: Applied when items are collected

## Core Components

### Inventory Component

```csharp
// From Inventory.qtn
component Inventory
{
    QList<InventoryItem> Items;
}

struct InventoryItem
{
    EItemType Type;
    FP Value;
}

enum EItemType
{
    None,
    Coin,
    PowerUp,
    HealthKit
}
```

### ObjectivePoint (Collectible) Component

```csharp
// From ObjectivePoint.qtn
component ObjectivePoint
{
    Boolean IsActive;
    EItemType Type;
    FP Value;
}
```

## InventorySystem Implementation

The `InventorySystem` handles managing inventories and applying effects:

```csharp
[Preserve]
public unsafe class InventorySystem : SystemMainThreadFilter<InventorySystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public Inventory* Inventory;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Process inventory items for effects
        for (int i = 0; i < filter.Inventory->Items.Length; i++)
        {
            InventoryItem* item = &filter.Inventory->Items[i];
            
            // Apply item effects
            switch (item->Type)
            {
                case EItemType.PowerUp:
                    ApplyPowerUpEffect(frame, filter.Entity, item);
                    // Remove consumed item
                    filter.Inventory->Items.RemoveAt(i);
                    i--;
                    break;
                    
                case EItemType.HealthKit:
                    ApplyHealthKitEffect(frame, filter.Entity, item);
                    // Remove consumed item
                    filter.Inventory->Items.RemoveAt(i);
                    i--;
                    break;
                
                // Coins are persistent items that don't have immediate effects
                case EItemType.Coin:
                    // No immediate effect, just stored for game objective
                    break;
            }
        }
    }
    
    private void ApplyPowerUpEffect(Frame frame, EntityRef entity, InventoryItem* item)
    {
        // Apply temporary speed boost
        AttributesHelper.ChangeAttribute(
            frame, 
            entity, 
            EAttributeType.Speed, 
            EModifierAppliance.Timer, 
            EModifierOperation.Multiply, 
            FP._0_50, // 50% speed boost
            FP._5);   // 5 second duration
            
        // Send event for visualization
        frame.Events.PowerUpActivated(entity, "SpeedBoost");
    }
    
    private void ApplyHealthKitEffect(Frame frame, EntityRef entity, InventoryItem* item)
    {
        // Only apply if character has health component
        if (!frame.Has<Health>(entity))
            return;
            
        Health* health = frame.Unsafe.GetPointer<Health>(entity);
        
        // Skip if character is dead
        if (health->IsDead)
            return;
            
        // Calculate health to restore
        FP maxHealth = AttributesHelper.GetCurrentValue(frame, entity, EAttributeType.Health);
        FP healAmount = maxHealth * item->Value;
        
        // Apply healing
        health->Current = FPMath.Min(health->Current + healAmount, maxHealth);
        
        // Send event for visualization
        frame.Events.CharacterHealed(entity);
    }
}
```

## ObjectivePointSystem Implementation

The `ObjectivePointSystem` handles collectible objects in the world:

```csharp
[Preserve]
public unsafe class ObjectivePointSystem : SystemMainThreadFilter<ObjectivePointSystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public ObjectivePoint* ObjectivePoint;
        public Transform2D* Transform;
        public PhysicsCollider2D* Collider;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Skip if not active
        if (!filter.ObjectivePoint->IsActive)
            return;
            
        // Check for characters in range
        var hits = Physics2D.OverlapShape(frame, filter.Collider->Shape, *filter.Transform);
        foreach (var hit in hits)
        {
            // Only process character entities
            if (!frame.Has<Character>(hit) || !frame.Has<Inventory>(hit))
                continue;
                
            // Skip dead characters
            if (frame.Has<Health>(hit) && frame.Get<Health>(hit).IsDead)
                continue;
                
            // Add item to character inventory
            AddItemToInventory(frame, hit, filter.ObjectivePoint->Type, filter.ObjectivePoint->Value);
            
            // Deactivate collectible
            filter.ObjectivePoint->IsActive = false;
            
            // Set respawn timer based on item type
            FP respawnTime = GetRespawnTimeForItem(frame, filter.ObjectivePoint->Type);
            frame.Timer.Set(filter.Entity, "RespawnTimer", respawnTime, () => {
                if (frame.Exists(filter.Entity))
                {
                    ObjectivePoint* point = frame.Unsafe.GetPointer<ObjectivePoint>(filter.Entity);
                    point->IsActive = true;
                }
            });
            
            // Send collection event
            SendCollectionEvent(frame, hit, filter.ObjectivePoint->Type);
            
            break;
        }
    }
    
    private void AddItemToInventory(Frame frame, EntityRef character, EItemType itemType, FP value)
    {
        Inventory* inventory = frame.Unsafe.GetPointer<Inventory>(character);
        
        // Create item
        InventoryItem item = new InventoryItem
        {
            Type = itemType,
            Value = value
        };
        
        // Add to inventory
        inventory->Items.Add(frame, item);
    }
    
    private FP GetRespawnTimeForItem(Frame frame, EItemType itemType)
    {
        // Different respawn times based on item type
        switch (itemType)
        {
            case EItemType.Coin:
                return frame.RuntimeConfig.CoinRespawnTime;
                
            case EItemType.PowerUp:
                return frame.RuntimeConfig.PowerUpRespawnTime;
                
            case EItemType.HealthKit:
                return frame.RuntimeConfig.HealthKitRespawnTime;
                
            default:
                return FP._10; // Default 10 seconds
        }
    }
    
    private void SendCollectionEvent(Frame frame, EntityRef character, EItemType itemType)
    {
        // Send appropriate event based on item type
        switch (itemType)
        {
            case EItemType.Coin:
                frame.Events.CoinCollected(character);
                break;
                
            case EItemType.PowerUp:
                frame.Events.PowerUpCollected(character);
                break;
                
            case EItemType.HealthKit:
                frame.Events.HealthKitCollected(character);
                break;
        }
    }
}
```

## ItemDrop System

The `ItemDropSystem` handles dropping items when characters die:

```csharp
[Preserve]
public unsafe class ItemDropSystem : SystemMainThread, ISignalOnCharacterDefeated
{
    public void OnCharacterDefeated(Frame frame, EntityRef character)
    {
        // Skip if no inventory
        if (!frame.Has<Inventory>(character) || !frame.Has<Transform2D>(character))
            return;
            
        Inventory* inventory = frame.Unsafe.GetPointer<Inventory>(character);
        Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(character);
        
        // Count items to drop
        int coinCount = 0;
        
        for (int i = 0; i < inventory->Items.Length; i++)
        {
            if (inventory->Items[i].Type == EItemType.Coin)
            {
                coinCount++;
            }
        }
        
        // Drop all coins
        DropCoins(frame, transform->Position, coinCount);
        
        // Clear inventory
        inventory->Items.Clear();
    }
    
    private void DropCoins(Frame frame, FPVector2 position, int count)
    {
        // No coins to drop
        if (count <= 0)
            return;
            
        // Spawn coins in a random pattern around the drop position
        for (int i = 0; i < count; i++)
        {
            // Calculate random drop position
            FP angle = FP.FromFloat_UNSAFE(frame.RandomInRange(0, 360));
            FP distance = FP.FromFloat_UNSAFE(frame.RandomInRange(1, 3));
            FPVector2 dropPos = position + FPVector2.FromAngle(angle) * distance;
            
            // Create coin entity
            EntityRef coinEntity = frame.Create(frame.RuntimeConfig.CoinPrototype);
            
            // Position the coin
            Transform2D* coinTransform = frame.Unsafe.GetPointer<Transform2D>(coinEntity);
            coinTransform->Position = dropPos;
            
            // Activate the objective point
            ObjectivePoint* objectivePoint = frame.Unsafe.GetPointer<ObjectivePoint>(coinEntity);
            objectivePoint->IsActive = true;
            objectivePoint->Type = EItemType.Coin;
            objectivePoint->Value = FP._1;
        }
    }
}
```

## Team Score Calculation

The inventory system is central to the Coin Grab game mode's scoring:

```csharp
// From TeamDataSystem.cs (simplified)
private void UpdateTeamScores(Frame frame)
{
    // Reset team scores
    for (int i = 0; i < frame.Global->Teams.Length; i++)
    {
        frame.Global->Teams[i].Score = 0;
    }
    
    // Count coins held by each team
    var characters = frame.Filter<Character, TeamInfo, Inventory>();
    while (characters.NextUnsafe(out EntityRef entity, out Character* character,
        out TeamInfo* teamInfo, out Inventory* inventory))
    {
        byte coinCount = CountCoins(frame, inventory);
        frame.Global->Teams[teamInfo->Index].Score += coinCount;
    }
}

private byte CountCoins(Frame frame, Inventory* inventory)
{
    byte count = 0;
    
    // Count coin items in inventory
    for (int i = 0; i < inventory->Items.Length; i++)
    {
        var item = inventory->Items[i];
        if (item.Type == EItemType.Coin)
        {
            count++;
        }
    }
    
    return count;
}
```

## Item Spawner System

The `ItemSpawnerSystem` handles spawning collectibles at the start of the match:

```csharp
[Preserve]
public unsafe class ItemSpawnerSystem : SystemMainThread, ISignalOnGameStart
{
    public void OnGameStart(Frame frame)
    {
        // Spawn coins based on map data
        SpawnItems(frame, EItemType.Coin, frame.RuntimeConfig.CoinSpawnPositions);
        
        // Spawn power-ups
        SpawnItems(frame, EItemType.PowerUp, frame.RuntimeConfig.PowerUpSpawnPositions);
        
        // Spawn health kits
        SpawnItems(frame, EItemType.HealthKit, frame.RuntimeConfig.HealthKitSpawnPositions);
    }
    
    private void SpawnItems(Frame frame, EItemType itemType, FPVector2[] positions)
    {
        // No positions to spawn at
        if (positions == null || positions.Length == 0)
            return;
            
        // Get appropriate prototype based on item type
        AssetRef<EntityPrototype> prototype = GetPrototypeForItemType(frame, itemType);
        if (!prototype.Id.IsValid)
            return;
            
        // Spawn at each position
        for (int i = 0; i < positions.Length; i++)
        {
            // Create entity
            EntityRef itemEntity = frame.Create(prototype);
            
            // Set position
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(itemEntity);
            transform->Position = positions[i];
            
            // Configure objective point
            ObjectivePoint* objectivePoint = frame.Unsafe.GetPointer<ObjectivePoint>(itemEntity);
            objectivePoint->IsActive = true;
            objectivePoint->Type = itemType;
            objectivePoint->Value = GetValueForItemType(itemType);
        }
    }
    
    private AssetRef<EntityPrototype> GetPrototypeForItemType(Frame frame, EItemType itemType)
    {
        switch (itemType)
        {
            case EItemType.Coin:
                return frame.RuntimeConfig.CoinPrototype;
                
            case EItemType.PowerUp:
                return frame.RuntimeConfig.PowerUpPrototype;
                
            case EItemType.HealthKit:
                return frame.RuntimeConfig.HealthKitPrototype;
                
            default:
                return default;
        }
    }
    
    private FP GetValueForItemType(EItemType itemType)
    {
        switch (itemType)
        {
            case EItemType.Coin:
                return FP._1;
                
            case EItemType.PowerUp:
                return FP._0_50; // 50% boost
                
            case EItemType.HealthKit:
                return FP._0_25; // 25% of max health
                
            default:
                return FP._0;
        }
    }
}
```

## Unity View Integration

The inventory system connects to Unity visualization:

```csharp
// In CharacterView.cs (Unity side, simplified)
public class CharacterView : QuantumMonoBehaviour
{
    public GameObject coinVisual;
    public ParticleSystem powerUpEffect;
    public ParticleSystem healthEffect;
    
    private int _lastCoinCount = 0;
    
    protected override void OnEntityInstantiated()
    {
        base.OnEntityInstantiated();
        
        // Hide coin visual initially
        coinVisual.SetActive(false);
    }
    
    protected override void OnEntityUpdated(bool wasSet)
    {
        base.OnEntityUpdated(wasSet);
        
        if (!IsEntityValid)
            return;
            
        // Update coin visual
        int coinCount = GetCoinCount();
        
        if (coinCount > 0)
        {
            coinVisual.SetActive(true);
        }
        else
        {
            coinVisual.SetActive(false);
        }
        
        // Play effects if coin count changed
        if (coinCount > _lastCoinCount)
        {
            AudioManager.Instance.PlaySound("coin_pickup");
        }
        else if (coinCount < _lastCoinCount)
        {
            AudioManager.Instance.PlaySound("coin_drop");
        }
        
        _lastCoinCount = coinCount;
    }
    
    private int GetCoinCount()
    {
        Frame frame = QuantumGame.Current.Frames.Predicted;
        
        if (!frame.Exists(EntityRef) || !frame.Has<Inventory>(EntityRef))
            return 0;
            
        Inventory inventory = frame.Get<Inventory>(EntityRef);
        int count = 0;
        
        // Count coins
        for (int i = 0; i < inventory.Items.Length; i++)
        {
            if (inventory.Items[i].Type == EItemType.Coin)
            {
                count++;
            }
        }
        
        return count;
    }
    
    // Called by events
    public void OnPowerUpCollected()
    {
        powerUpEffect.Play();
        AudioManager.Instance.PlaySound("powerup_pickup");
    }
    
    public void OnHealthKitCollected()
    {
        healthEffect.Play();
        AudioManager.Instance.PlaySound("health_pickup");
    }
}
```

## Best Practices

1. **Simple Inventory Structure**: Keep the inventory system straightforward for a fast-paced game
2. **Event-Based Visualization**: Use events to synchronize inventory changes with visual effects
3. **Type-Based Item Handling**: Use enum types to differentiate item behaviors
4. **Team-Based Coin Counting**: Calculate team scores based on aggregated inventories
5. **Automatic Item Respawning**: Use timers to respawn collected items
6. **Physics-Based Collection**: Use physics triggers for item collection
7. **Deterministic Item Dropping**: Ensure consistent behavior for dropped items

## Implementation Notes

1. The inventory system uses a simple list structure for storing items
2. Coins are the primary collectible in the Coin Grab game mode
3. Items are collected through physics collision detection
4. Items automatically respawn after being collected
5. Characters drop all coins when they die
6. Team scores are calculated by counting coins in all team members' inventories
7. All inventory operations are fully deterministic for network consistency