# Player Connection Management - Quantum Simple FPS

> **Implementation Note**: This project uses a minimal `MenuUI.cs` that extends the standard Quantum Menu connection system. The implementation focuses on cursor management and menu visibility.

Quantum Simple FPS implements a streamlined connection system built on top of the standard Quantum Menu framework, with minimal customization for FPS-specific needs.

## Core Implementation

### MenuUI Connection Handler

**File: `/Assets/Scripts/UI/MenuUI.cs`** ✓

```csharp
namespace SimpleFPS
{
    public class MenuUI : QuantumMenuConnectionBehaviourSDK
    {
        [SerializeField]
        private GameObject[] _menuObjects;

        private bool _isBusy;
        private bool _isConnected;

        public override async Task<ConnectResult> ConnectAsync(QuantumMenuConnectArgs connectionArgs)
        {
            _isBusy = true;
            ConnectResult result = await base.ConnectAsync(connectionArgs);
            _isBusy = false;
            return result;
        }

        private void Update()
        {
            if (_isBusy == true)
                return;
            if (_isConnected == IsConnected)
                return;

            _isConnected = IsConnected;

            if (_isConnected == false)
            {
                // Show cursor for menu navigation
                Cursor.lockState = CursorLockMode.None;
                Cursor.visible = true;
            }

            foreach (GameObject go in _menuObjects)
            {
                go.SetActive(_isConnected == false);
            }
        }
    }
}
```

## Connection Features

### 1. **Automatic Cursor Management**
- Shows cursor when disconnected (in menu)
- Game code hides cursor during gameplay
- Seamless transition between menu and game

### 2. **Menu Visibility Control**
- Menu objects automatically hide when connected
- Show again on disconnection
- Clean UI state management

### 3. **Async Connection Handling**
- Non-blocking connection process
- UI remains responsive during connection
- Busy state prevents multiple connection attempts

## Standard Quantum Callbacks

The game can implement standard callbacks for FPS-specific logic:

```csharp
public class FPSPlayerManager : QuantumCallbacks
{
    public override void OnPlayerConnected(QuantumGame game, int player)
    {
        // Spawn player at team spawn point
        var team = DetermineTeam(game, player);
        var spawnPoint = GetTeamSpawnPoint(game, team);
        SpawnPlayer(game, player, spawnPoint);
    }
    
    public override void OnPlayerDisconnected(QuantumGame game, int player)
    {
        // Handle player leaving mid-match
        if (IsMatchInProgress(game))
        {
            // Option 1: Remove player immediately
            RemovePlayer(game, player);
            
            // Option 2: Keep player entity for reconnection window
            // MarkPlayerAsDisconnected(game, player);
        }
    }
}
```

## Connection Flow

### Standard FPS Connection Sequence

1. **Main Menu** - Player clicks "Play" or "Quick Match"
2. **Connection** - MenuUI handles async connection
3. **Matchmaking** - Standard Quantum Menu matchmaking
4. **Game Start** - Menu objects hide, cursor locks
5. **In-Game** - Full FPS controls active

## Disconnection Handling

### Clean Disconnection
```csharp
public override async Task DisconnectAsync(int reason)
{
    _isBusy = true;
    await base.DisconnectAsync(reason);
    _isBusy = false;
    
    // Menu objects and cursor are handled by Update()
}
```

### Connection Loss
The standard Quantum Menu handles unexpected disconnections:
- Returns to main menu
- Shows appropriate error message
- Resets game state

## Team Management

Handle team assignment after connection:

```csharp
public class TeamManager : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        // Auto-balance teams
        int team1Count = CountPlayersInTeam(f, 0);
        int team2Count = CountPlayersInTeam(f, 1);
        
        int assignedTeam = team1Count <= team2Count ? 0 : 1;
        
        // Create player with team
        var playerEntity = f.Create(f.FindAsset<EntityPrototype>(PLAYER_PROTOTYPE));
        f.Add(playerEntity, new PlayerLink { Player = player });
        f.Add(playerEntity, new Team { Index = assignedTeam });
    }
}
```

## Best Practices

1. **Keep It Simple** - Use standard Quantum Menu features
2. **Handle Cursor Properly** - Critical for FPS games
3. **Quick Connections** - Minimize time to gameplay
4. **Clear Team Assignment** - Handle in game logic
5. **No Complex UI** - Focus on getting into matches

## Common FPS Scenarios

### Quick Match
Uses standard Quantum Menu quick match:
```csharp
// Triggered by UI button
// MenuUI.ConnectAsync() handles the rest
```

### Server Browser
Can be implemented using Quantum Menu's room listing:
```csharp
// Standard Quantum Menu provides room list
// Filter by game mode, map, etc.
```

### Reconnection
Typically disabled for competitive FPS:
```csharp
// In room configuration
PlayerTtl = 0;        // No reconnection
CloseOnStart = true;  // Lock match
```

## Performance Considerations

### Connection Optimization
- Minimal UI updates during connection
- Async operations prevent blocking
- Simple state management

### In-Game Efficiency
- Menu objects fully deactivated when connected
- No unnecessary Update() calls when stable
- Clean separation of menu and game logic

This minimal approach provides everything needed for FPS multiplayer while maintaining simplicity and performance.