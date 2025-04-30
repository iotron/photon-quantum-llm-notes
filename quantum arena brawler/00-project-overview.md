# Quantum Arena Brawler Project Overview

This document provides a comprehensive overview of the Quantum Sports Arena Brawler sample project for Photon Quantum 3.0.3. The notes in this directory are structured to help you understand how Quantum works in practice through this sample game.

## Game Description

Quantum Sports Arena Brawler is a top-down 3v3 sports arena brawler where players:
- Pass the ball between teammates
- Punch opponents off the arena
- Score goals against the enemy team

The game is designed for fast-paced multiplayer action supporting up to 6 players, with up to 4 local players via split screen. It implements various gameplay techniques to ensure smooth multiplayer experience even at higher pings.

## Technical Information
- Built with Unity 2021.3.18f1
- Platforms: PC (Windows/Mac)
- Quantum version: 3.0.3 (Build 642)

## Project Structure

The game is organized into these key directories:

### Simulation Code (Quantum)
- **Assets/QuantumUser/Simulation/Quantum Sports Arena Brawler**: Contains the deterministic simulation code
  - **DSL**: QTN files defining game state (Ability, Ball, Player, etc.)
  - **Systems**: Implement game logic (Abilities, Ball handling, Player movement, etc.)
  - **Assets**: Define configuration for game objects and abilities

### Unity View Code
- **Assets/SportsArenaBrawler/Scripts**: Contains Unity-side view code
  - **Ball**: Ball visualization
  - **Player**: Player visualization and controllers
  - **Local Player**: Multi-local player management
  - **UI**: Game interface
  - **Effects**: Visual effects system

## Key Features Demonstrated

1. **Multiple Local Players**
   - Split-screen support for up to 4 local players
   - Automatic input device assignment
   - Custom lobby filtering based on local player count

2. **Data-Driven Ability System**
   - Input buffering for smoother gameplay
   - Activation delay to prevent mispredictions in multiplayer
   - Different ability sets based on ball possession

3. **Advanced Ball Physics**
   - Custom interpolation for fast-moving ball
   - Adaptive gravity scaling for varied throw styles
   - Lateral friction for controlled ball movement

4. **Character Controller**
   - Dynamic KCC configuration changes based on player state
   - "Coyote time" mechanic for better platforming feel
   - Momentum preservation during abilities

5. **Status Effects System**
   - Stun and knockback implementation
   - Recovery mechanics

6. **Game State Management**
   - Complete game loop (starting, running, scoring, game over)
   - Score tracking
   - Team mechanics

## Documentation Structure

The following documents provide detailed breakdowns of the different systems in the Quantum Arena Brawler sample:

1. [Game State Definition](01-game-state-definition.md): Core QTN state definitions
2. [Ability System](02-ability-system.md): Data-driven ability implementation
3. [Ball Handling System](03-ball-handling-system.md): Ball physics and interactions
4. [Player System](04-player-system.md): Player controllers and status
5. [Game Flow Management](05-game-flow-management.md): Game states and scoring
6. [Local Multiplayer](06-local-multiplayer.md): Split-screen implementation
7. [View Integration](07-view-integration.md): Quantum-Unity integration

Each document contains code examples that demonstrate Quantum patterns and how they're applied in this game.
