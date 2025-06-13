# Player Connection Management - Quantum Motor Dome

## Overview

Quantum Motor Dome implements a **streamlined connection system** optimized for quick competitive matches. It features automatic reconnection, custom RealtimeClient management, and seamless transitions between matches without returning to the main menu.

## Connection Architecture

### 1. **Custom Client Management**
```csharp
public class Matchmaker : QuantumCallbacks, IConnectionCallbacks, 
                          IMatchmakingCallbacks, IInRoomCallbacks
{
    public static RealtimeClient Client { get; private set; }
    
    private void Awake()
    {
        // Custom RealtimeClient instead of PhotonNetwork
        Client = new RealtimeClient();
        Client.AddCallbackTarget(Instance);
        
        AppSettings = new AppSettings(PhotonServerSettings.Global.AppSettings);
    }
    
    private void Update()
    {
        Client?.Service(); // Manual update loop
    }
}
```

### 2. **Connection Layers**
- **RealtimeClient**: Direct Photon client control
- **Matchmaker**: Centralized connection management
- **QuantumRunner**: Deterministic game simulation
- **Event System**: Custom event handling

## Connection Flow

### 1. **Initial Connection**
```csharp
public static void Connect(System.Action<ConnectionStatus> statusUpdatedCallback)
{
    if (Client.IsConnected) return;
    
    onStatusUpdated = statusUpdatedCallback;
    
    if (Client.ConnectUsingSettings(AppSettings))
    {
        onStatusUpdated?.Invoke(new ConnectionStatus(
            "Establishing Connection", 
            State.ConnectingToServer
        ));
    }
    else
    {
        onStatusUpdated?.Invoke(new ConnectionStatus(
            "Unable to Connect", 
            State.Failed
        ));
    }
}
```

### 2. **Automatic Room Creation**
```csharp
void IConnectionCallbacks.OnConnectedToMaster()
{
    Log("OnConnectedToMaster");
    
    // Skip traditional lobby, go straight to matchmaking
    JoinRandomRoomArgs joinRandomParams = new JoinRandomRoomArgs();
    EnterRoomArgs enterRoomParams = new EnterRoomArgs()
    {
        RoomOptions = new RoomOptions()
        {
            IsVisible = true,
            MaxPlayers = maxPlayers,
            Plugins = new string[] { "QuantumPlugin" },
            PlayerTtl = PhotonServerSettings.Global.PlayerTtlInSeconds * 1000,
            EmptyRoomTtl = PhotonServerSettings.Global.EmptyRoomTtlInSeconds * 1000
        }
    };
    
    if (Client.OpJoinRandomOrCreateRoom(joinRandomParams, enterRoomParams))
    {
        onStatusUpdated?.Invoke(new ConnectionStatus(
            "Connecting To Room", 
            State.ConnectingToRoom
        ));
    }
}
```

## Player Identification

### Unique Player System
```csharp
public class PlayerIdentity
{
    public static string GetOrCreateUserId()
    {
        string userId = PlayerPrefs.GetString("UserId", "");
        
        if (string.IsNullOrEmpty(userId))
        {
            // Generate unique ID
            userId = System.Guid.NewGuid().ToString();
            PlayerPrefs.SetString("UserId", userId);
        }
        
        return userId;
    }
    
    public static void ConfigureClient()
    {
        Client.UserId = GetOrCreateUserId();
        Client.NickName = LocalData.nickname;
    }
}
```

### Player Data Persistence
```csharp
public class PlayerDataManager
{
    public static void SavePlayerData()
    {
        var data = new PlayerSaveData
        {
            Nickname = LocalData.nickname,
            PrimaryColor = LocalData.primaryColor,
            SecondaryColor = LocalData.secondaryColor,
            TrailColor = LocalData.trailColor,
            LastRegion = Client.CloudRegion,
            Statistics = GetPlayerStats()
        };
        
        string json = JsonUtility.ToJson(data);
        PlayerPrefs.SetString("PlayerData", json);
    }
    
    public static void LoadPlayerData()
    {
        string json = PlayerPrefs.GetString("PlayerData", "");
        if (!string.IsNullOrEmpty(json))
        {
            var data = JsonUtility.FromJson<PlayerSaveData>(json);
            ApplyPlayerData(data);
        }
    }
}
```

## Connection State Management

### State Transitions
```csharp
public class ConnectionStateManager
{
    private State currentState = State.Undefined;
    private static System.Action<ConnectionStatus> onStatusUpdated;
    
    public void UpdateState(State newState, string message)
    {
        if (IsValidTransition(currentState, newState))
        {
            currentState = newState;
            onStatusUpdated?.Invoke(new ConnectionStatus(message, newState));
            
            HandleStateChange(newState);
        }
    }
    
    private void HandleStateChange(State state)
    {
        switch (state)
        {
            case State.ConnectingToServer:
                ShowConnectingUI();
                break;
                
            case State.JoinedRoom:
                InitializeElevatorLobby();
                break;
                
            case State.GameStarted:
                TransitionToGame();
                break;
                
            case State.Failed:
                ShowErrorDialog();
                break;
        }
    }
}
```

