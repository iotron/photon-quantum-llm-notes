# Player Connection Management - Sports Arena Brawler

Sports Arena Brawler implements a robust player connection system that handles both **local device connections** and **network connections with multiple local players per client**. This dual approach provides flexibility for various gameplay scenarios.

## Connection Management Architecture

### Local Connection Management

Focuses on direct input device management and player sessions within a single game instance.

#### Core Components

##### Device Connection Handler
```csharp
public class DeviceConnectionHandler : MonoBehaviour
{
    private Dictionary<int, DeviceState> deviceStates = new();
    private Dictionary<int, LocalPlayerSession> activeSessions = new();
    
    public void OnDeviceConnected(InputDevice device)
    {
        deviceStates[device.deviceId] = DeviceState.Available;
        
        // Check if device should auto-join
        if (ShouldAutoJoin(device))
        {
            AttemptPlayerJoin(device);
        }
    }
    
    public void OnDeviceDisconnected(InputDevice device)
    {
        if (IsAssignedToPlayer(device))
        {
            HandlePlayerDisconnect(device);
        }
        deviceStates.Remove(device.deviceId);
    }
}
```

##### Local Player Session
```csharp
public struct LocalPlayerSession
{
    public int PlayerId;
    public int DeviceId;
    public PlayerInput Input;
    public CameraController Camera;
    public GameObject Character;
    public QuantumPlayerRef QuantumRef;
    public ConnectionState State;
}

public enum ConnectionState
{
    Disconnected,
    Joining,
    Connected,
    Leaving
}
```

### Network Connection Management

Handles multiple local players per network client, enabling complex scenarios like online play with local friends.

#### Player Identification System

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

## Connection Flows

### Local Device Connection Flow

1. **Device Detection**
   ```csharp
   PlayerInputManager.instance.onPlayerJoined += OnPlayerJoined;
   PlayerInputManager.instance.onPlayerLeft += OnPlayerLeft;
   ```

2. **Player Assignment**
   ```csharp
   public void OnPlayerJoined(PlayerInput playerInput)
   {
       // Assign next available slot
       int slot = GetNextAvailableSlot();
       
       // Create session
       var session = new LocalPlayerSession
       {
           PlayerId = slot,
           DeviceId = playerInput.devices[0].deviceId,
           Input = playerInput,
           State = ConnectionState.Joining
       };
       
       // Register with Quantum
       RegisterWithQuantum(session);
   }
   ```

3. **Quantum Integration**
   ```csharp
   private void RegisterWithQuantum(LocalPlayerSession session)
   {
       var playerData = new RuntimePlayer
       {
           PlayerNickname = $"Player {session.PlayerId + 1}",
           LocalPlayerId = session.PlayerId
       };
       
       session.QuantumRef = QuantumRunner.Default.Game.AddPlayer(playerData);
       session.State = ConnectionState.Connected;
   }
   ```

### Network Connection Flow

1. **Initial Connection with Multiple Players**
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
                   CustomData = SerializePlayerPreferences(i)
               };
           }
           
           return await base.ConnectAsyncInternal(connectArgs);
       }
   }
   ```

2. **Player Slot Allocation**
   ```csharp
   public class PlayerSlotManager : SystemMainThread
   {
       public override void OnPlayerConnected(Frame f, PlayerRef player)
       {
           var localPlayers = f.Game.GetLocalPlayers();
           if (localPlayers.Contains(player))
           {
               // Allocate team slot based on balance
               AllocateTeamSlot(f, player);
               
               // Create player entity
               CreatePlayerEntity(f, player);
           }
       }
       
       private void AllocateTeamSlot(Frame f, PlayerRef player)
       {
           int team1Count = CountPlayersInTeam(f, 0);
           int team2Count = CountPlayersInTeam(f, 1);
           
           int assignedTeam = team1Count <= team2Count ? 0 : 1;
           
           var playerData = f.GetPlayerData(player);
           playerData.Team = assignedTeam;
       }
   }
   ```

## Connection State Management

### Per-Player Connection Monitoring

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
                HandleDisconnection(f, filter, playerRef);
            }
            else if (isConnected && !wasConnected)
            {
                HandleReconnection(f, filter, playerRef);
            }
        }
    }
    
    private void HandleDisconnection(Frame f, ref Filter filter, PlayerRef playerRef)
    {
        filter.Link->DisconnectTime = f.Time;
        f.Events.PlayerDisconnected(playerRef);
        
        // Start grace period for reconnection
        StartReconnectionTimer(f, playerRef);
    }
    
    private void HandleReconnection(Frame f, ref Filter filter, PlayerRef playerRef)
    {
        var timeSinceDisconnect = f.Time - filter.Link->DisconnectTime;
        
        if (timeSinceDisconnect < FP._10) // Within 10 seconds
        {
            // Restore existing state
            filter.Link->DisconnectTime = FP._0;
            f.Events.PlayerReconnected(playerRef);
        }
        else
        {
            // Reset player
            ResetPlayerToSpawn(f, filter.Entity);
        }
    }
}
```

