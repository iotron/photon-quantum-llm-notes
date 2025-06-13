# Game Lobby Management - Sports Arena Brawler

Sports Arena Brawler implements a versatile lobby system that supports both **local couch multiplayer** and **online multiplayer with multiple local players**. This dual approach makes it unique among Quantum samples, catering to both party game scenarios and competitive online play.

## Implementation Modes

### 1. Local Couch Multiplayer Mode

This mode focuses on instant local play without network requirements, perfect for party gaming scenarios.

#### Core Components

##### LocalPlayersManager
- Singleton pattern for managing all local players
- Handles player registration and device assignment
- Coordinates between Unity's Input System and Quantum's player system

```csharp
public class LocalPlayersManager : MonoBehaviour
{
    public static LocalPlayersManager Instance { get; private set; }
    
    [SerializeField] private LocalPlayersConfig[] _localPlayersConfigPrefabs;
    private Dictionary<int, LocalPlayerAccess> _localPlayerAccessByPlayerIndices = new();
    
    public void RegisterPlayer(PlayerInput playerInput)
    {
        // Assign next available slot
        int slot = GetNextAvailableSlot();
        
        // Create player access
        var access = new LocalPlayerAccess
        {
            PlayerSlot = slot,
            PlayerInput = playerInput,
            DeviceId = playerInput.devices[0].deviceId
        };
        
        _localPlayerAccessByPlayerIndices.Add(slot, access);
    }
}
```

##### Dynamic Join System
- **Hot-join capability**: Players can join mid-match
- **Device detection**: Automatically assigns controllers/keyboards
- **Split-screen adaptation**: Dynamically adjusts camera viewports

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
    
    // Update split-screen layout
    CameraManager.Instance.ReconfigureViewports();
}
```

#### Local Lobby Flow

1. **Main Menu Scene**
   - Single "Start Game" button
   - No traditional lobby UI needed
   
2. **Player Registration**
   - Detects button press on unassigned devices
   - Creates PlayerInput component
   - Registers with LocalPlayersManager

3. **In-Game Join**
   - Unassigned controllers can join anytime
   - Creates new player entity in Quantum
   - Spawns character at designated spawn point

### 2. Online Multiplayer Mode

This mode supports multiple local players joining the same online match, using SQL lobbies for sophisticated matchmaking.

#### SQL Lobby Architecture

**File: `/Assets/SportsArenaBrawler/Scripts/Menu/LocalPlayerCountManager.cs`**

```csharp
public class LocalPlayerCountManager : MonoBehaviour, IInRoomCallbacks
{
    public const string LOCAL_PLAYERS_PROP_KEY = "LP";
    public const string TOTAL_PLAYERS_PROP_KEY = "C0";
    public static readonly TypedLobby SQL_LOBBY = new TypedLobby("customSqlLobby", LobbyType.Sql);
    
    private void UpdateRoomTotalPlayers()
    {
        if (_connection != null && _connection.Client.InRoom && _connection.Client.LocalPlayer.IsMasterClient)
        {
            int totalPlayers = 0;
            foreach (var player in _connection.Client.CurrentRoom.Players.Values)
            {
                if (player.CustomProperties.TryGetValue(LOCAL_PLAYERS_PROP_KEY, out var localPlayersCount))
                {
                    totalPlayers += (int)localPlayersCount;
                }
            }
            
            _connection.Client.CurrentRoom.SetCustomProperties(new PhotonHashtable
            {
                { TOTAL_PLAYERS_PROP_KEY, totalPlayers }
            });
        }
    }
}
```

#### Custom Connection Behavior

```csharp
public class SportsArenaBrawlerMenuConnectionBehaviourSDK : QuantumMenuConnectionBehaviourSDK
{
    protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args)
    {
        // Configure SQL matchmaking
        args.RandomMatchingType = MatchmakingMode.FillRoom;
        args.Lobby = LocalPlayerCountManager.SQL_LOBBY;
        args.CustomLobbyProperties = new string[] { LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY };
        
        // Dynamic SQL filter based on local player count
        args.SqlLobbyFilter = $"{LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY} <= " +
            $"{Input.MAX_COUNT - _localPlayersCountSelector.GetLastSelectedLocalPlayersCount()}";
    }
}
```

#### Online Matchmaking Flow

1. **Player Count Selection**: Players choose how many local players will join
2. **SQL Filter Generation**: Create filter based on available slots
3. **Room Search**: Find rooms with enough space for all local players
4. **Property Sync**: Update room properties with local player count
5. **Player Creation**: Create multiple RuntimePlayer instances

```csharp
public async Task ConnectWithLocalPlayers(int localPlayerCount)
{
    // Create runtime players for each local player
    var runtimePlayers = new RuntimePlayer[localPlayerCount];
    for (int i = 0; i < localPlayerCount; i++)
    {
        runtimePlayers[i] = new RuntimePlayer
        {
            PlayerNickname = $"{LocalData.nickname} P{i + 1}",
            PlayerAvatar = GetAvatarForLocalPlayer(i)
        };
    }
    
    var connectArgs = new QuantumMenuConnectArgs
    {
        RuntimePlayers = runtimePlayers,
        MaxPlayerCount = Input.MAX_COUNT,
        CustomLobbyProperties = new[] { LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY }
    };
    
    await _connection.ConnectAsync(connectArgs);
}
```

## Shared Components

### LocalPlayerAccess Structure
Links Unity's PlayerInput to Quantum player entities and manages per-player resources:

```csharp
public class LocalPlayerAccess : MonoBehaviour
{
    public bool IsMainLocalPlayer { get; set; }
    public Camera PlayerCamera { get; private set; }
    public Canvas PlayerCanvas { get; private set; }
    public PlayerInput PlayerInput { get; private set; }
    public int LocalPlayerIndex { get; private set; }
    
