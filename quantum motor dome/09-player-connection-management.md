# Player Connection Management - Quantum Motor Dome

Quantum Motor Dome implements a robust player connection system for vehicle combat arena gameplay. The system handles player joining, disconnection, and maintains game flow even when players leave mid-match.

## Connection Architecture

### Matchmaker Connection Flow

**File: `/Assets/Scripts/Matchmaker.cs`**

```csharp
public class Matchmaker : QuantumCallbacks, IConnectionCallbacks, IMatchmakingCallbacks, IInRoomCallbacks
{
    public static event System.Action OnQuantumGameStart;
    public static event System.Action OnRealtimeJoinedRoom;
    public static event System.Action<Player> OnRealtimePlayerJoined;
    public static event System.Action<Player> OnRealtimePlayerLeft;
    
    private void Awake()
    {
        Instance = this;
        DontDestroyOnLoad(gameObject);
        
        SceneLoader.OnSceneLoadDone += SendData;
        
        AppSettings = new AppSettings(PhotonServerSettings.Global.AppSettings);
        
        Client = new RealtimeClient();
        Client.AddCallbackTarget(Instance);
    }
    
    void IMatchmakingCallbacks.OnJoinedRoom()
    {
        onStatusUpdated?.Invoke(new ConnectionStatus("Joined Room", State.JoinedRoom));
        Log("Joined room");
        OnRealtimeJoinedRoom?.Invoke();
        StartQuantumGame();
    }
}
```

## Player Initialization

### Runtime Player Setup

```csharp
void SendData()
{
    // Configure player data with customization
    runtimePlayer.PlayerNickname = LocalData.nickname;
    
    // Vehicle colors
    Color32 c;
    c = LocalData.primaryColor; 
    runtimePlayer.primaryColor = new ColorRGBA(c.r, c.g, c.b);
    c = LocalData.secondaryColor; 
    runtimePlayer.secondaryColor = new ColorRGBA(c.r, c.g, c.b);
    c = LocalData.trailColor; 
    runtimePlayer.trailColor = new ColorRGBA(c.r, c.g, c.b);
    
    // Add player to game
    QuantumRunner.Default.Game.AddPlayer(runtimePlayer);
}
```

### Player Vehicle Creation

```csharp
public unsafe class PlayerVehicleSpawner : SystemSignalsOnly, ISignalOnPlayerConnected
{
    public void OnPlayerConnected(Frame f, PlayerRef player)
    {
        var playerData = f.GetPlayerData(player);
        if (playerData == null) return;
        
        // Find spawn point
        var spawnPoint = GetAvailableSpawnPoint(f, player);
        
        // Create vehicle entity
        var vehiclePrototype = f.FindAsset<EntityPrototype>(playerData.VehiclePrototype);
        var vehicle = f.Create(vehiclePrototype);
        
        // Set player link
        if (f.Unsafe.TryGetPointer<PlayerLink>(vehicle, out var playerLink))
        {
            playerLink->PlayerRef = player;
        }
        
        // Apply customization
        if (f.Unsafe.TryGetPointer<VehicleCustomization>(vehicle, out var customization))
        {
            customization->PrimaryColor = playerData.primaryColor;
            customization->SecondaryColor = playerData.secondaryColor;
            customization->TrailColor = playerData.trailColor;
        }
        
        // Position at spawn
        if (f.Unsafe.TryGetPointer<Transform3D>(vehicle, out var transform))
        {
            transform->Position = spawnPoint.Position;
            transform->Rotation = spawnPoint.Rotation;
        }
        
        // Initialize vehicle stats
        InitializeVehicleStats(f, vehicle);
        
        f.Events.PlayerVehicleSpawned(player, vehicle);
    }
}
```

## Connection State Monitoring

### Player Presence Tracking

```csharp
public class PlayerConnectionTracker : SystemMainThread
{
    private Dictionary<PlayerRef, PlayerConnectionState> connectionStates = new();
    
    public struct PlayerConnectionState
    {
        public bool IsConnected;
        public FP LastInputTime;
        public int MissedInputFrames;
    }
    
    public override void Update(Frame f)
    {
        for (PlayerRef player = 0; player < f.PlayerCount; player++)
        {
            var inputFlags = f.GetPlayerInputFlags(player);
            bool isPresent = (inputFlags & DeterministicInputFlags.PlayerNotPresent) == 0;
            
            if (!connectionStates.TryGetValue(player, out var state))
            {
                state = new PlayerConnectionState();
            }
            
            // Track connection changes
            if (isPresent != state.IsConnected)
            {
                state.IsConnected = isPresent;
                
                if (!isPresent)
                {
                    HandlePlayerDisconnect(f, player);
                }
                else
                {
                    HandlePlayerReconnect(f, player);
                }
            }
            
            // Track input reliability
            if (isPresent)
            {
                if ((inputFlags & DeterministicInputFlags.HasInput) != 0)
                {
                    state.LastInputTime = f.Time;
                    state.MissedInputFrames = 0;
                }
                else
                {
                    state.MissedInputFrames++;
                }
            }
            
            connectionStates[player] = state;
        }
    }
}
```

