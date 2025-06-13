# Player Connection Management - Sports Arena Brawler

Sports Arena Brawler implements a robust player connection system that handles multiple local players per client, making it unique among the Quantum samples. This chapter covers how the game manages player connections, disconnections, and local player assignments.

## Multi-Local Player Architecture

### Player Identification System

Each client can have multiple local players, requiring careful management of player references:

**File: `/Assets/SportsArenaBrawler/Scripts/Player/Local Player/LocalPlayersManager.cs`**

```csharp
public class LocalPlayersManager : MonoBehaviour
{
    private Dictionary<int, LocalPlayerAccess> _localPlayerAccessByPlayerIndices = new();
    
    public LocalPlayerAccess InitializeLocalPlayer(PlayerViewController playerViewController)
    {
        LocalPlayerAccess localPlayerAccess = GetLocalPlayerAccess(playerViewController.PlayerRef);
        localPlayerAccess.InitializeLocalPlayer(playerViewController);
        return localPlayerAccess;
    }
    
    public LocalPlayerAccess GetLocalPlayerAccess(int playerIndex)
    {
        if (_localPlayerAccessByPlayerIndices.Count == 0)
        {
            Initialize();
        }
        
        _localPlayerAccessByPlayerIndices.TryGetValue(playerIndex, out LocalPlayerAccess localPlayerAccess);
        return localPlayerAccess;
    }
}
```

## Connection Flow

### Initial Connection with Multiple Players

```csharp
public class SportsArenaBrawlerConnectionManager : QuantumMenuConnectionBehaviourSDK
{
    protected override async Task<ConnectResult> ConnectAsyncInternal(QuantumMenuConnectArgs connectArgs)
    {
        // Get local player count from UI
        int localPlayerCount = _localPlayersCountSelector.GetLastSelectedLocalPlayersCount();
        
        // Create runtime players for each local player
        connectArgs.RuntimePlayers = new RuntimePlayer[localPlayerCount];
        for (int i = 0; i < localPlayerCount; i++)
        {
            connectArgs.RuntimePlayers[i] = new RuntimePlayer
            {
                PlayerNickname = GetPlayerNickname(i),
                PlayerAvatar = GetPlayerAvatar(i),
                // Custom data for team assignment, etc.
                CustomData = SerializePlayerPreferences(i)
            };
        }
        
        // Set up connection with proper player count
        connectArgs.MaxPlayerCount = Input.MAX_COUNT;
        
        return await base.ConnectAsyncInternal(connectArgs);
    }
}
```

### Player Slot Allocation

The game uses a sophisticated system to allocate player slots across multiple local players:

```csharp
public class PlayerSlotManager : SystemMainThread
{
    public override void OnPlayerConnected(Frame f, PlayerRef player)
    {
        // Check if this is a local player
        var localPlayers = f.Game.GetLocalPlayers();
        if (localPlayers.Contains(player))
        {
            // Allocate team slot based on available positions
            AllocateTeamSlot(f, player);
            
            // Create player entity
            CreatePlayerEntity(f, player);
        }
    }
    
    private void AllocateTeamSlot(Frame f, PlayerRef player)
    {
        // Find best team balance
        int team1Count = CountPlayersInTeam(f, 0);
        int team2Count = CountPlayersInTeam(f, 1);
        
        int assignedTeam = team1Count <= team2Count ? 0 : 1;
        
        // Store team assignment
        var playerData = f.GetPlayerData(player);
        playerData.Team = assignedTeam;
    }
}
```

## Local Player Access Management

### Player-Specific Resources

**File: `/Assets/SportsArenaBrawler/Scripts/Player/Local Player/LocalPlayerAccess.cs`**

```csharp
public class LocalPlayerAccess : MonoBehaviour
{
    public bool IsMainLocalPlayer { get; set; }
    public Camera PlayerCamera { get; private set; }
    public Canvas PlayerCanvas { get; private set; }
    public AudioListener PlayerAudioListener { get; private set; }
    
    private PlayerViewController _playerViewController;
    private int _localPlayerIndex;
    
    public void InitializeLocalPlayer(PlayerViewController playerViewController)
    {
        _playerViewController = playerViewController;
        _localPlayerIndex = DetermineLocalPlayerIndex(playerViewController.PlayerRef);
        
        // Configure player-specific components
        ConfigureCamera();
        ConfigureUI();
        ConfigureAudio();
        ConfigureInput();
    }
    
    private void ConfigureCamera()
    {
        // Set viewport based on player count and index
        var localPlayerCount = QuantumRunner.Default.Game.GetLocalPlayers().Count;
        PlayerCamera.rect = CalculateViewportRect(_localPlayerIndex, localPlayerCount);
        
        // Only main player gets certain UI elements
        if (IsMainLocalPlayer)
        {
            PlayerCamera.cullingMask |= LayerMask.GetMask("MainUI");
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
            default:
                return new Rect(0, 0, 1, 1);
        }
    }
}
```