    public void InitializeLocalPlayer(PlayerViewController playerViewController)
    {
        // Configure camera and UI for this local player
        ConfigureCamera(playerViewController);
        ConfigureUI(playerViewController);
        
        // Set up input handling
        SetupInputHandling(playerViewController.PlayerRef);
    }
}
```

### Split-Screen Management

Handles viewport configuration for multiple local players:

```csharp
public class LocalPlayersConfig : MonoBehaviour
{
    [SerializeField] private LocalPlayerAccess[] _localPlayerAccesses;
    
    private void ConfigureSplitScreen()
    {
        int playerCount = _localPlayerAccesses.Length;
        
        switch (playerCount)
        {
            case 1:
                SetupFullScreen(_localPlayerAccesses[0]);
                break;
            case 2:
                SetupVerticalSplit(_localPlayerAccesses);
                break;
            case 3:
            case 4:
                SetupQuadrantSplit(_localPlayerAccesses);
                break;
        }
    }
    
    private Rect CalculateViewportRect(int playerIndex, int totalPlayers)
    {
        switch (totalPlayers)
        {
            case 1:
                return new Rect(0, 0, 1, 1);
            case 2:
                return playerIndex == 0 
                    ? new Rect(0, 0.5f, 1, 0.5f) 
                    : new Rect(0, 0, 1, 0.5f);
            case 3:
            case 4:
                float x = playerIndex % 2 == 0 ? 0 : 0.5f;
                float y = playerIndex < 2 ? 0.5f : 0;
                return new Rect(x, y, 0.5f, 0.5f);
        }
    }
}
```

## Mode Selection

The game can be configured to use either local or online mode:

```csharp
public class LobbyModeSelector : MonoBehaviour
{
    public enum LobbyMode
    {
        LocalOnly,      // Couch co-op only
        OnlineOnly,     // Online with single player per client
        Hybrid          // Online with multiple local players
    }
    
    [SerializeField] private LobbyMode _lobbyMode = LobbyMode.Hybrid;
    
    public void InitializeLobbySystem()
    {
        switch (_lobbyMode)
        {
            case LobbyMode.LocalOnly:
                InitializeLocalOnlyLobby();
                break;
            case LobbyMode.OnlineOnly:
                InitializeOnlineLobby(maxLocalPlayers: 1);
                break;
            case LobbyMode.Hybrid:
                InitializeHybridLobby();
                break;
        }
    }
}
```

## Best Practices

### Local Multiplayer
1. **Device Management**
   - Cache device references to prevent reassignment
   - Handle device disconnection gracefully
   - Support keyboard + multiple gamepads

2. **Player Identification**
   - Visual indicators (colors, UI elements)
   - Persistent player numbers/names
   - Clear spawn positions

### Online Multiplayer
1. **Always validate total player count** before joining rooms
2. **Update room properties atomically** to avoid race conditions
3. **Handle disconnections gracefully** - recalculate totals
4. **Test with maximum local players** to ensure UI scales properly
5. **Consider network bandwidth** when multiple local players share connection

### Shared
1. **Performance Optimization**
   - Optimize split-screen rendering
   - Manage UI duplication efficiently
   - Consider LOD adjustments per viewport

2. **Input Handling**
   - Separate input channels per player
   - Use proper input prefixes
   - Handle input conflicts

## Common Issues and Solutions

### Issue: Room Full Despite Available Slots (Online)
```csharp
// Solution: Check total players, not just client count
bool CanJoinRoom(Room room, int localPlayerCount)
{
    int currentTotal = 0;
    if (room.CustomProperties.TryGetValue(TOTAL_PLAYERS_PROP_KEY, out var total))
    {
        currentTotal = (int)total;
    }
    
    return currentTotal + localPlayerCount <= Input.MAX_COUNT;
}
```

### Issue: Input Conflicts Between Local Players
```csharp
// Solution: Separate input channels per player
public void SetupInputHandling(PlayerRef playerRef)
{
    int localIndex = GetLocalPlayerIndex(playerRef);
    var inputPrefix = $"P{localIndex + 1}_";
    
    // Use prefixed input axes
    _moveAxis = inputPrefix + "Move";
    _fireButton = inputPrefix + "Fire";
}
```

### Issue: Device Assignment Conflicts (Local)
```csharp
// Solution: Track device states
private Dictionary<int, DeviceState> deviceStates;

public void OnDeviceConnected(InputDevice device)
{
    if (!IsDeviceAssigned(device))
    {
        deviceStates[device.deviceId] = DeviceState.Available;
        AttemptPlayerJoin(device);
    }
}
```

## Debugging Tools

### Connection Monitor
```csharp
public class LobbyDebugInfo : MonoBehaviour
{
    void OnGUI()
    {
        GUILayout.Label($"Lobby Mode: {currentMode}");
        GUILayout.Label($"Local Players: {localPlayerCount}");
        GUILayout.Label($"Total Players in Room: {totalPlayers}/{maxPlayers}");
        
        foreach (var player in localPlayers)
        {
            GUILayout.Label($"P{player.Index}: {player.DeviceName} - {player.State}");
        }
    }
}
```

This comprehensive lobby system makes Sports Arena Brawler suitable for various multiplayer scenarios, from casual couch gaming to competitive online play with friends.