## Disconnection Handling

### Vehicle AI Takeover

```csharp
public unsafe class DisconnectedVehicleHandler : SystemMainThread
{
    public override void Update(Frame f)
    {
        var filter = f.Filter<PlayerLink, VehicleController>();
        
        while (filter.NextUnsafe(out var entity, out var playerLink, out var controller))
        {
            var inputFlags = f.GetPlayerInputFlags(playerLink->PlayerRef);
            bool isDisconnected = (inputFlags & DeterministicInputFlags.PlayerNotPresent) != 0;
            
            if (isDisconnected && !controller->IsAIControlled)
            {
                ConvertToAI(f, entity, playerLink, controller);
            }
        }
    }
    
    private void ConvertToAI(Frame f, EntityRef entity, PlayerLink* playerLink, VehicleController* controller)
    {
        // Mark as AI controlled
        controller->IsAIControlled = true;
        playerLink->DisconnectTime = f.Time;
        
        // Add basic AI behavior
        f.Add(entity, new VehicleAI
        {
            Behavior = VehicleAI.BehaviorType.Defensive,
            TargetSelection = VehicleAI.TargetMode.Nearest,
            AggressionLevel = FP._0_50
        });
        
        // Reduce vehicle performance to balance gameplay
        if (f.Unsafe.TryGetPointer<VehicleStats>(entity, out var stats))
        {
            stats->MaxSpeed *= FP._0_75;
            stats->Acceleration *= FP._0_75;
        }
        
        f.Events.PlayerDisconnected(playerLink->PlayerRef);
    }
}
```

### Cleanup and Resource Management

```csharp
public class DisconnectionCleanup : QuantumCallbacks
{
    public override void OnPlayerRemoved(PlayerRef player, QuantumGame game)
    {
        // Find and remove player's vehicle
        var frame = game.Frames.Verified;
        var filter = frame.Filter<PlayerLink>();
        
        while (filter.NextUnsafe(out var entity, out var playerLink))
        {
            if (playerLink->PlayerRef == player)
            {
                // Store final stats
                StorePlayerStats(frame, entity, player);
                
                // Destroy vehicle after delay
                ScheduleVehicleRemoval(frame, entity);
                break;
            }
        }
    }
    
    private void ScheduleVehicleRemoval(Frame frame, EntityRef vehicle)
    {
        // Add destruction timer component
        frame.Add(vehicle, new DestructionTimer
        {
            TimeRemaining = FP._3, // 3 seconds
            DestroyOnExpire = true
        });
        
        // Trigger explosion effect
        frame.Events.VehicleDestroyed(vehicle, true);
    }
}
```

## Player Rejoining

### Reconnection Support

```csharp
public class PlayerReconnectionHandler : IConnectionCallbacks
{
    private Dictionary<string, PlayerSessionData> disconnectedPlayers = new();
    
    public void OnPlayerDisconnected(Player player)
    {
        // Store session data for potential reconnection
        var sessionData = new PlayerSessionData
        {
            UserId = player.UserId,
            Nickname = player.NickName,
            DisconnectTime = Time.time,
            Score = GetPlayerScore(player),
            VehicleHealth = GetVehicleHealth(player)
        };
        
        disconnectedPlayers[player.UserId] = sessionData;
    }
    
    public void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        // Check if this is a reconnecting player
        if (disconnectedPlayers.TryGetValue(targetPlayer.UserId, out var sessionData))
        {
            float disconnectDuration = Time.time - sessionData.DisconnectTime;
            
            if (disconnectDuration < 30f) // 30 second grace period
            {
                RestorePlayerSession(targetPlayer, sessionData);
                disconnectedPlayers.Remove(targetPlayer.UserId);
            }
        }
    }
}
```

## Network Quality Management

### Connection Quality Monitoring

