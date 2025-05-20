# Bot Setup and Management

This document details how bots are created, configured, and managed in the twin stick shooter game.

## AISetupHelper Class

The AISetupHelper class is responsible for creating and managing bots:

```csharp
public unsafe static class AISetupHelper
{
    public static void FillWithBots(Frame frame) { /* Implementation */ }
    public static void CreateBot(Frame frame, PlayerRef playerRef, int teamId) { /* Implementation */ }
    public static void Botify(Frame frame, EntityRef entity) { /* Implementation */ }
    public static void Debotify(Frame frame, EntityRef entity) { /* Implementation */ }
}
```

This static class provides methods for:
- Filling empty player slots with bots
- Creating individual bots
- Converting existing entities into bots
- Removing bot capabilities from entities

## Bot Creation and Room Filling

### FillWithBots

```csharp
public static void FillWithBots(Frame frame)
{
    // for each team, have an integer with max players count
    // for every character, subtract from those integers based on player connectivity and their team ids
    // with the remnant integers, create bots and set teams

    List<int> neededPlayerRefs = new List<int>() { 1, 2, 3, 4, 5, 6 };
    int neededBotsTeamA = 3;
    int neededBotsTeamB = 3;

    for (int i = 0; i < frame.PlayerCount; i++)
    {
        var playerLinks = frame.Filter<PlayerLink, TeamInfo>();
        while(playerLinks.Next(out EntityRef entity, out PlayerLink playerLink, out TeamInfo teamInfo))
        {
            if(playerLink.PlayerRef == i)
            {
                if(teamInfo.Index == 0)
                {
                    neededBotsTeamA -= 1;
                }
                else
                {
                    neededBotsTeamB -= 1;
                }

                neededPlayerRefs.Remove(i);
            }
        }
    }

    for (int i = 0; i < neededBotsTeamA; i++)
    {
        int randomIndex = frame.RNG->Next(0, neededPlayerRefs.Count);
        CreateBot(frame, neededPlayerRefs[randomIndex], 0);
        neededPlayerRefs.RemoveAt(randomIndex);
    }

    for (int i = 0; i < neededBotsTeamB; i++)
    {
        int randomIndex = frame.RNG->Next(0, neededPlayerRefs.Count);
        CreateBot(frame, neededPlayerRefs[randomIndex], 1);
        neededPlayerRefs.RemoveAt(randomIndex);
    }
}
```

This method fills empty player slots with bots:
1. Determines how many bots are needed for each team
2. Assigns available player reference indices to bots
3. Creates bots for each team with random player references

### CreateBot

```csharp
public static void CreateBot(Frame frame, PlayerRef playerRef, int teamId)
{
    int randomBotId = frame.RNG->Next(0, frame.RuntimeConfig.RoomFillBots.Length);
    var botPrototype = frame.RuntimeConfig.RoomFillBots[randomBotId];

    EntityRef botCharacter = frame.Create(botPrototype);

    // Store it's PlayerRef so we can later use it for input polling
    PlayerLink* playerLink = frame.Unsafe.GetPointer<PlayerLink>(botCharacter);
    playerLink->PlayerRef = playerRef;

    // Save the character's team, also defined on the Menu
    TeamInfo* teamInfo = frame.Unsafe.GetPointer<TeamInfo>(botCharacter);
    teamInfo->Index = teamId;

    // Spawn the character
    frame.Signals.OnRespawnCharacter(botCharacter, true);

    Botify(frame, botCharacter);
}
```

This method creates a single bot:
1. Selects a random bot prototype from the runtime configuration
2. Creates an entity from the prototype
3. Assigns a player reference and team ID
4. Spawns the character in the game
5. Calls Botify to add AI components

## Bot Component Setup

### Botify

