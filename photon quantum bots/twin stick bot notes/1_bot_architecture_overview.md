# Twin Stick Shooter Bot Architecture Overview

This document provides a high-level overview of the bot system architecture in the Photon Quantum twin stick shooter game.

## Core Architecture Components

The bot system in the twin stick shooter game follows a modular architecture with these key components:

1. **Brain (HFSM)**: The Hierarchical Finite State Machine handles all decision-making
2. **Muscles (Steering)**: Context Steering handles movement based on desires, threats, and obstacles
3. **Senses (Sensors)**: Multiple sensor systems gather information about the game state
4. **Memory (Blackboard & AIMemory)**: Dual memory systems for both immediate and persistent information

## Component Relationships

```
                    ┌─────────────────┐
                    │                 │
                    │    AISystem     │
                    │                 │
                    └────────┬────────┘
                             │
           ┌────────────────┼────────────────┐
           │                │                │
┌──────────▼─────────┐ ┌────▼─────┐ ┌────────▼──────────┐
│                    │ │          │ │                    │
│  HFSMManager       │ │ Steering │ │ Sensors            │
│  (Decision-making) │ │ (Movement)│ │ (Perception)      │
│                    │ │          │ │                    │
└──────────┬─────────┘ └────┬─────┘ └────────┬──────────┘
           │                │                │
           │         ┌──────▼────────────────▼────┐
           │         │                             │
┌──────────▼─────────┐                 ┌───────────▼────────┐
│                    │                 │                     │
│  AIBlackboard      │◄────────────────┤ AIMemory           │
│  (Short-term)      │                 │ (Long-term)        │
│                    │                 │                     │
└────────────────────┘                 └─────────────────────┘
```

## Component Responsibilities

### Bot Component
The core Bot component serves as the main container for bot behavior:
- Contains input data (movement direction, attack commands)
- References configuration assets (HFSM, blackboard initializer, etc.)
- Tracks whether the bot is active

### AISystem
The AISystem drives the entire bot behavior chain:
- Updates sensors at their configured tick rates
- Processes movement through context steering
- Updates HFSM for decision making
- Reacts to game events (attacks, skills, etc.)

### HFSM Decision Making
The Hierarchical Finite State Machine provides structured decision making:
- Uses a tree of states for complex behaviors
- Transitions between states based on conditions
- Each state can execute specific actions
- States can contain sub-states (hierarchical structure)

### Context Steering
The steering system handles all movement:
- Can use either NavMesh-based steering or direct context steering
- Processes threats and obstacles for avoidance
- Handles randomized evasion for natural movement
- Manages targeting and engagement

### Sensors
Multiple sensor systems gather information:
- SensorEyes: Detects visible entities
- SensorHealth: Monitors health state
- SensorCollectibles: Finds and evaluates pickups
- SensorThreats: Detects and evaluates dangers
- SensorTactics: Evaluates tactical options

### Memory Systems
Two complementary memory systems:
- Blackboard: Short-term memory for HFSM decision making
- AIMemory: Long-term memory for tracking threats and other information

## Bot Lifecycle

1. **Creation**: AISetupHelper creates a bot from a prototype
2. **Initialization**: Bot is set up with NavMesh, Blackboard, and HFSM components
3. **Sensing**: Sensors gather information at configured tick rates
4. **Decision**: HFSM processes the current state and decides actions
5. **Action**: Movement and attack decisions are applied to the Bot's input
6. **Execution**: Movement and combat systems process the bot's input

## Performance Considerations

The bot system is designed with performance in mind:
- Sensors operate at different tick rates to distribute processing
- SystemMainThreadFilter efficiently processes only relevant entities
- NavMesh queries are used sparingly and efficiently
- Memory is managed with pooled lists and preallocated memory
