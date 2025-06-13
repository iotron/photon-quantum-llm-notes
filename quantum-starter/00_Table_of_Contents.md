# Quantum Starter - Table of Contents

Complete guide to Photon Quantum 3 fundamentals with comprehensive coverage of all core systems.

## Core Concepts (Chapters 1-7)

### 1. [Quantum Overview](01_Quantum_Overview.md)
- Introduction to deterministic multiplayer
- Architecture overview
- Key concepts and terminology
- Quantum vs traditional networking

### 2. [Entity Component System](02_Entity_Component_System.md)
- ECS architecture in Quantum
- Components, Systems, and Entities
- Filters and queries
- Performance optimization

### 3. [Networking and Synchronization](03_Networking_and_Synchronization.md)
- Deterministic simulation model
- Input collection and distribution
- Client-server architecture
- Photon Realtime integration

### 4. [Quantum DSL](04_Quantum_DSL.md)
- Domain Specific Language syntax
- Defining components and structs
- Asset definitions
- Code generation

### 5. [Physics System](05_Physics_System.md)
- Deterministic physics
- 2D and 3D physics
- Collision detection
- Physics configuration

### 6. [Unity Integration](06_Unity_Integration.md)
- View components
- Input handling
- Asset linking
- Debug visualization

### 7. [Prediction and Rollback](07_Prediction_and_Rollback.md)
- Client-side prediction
- Rollback mechanisms
- Prediction culling
- Optimization strategies

## Multiplayer Systems (Chapters 8-9) 🆕

### 8. [Game Lobby Management](08_Game_Lobby_Management.md) 
**Comprehensive coverage of lobby systems including:**
- Room creation and configuration
- Matchmaking implementation
- Custom lobby properties
- SQL filtering for rooms
- Player list management
- Pre-game synchronization
- Ready system implementation
- Local multiplayer support
- Host migration handling

**Key Code Examples:**
- `QuantumMenuConnectionBehaviourSDK` - Core connection management
- `SportsArenaBrawlerMenuConnectionBehaviourSDK` - Custom lobby filtering
- `LobbySystem` - In-game lobby timer
- Skill-based matchmaking patterns

### 9. [Player Connection Management](09_Player_Connection_Management.md)
**Complete player lifecycle management including:**
- Connection establishment flow
- Player slot allocation
- Authentication handling
- Disconnection detection
- Reconnection system
- Late-join support
- Network quality monitoring
- Multi-client management
- Connection state persistence

**Key Code Examples:**
- `QuantumAddRuntimePlayers` - Runtime player addition
- `PlayerManager` - Player registry pattern
- `LocalPlayerManager` - Local player handling
- Reconnection information storage
- Connection event callbacks

## Navigation Guide

### For Beginners
Start with chapters 1-3 to understand the fundamental concepts, then proceed to chapter 6 for Unity integration.

### For Multiplayer Focus
After basics (1-3), jump to chapters 8-9 for comprehensive multiplayer implementation.

### For Gameplay Programming
Focus on chapters 2 (ECS), 4 (DSL), and 5 (Physics) for core gameplay systems.

### For Optimization
Study chapter 7 (Prediction) and relevant sections in chapters 8-9 for network optimization.

## Quick Reference

### Essential Classes
- `QuantumRunner` - Main game runner
- `Frame` - Game state container
- `SystemBase` - Base class for systems
- `QuantumEntityView` - Unity-Quantum bridge
- `QuantumMenuConnectionBehaviourSDK` - Connection management
- `RuntimePlayer` - Player data structure

### Key Patterns
- Input collection and polling
- Entity view creation
- Event handling
- Player state management
- Connection lifecycle
- Lobby configuration

## Sample Project References

Each chapter includes code snippets from various sample projects:
- **Quantum Starter** - Basic templates
- **Sports Arena Brawler** - Local multiplayer lobby
- **Quantum Karts** - Player management
- **Motor Dome** - Lobby timer system
- **Simple FPS** - FPS networking patterns

## Additional Resources

- Unity sample projects: `/Volumes/ExSSD/Unity Projects/`
- Obsidian notes: `/Users/anik/Documents/Obsidian/Claude/`
- [Official Documentation](https://doc.photonengine.com/quantum/v3)
