# Sensors and Perception System

This document details the sensors and perception system used by bots in the twin stick shooter game.

## Sensor Overview

Sensors are the "eyes and ears" of the bot, responsible for gathering information about the game state and storing it in the bot's blackboard. Each sensor:

- Has its own tick rate for performance optimization
- Focuses on a specific aspect of the game state
- Updates the bot's blackboard with new information
- May update the bot's memory with long-term information

## Base Sensor Class

All sensors inherit from the Sensor base class:

```csharp
public abstract class Sensor : AssetObject
{
    public FP TickRate = FP._0_20; // Default 5 times per second
    
    public abstract void Execute(Frame frame, EntityRef entity);
    
    protected FP GetTickTimer(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        string timerKey = $"SensorTickTimer{GetType().Name}";
        
        if (!blackboard->Has(timerKey))
        {
            blackboard->Set(timerKey, FP._0);
        }
        
        return blackboard->Get<FP>(timerKey);
    }
    
    protected void ResetTickTimer(Frame frame, EntityRef entity)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        string timerKey = $"SensorTickTimer{GetType().Name}";
        
        blackboard->Set(timerKey, TickRate);
    }
    
    protected void DecrementTickTimer(Frame frame, EntityRef entity, FP deltaTime)
    {
        AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
        string timerKey = $"SensorTickTimer{GetType().Name}";
        
        FP currentTimer = blackboard->Get<FP>(timerKey);
        blackboard->Set(timerKey, currentTimer - deltaTime);
    }
}
```

Key aspects of the Sensor base class:
- `TickRate`: How often the sensor updates
- `Execute()`: Called by the AISystem to run the sensor
- Helper methods for managing the sensor's tick timer

## Sensor Configuration

Sensors are configured in the AIConfig asset:

```csharp
public class AIConfig : AssetObject
{
    [SerializeField]
    public Sensor[] SensorsInstances;
    
    public T GetSensor<T>() where T : Sensor
    {
        foreach (var sensor in SensorsInstances)
        {
            if (sensor is T typedSensor)
            {
                return typedSensor;
            }
        }
        
        return null;
    }
}
```

Each bot type has its own AIConfig with specific sensors.

## Core Sensors

### SensorEyes

```csharp
public class SensorEyes : Sensor
{
    public FP DetectionRange = FP._10;
    public override void Execute(Frame frame, EntityRef entity)
    {
        var tickTimer = GetTickTimer(frame, entity);
        if (tickTimer <= 0)
        {
            ResetTickTimer(frame, entity);
            
            // Get required components
            AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            TeamInfo* teamInfo = frame.Unsafe.GetPointer<TeamInfo>(entity);
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            
            // Find and evaluate all visible characters
            var allCharacters = frame.Filter<Character, TeamInfo, Transform2D>();
            
            EntityRef closestTarget = default;
            FP closestDistanceSq = FP.UseableMax;
            
            while (allCharacters.Next(out EntityRef characterRef, out Character character, out TeamInfo targetTeamInfo, out Transform2D targetTransform))
            {
                // Skip allies and self
                if (teamInfo->Index == targetTeamInfo.Index || characterRef == entity)
                    continue;
                
                // Check if character is within detection range
                FP distanceSq = FPVector2.DistanceSquared(transform->Position, targetTransform.Position);
                if (distanceSq > DetectionRange * DetectionRange)
                    continue;
                
                // Check line of sight
                if (!CheckLineOfSight(frame, transform->Position, targetTransform.Position))
                    continue;
                
                // Check if this is the closest target
                if (distanceSq < closestDistanceSq)
                {
                    closestTarget = characterRef;
                    closestDistanceSq = distanceSq;
                }
            }
            
            // Update the blackboard with the closest target
            if (closestTarget != default)
            {
                blackboard->Set("TargetEntity", closestTarget);
                blackboard->Set("TargetVisible", true);
                blackboard->Set("TargetDistance", FPMath.Sqrt(closestDistanceSq));
            }
            else
            {
                blackboard->Set("TargetVisible", false);
            }
        }
        else
        {
            DecrementTickTimer(frame, entity, frame.DeltaTime);
        }
    }
    
    private bool CheckLineOfSight(Frame frame, FPVector2 start, FPVector2 end)
    {
        var hit = frame.Physics2D.Raycast(start, (end - start).Normalized, FPVector2.Distance(start, end), frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics);
        return !hit.HasValue;
    }
}
```