```csharp
public class NetworkQualityMonitor : MonoBehaviour
{
    [SerializeField] private NetworkIndicatorUI networkIndicator;
    private float poorConnectionThreshold = 150f; // ms
    
    void Update()
    {
        if (Matchmaker.Client == null || !Matchmaker.Client.InRoom) return;
        
        // Get network stats
        var stats = QuantumRunner.Default?.Session?.Stats;
        if (stats == null) return;
        
        // Update UI indicator
        networkIndicator.SetPing(stats.Ping);
        networkIndicator.SetPacketLoss(stats.PacketLoss);
        
        // Show warnings for poor connection
        if (stats.Ping > poorConnectionThreshold || stats.PacketLoss > 0.05f)
        {
            ShowPoorConnectionWarning(stats.Ping, stats.PacketLoss);
        }
        
        // Handle severe connection issues
        if (stats.Ping > 500 || stats.PacketLoss > 0.15f)
        {
            ConsiderDisconnection();
        }
    }
    
    private void ConsiderDisconnection()
    {
        // Show dialog asking if player wants to leave
        InterfaceManager.Instance.ShowConnectionDialog(
            "Poor connection detected. Continue playing?",
            onContinue: () => { /* Keep playing */ },
            onLeave: () => { Matchmaker.Disconnect(); }
        );
    }
}
```

## Player State Persistence

### Score and Stats Tracking

```csharp
public struct PlayerPersistentStats
{
    public int Score;
    public int Eliminations;
    public int Deaths;
    public FP DamageDealt;
    public FP DistanceTraveled;
}

public unsafe class PlayerStatsTracker : SystemMainThreadFilter<PlayerStatsTracker.Filter>
{
    public struct Filter
    {
        public EntityRef Entity;
        public PlayerLink* Link;
        public VehicleStats* Stats;
    }
    
    private Dictionary<PlayerRef, PlayerPersistentStats> playerStats = new();
    
    public override void Update(Frame f, ref Filter filter)
    {
        if (!playerStats.TryGetValue(filter.Link->PlayerRef, out var stats))
        {
            stats = new PlayerPersistentStats();
        }
        
        // Update stats
        stats.Score = filter.Stats->Score;
        stats.Eliminations = filter.Stats->Eliminations;
        stats.DamageDealt = filter.Stats->TotalDamageDealt;
        
        playerStats[filter.Link->PlayerRef] = stats;
        
        // Sync to UI
        if (f.Number % 30 == 0) // Every half second
        {
            f.Events.PlayerStatsUpdated(filter.Link->PlayerRef, stats);
        }
    }
}
```

## Connection Events

### Event Broadcasting

```csharp
void IInRoomCallbacks.OnPlayerEnteredRoom(Player newPlayer)
{
    Log($"Player {newPlayer} entered the room");
    OnRealtimePlayerJoined?.Invoke(newPlayer);
    
    // Notify game systems
    BroadcastPlayerJoined(newPlayer);
    
    // Update UI
    RefreshPlayerList();
    ShowPlayerJoinedNotification(newPlayer.NickName);
}

void IInRoomCallbacks.OnPlayerLeftRoom(Player otherPlayer)
{
    Log($"Player {otherPlayer} left the room");
    OnRealtimePlayerLeft?.Invoke(otherPlayer);
    
    // Handle mid-game departure
    if (IsGameInProgress())
    {
        ConvertPlayerVehicleToAI(otherPlayer);
    }
    
    // Update UI
    RefreshPlayerList();
    ShowPlayerLeftNotification(otherPlayer.NickName);
}
```

## Best Practices

1. **Convert disconnected vehicles to AI** to maintain game balance
2. **Store player stats** for post-game results
3. **Implement reconnection grace period** for brief disconnects
4. **Monitor connection quality** and provide feedback
5. **Clean up resources** after player removal
6. **Handle edge cases** like host migration
7. **Test with unstable connections** to ensure robustness
8. **Provide clear UI feedback** for all connection states

## Common Patterns

### Host Migration

```csharp
void IInRoomCallbacks.OnMasterClientSwitched(Player newMasterClient)
{
    Log($"New host: {newMasterClient.NickName}");
    
    // Update UI to show new host
    UpdateHostIndicator(newMasterClient);
    
    // Re-validate game state if needed
    if (IsInLobby())
    {
        ValidateLobbyState();
    }
}
```

### Connection Recovery

```csharp
public async Task AttemptConnectionRecovery()
{
    int retryCount = 0;
    const int maxRetries = 3;
    
    while (retryCount < maxRetries)
    {
        try
        {
            await Task.Delay(1000 * (retryCount + 1));
            
            if (await TryReconnect())
            {
                ShowNotification("Connection restored!");
                return;
            }
        }
        catch (Exception e)
        {
            Debug.LogError($"Recovery attempt {retryCount + 1} failed: {e}");
        }
        
        retryCount++;
    }
    
    // Recovery failed
    ShowError("Unable to restore connection");
    ReturnToMainMenu();
}
```

This comprehensive connection management system ensures Motor Dome maintains smooth gameplay even with player disconnections and network issues.
