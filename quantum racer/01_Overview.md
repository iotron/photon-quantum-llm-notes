# Quantum Racer 2.5D Overview

## Game Description
Quantum Racer 2.5D is a multiplayer racing game built with Photon Quantum, supporting up to 99 players. It's a retro-style racer with arcade physics, featuring:

- Different vehicle types with unique stats
- Varied surface types with different driving conditions
- AI drivers with adjustable difficulty
- Full race loop: Ready check, Countdown, Race, Scoreboard
- Lap tracking, timing, and position systems
- Joystick support

## Technical Information
- Built with Unity 2021.3.37f1
- Platforms: PC (Windows/Mac)
- Version: 3.0.2 (Build 604)
- Release Date: March 19, 2025

## Key Controls
- **W**: Accelerate
- **S**: Brake
- **A/D**: Turn left/right
- **J/L**: Lean sideways
- **I/K**: Lean front/back during flights

## Project Structure
The game is organized into several key directories:

1. **Assets/QuantumUser/Simulation**: Core game logic
   - **Racer**: Main game-specific code
   - **Modifiers**: Special effects like boosters, jumps, etc.

2. **Assets/QuantumUser/View**: Client-side visualization
   - **Racer**: UI and camera systems
   
3. **Assets/QuantumUser/Resources**: Game configurations
   - **Racer/CarSpecs**: Vehicle configurations
   - **Racer/Modifiers**: Effect assets
   - **Racer/Bots**: AI configuration

4. **Assets/Photon**: Quantum networking framework

## Core Game Concepts
- **Racer Component**: Main vehicle component
- **RaceManager**: Singleton managing race state
- **Bot System**: AI implementation
- **Checkpoint System**: Track progress tracking
- **Modifiers**: Special effects on the track

## Multiplayer Features
- Full online multiplayer using Photon Quantum
- Support for up to 99 players
- Deterministic physics simulation
- Bot players to fill empty slots

## Game Highlights
- Arcade racing physics
- Different vehicles with unique stats
- Lap and time tracking
- Position in race grid
- Various modifiers affecting gameplay
