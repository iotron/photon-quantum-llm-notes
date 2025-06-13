# Game Lobby Management - Sports Arena Brawler

Sports Arena Brawler implements a sophisticated lobby system with support for multiple local players joining the same online match. This is particularly useful for couch co-op scenarios where multiple players share a single console/PC.

## Local Multiplayer Lobby Architecture

### SQL Lobby with Player Count Filtering

The game uses Photon's SQL lobby feature to ensure proper matchmaking based on total player slots:

**File: `/Assets/SportsArenaBrawler/Scripts/Menu/LocalPlayerCountManager.cs`**

```csharp
public class LocalPlayerCountManager : MonoBehaviour, IInRoomCallbacks
{
    public const string LOCAL_PLAYERS_PROP_KEY = "LP";
    public const string TOTAL_PLAYERS_PROP_KEY = "C0";
    public static readonly TypedLobby SQL_LOBBY = new TypedLobby("customSqlLobby", LobbyType.Sql);
    
    private void UpdateLocalPlayersCount()
    {
        _connection.Client?.LocalPlayer.SetCustomProperties(new PhotonHashtable()
        {
            { LOCAL_PLAYERS_PROP_KEY, _menuController.GetLastSelectedLocalPlayersCount() }
        });
    }
    
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

### Custom Connection Behavior

**File: `/Assets/SportsArenaBrawler/Scripts/Menu/SportsArenaBrawlerMenuConnectionBehaviourSDK.cs`**

```csharp
public class SportsArenaBrawlerMenuConnectionBehaviourSDK : QuantumMenuConnectionBehaviourSDK
{
    [SerializeField]
    private SportsArenaBrawlerLocalPlayerController _localPlayersCountSelector;
    
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

## Local Player Selection UI

### Player Count Selection

The game allows players to select how many local players will join before matchmaking:

```csharp
public class SportsArenaBrawlerLocalPlayerController : MonoBehaviour
{
    private int _selectedLocalPlayerCount = 1;
    
    public int GetLastSelectedLocalPlayersCount() => _selectedLocalPlayerCount;
    
    public void SelectLocalPlayerCount(int count)
    {
        _selectedLocalPlayerCount = Mathf.Clamp(count, 1, Input.MAX_COUNT);
        UpdateUI();
        
        // Update matchmaking filters
        UpdateMatchmakingCriteria();
    }
}
```

## Room Property Synchronization

### Master Client Responsibilities

The master client manages total player count across all connected clients:

```csharp
public void OnPlayerPropertiesUpdate(Player targetPlayer, PhotonHashtable changedProps)
{
    if (changedProps.TryGetValue(LOCAL_PLAYERS_PROP_KEY, out object localPlayersCount))
    {
        // Recalculate total players when any client updates their local count
        UpdateRoomTotalPlayers();
    }
}

public void OnPlayerLeftRoom(Player otherPlayer)
{
    // Update total count when a client disconnects
    UpdateRoomTotalPlayers();
}
```

## Local Players Manager

### Managing Multiple Local Players

**File: `/Assets/SportsArenaBrawler/Scripts/Player/Local Player/LocalPlayersManager.cs`**

```csharp
public class LocalPlayersManager : MonoBehaviour
{
    public static LocalPlayersManager Instance { get; private set; }
    
    [SerializeField] private LocalPlayersConfig[] _localPlayersConfigPrefabs;
    private Dictionary<int, LocalPlayerAccess> _localPlayerAccessByPlayerIndices = new();
    
    private void Initialize()
    {
        var localPlayerIndices = QuantumRunner.Default.Game.GetLocalPlayers();
        if(localPlayerIndices.Count == 0) return;
        
        // Instantiate appropriate config based on player count
        LocalPlayersConfig localPlayersConfig = Instantiate(
            _localPlayersConfigPrefabs[localPlayerIndices.Count - 1], transform);
            
        for (int i = 0; i < localPlayerIndices.Count; i++)
        {
            LocalPlayerAccess localPlayerAccess = localPlayersConfig.GetLocalPlayerAccess(i);
            localPlayerAccess.IsMainLocalPlayer = i == 0;
            
            _localPlayerAccessByPlayerIndices.Add(localPlayerIndices[i], localPlayerAccess);
        }
    }
    
    public LocalPlayerAccess InitializeLocalPlayer(PlayerViewController playerViewController)
    {
        LocalPlayerAccess localPlayerAccess = GetLocalPlayerAccess(playerViewController.PlayerRef);
        localPlayerAccess.InitializeLocalPlayer(playerViewController);
        return localPlayerAccess;
    }
}
```

### Local Player Access Configuration

```csharp
public class LocalPlayerAccess : MonoBehaviour
{
    public bool IsMainLocalPlayer { get; set; }
    public Camera PlayerCamera { get; private set; }
    public Canvas PlayerCanvas { get; private set; }
    
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

## Matchmaking Flow

### Connection Process

1. **Player Count Selection**: Players choose how many local players will join
2. **SQL Filter Generation**: Create filter based on available slots
3. **Room Search**: Find rooms with enough space for all local players
4. **Property Sync**: Update room properties with local player count
5. **Player Creation**: Create multiple RuntimePlayer instances

### Implementation Example

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
        // Custom properties for SQL filtering
        CustomLobbyProperties = new[] { LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY }
    };
    
    await _connection.ConnectAsync(connectArgs);
}
```

## UI Adaptation

### Split Screen Setup

```csharp
public class LocalPlayersConfig : MonoBehaviour
{
    [SerializeField] private LocalPlayerAccess[] _localPlayerAccesses;
    
    public LocalPlayerAccess GetLocalPlayerAccess(int index)
    {
        return _localPlayerAccesses[index];
    }
    
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
}
```

## Lobby Events

### Custom Event Handling

```csharp
public class SportsArenaBrawlerLobbyEvents : MonoBehaviour
{
    void Start()
    {
        var connection = GetComponent<QuantumMenuConnectionBehaviourSDK>();
        
        // Listen for room property updates
        connection.Client.CallbackMessage.Listen<OnRoomPropertiesUpdateMsg>(msg =>
        {
            if (msg.propertiesThatChanged.TryGetValue(
                LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY, out var totalPlayers))
            {
                UpdateLobbyUI((int)totalPlayers);
            }
        });
    }
    
    void UpdateLobbyUI(int totalPlayers)
    {
        // Update UI to show total players across all clients
        _playerCountText.text = $"Players in Lobby: {totalPlayers}/{Input.MAX_COUNT}";
    }
}
```

## Best Practices

1. **Always validate total player count** before joining rooms
2. **Update room properties atomically** to avoid race conditions
3. **Handle disconnections gracefully** - recalculate totals
4. **Test with maximum local players** to ensure UI scales properly
5. **Consider network bandwidth** when multiple local players share connection
6. **Implement proper input separation** for local players
7. **Use SQL lobbies** for complex matchmaking criteria

## Common Issues and Solutions

### Issue: Room Full Despite Available Slots
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

This comprehensive local multiplayer lobby system makes Sports Arena Brawler ideal for party games and local competitive play.
