# Twin Stick Shooter Bot Implementation

## Overview

The Twin Stick Shooter sample is a comprehensive example of how to implement the Quantum Bot SDK in a multiplayer game. It showcases various AI techniques in a top-down shooter environment, with bots that can fill empty player slots and replace disconnected players.

## Key AI Features

### Bot SDK Integration

- **HFSM as Character "Brain"**: Uses Hierarchical Finite State Machine for main bot decision-making
- **Player Replacement**: Seamlessly takes over for disconnected players
- **Room Filling**: Automatically adds bots to reach the desired player count
- **Named Bots**: Pulls random names from a text file for bot identification

### Input Architecture

- **Unified Input Structure**: Both player and bot-controlled characters use the same input data structure
- **Input Polling System**: Cleanly separates input source from character control
- **Input Application**: Character systems process inputs regardless of source

![Input Polling System](/docs/img/quantum/v2/game-samples/twin-stick-shooter/Polling%20Input.jpg)

### AI Building Blocks

The AI system is composed of several key components working together:

1. **Sensors**: Data-driven perception system that detects game elements
2. **Tactical AI**: Decision-making for individual character actions
3. **AIMemory**: Time-delayed storage and retrieval of information
4. **AI Director**: Team-level strategy coordination

![AI Building Blocks](/docs/img/quantum/v2/game-samples/twin-stick-shooter/The%20AI%20building%20blocks.jpg)

## Implementation Details

### Character Control System

- **Top-Down KCC (Kinematic Character Controller)**: Handles movement and collision
- **Context Steering**: Evaluates multiple movement desires to produce final direction
- **Attribute System**: Uses a union-based approach for character stats

### AI Sensor System

The sensor system provides a data-driven approach to perception:
- Separate sensors for different detection needs (enemies, items, dangers)
- Configurable parameters for detection range, angle, and priority
- Results fed into decision-making systems

### AI Memory

- Introduces realistic limitations to bot knowledge
- Information becomes available after a delay (simulating reaction time)
- Information expires after a period (simulating forgetfulness)
- Creates more natural, human-like behavior

### Team Strategy via AI Director

- Central system that analyzes team performance
- Assigns roles and strategies to individual bots
- Coordinates group behavior toward game objectives
- Adapts strategy based on game state

![Strategy and Tactics](/docs/img/quantum/v2/game-samples/twin-stick-shooter/Strategy%20and%20Tactics.jpg)

### Game Manager HFSM

- Controls game flow and state transitions
- Manages game mode rules and victory conditions
- Handles round start/end and scoring
- Example of using HFSM for systems beyond character control

![Game Management](/docs/img/quantum/v2/game-samples/twin-stick-shooter/Game%20Management.jpg)

## Level Design Integration

- **Custom marker system**: Special points in levels for bot guidance
- **Navigation mesh usage**: Bots use Quantum's navigation system for pathfinding
- **Strategic positions**: Cover points, ambush locations, item spawn locations

## Implementation Highlights

### Bot Creation Code

```csharp
// Example of bot creation (simplified)
private void CreateBot(Frame frame) {
  // Create entity from prototype
  var botEntity = frame.Create();
  
  // Add HFSM agent component
  var hfsmAgent = new HFSMAgent();
  frame.Set(botEntity, hfsmAgent);
  
  // Initialize the HFSM with the appropriate root
  var hfsmRoot = frame.FindAsset<HFSMRoot>(botBrainAsset.Id);
  HFSMManager.Init(frame, botEntity, hfsmRoot);
  
  // Add bot component to flag entity as AI-controlled
  frame.Set(botEntity, new BotFlag());
  
  // Add fake player data
  var botPlayerData = GetRandomBotData();
  frame.Set(botEntity, new PlayerData { 
    Name = botPlayerData.Name,
    Team = GetBalancedTeam(frame)
  });
}
```

### Player Replacement System

```csharp
// Example of player replacement logic (simplified)
public void OnPlayerDisconnected(Frame frame, PlayerRef player) {
  // Find the entity controlled by this player
  var entity = FindEntityForPlayer(frame, player);
  if (entity == EntityRef.None) return;
  
  // Add HFSM agent component
  var hfsmAgent = new HFSMAgent();
  frame.Set(entity, hfsmAgent);
  
  // Initialize the HFSM with the appropriate root
  var hfsmRoot = frame.FindAsset<HFSMRoot>(botBrainAsset.Id);
  HFSMManager.Init(frame, entity, hfsmRoot);
  
  // Flag entity as bot-controlled
  frame.Set(entity, new BotFlag());
  
  // Keep player data intact for potential reconnection
}
```

## Lessons from the Implementation

1. **Unified Input System**: Separating input from processing simplifies bot integration
2. **Layered AI**: Using different systems for tactics, strategy, and game management
3. **Data-Driven Approach**: Configuration-based systems for flexibility
4. **Memory Systems**: Introducing limitations creates more natural behavior
5. **Debugging Tools**: Using Bot SDK's debugger was crucial for development

## Performance Considerations

- HFSM was chosen for efficiency with multiple bots
- Sensor calculations are optimized to run only when needed
- Context steering calculations are streamlined for minimal processing
- AI Director updates less frequently than individual bot AI
