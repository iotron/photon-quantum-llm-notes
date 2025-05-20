# AI System Implementation Details

This document provides a detailed analysis of the AISystem implementation in the Photon Quantum twin stick shooter game.

## AISystem Class Overview

The AISystem is the central system that orchestrates all bot behaviors:

```csharp
public unsafe class AISystem : SystemMainThreadFilter<AISystem.Filter>, ISignalOnComponentAdded<Bot>, ISignalOnNavMeshMoveAgent,
    ISignalOnGameStart, ISignalOnCreateAttack, ISignalOnCreateSkill
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform2D* Transform;
        public Bot* Bot;
        public Health* Health;
        public AISteering* AISteering;
    }
    
    // Implementation methods...
}
```

Key aspects:
- Uses SystemMainThreadFilter for efficient entity filtering
- Implements multiple signal interfaces to respond to various game events
- Filter struct ensures only relevant entities are processed

## Core Methods

### OnAdded

```csharp
public void OnAdded(Frame frame, EntityRef entity, Bot* component)
{
    if (component->IsActive == true)
    {
        AISetupHelper.Botify(frame, entity);
    }
}
```

This method is called when a Bot component is added to an entity. If the Bot is active, it calls `AISetupHelper.Botify()` to initialize all necessary AI components.

### Update

```csharp
public override void Update(Frame frame, ref Filter filter)
{
    if (filter.Bot->IsActive == false)
    {
        return;
    }

    if(filter.Health->IsDead == true)
    {
        return;
    }

    UpdateSensors(frame, filter.Entity);
    HandleContextSteering(frame, filter);
    HFSMManager.Update(frame, frame.DeltaTime, filter.Entity);
}
```

The Update method is the primary driver of bot behavior:
1. Checks if the bot is active and alive
2. Updates sensors to gather new information
3. Processes movement through context steering
4. Updates the HFSM to make decisions

### UpdateSensors

```csharp
private void UpdateSensors(Frame frame, EntityRef entity)
{
    AIConfig aiConfig = frame.FindAsset<AIConfig>(frame.Get<HFSMAgent>(entity).Config.Id);
    Sensor[] sensors = aiConfig.SensorsInstances;
    for (int i = 0; i < sensors.Length; i++)
    {
        Assert.Check(sensors[i] != null, "Sensor {0} not found, for entity {1}", i, entity);
        Assert.Check(sensors[i].TickRate != 0, "Sensor {0} needs to have a Tick Rate greater than zero", i);
        sensors[i].Execute(frame, entity);
    }
}
```

This method:
1. Gets the AIConfig asset for the bot
2. Retrieves all sensor instances
3. Executes each sensor, which internally handles its own tick rate

### HandleContextSteering

```csharp
private void HandleContextSteering(Frame frame, Filter filter)
{
    // Process the final desired direction
    FPVector2 desiredDirection = filter.AISteering->GetDesiredDirection(frame, filter.Entity);

    // Lerp the current value towards the desired one so it doesn't turn too subtle
    filter.AISteering->CurrentDirection = FPVector2.MoveTowards(filter.AISteering->CurrentDirection, desiredDirection,
        frame.DeltaTime * filter.AISteering->LerpFactor);

    // The MovementDirection input is (de)coded and it is always normalized (unless it's value is zero)
    // That's why we compute the direction in a regular FPVector2 for the MoveTowards to properly work
    // Then we assign the value to the bot input, which is later used by the InputSystem in order to move the KCC
    filter.Bot->Input.MoveDirection = filter.AISteering->CurrentDirection;
}
```

This method:
1. Gets the desired movement direction from the AI steering component
2. Smoothly interpolates from the current direction to the desired direction
3. Assigns the result to the bot's input for processing by the movement system

### OnNavMeshMoveAgent

```csharp
public void OnNavMeshMoveAgent(Frame frame, EntityRef entity, FPVector2 desiredDirection)
{
    AISteering* aiSteering = frame.Unsafe.GetPointer<AISteering>(entity);

    if (aiSteering->IsNavMeshSteering == true)
    {
        aiSteering->MainSteeringData.SteeringEntryNavMesh->SetData(desiredDirection);
    }
}
```

This method is called when the NavMesh system calculates a desired direction. If the bot is using NavMesh steering, it updates the steering data with the calculated direction.

### OnGameStart

```csharp
public void OnGameStart(Frame frame)
{
    var allBots = frame.Filter<Bot, AIMemory, TeamInfo>();
    while (allBots.NextUnsafe(out EntityRef agentRef, out Bot* bot, out AIMemory* aiMemory, out TeamInfo* agentTeamInfo))
    {
        if (bot->IsActive == false)
        {
            continue;
        }

        var allCharacters = frame.Filter<Character, TeamInfo>();
        while (allCharacters.Next(out EntityRef characterRef, out Character character, out TeamInfo teamInfo))
        {
            if (agentTeamInfo->Index == teamInfo.Index)
            {
                continue;
            }

            AIMemoryEntry* memoryEntry = aiMemory->AddInfiniteMemory(frame, EMemoryType.AreaAvoidance);
            memoryEntry->Data.AreaAvoidance->SetData(characterRef, runDistance: FP._2);
        }
    }
}
```

When the game starts, this method:
1. Iterates through all active bots
2. For each bot, processes all characters from opposing teams
3. Adds an avoidance memory entry for each opposing character
4. This ensures bots will try to maintain some distance from opponents even when not directly targeting them

### Attack Signal Handlers

```csharp
public void OnCreateAttack(Frame frame, EntityRef attackEntity, Attack* attack)
{
    // Implementation that registers attacks for avoidance
}

public void OnCreateSkill(Frame frame, EntityRef attacker, FPVector2 characterPos, SkillData data, FPVector2 actionDirection)
{
    // Implementation that registers skills for avoidance
}
```

These methods are called when attacks and skills are created. They:
1. Iterate through all bots from opposing teams
2. Use the SensorThreats component to register the attack/skill
3. This allows bots to detect and avoid incoming attacks and projectiles

## Dependencies and Integration

The AISystem depends on:
- **Bot Component**: Contains input data and configuration references
- **Health Component**: Determines if the bot is alive
- **Transform2D Component**: Provides position and orientation
- **AISteering Component**: Handles movement decision-making
- **AIConfig Asset**: Provides configuration for sensors and behavior
- **HFSMAgent Component**: Manages the HFSM for decision-making

The AISystem integrates with:
- **NavMesh System**: For pathfinding and movement
- **Attack System**: For reacting to attacks and threats
- **Skill System**: For reacting to skills
- **Input System**: For processing bot's input commands

## Performance Considerations

The AISystem uses several techniques to optimize performance:
1. **Entity Filtering**: Only processes entities with required components
2. **Sensor Tick Rates**: Each sensor has its own update frequency
3. **Conditional Processing**: Skips logic for inactive or dead bots
4. **Memory Management**: Uses optimized memory access patterns

## Error Handling

The system includes several assertions to check for invalid configurations:
- Null sensor checks
- Tick rate validation
- Component presence validation

## Threading Considerations

The AISystem is designed for Quantum's deterministic single-threaded execution:
- All operations are deterministic to ensure consistent simulation across clients
- Uses Quantum's fixed-point math for consistent results
- Thread safety is ensured by Quantum's frame-based execution model
