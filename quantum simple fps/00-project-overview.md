# Quantum Simple FPS 3.0.0 Project Overview

This document provides a comprehensive overview of the Quantum Simple FPS sample project for Photon Quantum 3.0.0. These notes are structured to help you understand how a multiplayer FPS game is implemented using Quantum's deterministic networking framework.

## Project Structure

The Simple FPS game demonstrates a multiplayer first-person shooter built with Quantum's deterministic networking framework. The project is organized as follows:

### Core Simulation Code (Quantum)
- **Assets/QuantumUser/Simulation**: Contains all the deterministic simulation code
  - `.qtn` files: Quantum DSL files defining the game state
  - System classes: Implement game logic (Player, Weapons, Health, Gameplay)
  - Asset classes: Define configuration for game objects

### Unity View Code
- **Assets/Scripts**: Contains Unity-side view code
  - Player views and animations
  - Weapon models and visual effects
  - UI elements and HUD
  - Input handling for different platforms

## Key Features Demonstrated

1. **FPS Character Controller**: Deterministic first-person movement using Quantum KCC
2. **Weapons System**: Multiple weapon types with different behaviors
3. **Damage System**: Raycast-based shooting with hit detection
4. **Lag Compensation**: Historical state buffering for fair hit detection
5. **Player Respawn System**: Player respawning after death
6. **Match Flow**: Game state management, including skirmish and game phases
7. **Input Handling**: Player input collection and processing

## Documentation Structure

The following documents provide detailed breakdowns of the different systems in the Simple FPS sample:

1. [Input System](01-input-system.md): How player input is defined and processed
2. [Player System](02-player-system.md): Character movement and controls
3. [Weapons System](03-weapons-system.md): Weapons, firing mechanics, and damage
4. [Health System](04-health-system.md): Health management and damage application
5. [Gameplay System](05-gameplay-system.md): Game state, respawning, and statistics
6. [Lag Compensation](06-lag-compensation.md): Techniques for fair hit detection
7. [Pickups System](07-pickups-system.md): Item collection mechanics

Each document contains code examples that demonstrate Quantum patterns and how they're applied in an actual game.

## Architecture Overview

Quantum Simple FPS follows Quantum's core architecture principles:

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
- **Entities**: Dynamic game objects (players, weapons, pickups)
- **Components**: Data containers attached to entities
- **Systems**: Logic that processes entities with specific components

### Networking Model

The predict/rollback networking model:
- **Prediction**: Each client predicts game state based on local input
- **Rollback**: When actual input arrives, state is corrected if necessary
- **Determinism**: Same input always produces the same output
- **Lag Compensation**: Historical state buffering for fair hit detection

## Core Systems Overview

### Player System
- Processes player input
- Controls character movement using KCC
- Manages player spawning and linking

### Weapons System
- Handles weapon switching
- Implements firing mechanics
- Manages ammo and reloading
- Performs hit detection using raycasts

### Health System
- Tracks player health
- Handles damage application
- Manages temporary immortality after spawn

### Gameplay System
- Controls game state (skirmish, running, finished)
- Manages player respawning
- Tracks player statistics (kills, deaths)
- Handles match flow and win conditions

### Lag Compensation System
- Buffers historical transform data
- Creates proxy entities for lag-compensated shots
- Ensures fair hit detection regardless of network conditions

## How To Use These Notes

- Start with the Project Overview to understand the game's architecture
- Read the Input System documentation to see how player actions are captured
- Follow other documents based on specific systems you're interested in
- Use the code examples as reference when implementing similar systems

The focus is on presenting accurate, error-free code examples that can be directly used as templates for your own Quantum FPS projects.
