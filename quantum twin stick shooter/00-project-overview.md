# Quantum Twin Stick Shooter Project Overview

This document provides a comprehensive overview of the Quantum Twin Stick Shooter sample project for Photon Quantum 3.0.2. These notes are structured to help you understand how a multiplayer top-down twin stick shooter game is implemented using Quantum's deterministic networking framework.

## Project Structure

The Twin Stick Shooter demonstrates a multiplayer game built with Quantum's deterministic networking framework. The project is organized as follows:

### Core Simulation Code (Quantum)
- **Assets/QuantumUser/Simulation**: Contains all the deterministic simulation code
  - `DSL/*.qtn` files: Quantum DSL files defining the game state
  - `System/*.cs` files: System classes implementing game logic
  - `AI/*.cs` files: AI behaviors and decision making
  - `AssetDefinition/*.cs` files: Define configuration for game objects

### Unity View Code
- **Assets/TwinStickShooter/Scripts**: Contains Unity-side view code
  - Player views and animations
  - Weapon visualizations and effects
  - UI elements and HUD
  - Input handling for different platforms

## Key Features Demonstrated

1. **Top-Down Character Controller**: Deterministic twin-stick movement using Quantum KCC (Kinematic Character Controller)
2. **Skills System**: Data-driven abilities with different behaviors
3. **Bot SDK Integration**: AI-controlled characters using Hierarchical Finite State Machine (HFSM)
4. **Team-Based Gameplay**: Coin collection game mode with team strategy
5. **AI Director**: Team-level strategy management for coordinated AI behavior
6. **Context Steering**: Sophisticated movement behavior for AI characters
7. **Input Handling**: Unified input system for both players and bots
8. **Attributes System**: Character stats and modifiers using a flexible system

## Technical Highlights

### AI Implementation
- **Bot SDK**: Comprehensive use of Quantum's Bot SDK
- **HFSM**: Hierarchical Finite State Machine for AI decision making
- **AI Director**: Team-level coordination of AI characters
- **Data-Driven Sensors**: Configurable perception systems for AI
- **Context Steering**: Multiple weighted vectors for movement decisions
- **AI Memory**: Time-based information storage and recall
- **Bot Replacement**: Automatic replacement of disconnected players with bots

### Game Systems
- **Skill System**: Data-driven abilities with customizable behavior
- **Attributes System**: Flexible stat management with modifiers
- **Team-Based Gameplay**: Coin collection with scoring system
- **Game Flow Management**: HFSM-based game state control
- **Unified Input**: Same input structure used for both players and bots
- **KCC Integration**: Top-down character controller

## Architecture Overview

Quantum Twin Stick Shooter follows Quantum's core architecture principles:

### Simulation-View Separation

```
Simulation (Quantum) → Events → View (Unity)
             ↑           ↓
             └─ Input ───┘
```

- **Simulation**: Deterministic game logic running in Quantum
- **View**: Visual representation in Unity
- **Events**: One-way communication from simulation to view
- **Input**: Player commands sent from view to simulation

### ECS Implementation

The game uses Quantum's Entity Component System:
- **Entities**: Dynamic game objects (characters, skills, attacks)
- **Components**: Data containers attached to entities
- **Systems**: Logic that processes entities with specific components

### Networking Model

The predict/rollback networking model:
- **Prediction**: Each client predicts game state based on local input
- **Rollback**: When actual input arrives, state is corrected if necessary
- **Determinism**: Same input always produces the same output

## Core Systems Overview

### Movement System
- Processes player/bot input
- Controls character movement using KCC
- Handles movement locks during attacks

### Input System
- Handles input from players
- Switches to bot input when players disconnect
- Provides unified input structure for both players and bots

### AI System
- Manages HFSM updates for bot decision making
- Handles context steering for movement
- Updates AI sensors based on game state

### Skills System
- Implements character abilities
- Manages skill activation, updates, and deactivation
- Handles skill effects and attacks

### Attributes System
- Manages character stats (health, speed, etc.)
- Processes modifiers and effects
- Provides a flexible framework for character customization

### Game Manager System
- Controls overall game flow using HFSM
- Manages game states (character selection, playing, game over)
- Handles match timing and victory conditions

## Game Modes

The main game mode is **Coin Grab**:
- Teams collect coins scattered around the map
- The first team to accumulate and maintain 10+ coins for 15 seconds wins
- Strategic elements involve both offensive and defensive play
- AI Director manages team strategies based on game state

## Characters

The game features 3 unique character types:
- Each character has unique stats and abilities
- Each character has 2 skills (basic and special)
- Character selection phase at the beginning of matches
- Character-specific attributes affect gameplay

## Code Examples and Usage Guidelines

The documentation provides accurate, error-free code examples that can be directly used as templates for your own Quantum multiplayer projects. Follow these guidelines:

1. Start with the Project Overview to understand the game's architecture
2. Examine specific systems based on your implementation needs
3. Use the provided code examples as a reference for your own implementation
4. Pay special attention to the data-driven architecture for skills and AI