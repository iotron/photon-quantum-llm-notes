# Player Connection Management - Quantum Platform Shooter 2D

> **Implementation Note**: This project uses the **standard Quantum Menu** framework for all connection management. No custom player connection implementation was found in the project files.

Quantum Platform Shooter 2D leverages the built-in Quantum Menu connection system, which provides robust player connection handling suitable for platform shooter gameplay.

## Standard Connection Architecture

### Quantum Menu Integration
The game uses the default Quantum Menu connection flow:

1. **Main Menu** → Player initiates connection
2. **Photon Master Server** → Authentication and region selection
3. **Room Join/Create** → Matchmaking based on criteria
4. **Quantum Start** → Deterministic simulation begins
5. **In-Game** → Connected and playing

## Connection Features

### Automatic Player Management
```csharp
// Standard Quantum callbacks can be used for game-specific logic
public class PlatformShooterCallbacks : QuantumCallbacks
{
    public override void OnPlayerConnected(QuantumGame game, int player)
    {
        // Spawn player character
        var spawn = GetSpawnPoint(player);
        CreatePlayerCharacter(game, player, spawn);
    }
    
    public override void OnPlayerDisconnected(QuantumGame game, int player)
    {
        // Remove player character
        RemovePlayerCharacter(game, player);
        
        // Update UI
        UpdatePlayerList();
    }
}
```

### Photon Realtime Events
```csharp
public class ConnectionEventHandler : MonoBehaviourPunCallbacks
{
    public override void OnConnectedToMaster()
    {
        Debug.Log("Connected to Photon Master Server");
        // Quantum Menu handles the rest
    }
    
    public override void OnJoinedRoom()
    {
        Debug.Log($"Joined room: {PhotonNetwork.CurrentRoom.Name}");
        // Wait for Quantum to start
    }
    
    public override void OnPlayerEnteredRoom(Player newPlayer)
    {
        // New player joined - update lobby UI if still in lobby
        if (!QuantumRunner.Default)
        {
            RefreshLobbyPlayerList();
        }
    }
}
```

## Connection Configuration

### Room Settings
Through Quantum Menu configuration:

```csharp
// These settings are typically configured in the Quantum Menu prefab
RoomOptions roomOptions = new RoomOptions()
{
    MaxPlayers = 4,                    // Platform shooter sweet spot
    PlayerTtl = 10000,                 // 10 second reconnect window
    EmptyRoomTtl = 0,                  // Room closes when empty
    CloseOnStart = true,               // No late joining during match
    IsVisible = true,                  // Visible in room list
    IsOpen = true                      // Open for matchmaking
};
```

## Handling Connection States

### Connection Loss
The standard Quantum Menu handles most disconnection scenarios:

```csharp
public override void OnDisconnected(DisconnectCause cause)
{
    switch (cause)
    {
        case DisconnectCause.DisconnectByClientLogic:
            // Intentional disconnect - return to menu normally
            break;
            
        case DisconnectCause.DisconnectByServerTimeout:
        case DisconnectCause.Exception:
        case DisconnectCause.ServerTimeout:
            // Show error message
            ShowConnectionError(cause);
            break;
    }
    
    // Quantum Menu handles the return to main menu
}
```

### Reconnection Support
Platform shooters typically don't support mid-match reconnection:

```csharp
// Configure in room options
roomOptions.PlayerTtl = 0;      // No reconnection
roomOptions.CloseOnStart = true; // Lock room when game starts
```

## Player Spawn Management

### Spawn on Connection
```csharp
public class SpawnManager : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        // Find spawn point
        var spawnPoints = f.GetComponentIterator<SpawnPoint>();
        var spawn = SelectSpawnPoint(spawnPoints, player);
        
        // Create character
        var character = f.Create(f.Map.CharacterPrototype);
        f.Add(character, new PlayerLink { Player = player });
        f.Add(character, spawn.Transform);
        
        // Initialize character
        InitializeCharacter(f, character, player);
    }
}
```

## Best Practices

1. **Use Standard Flow** - Don't reinvent connection handling
2. **Configure Through Inspector** - Use Quantum Menu settings
3. **Handle Game Logic Only** - Let framework handle networking
4. **Clear Spawn Rules** - Define spawn behavior for connections
5. **No Mid-Match Joining** - Keep matches competitive

## Common Scenarios

### Quick Match
Standard Quantum Menu quick match:
```csharp
// Handled by Quantum Menu UI
// No custom code needed
```

### Private Matches
Using room codes through Quantum Menu:
```csharp
// Players share room code
// Quantum Menu handles the join process
```

### Team Assignment
Handle in game logic after connection:
```csharp
public void OnPlayerConnected(Frame f, PlayerRef player)
{
    // Assign to team with fewer players
    var team = GetTeamWithFewerPlayers(f);
    AssignPlayerToTeam(f, player, team);
}
```

## Debugging Connection Issues

### Enable Quantum Menu Debug Mode
- Shows connection status
- Displays room information
- Logs Photon events

### Common Issues
1. **Players not spawning** - Check spawn point configuration
2. **Immediate disconnection** - Verify room settings
3. **Can't find matches** - Check region and filters

The standard Quantum Menu connection system provides everything needed for a smooth platform shooter multiplayer experience without requiring custom implementation.