## Disconnection Handling

### Local Player Disconnection

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
            
            // Cleanup sequence
            StartCoroutine(GracefulDisconnect(playerRef));
        }
    }
    
    private IEnumerator GracefulDisconnect(PlayerRef playerRef)
    {
        // Show leaving animation
        yield return PlayDisconnectAnimation(playerRef);
        
        // Remove from game
        QuantumRunner.Default.Game.RemovePlayer(playerRef);
        
        // Update local tracking
        LocalPlayersManager.Instance.RemoveLocalPlayer(playerRef);
        
        // Reconfigure viewports
        CameraManager.Instance.ReconfigureViewports();
        
        // Update room properties if online
        if (IsOnlineMode())
        {
            UpdateLocalPlayerCount();
        }
    }
}
```

### Network Client Disconnection

```csharp
public class ClientDisconnectHandler : QuantumCallbacks
{
    public override void OnPlayerRemoved(PlayerRef player, QuantumGame game)
    {
        // Check if entire client disconnected
        var client = game.GetPlayerClient(player);
        bool hasOtherPlayersFromClient = CheckForOtherPlayersFromClient(game, client, player);
        
        if (!hasOtherPlayersFromClient)
        {
            // Entire client disconnected
            HandleClientDisconnect(client);
        }
        else
        {
            // Just one local player left
            HandleSinglePlayerDisconnect(player);
        }
    }
    
    private void HandleClientDisconnect(int clientId)
    {
        // Update room total players
        if (PhotonNetwork.IsMasterClient)
        {
            RecalculateTotalPlayers();
        }
        
        // Clean up client-specific resources
        CleanupClientResources(clientId);
    }
}
```

## Input Assignment System

### Multi-Player Input Handling

```csharp
public class LocalPlayerInputHandler : QuantumEntityViewComponent
{
    private int _localPlayerIndex;
    private string _inputPrefix;
    private InputDevice _assignedDevice;
    
    public override void OnActivate(Frame frame)
    {
        var playerLink = GetPredictedQuantumComponent<PlayerLink>();
        if (playerLink == null) return;
        
        // Determine if this is a local player
        var localPlayers = QuantumRunner.Default.Game.GetLocalPlayers();
        _localPlayerIndex = localPlayers.IndexOf(playerLink.PlayerRef);
        
        if (_localPlayerIndex >= 0)
        {
            SetupLocalInput();
        }
        else
        {
            enabled = false;
        }
    }
    
    private void SetupLocalInput()
    {
        // Get assigned device
        _assignedDevice = LocalPlayersManager.Instance.GetDeviceForPlayer(_localPlayerIndex);
        
        // Set up input prefix for keyboard fallback
        _inputPrefix = _localPlayerIndex == 0 ? "" : $"P{_localPlayerIndex + 1}_";
        
        // Subscribe to input polling
        QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
    }
    
    private void PollInput(CallbackPollInput callback)
    {
        if (callback.PlayerRef != GetComponent<QuantumEntityView>().PlayerRef) return;
        
        var input = new Quantum.Input();
        
        if (_assignedDevice != null)
        {
            // Use device-specific input
            input.Movement = ReadMovementFromDevice(_assignedDevice);
            input.Actions = ReadActionsFromDevice(_assignedDevice);
        }
        else
        {
            // Fallback to keyboard with prefix
            input.Movement = ReadMovementFromKeyboard(_inputPrefix);
            input.Actions = ReadActionsFromKeyboard(_inputPrefix);
        }
        
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
    public Dictionary<string, object> CustomData;
}

public class PlayerReconnectionManager : SystemMainThread
{
    private Dictionary<string, PlayerPersistentData> _disconnectedPlayerData = new();
    