SensorEyes is responsible for finding and evaluating potential targets:
1. Searches for all characters on opposing teams
2. Filters by distance and line of sight
3. Updates the blackboard with the closest valid target

### SensorHealth

```csharp
public class SensorHealth : Sensor
{
    public FP LowHealthThreshold = FP._0_25; // 25% health
    public FP HighHealthThreshold = FP._0_75; // 75% health
    
    public override void Execute(Frame frame, EntityRef entity)
    {
        var tickTimer = GetTickTimer(frame, entity);
        if (tickTimer <= 0)
        {
            ResetTickTimer(frame, entity);
            
            // Get required components
            AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            Health* health = frame.Unsafe.GetPointer<Health>(entity);
            
            // Calculate health percentage
            FP healthPercentage = health->CurrentHealth / health->MaxHealth;
            
            // Update blackboard
            blackboard->Set("HealthPercentage", healthPercentage);
            blackboard->Set("IsLowHealth", healthPercentage <= LowHealthThreshold);
            blackboard->Set("IsHighHealth", healthPercentage >= HighHealthThreshold);
        }
        else
        {
            DecrementTickTimer(frame, entity, frame.DeltaTime);
        }
    }
}
```

SensorHealth monitors the bot's health:
1. Calculates the current health percentage
2. Determines if health is low or high based on thresholds
3. Updates the blackboard with health information

### SensorCollectibles

```csharp
public class SensorCollectibles : Sensor
{
    public FP DetectionRange = FP._15;
    
    public override void Execute(Frame frame, EntityRef entity)
    {
        var tickTimer = GetTickTimer(frame, entity);
        if (tickTimer <= 0)
        {
            ResetTickTimer(frame, entity);
            
            // Get required components
            AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            
            // Find and evaluate all collectibles
            var allCollectibles = frame.Filter<Collectible, Transform2D>();
            
            EntityRef bestCollectible = default;
            FP bestValue = FP._0;
            
            while (allCollectibles.Next(out EntityRef collectibleRef, out Collectible collectible, out Transform2D collectibleTransform))
            {
                // Check if collectible is within detection range
                FP distanceSq = FPVector2.DistanceSquared(transform->Position, collectibleTransform.Position);
                if (distanceSq > DetectionRange * DetectionRange)
                    continue;
                
                // Check line of sight
                if (!CheckLineOfSight(frame, transform->Position, collectibleTransform.Position))
                    continue;
                
                // Calculate value based on collectible type and distance
                FP distance = FPMath.Sqrt(distanceSq);
                FP value = EvaluateCollectibleValue(collectible) / distance;
                
                // Check if this is the best collectible
                if (value > bestValue)
                {
                    bestCollectible = collectibleRef;
                    bestValue = value;
                }
            }
            
            // Update the blackboard with the best collectible
            if (bestCollectible != default)
            {
                blackboard->Set("TargetCollectible", bestCollectible);
                blackboard->Set("CollectibleValue", bestValue);
                blackboard->Set("HasCollectibleTarget", true);
            }
            else
            {
                blackboard->Set("HasCollectibleTarget", false);
            }
        }
        else
        {
            DecrementTickTimer(frame, entity, frame.DeltaTime);
        }
    }
    
    private FP EvaluateCollectibleValue(Collectible collectible)
    {
        // Calculate value based on collectible type
        switch (collectible.Type)
        {
            case CollectibleType.Health:
                return FP._10;
            case CollectibleType.PowerUp:
                return FP._15;
            case CollectibleType.Coin:
                return FP._5;
            default:
                return FP._1;
        }
    }
    
    private bool CheckLineOfSight(Frame frame, FPVector2 start, FPVector2 end)
    {
        var hit = frame.Physics2D.Raycast(start, (end - start).Normalized, FPVector2.Distance(start, end), frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics);
        return !hit.HasValue;
    }
}
```

