# Quantum Menu SDK Documentation

## Overview

Comprehensive documentation for using Photon Quantum Menu SDK in Unity projects, with focus on implementing robust multiplayer connection and lobby management systems.

## Table of Contents

### 📚 Chapters

1. **[[1. Overview and Introduction]]**
   - What is Quantum Menu SDK
   - Key benefits and features
   - Architecture overview
   - Quick start example

2. **[[2. Core Connection Functions]]**
   - ConnectAsync() method
   - QuantumMenuConnectArgs
   - Connection properties
   - Direct client/runner access

3. **[[3. Customization and Extension]]**
   - Extending QuantumMenuConnectionBehaviourSDK
   - SQL lobby implementation
   - RuntimePlayer customization
   - Authentication integration

4. **[[4. UI System Integration]]**
   - Using custom UI with SDK
   - Integration approaches
   - State management
   - Complete UI examples

5. **[[5. Matchmaking and Room Management]]**
   - Matchmaking modes
   - Room properties
   - SQL filtering
   - Player count management

6. **[[6. Error Handling and Events]]**
   - ConnectResult structure
   - Error codes
   - Event handling
   - Reconnection strategies

### 📁 Project Implementations

7. **[[7. Project Implementations - Bot SDK Sample]]**
   - Reference implementation with full code examples
   - Bot integration ready
   - Development focus
   - File paths: `quantum-botsdk-sample-development-3.0.0/`

8. **[[8. Project Implementations - Quantum Karts]]**
   - 6-player racing lobbies with implementation details
   - Track selection system code
   - Mobile optimization examples
   - File paths: `quantum-karts-3.0.2/`

9. **[[9. Project Implementations - Platform Shooter 2D]]**
   - Custom UI plugins with complete source code
   - Menu variants system implementation
   - 2D game adaptations with prefab details
   - File paths: `quantum-platform-shooter-2d-3.0.2/`

10. **[[10. Project Implementations - Quantum Racer 2.5D]]**
    - Isometric UI design patterns
    - 2.5D perspective handling code
    - Performance optimization techniques
    - File paths: `quantum-racer-2.5d-3.0.2/`

11. **[[11. Project Implementations - Simple FPS]]**
    - 8-player deathmatch with matchmaking code
    - FPS-specific UI implementations
    - Advanced SQL lobby filtering examples
    - File paths: `quantum-simple-fps-3.0.0/`

12. **[[12. Project Implementations - Sports Arena Brawler]]**
    - Local multiplayer support with full source
    - SQL lobby filtering implementation
    - Complex player management system code
    - File paths: `quantum-sports-arena-brawler-3.0.3/`

13. **[[13. Project Implementations - Twin Stick Shooter]]**
    - Arcade-style menu implementations
    - Wave system integration with code examples
    - Quick match system source code
    - File paths: `quantum-twinstickshooter-3.0.2/`

14. **[[14. Project Implementations - Other Projects]]**
    - Projects without SDK analysis
    - Integration decision matrix
    - Migration guide with examples

## Key Concepts

### Connection Architecture
```
QuantumMenuSDK
├── Connection Layer (QuantumMenuConnectionBehaviourSDK)
│   ├── Photon Realtime Client
│   ├── Quantum Runner Management
│   └── Scene Loading
├── UI Layer (Optional)
│   ├── QuantumMenuUIController
│   └── Screen System
└── Configuration
    ├── QuantumMenuConfig
    └── QuantumMenuConnectArgs
```

### Benefits Over Custom Implementation

| Feature | Custom (Motor Dome) | SDK Extension |
|---------|-------------------|---------------|
| Code Required | ~500+ lines | ~100 lines |
| Error Handling | Manual | Built-in |
| Reconnection | Manual | Automatic |
| Scene Loading | Manual | Automatic |
| UI System | Build from scratch | Optional/Ready |

## Project Implementation Summary

### Projects Using Quantum Menu SDK
1. **Bot SDK Sample** - Clean reference implementation
2. **Quantum Karts** - Racing game with 6-player lobbies
3. **Platform Shooter 2D** - Advanced UI customization with plugins
4. **Quantum Racer 2.5D** - Isometric racing with perspective UI
5. **Simple FPS** - 8-player deathmatch with FPS optimizations
6. **Sports Arena Brawler** - Most complex with local multiplayer
7. **Twin Stick Shooter** - Arcade-style quick match system

### Projects Without SDK
- **Motor Dome** - Uses custom implementation
- **Quantum Starter** - Blank slate for developers

> 📦 **Note**: Chapters 7-14 now include detailed code implementations with complete file paths and source code examples from each Unity project. Each chapter contains:
> - Full source code listings
> - Exact file paths for all implementations
> - Configuration file contents
> - Custom behavior examples
> - Integration patterns with code samples

## Quick Reference

### Basic Connection
```csharp
var connectArgs = new QuantumMenuConnectArgs
{
    Scene = gameScene,
    Username = "Player1",
    MaxPlayerCount = 6
};

var result = await connection.ConnectAsync(connectArgs);
```

### Extend for Custom Game
```csharp
public class MyGameConnection : QuantumMenuConnectionBehaviourSDK
{
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, 
        ref MatchmakingArguments args)
    {
        // Your customizations
        args.Lobby = new TypedLobby("MyLobby", LobbyType.Sql);
        args.SqlLobbyFilter = "GameMode = 'Ranked'";
    }
}
```

## Related Documentation

- [[photon quantum]] - General Quantum documentation
- [[quantum-starter]] - Basic Quantum setup
- Official Docs: https://doc.photonengine.com/quantum/current/manual/sample-menu

## Version

Documentation created for:
- Quantum SDK 3.0
- Unity 2022.3.54f1

---
*Last Updated: {{date}}*
