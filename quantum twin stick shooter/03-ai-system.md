# AI System

This document provides a comprehensive overview of the AI implementation in the Quantum Twin Stick Shooter, explaining how bots make decisions and navigate the game world.

## AI Architecture Overview

The AI system in Twin Stick Shooter consists of several integrated components:

1. **HFSM (Hierarchical Finite State Machine)**: The "brain" for decision making
2. **Context Steering**: The "muscles" that produce movement behaviors
3. **AI Memory**: Time-based storage and recall of game information
4. **AI Sensors**: Perception systems that gather information from the game world
5. **AI Director**: Team-level strategy coordination

This multi-layered approach creates sophisticated and responsive bot behavior.

## Core Components

### Bot Component

```csharp
// From Bot.qtn
component Bot
{
    Boolean IsActive;
    QuantumDemoInputTopDown Input;
}
```

### HFSM Agent

```csharp
// Generated from Bot SDK
component HFSMAgent
{
    asset_ref<AIConfig> Config;
    HFSMData Data;
}
```

### AI Memory

```csharp
// From AIMemory.qtn
component AIMemory
{
    QList<AIMemoryEntry> Entries;
    byte NextEntryIndex;
}
```

### AI Steering

```csharp
// From AISteering.qtn
component AISteering
{
    FPVector2 CurrentDirection;
    FP LerpFactor;
    Boolean IsNavMeshSteering;
    SteeringData MainSteeringData;
    SteeringData ThreatSteeringData;
    SteeringData DesireSteeringData;
    SteeringData AvoidanceSteeringData;
}
```

## AI System Implementation

The `AISystem` is the central controller for bot behavior:

```csharp
[Preserve]
public unsafe class AISystem : SystemMainThreadFilter<AISystem.Filter>, 
    ISignalOnComponentAdded<Bot>, 
    ISignalOnNavMeshMoveAgent,
    ISignalOnGameStart, 
    ISignalOnCreateAttack, 
    ISignalOnCreateSkill
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform2D* Transform;
        public Bot* Bot;
        public Health* Health;
        public AISteering* AISteering;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        if (filter.Bot->IsActive == false)
            return;

        if(filter.Health->IsDead == true)
            return;

        // 1. Update sensors to gather information
        UpdateSensors(frame, filter.Entity);

        // 2. Update movement using context steering
        HandleContextSteering(frame, filter);

        // 3. Update the HFSM for decision making
        HFSMManager.Update(frame, frame.DeltaTime, filter.Entity);
    }
    
    // Other methods...
}
```

## AI Decision Making (HFSM)

The HFSM (Hierarchical Finite State Machine) provides a structured decision-making framework:

```csharp
// Example HFSM setup (simplified)
public static HFSMRoot CreateBotHFSM()
{
    // Create root and main states
    HFSMRoot root = new HFSMRoot();
    
    var idle = root.AddState("Idle");
    var attack = root.AddState("Attack");
    var collect = root.AddState("Collect");
    var escape = root.AddState("Escape");
    var hide = root.AddState("Hide");
    
    // Define transitions between states
    idle.AddTransition(attack, new HasTargetInRange());
    idle.AddTransition(collect, new CollectibleExists());
    attack.AddTransition(escape, new HealthBelowThreshold());
    escape.AddTransition(hide, new FindBushToHide());
    
    // Define behaviors in each state
    idle.SetUpdateAction(new WanderAroundAction());
    attack.SetUpdateAction(new AttackTargetAction());
    collect.SetUpdateAction(new ChaseCollectible());
    escape.SetUpdateAction(new FindEscapeRoute());
    hide.SetUpdateAction(new HideInBush());
    
    return root;
}
```

Each state can contain leaf nodes with specific decision-making logic:

```csharp
// Example of a decision node
public class HasTargetInRange : HFSMDecision
{
    public FP Range = 5;
    
    public override unsafe Boolean Decide(Frame frame, EntityRef entity)
    {
        if (!frame.TryGet(entity, out AIMemory memory))
            return false;
            
        // Check if any detected enemy is within range
        for (int i = 0; i < memory.Entries.Length; i++)
        {
            AIMemoryEntry* entry = &memory.Entries[i];
            if (entry->Type == EMemoryType.Enemy && entry->IsValid)
            {
                FP distanceSq = FPVector2.DistanceSquared(
                    frame.Get<Transform2D>(entity).Position,
                    entry->Position
                );
                
                if (distanceSq <= Range * Range)
                    return true;
            }
        }
        
        return false;
    }
}
```

## AI Memory System

The AI Memory system provides time-based storage and recall of game information:

```csharp
// From MemorySystem.cs (simplified)
[Preserve]
public unsafe class MemorySystem : SystemMainThreadFilter<MemorySystem.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public AIMemory* Memory;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        for (int i = 0; i < filter.Memory->Entries.Length; i++)
        {
            AIMemoryEntry* entry = &filter.Memory->Entries[i];
            
            if (entry->IsValid == false)
                continue;
                
            // Update entry timer
            entry->TTL += frame.DeltaTime;
            
            // Memory becomes available after delay
            if (entry->RecallDelay > 0 && entry->TTL < entry->RecallDelay)
                continue;
                
            // Memory expires after duration
            if (entry->Duration > 0 && entry->TTL >= entry->Duration)
            {
                entry->IsValid = false;
                continue;
            }
            
            // Update entry-specific data
            UpdateMemoryEntryData(frame, filter.Entity, entry);
        }
    }
    
    private void UpdateMemoryEntryData(Frame frame, EntityRef entity, AIMemoryEntry* entry)
    {
        switch (entry->Type)
        {
            case EMemoryType.Enemy:
                UpdateEnemyMemory(frame, entry);
                break;
                
            case EMemoryType.Collectible:
                UpdateCollectibleMemory(frame, entry);
                break;
                
            // Other memory types...
        }
    }
}
```

Memory entries can be added to store information about game entities:

```csharp
// Adding a memory entry (simplified)
public unsafe AIMemoryEntry* AddMemory(Frame frame, EMemoryType type)
{
    // Find first available slot or overwrite oldest
    byte index = NextEntryIndex;
    NextEntryIndex = (byte)((NextEntryIndex + 1) % Entries.Length);
    
    AIMemoryEntry* entry = &Entries[index];
    entry->Type = type;
    entry->IsValid = true;
    entry->TTL = 0;
    
    // Default values based on type
    switch (type)
    {
        case EMemoryType.Enemy:
            entry->RecallDelay = 0;
            entry->Duration = 5;
            break;
            
        case EMemoryType.Collectible:
            entry->RecallDelay = 0;
            entry->Duration = 10;
            break;
            
        // Other types...
    }
    
    return entry;
}
```

## Context Steering

Context Steering calculates movement direction based on weighted influences:

```csharp
// In AISystem.cs (simplified)
private void HandleContextSteering(Frame frame, Filter filter)
{
    // Get final desired direction from weighted influences
    FPVector2 desiredDirection = filter.AISteering->GetDesiredDirection(frame, filter.Entity);

    // Smooth transitions
    filter.AISteering->CurrentDirection = FPVector2.MoveTowards(
        filter.AISteering->CurrentDirection, 
        desiredDirection,
        frame.DeltaTime * filter.AISteering->LerpFactor);

    // Set as bot input
    filter.Bot->Input.MoveDirection = filter.AISteering->CurrentDirection;
}
```

The steering entries contain weighted influence vectors:

```csharp
// SteeringEntry structure (simplified)
public struct SteeringEntry
{
    public FPVector2 Direction;
    public FP Weight;
    public Boolean IsValid;
    
    public void SetData(FPVector2 direction, FP weight = 1)
    {
        Direction = direction.Normalized;
        Weight = weight;
        IsValid = true;
    }
}
```

## AI Sensors

Sensors gather information from the game world:

```csharp
// Base Sensor class (simplified)
public abstract class Sensor
{
    public int TickRate = 5;
    protected int TickCounter;
    
    public virtual void Execute(Frame frame, EntityRef entity)
    {
        TickCounter++;
        if (TickCounter >= TickRate)
        {
            TickCounter = 0;
            Sense(frame, entity);
        }
    }
    
    protected abstract void Sense(Frame frame, EntityRef entity);
}

// Example sensor implementation
public class SensorEnemies : Sensor
{
    public FP DetectionRadius = 10;
    
    protected override void Sense(Frame frame, EntityRef entity)
    {
        TeamInfo agentTeam = frame.Get<TeamInfo>(entity);
        Transform2D agentTransform = frame.Get<Transform2D>(entity);
        
        // Find all characters in detection radius
        var characters = frame.Filter<Character, TeamInfo, Transform2D>();
        while (characters.NextUnsafe(out EntityRef characterEntity, out Character* character, 
               out TeamInfo* characterTeam, out Transform2D* characterTransform))
        {
            // Ignore same team
            if (agentTeam.Index == characterTeam->Index)
                continue;
                
            // Check distance
            FP distanceSq = FPVector2.DistanceSquared(
                agentTransform.Position, 
                characterTransform->Position);
                
            if (distanceSq <= DetectionRadius * DetectionRadius)
            {
                // Add to memory
                AIMemory* memory = frame.Unsafe.GetPointer<AIMemory>(entity);
                AIMemoryEntry* entry = memory->AddMemory(frame, EMemoryType.Enemy);
                entry->EntityRef = characterEntity;
                entry->Position = characterTransform->Position;
            }
        }
    }
}
```

## AI Director

The AI Director coordinates team-level strategy:

```csharp
// AIDirector data structure (simplified)
struct AIDirector
{
    byte TickInterval;
    int TeamIndex;
    AIDirectorMemory Memory;
}

// Director system (simplified)
[Preserve]
public unsafe class AIDirectorSystem : SystemMainThread
{
    public override void Update(Frame frame)
    {
        // Update each team's director
        for (int i = 0; i < 2; i++)
        {
            AIDirector* director = &frame.Global->AIDirectors[i];
            director->TickInterval++;
            
            if (director->TickInterval >= 30)
            {
                director->TickInterval = 0;
                UpdateTeamStrategy(frame, director);
            }
        }
    }
    
    private void UpdateTeamStrategy(Frame frame, AIDirector* director)
    {
        // Count available coins
        int availableCoins = CountAvailableCoins(frame);
        director->Memory.AvailableCoins = (byte)availableCoins;
        
        // Count team members with coins
        int teamMembersWithCoins = CountTeamMembersWithCoins(frame, director->TeamIndex);
        
        // Determine optimal strategy based on game state
        AITactic teamTactic;
        
        if (teamMembersWithCoins > 2)
        {
            teamTactic = AITactic.Defend;
        }
        else if (availableCoins > 5)
        {
            teamTactic = AITactic.Collect;
        }
        else if (GetOpponentCoins(frame, director->TeamIndex) > 8)
        {
            teamTactic = AITactic.Attack;
        }
        else
        {
            teamTactic = AITactic.Balanced;
        }
        
        // Broadcast tactic to team members
        BroadcastTacticToTeam(frame, director->TeamIndex, teamTactic);
    }
}
```

## Bot Creation and Replacement

Players who disconnect are automatically replaced by bots:

```csharp
// In InputSystem.cs (simplified)
private bool IsControlledByAI(Frame frame, Filter filter, int playerRef)
{
    // If player disconnected, convert to bot
    bool playerNotPresent = frame.GetPlayerInputFlags(playerRef).HasFlag(DeterministicInputFlags.PlayerNotPresent);
    if (playerNotPresent && frame.Get<Bot>(filter.Entity).IsActive == false)
    {
        if (frame.IsVerified)
        {
            AISetupHelper.Botify(frame, filter.Entity);
        }
    }
    
    // Check if entity is controlled by bot
    if (frame.TryGet(filter.Entity, out Bot bot) == false)
        return false;
        
    return bot.IsActive;
}
```

The `AISetupHelper.Botify` method configures a character for AI control:

```csharp
// In AISetupHelper.cs (simplified)
public static void Botify(Frame frame, EntityRef entity)
{
    // Activate bot component
    Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
    bot->IsActive = true;
    
    // Setup HFSM
    AIConfig aiConfig = frame.FindAsset<AIConfig>(frame.RuntimeConfig.DefaultBotConfig.Id);
    HFSMRoot hfsmRoot = frame.FindAsset<HFSMRoot>(aiConfig.HFSM.Id);
    HFSMData* hfsmData = frame.Unsafe.AddOrGetPointer<HFSMData>(entity);
    hfsmData->Root = hfsmRoot;
    HFSMManager.Init(frame, hfsmData, entity, hfsmRoot);
    
    // Setup memory
    AIMemory* aiMemory = frame.Unsafe.AddOrGetPointer<AIMemory>(entity);
    aiMemory->Initialize();
    
    // Setup navigation components
    frame.Unsafe.AddComponent<NavMeshPathfinder>(entity);
    frame.Unsafe.AddComponent<NavMeshSteeringAgent>(entity);
    NavMeshPathfinder* pathfinder = frame.Unsafe.GetPointer<NavMeshPathfinder>(entity);
    pathfinder->Settings = aiConfig.NavMeshPathfinderSettings;
    
    // Setup steering
    AISteering* aiSteering = frame.Unsafe.AddOrGetPointer<AISteering>(entity);
    aiSteering->Initialize();
}
```

## Best Practices

1. **Modular AI Components**: Separate decision-making (HFSM), movement (steering), and perception (sensors)
2. **Data-Driven Configuration**: Use assets to define AI behaviors, making them easy to adjust
3. **Reuse Player Systems**: Design AI to work with the same systems as player-controlled characters
4. **Memory-Based Perception**: Use a memory system to store and forget information over time
5. **Hierarchical Decision Making**: Use multiple levels (individual HFSM, team director) for coordination
6. **Context Steering**: Combine multiple weighted influences for natural movement
7. **Seamless Player-Bot Transition**: Design systems to handle player disconnections gracefully

## Implementation Notes

1. The AI uses the same input structure as player-controlled characters
2. Sensors perform periodic updates to reduce computational overhead
3. Memory entries have configurable recall delay and duration
4. Context steering combines influences from goals, obstacles, and threats
5. The AI Director provides team-level strategy coordination
6. All AI calculations are fully deterministic for network consistency