```csharp
public static void Botify(Frame frame, EntityRef entity)
{
    Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);

    // -- NAVMESH
    var agentConfig = frame.FindAsset<NavMeshAgentConfig>(bot->NavMeshAgentConfig);
    var navMeshPathfinder = NavMeshPathfinder.Create(frame, entity, agentConfig);
    frame.Add<NavMeshPathfinder>(entity, navMeshPathfinder);
    //frame.AddOrGet<NavMeshPathfinder>(entity, out var pathfinder);
    //pathfinder->SetConfig(frame, entity, bot->NavMeshAgentConfig);

    if (frame.Has<NavMeshSteeringAgent>(entity) == false)
    {
        frame.Add<NavMeshSteeringAgent>(entity);
    }

    if (frame.Has<NavMeshAvoidanceAgent>(entity) == false)
    {
        frame.Add<NavMeshAvoidanceAgent>(entity);
    }

    // -- BLACKBOARD
    frame.Add<AIBlackboardComponent>(entity, out var blackboardComponent);
    var blackboardInitializer = frame.FindAsset<AIBlackboardInitializer>(bot->BlackboardInitializer.Id);
    AIBlackboardInitializer.InitializeBlackboard(frame, blackboardComponent, blackboardInitializer);

    // -- HFSM AGENT
    frame.Add<HFSMAgent>(entity, out var hfsmAgent);
    HFSMRoot hfsmRoot = frame.FindAsset<HFSMRoot>(bot->HFSMRoot.Id);
    HFSMManager.Init(frame, entity, hfsmRoot);
    hfsmAgent->Config = bot->AIConfig;

    bot->IsActive = true;

    Quantum.BotSDK.BotSDKDebuggerSystem.AddToDebugger<HFSMAgent>(frame, entity, *hfsmAgent);
}
```

This method adds AI components to an entity:
1. Sets up NavMesh components for pathfinding and movement
2. Adds an AIBlackboardComponent and initializes it
3. Adds an HFSMAgent and initializes it with the configured HFSM
4. Sets the bot's IsActive flag to true
5. Adds the bot to the debugger for monitoring

### Debotify

```csharp
public static void Debotify(Frame frame, EntityRef entity)
{
    frame.Remove<NavMeshPathfinder>(entity);
    frame.Remove<NavMeshSteeringAgent>(entity);
    frame.Remove<NavMeshAvoidanceAgent>(entity);

    frame.Unsafe.GetPointer<AIBlackboardComponent>(entity)->Free(frame);
    frame.Remove<AIBlackboardComponent>(entity);

    frame.Remove<HFSMAgent>(entity);

    frame.Unsafe.GetPointer<Bot>(entity)->IsActive = false;
}
```

This method removes AI components from an entity:
1. Removes NavMesh components
2. Frees and removes the AIBlackboardComponent
3. Removes the HFSMAgent
4. Sets the bot's IsActive flag to false

## Bot Component

```csharp
public unsafe struct Bot
{
    public Input Input;
    public DynamicAssetRef<NavMeshAgentConfig> NavMeshAgentConfig;
    public AssetRef BlackboardInitializer;
    public AssetRef HFSMRoot;
    public DynamicAssetRef<AIConfig> AIConfig;
    public bool IsActive;
}

public unsafe struct Input
{
    public FPVector2 MoveDirection;
    public FPVector2 AimDirection;
    public bool Attack;
    public bool SpecialAttack;
    public bool Jump;
    public bool Dash;
}
```

The Bot component contains:
- Input data for movement and actions
- References to configuration assets
- An IsActive flag to enable/disable bot behavior

## Runtime Configuration

```csharp
public partial class RuntimeConfig
{
    public EntityPrototype[] RoomFillBots;
}
```

The RuntimeConfig class contains an array of bot prototypes that can be used to fill empty player slots.

## Bot Prototype Asset

Bot prototypes are EntityPrototype assets that define the initial state of a bot:

```csharp
[CreateAssetMenu(menuName = "Quantum/EntityPrototype/Bot")]
public class BotPrototype : EntityPrototype
{
    public override unsafe EntityRef Create(Frame frame)
    {
        EntityRef entity = frame.Create();
        
        // Add basic components
        frame.Add<Transform2D>(entity);
        frame.Add<PhysicsCollider2D>(entity);
        frame.Add<Character>(entity);
        frame.Add<Health>(entity);
        frame.Add<TeamInfo>(entity);
        frame.Add<PlayerLink>(entity);
        
        // Add bot-specific components
        frame.Add<Bot>(entity, out var bot);
        bot->NavMeshAgentConfig = NavMeshAgentConfig;
        bot->BlackboardInitializer = BlackboardInitializer;
        bot->HFSMRoot = HFSMRoot;
        bot->AIConfig = AIConfig;
        bot->IsActive = false; // Will be activated by Botify
        
        frame.Add<AISteering>(entity, out var steering);
        steering->LerpFactor = FP._5;
        steering->MainSteeringWeight = FP._1;
        steering->MaxEvasionDuration = FP._1;
        
        // Add other components
        
        return entity;
    }
    
    // Configuration assets
    public DynamicAssetRef<NavMeshAgentConfig> NavMeshAgentConfig;
    public AssetRef BlackboardInitializer;
    public AssetRef HFSMRoot;
    public DynamicAssetRef<AIConfig> AIConfig;
}
```

