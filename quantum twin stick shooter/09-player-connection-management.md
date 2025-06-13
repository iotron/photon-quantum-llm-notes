# Player Connection Management - Quantum Twin Stick Shooter

> **Implementation Note**: This project uses the **standard Quantum Menu** framework for all connection management. No custom player connection implementation was found in the project files.

Quantum Twin Stick Shooter leverages the built-in Quantum Menu connection system, which is ideal for arcade-style games with drop-in/drop-out gameplay.

## Connection Architecture

### Standard Quantum Menu Flow
The game follows the typical Quantum connection pattern:

1. **Main Menu** → Quick Play or Host Game
2. **Photon Connection** → Automatic server selection
3. **Room Join/Create** → Find or create arcade session
4. **Quantum Start** → Begin wave-based gameplay
5. **Drop-in/Drop-out** → Players can join/leave freely

## Connection Features for Arcade Gameplay

### Dynamic Player Management
```csharp
public class TwinStickPlayerManager : QuantumCallbacks
{
    public override void OnPlayerConnected(QuantumGame game, int player)
    {
        // Spawn player in safe zone
        var safeSpawn = FindSafeSpawnPoint(game);
        CreatePlayerShip(game, player, safeSpawn);
        
        // Grant spawn invulnerability
        GrantSpawnProtection(game, player);
        
        // Scale difficulty for new player
        AdjustDifficultyForPlayerCount(game);
    }
    
    public override void OnPlayerDisconnected(QuantumGame game, int player)
    {
        // Remove player ship
        RemovePlayerShip(game, player);
        
        // Redistribute player's power-ups
        RedistributePowerUps(game, player);
        
        // Adjust difficulty
        AdjustDifficultyForPlayerCount(game);
    }
}
```

### Drop-In Support
```csharp
public class DropInManager : MonoBehaviourPunCallbacks
{
    public override void OnPlayerEnteredRoom(Player newPlayer)
    {
        if (IsGameInProgress())
        {
            // Welcome message
            ShowPlayerJoinedNotification(newPlayer.NickName);
            
            // Will spawn on next wave or safe moment
            QueuePlayerForSpawn(newPlayer);
        }
    }
    
    private bool IsGameInProgress()
    {
        return QuantumRunner.Default != null && 
               QuantumRunner.Default.IsRunning;
    }
}
```

## Room Configuration for Arcade

### Open Room Settings
Configure through Quantum Menu or room options:

```csharp
RoomOptions arcadeRoom = new RoomOptions()
{
    MaxPlayers = 4,                    // Co-op limit
    PlayerTtl = 0,                     // No reconnection needed
    EmptyRoomTtl = 300000,             // 5 minutes persistence
    CloseOnStart = false,              // Allow drop-in
    IsVisible = true,                  // Public games
    IsOpen = true                      // Always accepting players
};
```

## Connection Events

### Using Photon Callbacks
```csharp
public class ArcadeConnectionHandler : MonoBehaviourPunCallbacks
{
    public override void OnJoinedRoom()
    {
        Debug.Log($"Joined arcade session: {PhotonNetwork.CurrentRoom.Name}");
        UpdatePlayerCountUI();
    }
    
    public override void OnPlayerEnteredRoom(Player newPlayer)
    {
        // Arcade-style welcome
        PlayJoinSound();
        ShowJoinEffect();
        UpdatePlayerList();
    }
    
    public override void OnPlayerLeftRoom(Player otherPlayer)
    {
        // Simple goodbye
        UpdatePlayerList();
        
        // Check if should continue
        if (PhotonNetwork.CurrentRoom.PlayerCount == 0)
        {
            // End session after delay
            StartCoroutine(EndSessionIfEmpty());
        }
    }
}
```

## Wave-Based Connection Handling

### Safe Spawn Windows
```csharp
public class WaveSpawnManager : SystemMainThread
{
    private List<PlayerRef> _pendingSpawns = new List<PlayerRef>();
    
    public override void Update(Frame f)
    {
        if (IsWaveTransition(f) && _pendingSpawns.Count > 0)
        {
            foreach (var player in _pendingSpawns)
            {
                SpawnPlayer(f, player);
            }
            _pendingSpawns.Clear();
        }
    }
    
    private bool IsWaveTransition(Frame f)
    {
        return f.Global->WaveState == WaveState.Intermission;
    }
}
```

## Simplified Connection UI

### Quick Play Focus
The standard Quantum Menu can be configured for arcade simplicity:

```csharp
// Single button to play
public void OnQuickPlayClicked()
{
    // Quantum Menu handles:
    // 1. Connect to Photon
    // 2. Find suitable room
    // 3. Create if none found
    // 4. Start playing
}
```

### Minimal Lobby
- No complex pre-game setup
- Jump straight into action
- Character selection can happen in-game

## Best Practices for Arcade Games

1. **Always Open Rooms** - Allow drop-in gameplay
2. **No Reconnection** - Keep it simple
3. **Dynamic Difficulty** - Scale with player count
4. **Safe Spawning** - Don't spawn in danger
5. **Quick Sessions** - Easy in, easy out

## Common Arcade Patterns

### Local Co-op Support
If supporting local multiplayer:
```csharp
public class LocalCoopManager : MonoBehaviour
{
    public void AddLocalPlayer(int controllerIndex)
    {
        // Standard Quantum doesn't support multiple local players
        // This would require custom implementation like Sports Arena Brawler
    }
}
```

### AI Companion System
When playing solo:
```csharp
public override void OnGameStart(QuantumGame game, bool isResync)
{
    if (game.PlayerCount == 1)
    {
        // Optionally add AI companions
        AddAICompanions(game, 1); // Add 1 AI helper
    }
}
```

### Score Persistence
Track scores across sessions:
```csharp
public override void OnPlayerDisconnected(QuantumGame game, int player)
{
    // Save score before removing player
    var score = GetPlayerScore(game, player);
    SaveHighScore(player, score);
}
```

## Performance Considerations

### Scalable Systems
- Enemy count scales with players
- Effect density adjusts
- Network traffic optimized

### Simple State Management
- No complex lobby states
- Direct menu-to-game flow
- Minimal connection overhead

## Debugging Drop-In/Out

### Connection Monitor
```csharp
void OnGUI()
{
    if (!Debug.isDebugBuild) return;
    
    GUILayout.BeginArea(new Rect(10, 10, 200, 150));
    GUILayout.Label("Connection Debug");
    
    if (PhotonNetwork.InRoom)
    {
        GUILayout.Label($"Room: {PhotonNetwork.CurrentRoom.Name}");
        GUILayout.Label($"Players: {PhotonNetwork.CurrentRoom.PlayerCount}/4");
        GUILayout.Label($"Open: {PhotonNetwork.CurrentRoom.IsOpen}");
        
        if (GUILayout.Button("Simulate Drop-In"))
        {
            // Test drop-in flow
        }
    }
    
    GUILayout.EndArea();
}
```

This standard connection system provides the perfect foundation for arcade-style twin-stick shooter gameplay with seamless multiplayer support.