## Connection State Monitoring

### Per-Player Connection Status

```csharp
public unsafe class PlayerConnectionMonitor : SystemMainThreadFilter<PlayerConnectionMonitor.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public PlayerLink* Link;
        public Transform3D* Transform;
    }
    
    public override void Update(Frame f, ref Filter filter)
    {
        var playerRef = filter.Link->PlayerRef;
        var inputFlags = f.GetPlayerInputFlags(playerRef);
        
        // Check connection status
        bool isConnected = (inputFlags & DeterministicInputFlags.PlayerNotPresent) == 0;
        bool wasConnected = filter.Link->IsConnected;
        
        if (isConnected != wasConnected)
        {
            filter.Link->IsConnected = isConnected;
            
            if (!isConnected)
            {
                // Player disconnected
                filter.Link->DisconnectTime = f.Time;
                f.Events.PlayerDisconnected(playerRef);
                
                // Start grace period for reconnection
                StartReconnectionTimer(f, playerRef);
            }
            else if (isConnected && !wasConnected)
            {
                // Player reconnected
                f.Events.PlayerReconnected(playerRef);
                HandleReconnection(f, filter);
            }
        }
    }
    
    private void HandleReconnection(Frame f, ref Filter filter)
    {
        // Restore player state
        var timeSinceDisconnect = f.Time - filter.Link->DisconnectTime;
        
        if (timeSinceDisconnect < FP._10) // Within 10 seconds
        {
            // Keep existing state
            filter.Link->DisconnectTime = FP._0;
        }
        else
        {
            // Reset player position
            ResetPlayerToSpawn(f, filter.Entity);
        }
    }
}
```

## Disconnection Handling

### Graceful Disconnection for Local Players

```csharp
public class LocalPlayerDisconnectHandler : MonoBehaviour
{
    public void OnLocalPlayerQuit(int localPlayerIndex)
    {
        var game = QuantumRunner.Default?.Game;
        if (game == null) return;
        
        var localPlayers = game.GetLocalPlayers();
        if (localPlayerIndex < localPlayers.Count)
        {
            PlayerRef playerRef = localPlayers[localPlayerIndex];
            
            // Remove player from game
            game.RemovePlayer(playerRef);
            
            // Update local player tracking
            LocalPlayersManager.Instance.RemoveLocalPlayer(playerRef);
            
            // Notify server of updated local player count
            UpdateLocalPlayerCount();
        }
    }
    
    private void UpdateLocalPlayerCount()
    {
        var client = QuantumRunner.Default?.NetworkClient;
        if (client != null)
        {
            client.LocalPlayer.SetCustomProperties(new PhotonHashtable
            {
                { LocalPlayerCountManager.LOCAL_PLAYERS_PROP_KEY, 
                  QuantumRunner.Default.Game.GetLocalPlayers().Count }
            });
        }
    }
}
```

### Client Disconnection Handling

```csharp
public class ClientDisconnectHandler : QuantumCallbacks
{
    public override void OnPlayerRemoved(PlayerRef player, QuantumGame game)
    {
        // Check if entire client disconnected
        var client = game.GetPlayerClient(player);
        bool hasOtherPlayersFromClient = false;
        
        for (int i = 0; i < game.PlayerCount; i++)
        {
            if (i != player && game.GetPlayerClient(i) == client)
            {
                hasOtherPlayersFromClient = true;
                break;
            }
        }
        
        if (!hasOtherPlayersFromClient)
        {
            // Entire client disconnected, update room properties
            HandleClientDisconnect(client);
        }
    }
}
```

## Input Assignment

### Multi-Player Input Handling

```csharp
public class LocalPlayerInputHandler : QuantumEntityViewComponent
{
    private int _localPlayerIndex;
    private string _inputPrefix;
    
    public override void OnActivate(Frame frame)
    {
        var playerLink = GetPredictedQuantumComponent<PlayerLink>();
        if (playerLink == null) return;
        
        // Determine if this is a local player
        var localPlayers = QuantumRunner.Default.Game.GetLocalPlayers();
        _localPlayerIndex = localPlayers.IndexOf(playerLink.PlayerRef);
        
        if (_localPlayerIndex >= 0)
        {
            // Set up input prefix for this local player
            _inputPrefix = _localPlayerIndex == 0 ? "" : $"P{_localPlayerIndex + 1}_";
            
            // Subscribe to input polling
            QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
        }
        else
        {
            // Not a local player, disable input
            enabled = false;
        }
    }
    
    private void PollInput(CallbackPollInput callback)
    {
        if (callback.PlayerRef != GetComponent<QuantumEntityView>().PlayerRef) return;
        
        var input = new Quantum.Input();
        
        // Read input with player-specific prefix
        input.Movement = new FPVector2(
            UnityEngine.Input.GetAxis(_inputPrefix + "Horizontal"),
            UnityEngine.Input.GetAxis(_inputPrefix + "Vertical")
        );
        
        input.Fire = UnityEngine.Input.GetButton(_inputPrefix + "Fire");
        input.Jump = UnityEngine.Input.GetButton(_inputPrefix + "Jump");
        
        callback.SetInput(input, DeterministicInputFlags.Repeatable);
    }
}
```