The BotPrototype asset defines:
1. The basic components required for a character
2. Bot-specific components and their initial configuration
3. References to other assets for bot configuration

## Bot Integration with Game Systems

### Integration with Player Joining

Bots are created when the game starts or when players leave:

```csharp
public class PlayerJoiningSystem : SystemMainThread, ISignalOnPlayerConnected, ISignalOnPlayerDisconnected
{
    public void OnPlayerConnected(Frame frame, PlayerRef playerRef)
    {
        // Create a player character
    }
    
    public void OnPlayerDisconnected(Frame frame, PlayerRef playerRef)
    {
        // Handle disconnection
        // Potentially replace with a bot
        var playerEntities = frame.Filter<PlayerLink>();
        while(playerEntities.Next(out EntityRef entity, out PlayerLink playerLink))
        {
            if(playerLink.PlayerRef == playerRef)
            {
                // Option 1: Remove the character
                frame.Destroy(entity);
                
                // Option 2: Convert to a bot
                AISetupHelper.Botify(frame, entity);
            }
        }
    }
}
```

### Integration with Game Start

Bots are created when the game starts if there aren't enough players:

```csharp
public class GameManagerSystem : SystemMainThread, ISignalOnGameStart
{
    public void OnGameStart(Frame frame)
    {
        // Fill empty slots with bots
        AISetupHelper.FillWithBots(frame);
        
        // Other game start logic
    }
}
```

## Bot Difficulty Configuration

The twin stick shooter implements different difficulty levels for bots:

```csharp
[CreateAssetMenu(menuName = "Quantum/AI/BotDifficulty")]
public class BotDifficultyConfig : AssetObject
{
    [Serializable]
    public struct DifficultySettings
    {
        public string Name;
        public FP AimAccuracy;
        public FP ReactionTime;
        public FP AggressionFactor;
        public FP DodgeProbability;
    }
    
    public DifficultySettings[] DifficultyLevels;
    
    public DifficultySettings GetDifficultySettings(int level)
    {
        return DifficultyLevels[Mathf.Clamp(level, 0, DifficultyLevels.Length - 1)];
    }
}
```

This configuration allows different difficulty levels to be defined and applied to bots.

## Bot Debugging

The twin stick shooter includes debugging tools for bots:

```csharp
public static class BotSDKDebuggerSystem
{
    public static void AddToDebugger<T>(Frame frame, EntityRef entity, T component) where T : struct
    {
        // Implementation
    }
    
    public static void RemoveFromDebugger(Frame frame, EntityRef entity)
    {
        // Implementation
    }
}
```

These tools allow developers to monitor bot behavior and state during gameplay.

## Integration with Unity Editor

The bot system integrates with the Unity Editor for configuration:

```csharp
[CustomEditor(typeof(BotPrototype))]
public class BotPrototypeEditor : Editor
{
    public override void OnInspectorGUI()
    {
        // Display and edit bot prototype properties
    }
}

[CustomEditor(typeof(AIConfig))]
public class AIConfigEditor : Editor
{
    public override void OnInspectorGUI()
    {
        // Display and edit AI configuration
    }
}

[CustomEditor(typeof(HFSMRoot))]
public class HFSMRootEditor : Editor
{
    public override void OnInspectorGUI()
    {
        // Display and edit HFSM structure
    }
}
```

These editor integrations allow designers to configure bot behavior without writing code.

## Bot Game Flow

### Spawning

1. Bots are created either at game start or when replacing disconnected players
2. The bot prototype is instantiated
3. Botify is called to add AI components
4. The bot is spawned in the game world

### Updates

1. The AISystem updates all bot sensors, HFSM, and steering
2. Sensors gather information about the game state
3. The HFSM makes decisions based on sensor data
4. Steering controls the bot's movement
5. Input commands are executed by standard game systems

### Destruction

1. Bots are destroyed when they die or when the game ends
2. Debotify is called to clean up AI components
3. Standard entity destruction handles the rest

This structured approach to bot management ensures that bots are properly integrated into the game and can be created, updated, and destroyed as needed.
