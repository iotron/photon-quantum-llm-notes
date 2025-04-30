# Quantum Platform Shooter 2D Project Overview

This document provides a comprehensive overview of the Quantum Platform Shooter 2D sample project for Photon Quantum 3.0.2. The notes in this directory are structured to help you understand how Quantum works in practice through this sample game.

## Project Structure

The Platform Shooter 2D game demonstrates a multiplayer 2D shooter built with Quantum's deterministic networking framework. The project is organized as follows:

### Core Simulation Code (Quantum)
- **Assets/QuantumUser/Simulation**: Contains all the deterministic simulation code
  - `.qtn` files: Quantum DSL files defining the game state (Character, Bullet, Weapon, etc.)
  - Systems: Implement game logic (Movement, Weapons, Bullets, Skills, etc.)
  - Data classes: Define configuration for game objects

### Unity View Code
- **Assets/PlatformShooter2D/Runtime**: Contains Unity-side view code
  - Character views and animations
  - Visual effects and audio
  - UI elements and HUD
  - Input handling

## Key Features Demonstrated

1. **Character Controller**: Deterministic 2D platformer movement
2. **Weapons System**: Multiple weapon types with different behaviors
3. **Skills System**: Character abilities with cooldowns
4. **Combat**: Projectiles, collision detection, and damage
5. **Respawn System**: Player respawning after death
6. **Input Handling**: Player input collection and processing

## Documentation Structure

The following documents provide detailed breakdowns of the different systems in the Platform Shooter 2D sample:

1. [Game State Definition](01-game-state-definition.md): How game state is defined using Quantum DSL
2. [Character System](02-character-system.md): Player character implementation
3. [Movement System](03-movement-system.md): Character movement and physics
4. [Weapons and Combat](04-weapons-and-combat.md): Weapons, bullets, and damage
5. [Skills System](05-skills-system.md): Character abilities implementation
6. [Unity Integration](06-unity-integration.md): How Unity view connects to Quantum
7. [Input Handling](07-input-handling.md): Input processing workflow

Each document contains code examples that demonstrate Quantum patterns and how they're applied in an actual game.

## Architecture Overview

Quantum Platform Shooter 2D follows Quantum's core architecture principles:

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
- **Entities**: Dynamic game objects (characters, bullets, skills)
- **Components**: Data containers attached to entities
- **Systems**: Logic that processes entities with specific components

### Networking Model

The predict/rollback networking model:
- **Prediction**: Each client predicts game state based on local input
- **Rollback**: When actual input arrives, state is corrected if necessary
- **Determinism**: Same input always produces the same output

## Core Systems Overview

### Player System
- Handles player joining
- Creates character entities
- Links players to characters

### Movement System
- Processes movement input
- Updates character positions
- Manages platformer physics using KCC2D

### Weapon System
- Handles weapon firing
- Manages ammunition and reloading
- Creates bullet entities

### Bullet System
- Updates bullet positions
- Detects collisions using raycasts
- Applies damage on hit

### Skill System
- Handles skill casting
- Creates skill entities
- Applies area effects

### Status System
- Manages character health
- Handles damage application
- Controls death and respawn

## Quantum-Unity Integration

The integration between Quantum and Unity is handled through:
- **Entity Views**: Connect Unity GameObjects to Quantum entities
- **Event Handlers**: Subscribe to Quantum events for visual effects
- **Input Polling**: Capture Unity input for Quantum simulation

## How To Use These Notes

- Start with the Project Overview to understand the game's architecture
- Read through the Game State Definition to see how Quantum DSL is used
- Follow the other documents based on the specific systems you're interested in
- Use the code examples as reference when implementing similar systems

The focus is on presenting accurate, error-free code examples that can be used as templates for your own Quantum projects.