SensorCollectibles finds and evaluates collectible items:
1. Searches for all collectibles within range
2. Filters by distance and line of sight
3. Evaluates the value of each collectible based on type and distance
4. Updates the blackboard with the best collectible

### SensorThreats

```csharp
public class SensorThreats : Sensor
{
    public FP ThreatDetectionRange = FP._10;
    public FP ThreatMemoryDuration = FP._5;
    
    public override void Execute(Frame frame, EntityRef entity)
    {
        var tickTimer = GetTickTimer(frame, entity);
        if (tickTimer <= 0)
        {
            ResetTickTimer(frame, entity);
            
            // Get required components
            AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            TeamInfo* teamInfo = frame.Unsafe.GetPointer<TeamInfo>(entity);
            Transform2D* transform = frame.Unsafe.GetPointer<Transform2D>(entity);
            
            // Find and evaluate all attacks
            var allAttacks = frame.Filter<Attack, Transform2D>();
            
            bool threatDetected = false;
            
            while (allAttacks.Next(out EntityRef attackRef, out Attack attack, out Transform2D attackTransform))
            {
                // Skip attacks from our team
                if (attack.TeamId == teamInfo->Index)
                    continue;
                
                // Check if attack is within detection range
                FP distanceSq = FPVector2.DistanceSquared(transform->Position, attackTransform.Position);
                if (distanceSq > ThreatDetectionRange * ThreatDetectionRange)
                    continue;
                
                // Add attack to memory for avoidance
                AIMemory* aiMemory = frame.Unsafe.GetPointer<AIMemory>(entity);
                AIMemoryEntry* memoryEntry = aiMemory->AddTemporaryMemory(frame, EMemoryType.AreaAvoidance, ThreatMemoryDuration);
                memoryEntry->Data.AreaAvoidance->SetData(attackRef, runDistance: attack.Range + FP._1);
                
                threatDetected = true;
            }
            
            // Update blackboard
            blackboard->Set("ThreatDetected", threatDetected);
        }
        else
        {
            DecrementTickTimer(frame, entity, frame.DeltaTime);
        }
    }
    
    // Called by AISystem when an attack is created
    public void OnCircularAttackCreated(Frame frame, EntityRef attackEntity, Attack* attack)
    {
        // Register the attack in all opposing bots' memory
        var bots = frame.Filter<Bot, AIMemory, TeamInfo>();
        while (bots.Next(out EntityRef botEntity, out Bot bot, out AIMemory aiMemory, out TeamInfo teamInfo))
        {
            if (bot.IsActive == false || teamInfo.Index == attack->TeamId)
                continue;
            
            AIMemoryEntry* memoryEntry = aiMemory.AddTemporaryMemory(frame, EMemoryType.AreaAvoidance, ThreatMemoryDuration);
            memoryEntry->Data.AreaAvoidance->SetData(attackEntity, runDistance: attack->Range + FP._1);
        }
    }
    
    // Called by AISystem when a projectile skill is created
    public void OnLinearAttackCreated(Frame frame, EntityRef attacker, FPVector2 characterPos, SkillData data, FPVector2 actionDirection)
    {
        // Register the projectile attack in all opposing bots' memory
        Transform2D attackerTransform = frame.Get<Transform2D>(attacker);
        TeamInfo teamInfo = frame.Get<TeamInfo>(attacker);
        
        var bots = frame.Filter<Bot, AIMemory, TeamInfo>();
        while (bots.Next(out EntityRef botEntity, out Bot bot, out AIMemory aiMemory, out TeamInfo botTeamInfo))
        {
            if (bot.IsActive == false || botTeamInfo.Index == teamInfo.Index)
                continue;
            
            AIMemoryEntry* memoryEntry = aiMemory.AddTemporaryMemory(frame, EMemoryType.LineAvoidance, ThreatMemoryDuration);
            memoryEntry->Data.LineAvoidance->SetData(attacker, actionDirection);
        }
    }
}
```

