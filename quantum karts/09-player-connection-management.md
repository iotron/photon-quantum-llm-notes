# Player Connection Management - Quantum Karts

> **Implementation Note**: This project uses the **standard Quantum Menu** framework for all connection management. No custom player connection implementation was found in the project files.

Quantum Karts relies on the built-in Quantum Menu connection system for handling player connections, disconnections, and reconnections. The standard implementation provides:

## Standard Connection Features

### 1. **Automatic Connection Handling**
- Players connect through Quantum Menu UI
- Photon Realtime manages the connection state
- Quantum Runner handles player registration

### 2. **Connection Flow**
```
Main Menu → Connect to Photon → Join/Create Room → Start Quantum Game
```

### 3. **Player Management**
- Standard Quantum callbacks for player events
- Automatic cleanup on disconnection
- Built-in reconnection support

## Using Standard Quantum Callbacks

The game can respond to player connection events using standard Quantum callbacks:

```csharp
public class KartPlayerManager : QuantumCallbacks
{
    public override void OnPlayerConnected(QuantumGame game, int player)
    {
        // Player joined - handled by Quantum
        Debug.Log($"Player {player} connected");
    }
    
    public override void OnPlayerDisconnected(QuantumGame game, int player)
    {
        // Player left - handled by Quantum
        Debug.Log($"Player {player} disconnected");
    }
}
```

## Photon Realtime Integration

Connection events can also be monitored through Photon callbacks:

```csharp
public class KartConnectionHandler : MonoBehaviourPunCallbacks
{
    public override void OnPlayerEnteredRoom(Player newPlayer)
    {
        // New player joined the room
        Debug.Log($"{newPlayer.NickName} joined the race");
    }
    
    public override void OnPlayerLeftRoom(Player otherPlayer)
    {
        // Player left the room
        Debug.Log($"{otherPlayer.NickName} left the race");
    }
    
    public override void OnDisconnected(DisconnectCause cause)
    {
        // Handle disconnection
        Debug.Log($"Disconnected: {cause}");
        // Return to menu is handled by Quantum Menu
    }
}
```

## Best Practices

1. **Let Quantum Menu handle connections** - Don't override unless necessary
2. **Use standard callbacks** for game-specific responses
3. **Keep connection logic simple** for racing games
4. **Focus on gameplay** rather than complex connection management

## Common Connection Scenarios

### Player Joins Mid-Race
By default, Quantum Karts rooms are closed when the race starts to prevent mid-race joining:

```csharp
// In room configuration
RoomOptions.CloseOnStart = true;
```

### Reconnection Support
The standard Quantum Menu provides reconnection within the timeout window:

```csharp
// In room configuration
RoomOptions.PlayerTtl = 10000; // 10 seconds to reconnect
```

### AI Bot Replacement
When a player disconnects, their kart can be replaced with an AI bot through game logic:

```csharp
public override void OnPlayerDisconnected(QuantumGame game, int player)
{
    if (game.Frames.Verified.TryGetPlayerObject(player, out var kart))
    {
        // Convert to AI control
        ConvertToAI(game.Frames.Verified, kart);
    }
}
```

This simplified approach lets developers focus on racing gameplay while Quantum handles the complex connection management.