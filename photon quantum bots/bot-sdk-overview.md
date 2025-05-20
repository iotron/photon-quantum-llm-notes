# Photon Quantum Bot SDK Overview

## Introduction

The Photon Quantum Bot SDK is a powerful toolset designed for implementing AI agents in multiplayer games. It allows developers to create bots that can fill up rooms when there are not enough players connected and replace players who get disconnected during gameplay.

The Bot SDK is divided into two main parts:
1. A **Visual Editor** created for easily defining and tweaking bot behaviors
2. **Deterministic AI code** that integrates with the Quantum simulation

## Supported AI Models

The Bot SDK supports three major AI programming models:

1. **Hierarchical Finite State Machine (HFSM)** - For state-based AI behaviors
2. **Behavior Tree (BT)** - For more complex decision-making hierarchies
3. **Utility Theory (UT)** - For score-based decision making

## Getting Started with Bot SDK

### Installation
- Bot SDK can be installed via the provided zip packages
- The SDK has two versions: Stable and Development (Circle members only)
- The SDK integrates into the Unity Editor workflow

### Opening the Editor
- Access via: `Window > Bot SDK > Open Editor`
- The editor provides a visual interface for creating and editing AI behaviors

## Key Components of Bot SDK

### 1. Blackboard System
- A data storage system that AI agents can read from and write to
- Provides a centralized way to share information between different parts of the AI
- Can be edited directly in the visual editor

### 2. AI Config
- Allows for different configurations of the same AI model
- Useful for creating variations of bots (e.g., different difficulty levels)

### 3. Debugging Tools
- Built-in debugger for visualizing AI behavior during runtime
- Supports highlighting current states, transitions, and nodes
- Provides real-time information about AI decision-making

## Implementing Bots in a Game

### Replacing Disconnected Players
- Use `PlayerConnectedSystem` with `ISignalOnPlayerConnected` and `ISignalOnPlayerDisconnected`
- Utilize `PlayerInputFlags` to detect player connectivity status
- Setup AI for entities that were controlled by disconnected players

### Filling Rooms with Bots
- Create entities controlled by AI from the start
- Use the difference between expected and connected player counts to determine bot count
- Implement variety by selecting from different bot configurations

### Architecture for Player and Bot Control
1. Systems read inputs from players via `frame.GetPlayerInput(playerIndex)`
2. Bots can use a similar structure: `component Bot { Input Input }`
3. AI systems generate fake inputs based on decision-making logic
4. Character systems process inputs regardless of source (player or bot)

## AI Models in Detail

### Hierarchical Finite State Machine (HFSM)
- Based on states, transitions, and actions
- Hierarchical structure for organizing complex behaviors
- Good for efficient AI with many agents

### Behavior Tree (BT)
- Tree-based structure with Root, Composite, Decorator, and Leaf nodes
- Status-driven execution (Success, Failure, Running)
- Events-driven for responsive behavior
- Good for complex behaviors with moderate amount of agents

### Utility Theory (UT)
- Mathematical model for decision-making
- Uses Response Curves to generate utility scores
- Considerations system for evaluating potential actions
- Good for emergent, score-based behaviors

## Practice Tips
- Use the appropriate AI model for your game needs:
  - HFSM for efficiency and many agents
  - BT for complex logic with moderate agent count
  - UT for score-based decision making
- Combine models if necessary for different aspects of behavior
- Use the debugging tools to visualize and fine-tune AI behavior
- Start simple and iterate your AI designs

## Integration with Quantum
- The AI code runs as part of the deterministic simulation
- All clients run the same AI logic, ensuring consistency
- Bot behaviors are defined using components and systems in Quantum
- Use `BotSDKSystem` to simplify initialization and memory management
