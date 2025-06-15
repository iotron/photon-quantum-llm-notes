# Quantum Menu SDK - Quick Reference

## Common Tasks

### 🚀 Quick Connection
```csharp
// Minimal connection
await connection.ConnectAsync(new QuantumMenuConnectArgs
{
    Scene = myScene,
    Username = "Player1"
});
```

### 🎮 Create Room with Filtering
```csharp
protected override void OnConnect(QuantumMenuConnectArgs connectArgs, 
    ref MatchmakingArguments args)
{
    args.Lobby = new TypedLobby("GameLobby", LobbyType.Sql);
    args.CustomRoomProperties = new Hashtable
    {
        { "GameMode", "Deathmatch" },
        { "MapName", "Arena1" }
    };
    args.SqlLobbyFilter = "GameMode = 'Deathmatch' AND MapName = 'Arena1'";
}
```

### 📊 Monitor Connection State
```csharp
// Check connection
bool connected = connection.IsConnected;
string room = connection.SessionName;
int ping = connection.Ping;

// Get players
List<string> players = connection.Usernames;
```

### 🔌 Handle Disconnection
```csharp
connection.SessionShutdownEvent += (cause, runner) =>
{
    switch (cause)
    {
        case ShutdownCause.NetworkError:
            ShowError("Connection lost");
            break;
    }
};
```

### 🎯 Custom Player Data
```csharp
// In RuntimePlayer.User.cs
public partial class RuntimePlayer
{
    public int TeamId;
    
    partial void SerializeUserData(BitStream stream)
    {
        stream.Serialize(ref TeamId);
    }
}
```

### 🏠 Update Room Properties
```csharp
var props = new Hashtable
{
    { "GameStarted", true },
    { "RoundNumber", 1 }
};
connection.Client.CurrentRoom.SetCustomProperties(props);
```

### 🔍 SQL Lobby Filtering Examples
```csharp
// Skill-based matching
args.SqlLobbyFilter = "Skill BETWEEN 1000 AND 1500";

// Multiple conditions
args.SqlLobbyFilter = 
    "GameMode = 'Ranked' AND " +
    "Players < 4 AND " +
    "Region = 'US'";

// Available operators: =, !=, <, >, <=, >=, AND, OR
```

### ⚡ Access Photon Client
```csharp
var client = connection.Client;
if (client?.InRoom == true)
{
    var room = client.CurrentRoom;
    Debug.Log($"Room: {room.Name}");
    Debug.Log($"Players: {room.PlayerCount}/{room.MaxPlayers}");
}
```

### 🎲 Access Quantum Runner
```csharp
var runner = connection.Runner;
if (runner?.Game != null)
{
    var frame = runner.Game.Frames.Verified;
    Debug.Log($"Tick: {frame.Number}");
}
```

### ⏱️ Set Room Persistence
```csharp
protected override void OnConnect(QuantumMenuConnectArgs connectArgs, 
    ref MatchmakingArguments args)
{
    args.PlayerTtlInSeconds = 300;      // 5 min reconnect window
    args.EmptyRoomTtlInSeconds = 60;    // 1 min empty room
}
```

## File Locations

| Component | Location |
|-----------|----------|
| SDK Base | `/Assets/Photon/QuantumMenu/Runtime/QuantumMenuConnectionBehaviourSDK.cs` |
| UI Controller | `/Assets/Photon/QuantumMenu/Runtime/QuantumMenuUIController.cs` |
| Connect Args | `/Assets/Photon/QuantumMenu/Runtime/QuantumMenuConnection.cs` |
| Your Extension | Create in `/Assets/Scripts/Connection/CustomConnectionBehaviour.cs` |

## Error Codes Reference

| Code | Constant | Meaning |
|------|----------|---------|
| 1 | UserRequest | User cancelled |
| 10 | NoAppId | Missing AppId |
| 20 | Disconnect | Network error |
| 21 | PluginError | Server error |
| 30 | RunnerFailed | Quantum failed |
| 40 | MapNotFound | Scene missing |
| 99 | ApplicationQuit | App closing |

## Matchmaking Modes

- `FillRoom` - Fill existing rooms first (recommended)
- `SerialMatching` - Join rooms in order
- `Random` - Random distribution

## Room Property Limits

- Max custom properties: 250
- Max lobby properties: 15
- Property key max length: 255 chars
- SQL filter max length: 350 chars

## Best Practices Checklist

- [ ] Always handle `ConnectResult`
- [ ] Subscribe to `SessionShutdownEvent`
- [ ] Set appropriate TTL values
- [ ] Use SQL lobby for complex filtering
- [ ] Minimize lobby properties
- [ ] Test reconnection scenarios
- [ ] Provide user feedback
- [ ] Clean up on destroy

## Common Patterns

### Loading Screen
```csharp
ShowLoading("Connecting...");
var result = await connection.ConnectAsync(args);
HideLoading();

if (!result.Success)
{
    ShowError(result.DebugMessage);
}
```

### Master Client Check
```csharp
bool isMaster = connection.Client?.LocalPlayer.IsMasterClient == true;
startButton.SetActive(isMaster);
```

### Safe Disconnect
```csharp
async void OnApplicationPause(bool paused)
{
    if (paused && connection.IsConnected)
    {
        await connection.DisconnectAsync();
    }
}
```