### Connection Monitoring
```csharp
public class ConnectionMonitor : MonoBehaviour
{
    private float pingInterval = 1f;
    private float timeoutThreshold = 10f;
    private float lastPingTime;
    
    void Start()
    {
        InvokeRepeating(nameof(CheckConnection), 1f, pingInterval);
    }
    
    void CheckConnection()
    {
        if (Client != null && Client.IsConnected)
        {
            int ping = Client.LoadBalancingPeer.RoundTripTime;
            UpdatePingDisplay(ping);
            
            // Check for timeout
            if (Time.time - lastPingTime > timeoutThreshold)
            {
                HandleConnectionTimeout();
            }
        }
    }
}
```

## Room Management

### Dynamic Room Properties
```csharp
public class RoomManager
{
    public static void ConfigureRoom()
    {
        if (Client.LocalPlayer.IsMasterClient)
        {
            var properties = new Hashtable
            {
                ["GameMode"] = "Arena",
                ["Map"] = SelectRandomMap(),
                ["StartTime"] = Client.ServerTimeInMilliSeconds,
                ["MatchId"] = System.Guid.NewGuid().ToString()
            };
            
            Client.CurrentRoom.SetCustomProperties(properties);
        }
    }
    
    public static void UpdateRoomState(string state)
    {
        var update = new Hashtable { ["State"] = state };
        Client.CurrentRoom.SetCustomProperties(update);
    }
}
```

### Player Slot Management
```csharp
public class PlayerSlotManager
{
    private static Dictionary<int, PlayerSlot> slots = new Dictionary<int, PlayerSlot>();
    
    public static void AssignPlayerSlot(Player player)
    {
        int slot = GetNextAvailableSlot();
        
        slots[player.ActorNumber] = new PlayerSlot
        {
            Player = player,
            SlotIndex = slot,
            JoinTime = DateTime.Now,
            IsReady = false
        };
        
        // Sync slot assignment
        player.SetCustomProperties(new Hashtable { ["Slot"] = slot });
    }
    
    public static void ReleasePlayerSlot(Player player)
    {
        if (slots.ContainsKey(player.ActorNumber))
        {
            int freedSlot = slots[player.ActorNumber].SlotIndex;
            slots.Remove(player.ActorNumber);
            
            // Make slot available for new players
            NotifySlotAvailable(freedSlot);
        }
    }
}
```

## Quantum Integration

### Game Session Start
```csharp
static void StartQuantumGame()
{
    SessionRunner.Arguments arguments = new SessionRunner.Arguments()
    {
        RuntimeConfig = Instance.runtimeConfig,
        GameMode = Photon.Deterministic.DeterministicGameMode.Multiplayer,
        PlayerCount = Client.CurrentRoom.MaxPlayers,
        ClientId = Client.LocalPlayer.UserId,
        Communicator = new QuantumNetworkCommunicator(Client),
        SessionConfig = QuantumDeterministicSessionConfigAsset.DefaultConfig,
    };
    
    QuantumRunner.StartGame(arguments);
}
```

### Player Data Injection
```csharp
void SendData()
{
    // Prepare runtime player data
    runtimePlayer.PlayerNickname = LocalData.nickname;
    
    Color32 c;
    c = LocalData.primaryColor; 
    runtimePlayer.primaryColor = new ColorRGBA(c.r, c.g, c.b);
    c = LocalData.secondaryColor; 
    runtimePlayer.secondaryColor = new ColorRGBA(c.r, c.g, c.b);
    c = LocalData.trailColor; 
    runtimePlayer.trailColor = new ColorRGBA(c.r, c.g, c.b);
    
    // Add to Quantum game
    QuantumRunner.Default.Game.AddPlayer(runtimePlayer);
}
```

## Disconnection Handling

### Graceful Disconnect
```csharp
public static void Disconnect()
{
    // Shutdown Quantum first
    QuantumRunner.ShutdownAll();
    Debug.Log("Shutdown");
    
    // Then disconnect network
    Client.Disconnect();
}
```

### Disconnect Recovery
```csharp
public void OnDisconnected(DisconnectCause cause)
{
    LogWarning($"Disconnected: {cause}");
    QuantumRunner.ShutdownAll();
    
    // Reset visual state
    InterfaceManager.Instance.elevatorObj.SetActive(false);
    AudioManager.LerpVolume(AudioManager.Instance.crowdSource, 0f, 0.5f);
    AudioManager.SetSnapshot("Default", 0.5f);
    if (CameraController.Instance) 
        CameraController.Instance.Effects.Unblur(0);
    
    // Handle based on cause
    switch (cause)
    {
        case DisconnectCause.DisconnectByClientLogic:
            // Intentional disconnect
            UnityEngine.SceneManagement.SceneManager.LoadScene(menuScene);
            break;
            
        case DisconnectCause.ServerTimeout:
        case DisconnectCause.ClientTimeout:
            // Try to reconnect
            AttemptReconnection();
            break;
            
        default:
            // Return to menu
            if (!isRequeueing)
            {
                UIScreen.activeScreen.BackTo(InterfaceManager.Instance.mainMenuScreen);
                UIScreen.Focus(InterfaceManager.Instance.playmodeScreen);
            }
            break;
    }
}
```