## Reconnection System

### Player State Persistence

```csharp
public struct PlayerPersistentData
{
    public int Score;
    public int Team;
    public FPVector3 LastPosition;
    public FP Health;
    public AbilityType CurrentAbility;
}

public class PlayerReconnectionManager : SystemMainThread
{
    private Dictionary<string, PlayerPersistentData> _disconnectedPlayerData = new();
    
    public void OnPlayerDisconnected(Frame f, PlayerRef player)
    {
        var playerData = f.GetPlayerData(player);
        if (playerData == null) return;
        
        // Get player entity
        var filter = f.Filter<PlayerLink, Transform3D, Health, AbilityInventory>();
        while (filter.NextUnsafe(out var entity, out var link, out var transform, 
               out var health, out var abilities))
        {
            if (link->PlayerRef == player)
            {
                // Store persistent data
                var persistentData = new PlayerPersistentData
                {
                    Score = playerData.Score,
                    Team = playerData.Team,
                    LastPosition = transform->Position,
                    Health = health->Current,
                    CurrentAbility = abilities->CurrentAbility
                };
                
                _disconnectedPlayerData[playerData.ClientId] = persistentData;
                break;
            }
        }
    }
    
    public void OnPlayerReconnected(Frame f, PlayerRef player, string clientId)
    {
        if (_disconnectedPlayerData.TryGetValue(clientId, out var persistentData))
        {
            // Restore player state
            RestorePlayerState(f, player, persistentData);
            _disconnectedPlayerData.Remove(clientId);
        }
    }
}
```

## Network Quality Management

### Per-Player Network Monitoring

```csharp
public class LocalPlayerNetworkMonitor : MonoBehaviour
{
    private Dictionary<PlayerRef, NetworkStats> _playerNetworkStats = new();
    
    void Update()
    {
        var runner = QuantumRunner.Default;
        if (runner?.Session == null) return;
        
        var localPlayers = runner.Game.GetLocalPlayers();
        foreach (var playerRef in localPlayers)
        {
            var stats = GetPlayerNetworkStats(playerRef);
            
            // Monitor individual player connection quality
            if (stats.PacketLoss > 0.05f || stats.Ping > 200)
            {
                ShowPlayerConnectionWarning(playerRef, stats);
            }
        }
    }
    
    private void ShowPlayerConnectionWarning(PlayerRef player, NetworkStats stats)
    {
        var localPlayerAccess = LocalPlayersManager.Instance.GetLocalPlayerAccess(player);
        if (localPlayerAccess != null)
        {
            // Show warning on specific player's UI
            localPlayerAccess.ShowConnectionWarning(stats.Ping, stats.PacketLoss);
        }
    }
}
```

## Best Practices

1. **Always track local player indices** for proper input and UI assignment
2. **Handle partial client disconnections** when only some local players leave
3. **Implement reconnection grace periods** appropriate for game type
4. **Store minimal persistent data** for reconnecting players
5. **Test with maximum local players** under poor network conditions
6. **Separate UI elements per player** to avoid confusion
7. **Consider bandwidth usage** with multiple local players
8. **Implement proper cleanup** when players disconnect

## Common Patterns

### Dynamic Player Addition

```csharp
public void AddLocalPlayerDuringGame()
{
    var currentLocalPlayers = QuantumRunner.Default.Game.GetLocalPlayers().Count;
    if (currentLocalPlayers >= Input.MAX_COUNT) return;
    
    // Find next available player slot
    int nextSlot = FindNextAvailableSlot();
    
    // Create new runtime player
    var newPlayer = new RuntimePlayer
    {
        PlayerNickname = $"Player {currentLocalPlayers + 1}",
        PlayerAvatar = GetDefaultAvatar()
    };
    
    // Add to game
    QuantumRunner.Default.Game.AddPlayer(nextSlot, newPlayer);
    
    // Update UI for split screen
    ReconfigureSplitScreen();
}
```

This comprehensive player connection management system enables Sports Arena Brawler to provide seamless local multiplayer experiences with robust handling of disconnections and reconnections.
