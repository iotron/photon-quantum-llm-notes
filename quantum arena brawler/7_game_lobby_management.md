# Game Lobby Management - Sports Arena Brawler

## Overview

Sports Arena Brawler implements a **local couch multiplayer** focused lobby system, designed to support up to 4 players on a single device. Unlike traditional online lobbies, this project prioritizes local player management with dynamic join/leave capabilities during gameplay.

## Key Components

### 1. **LocalPlayersManager** (Central Hub)
- Singleton pattern for managing all local players
- Handles player registration and device assignment
- Coordinates between Unity's Input System and Quantum's player system

### 2. **LocalPlayerAccess** Structure
- Links Unity's PlayerInput to Quantum player entities
- Manages camera controllers for split-screen gameplay
- Tracks individual player states and configurations

### 3. **Dynamic Join System**
- **Hot-join capability**: Players can join mid-match
- **Device detection**: Automatically assigns controllers/keyboards
- **Split-screen adaptation**: Dynamically adjusts camera viewports

## Lobby Flow

### Pre-Game Setup
1. **Main Menu Scene**
   - Single "Start Game" button
   - No traditional lobby UI needed
   
2. **Player Registration**
   ```csharp
   // Handled via Unity's PlayerInputManager
   - Detects button press on unassigned devices
   - Creates PlayerInput component
   - Registers with LocalPlayersManager
   ```

3. **Quantum Integration**
   - Local players mapped to Quantum player slots
   - Input polling through `LocalInput.cs`
   - Synchronized through deterministic simulation

### In-Game Join
1. **Press Start/Button to Join**
   - Unassigned controllers can join anytime
   - Creates new player entity in Quantum
   - Spawns character at designated spawn point

2. **Leave Mechanics**
   - Hold specific button to leave
   - Removes player from active roster
   - Adjusts split-screen layout

## Implementation Details

### LocalInput Integration
```csharp
private void PollInput(CallbackPollInput callback)
{
    var localPlayers = callback.Game.GetLocalPlayers();
    var player = localPlayers[callback.PlayerSlot];
    
    LocalPlayerAccess localPlayerAccess = 
        LocalPlayersManager.Instance.GetLocalPlayerAccess(player);
    
    if (localPlayerAccess != null)
    {
        // Process input from specific player's device
        Vector2 movement = playerInput.actions["Movement"].ReadValue<Vector2>();
        // ... additional input processing
    }
}
```

### Split-Screen Management
- **2 Players**: Horizontal split
- **3-4 Players**: Quad split
- **Dynamic Viewport Adjustment**: Cameras reposition on join/leave

## Best Practices

### 1. **Device Management**
- Cache device references to prevent reassignment
- Handle device disconnection gracefully
- Support keyboard + multiple gamepads

### 2. **Player Identification**
- Visual indicators (colors, UI elements)
- Persistent player numbers/names
- Clear spawn positions

### 3. **Performance Considerations**
- Optimize split-screen rendering
- Manage UI duplication efficiently
- Consider LOD adjustments per viewport

## Common Patterns

### Hot-Join Implementation
```csharp
public void OnPlayerJoined(PlayerInput playerInput)
{
    // Register with LocalPlayersManager
    var playerAccess = new LocalPlayerAccess
    {
        PlayerInput = playerInput,
        LocalPlayer = CreateLocalPlayer(playerInput)
    };
    
    // Add to Quantum game
    QuantumRunner.Default.Game.AddPlayer(playerData);
}
```

### Player Leave Handling
```csharp
public void OnPlayerLeft(PlayerInput playerInput)
{
    // Remove from LocalPlayersManager
    LocalPlayersManager.Instance.UnregisterPlayer(playerInput);
    
    // Update split-screen layout
    CameraManager.Instance.ReconfigureViewports();
}
```

## Unique Features

1. **No Network Lobby Required**
   - Instant game start
   - No waiting for other players
   - Seamless join/leave flow

2. **Couch Co-op Focus**
   - Optimized for local play
   - Shared screen experience
   - Social gaming emphasis

3. **Flexible Player Count**
   - Works with 1-4 players
   - Adapts gameplay dynamically
   - Maintains game balance

## Integration Points

- **Unity Input System**: Modern input handling
- **Quantum Callbacks**: Deterministic player management
- **Camera System**: Dynamic viewport configuration
- **UI System**: Per-player HUD elements

## Debugging Tips

1. **Input Issues**
   - Check PlayerInputManager settings
   - Verify device assignment
   - Monitor input action maps

2. **Split-Screen Problems**
   - Debug camera viewport values
   - Check render texture assignments
   - Verify UI canvas configurations

3. **Player Sync**
   - Ensure Quantum player IDs match
   - Verify input polling timing
   - Check deterministic state updates