## Network Events

### Custom Event System
```csharp
void IOnEventCallback.OnEvent(EventData photonEvent)
{
    switch (photonEvent.Code)
    {
        case 0: // Start game event
            StartQuantumGame();
            break;
            
        case 1: // Player ready event
            HandlePlayerReady(photonEvent);
            break;
            
        case 2: // Match result event
            HandleMatchResult(photonEvent);
            break;
    }
}

public static void SendStartGameEvent()
{
    Client.OpRaiseEvent(0, null, 
        new RaiseEventArgs() { Receivers = ReceiverGroup.All }, 
        SendOptions.SendReliable);
}
```

### Event Reliability
```csharp
public class ReliableEventManager
{
    private Queue<PendingEvent> pendingEvents = new Queue<PendingEvent>();
    
    public void SendReliableEvent(byte eventCode, object data)
    {
        var pendingEvent = new PendingEvent
        {
            Code = eventCode,
            Data = data,
            SendTime = Time.time,
            Attempts = 0
        };
        
        if (!TrySendEvent(pendingEvent))
        {
            pendingEvents.Enqueue(pendingEvent);
        }
    }
    
    void Update()
    {
        // Retry pending events
        if (pendingEvents.Count > 0 && Client.IsConnectedAndReady)
        {
            var pending = pendingEvents.Peek();
            if (TrySendEvent(pending))
            {
                pendingEvents.Dequeue();
            }
        }
    }
}
```

## Performance Optimization

### Connection Pooling
```csharp
public class ConnectionOptimizer
{
    public static void OptimizeForArenaMatch()
    {
        // High frequency updates for fast-paced gameplay
        Client.LoadBalancingPeer.SendRate = 60;
        Client.LoadBalancingPeer.SerializationRate = 30;
        
        // Reduce overhead
        Client.LoadBalancingPeer.DisconnectTimeout = 10000;
        Client.LoadBalancingPeer.EnableLobbyStatistics = false;
    }
    
    public static void OptimizeForLobby()
    {
        // Lower rates while waiting
        Client.LoadBalancingPeer.SendRate = 20;
        Client.LoadBalancingPeer.SerializationRate = 10;
    }
}
```

### Bandwidth Management
```csharp
public class BandwidthMonitor
{
    public static void MonitorUsage()
    {
        var stats = Client.LoadBalancingPeer.TrafficStatsIncoming;
        
        if (stats.TotalPacketBytes > BANDWIDTH_WARNING_THRESHOLD)
        {
            WarnHighBandwidth();
            ReduceUpdateRates();
        }
    }
}
```

## Best Practices

### 1. **Quick Reconnection**
- Maintain user ID across sessions
- Cache last room info
- Implement exponential backoff

### 2. **State Synchronization**
- Use reliable events for critical data
- Implement state validation
- Handle out-of-order messages

### 3. **Error Recovery**
- Graceful degradation
- Clear error messages
- Automatic retry logic

## Debugging Tools

### Connection Debugger
```csharp
public class MotorDomeDebugger : MonoBehaviour
{
    void OnGUI()
    {
        if (!Debug.isDebugBuild) return;
        
        GUI.Box(new Rect(10, 10, 300, 200), "Connection Debug");
        
        GUILayout.BeginArea(new Rect(15, 35, 290, 160));
        
        // Connection info
        GUILayout.Label($"State: {Matchmaker.Instance.CurrentState}");
        GUILayout.Label($"Connected: {Client?.IsConnected ?? false}");
        GUILayout.Label($"In Room: {Client?.InRoom ?? false}");
        GUILayout.Label($"Players: {Client?.CurrentRoom?.PlayerCount ?? 0}");
        
        // Network stats
        if (Client != null && Client.IsConnected)
        {
            var peer = Client.LoadBalancingPeer;
            GUILayout.Label($"Ping: {peer.RoundTripTime}ms");
            GUILayout.Label($"Send Rate: {peer.SendRate}");
            GUILayout.Label($"Bytes In: {peer.BytesIn}");
            GUILayout.Label($"Bytes Out: {peer.BytesOut}");
        }
        
        // Actions
        if (GUILayout.Button("Force Disconnect"))
        {
            Matchmaker.Disconnect();
        }
        
        GUILayout.EndArea();
    }
}
```

### Network Event Logger
```csharp
public class EventLogger : IOnEventCallback
{
    private List<EventLog> eventHistory = new List<EventLog>();
    
    public void OnEvent(EventData photonEvent)
    {
        eventHistory.Add(new EventLog
        {
            Code = photonEvent.Code,
            Sender = photonEvent.Sender,
            Data = photonEvent.CustomData,
            Timestamp = Time.time
        });
        
        // Keep last 50 events
        if (eventHistory.Count > 50)
            eventHistory.RemoveAt(0);
        
        Debug.Log($"[Event] Code: {photonEvent.Code}, " +
                 $"Sender: {photonEvent.Sender}, " +
                 $"Data: {photonEvent.CustomData}");
    }
}
```