    public void OnPlayerDisconnected(Frame f, PlayerRef player)
    {
        var playerData = f.GetPlayerData(player);
        if (playerData == null) return;
        
        // Store persistent data
        var persistentData = GatherPlayerData(f, player);
        _disconnectedPlayerData[playerData.ClientId] = persistentData;
        
        // Set reconnection timeout
        SetReconnectionTimeout(playerData.ClientId, 30f); // 30 seconds
    }
    
    public void OnPlayerReconnected(Frame f, PlayerRef player, string clientId)
    {
        if (_disconnectedPlayerData.TryGetValue(clientId, out var persistentData))
        {
            RestorePlayerState(f, player, persistentData);
            _disconnectedPlayerData.Remove(clientId);
        }
        else
        {
            // New player or timeout expired
            InitializeNewPlayer(f, player);
        }
    }
}
```

## Session Continuity

### Between Rounds
```csharp
public class SessionContinuityManager : MonoBehaviour
{
    private List<LocalPlayerSession> _persistentSessions = new();
    
    public void OnRoundEnd()
    {
        // Save all active sessions
        _persistentSessions.Clear();
        foreach (var session in GetActiveSessions())
        {
            _persistentSessions.Add(session);
        }
    }
    
    public void OnRoundStart()
    {
        // Restore sessions
        foreach (var session in _persistentSessions)
        {
            if (IsDeviceStillConnected(session.DeviceId))
            {
                RestoreSession(session);
            }
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
            
            // Handle severe connection issues
            if (stats.PacketLoss > 0.15f || stats.Ping > 500)
            {
                ConsiderPlayerMigration(playerRef);
            }
        }
    }
}
```

## Error Handling

### Common Issues and Recovery

```csharp
public class ConnectionErrorHandler : MonoBehaviour
{
    public void HandleConnectionError(ConnectionError error, PlayerRef player)
    {
        switch (error.Type)
        {
            case ConnectionErrorType.DeviceDisconnected:
                ShowReconnectPrompt(player);
                EnableAITakeover(player);
                break;
                
            case ConnectionErrorType.NetworkTimeout:
                StartReconnectionAttempt(player);
                break;
                
            case ConnectionErrorType.SessionFull:
                ShowSessionFullMessage();
                break;
                
            case ConnectionErrorType.VersionMismatch:
                ShowUpdateRequiredMessage();
                break;
        }
    }
}
```

## Best Practices

### Local Connections
1. **Clear Visual Feedback**
   - Connection status indicators
   - Device icons and player colors
   - Join/leave animations

2. **Robust Device Handling**
   - Support hot-swapping
   - Handle battery disconnects
   - Manage device conflicts

### Network Connections
1. **Track local player indices** for proper input and UI assignment
2. **Handle partial client disconnections** when only some local players leave
3. **Implement reconnection grace periods** appropriate for game type
4. **Store minimal persistent data** for reconnecting players
5. **Test with maximum local players** under poor network conditions

### Performance
1. **Input Polling Optimization**
   - Batch process all local players
   - Use event-driven input where possible
   - Align with Quantum simulation

2. **Resource Management**
   - Pool player objects
   - Lazy load player resources
   - Clean up properly on disconnect

## Debugging Tools

### Connection Monitor
```csharp
[System.Serializable]
public class ConnectionDebugInfo
{
    public void DrawDebugGUI()
    {
        GUILayout.BeginVertical("box");
        GUILayout.Label("=== Connection Status ===");
        
        // Local connections
        GUILayout.Label($"Local Players: {GetLocalPlayerCount()}");
        foreach (var session in GetLocalSessions())
        {
            GUILayout.Label($"  P{session.PlayerId}: {session.State} - Device: {session.DeviceId}");
        }
        
        // Network status
        if (IsOnlineMode())
        {
            GUILayout.Label($"Network Ping: {GetAveragePing()}ms");
            GUILayout.Label($"Packet Loss: {GetPacketLoss():P}");
        }
        
        GUILayout.EndVertical();
    }
}
```

This comprehensive connection management system enables Sports Arena Brawler to seamlessly handle various multiplayer scenarios while maintaining stable and responsive gameplay.