SensorThreats detects and evaluates threats:
1. Searches for all attacks from opposing teams
2. For each threat, adds an entry to the bot's memory for avoidance
3. Updates the blackboard with threat information
4. Provides methods for the AISystem to register new attacks and skills

### SensorTactics

```csharp
public class SensorTactics : Sensor
{
    [Serializable]
    public struct TacticalOption
    {
        public string Name;
        public FP Weight;
        public FP HealthThreshold;
        public FP TargetProximityThreshold;
        public bool RequiresTarget;
    }
    
    public TacticalOption[] TacticalOptions;
    
    public override void Execute(Frame frame, EntityRef entity)
    {
        var tickTimer = GetTickTimer(frame, entity);
        if (tickTimer <= 0)
        {
            ResetTickTimer(frame, entity);
            
            // Get required components
            AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(entity);
            
            // Get current state
            FP healthPercentage = blackboard->GetOrDefault<FP>("HealthPercentage");
            bool targetVisible = blackboard->GetOrDefault<bool>("TargetVisible");
            FP targetDistance = blackboard->GetOrDefault<FP>("TargetDistance");
            
            // Evaluate tactical options
            string bestTactic = "";
            FP bestScore = FP._0;
            
            foreach (var option in TacticalOptions)
            {
                // Skip options that require a target if none is visible
                if (option.RequiresTarget && !targetVisible)
                    continue;
                
                // Calculate score based on health and target proximity
                FP healthFactor = option.HealthThreshold > FP._0 ? 
                    FP._1 - FPMath.Abs(healthPercentage - option.HealthThreshold) : 
                    FP._1;
                
                FP proximityFactor = option.RequiresTarget && option.TargetProximityThreshold > FP._0 ? 
                    FP._1 - FPMath.Abs(targetDistance - option.TargetProximityThreshold) / FPMath.Max(targetDistance, option.TargetProximityThreshold) : 
                    FP._1;
                
                FP score = option.Weight * healthFactor * proximityFactor;
                
                // Check if this is the best option
                if (score > bestScore)
                {
                    bestTactic = option.Name;
                    bestScore = score;
                }
            }
            
            // Update blackboard
            blackboard->Set("CurrentTactic", bestTactic);
        }
        else
        {
            DecrementTickTimer(frame, entity, frame.DeltaTime);
        }
    }
}
```

SensorTactics evaluates and selects high-level tactics:
1. Considers multiple tactical options (e.g., engage, retreat, collect)
2. Evaluates each option based on health, target proximity, and other factors
3. Selects the best tactic and updates the blackboard

## Sensor Integration

Sensors are integrated into the bot system through:

1. **AIConfig Asset**: Each bot type has an AIConfig with specific sensors
2. **AISystem Update**: The AISystem calls UpdateSensors to execute all sensors
3. **Blackboard**: Sensors store information in the blackboard for use by the HFSM
4. **Memory**: Sensors can add entries to the bot's memory for long-term information

This integration allows sensors to gather information and make it available to the decision-making system.

## Performance Considerations

The sensor system is designed with performance in mind:
- Each sensor has its own tick rate
- Sensors use efficient filtering to process only relevant entities
- Sensors can use the blackboard to cache information
- Expensive operations (e.g., raycasts) are used sparingly

These optimizations allow the bot to gather comprehensive information about the game state without impacting performance too heavily.
