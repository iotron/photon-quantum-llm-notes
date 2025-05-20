# Photon Quantum Overview

Photon Quantum is a deterministic networking engine for real-time multiplayer games, designed to work with Unity. Its architecture is built around a deterministic simulation model, which means that identical inputs will produce identical outputs on all connected clients, making it ideal for fast-paced multiplayer games that require high precision and low latency.

## Core Concepts

### Deterministic Simulation

Quantum's core feature is its deterministic simulation engine:

- All game logic runs in a deterministic environment
- Fixed timesteps ensure consistent behavior across different devices
- Input is collected and synchronized across all clients
- Rollback and prediction are used to handle latency

### Component Architecture

Quantum uses a component-based architecture:

- Entities are containers for components
- Components store game state data
- Systems process entities with specific component combinations
- Signals provide a decoupled communication mechanism between systems

### Frame Structure

The Frame is the central object in Quantum:

- Contains all game state at a specific point in time
- Manages the entity registry
- Provides access to physics, navigation, and other subsystems
- Handles serialization for network transmission and rollback

### Prediction and Rollback

To handle network latency, Quantum employs prediction and rollback:

- Local clients predict game state based on local input
- When authoritative input arrives from the server, the simulation rolls back if necessary
- Prediction culling optimizes performance by only predicting relevant parts of the game

## Project Structure

The quantum-starter-3.0.3 project is organized as follows:

1. `/Assets/Photon/Quantum` - Core Quantum framework files
   - `/Assemblies` - Compiled assemblies for the Quantum engine
   - `/Editor` - Unity editor integration
   - `/Runtime` - Unity-side runtime code for Quantum
   - `/Simulation` - Core simulation code (deterministic game logic)

2. `/Assets/Common` - Shared code for all sample games
   - `/Scripts` - Unity-side scripts for input, UI, etc.
   - `/Simulation` - Quantum simulation code (systems, components)

3. Sample games
   - `/Assets/00_MainMenu` - Main menu scene and code
   - `/Assets/01_ThirdPersonCharacter` - Third-person character controller sample
   - `/Assets/02_Platformer` - Platformer game sample
   - `/Assets/03_Shooter` - Shooter game sample

4. `/Assets/QuantumUser` - User-specific Quantum code
   - `/Editor` - Custom editor scripts
   - `/Simulation` - Custom simulation code
   - `/View` - View components for connecting Unity objects to Quantum entities

## Key Files and Their Purpose

- `QuantumRunnerBehaviour.cs` - Unity MonoBehaviour that updates the Quantum simulation
- `QuantumRunnerLocalDebug.cs` - Helper for debugging Quantum in a local environment
- `Frame.cs` - The core simulation state container
- `QuantumEntityView.cs` - Connects Unity GameObjects to Quantum entities
- `QuantumSimulationCore.cs` - Core simulation engine
- `RuntimeConfig.cs` - Game-specific configuration
- `MovementSystem.cs` - Example system for handling character movement

In the following documents, we'll dive deeper into each of these key aspects of the Quantum framework.
