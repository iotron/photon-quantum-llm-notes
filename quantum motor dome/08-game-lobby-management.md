# Game Lobby Management - Quantum Motor Dome

Quantum Motor Dome implements a vehicle combat arena lobby system with custom matchmaking, pre-game countdown, and room management. The game features a sophisticated lobby timer and player readiness system.

## Matchmaker Architecture

### Custom Connection System

**File: `/Assets/Scripts/Matchmaker.cs`**

```csharp
public class Matchmaker : QuantumCallbacks, IConnectionCallbacks, IMatchmakingCallbacks, IInRoomCallbacks, IOnEventCallback
{
    public static Matchmaker Instance { get; private set; }
    public static RealtimeClient Client { get; private set; }
    
    [SerializeField] byte maxPlayers = 6;
    [SerializeField] RuntimeConfig runtimeConfig;
    [SerializeField] RuntimePlayer runtimePlayer;
    
    public enum State
    {
        Undefined = 0,
        ConnectingToServer,
        ConnectingToRoom,
        JoinedRoom,
        GameStarted,
        Failed = -1
    }
    
    public static void Connect(System.Action<ConnectionStatus> statusUpdatedCallback)
    {
        if (Client.IsConnected) return;
        
        onStatusUpdated = statusUpdatedCallback;
        
        if (Client.ConnectUsingSettings(AppSettings))
        {
            onStatusUpdated?.Invoke(new ConnectionStatus("Establishing Connection", State.ConnectingToServer));
        }
        else
        {
            onStatusUpdated?.Invoke(new ConnectionStatus("Unable to Connect", State.Failed));
        }
    }
}
```

### Room Creation and Joining

```csharp
void IConnectionCallbacks.OnConnectedToMaster()
{
    Log("OnConnectedToMaster");
    
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
        onStatusUpdated?.Invoke(new ConnectionStatus("Connecting To Room", State.ConnectingToRoom));
    }
}
```

## Lobby Timer System

### In-Game Lobby Countdown

**File: `/Assets/QuantumUser/Simulation/Game/Systems/LobbySystem.cs`**

```csharp
unsafe class LobbySystem : SystemMainThread, IGameState_Lobby
{
    public override void OnEnabled(Frame f)
    {
        if (f.SessionConfig.PlayerCount > 1)
        {
            // Set lobby timer based on configuration
            f.Global->clock = FrameTimer.FromSeconds(f, f.SimulationConfig.lobbyingDuration);
        }
        else
        {
            // Skip lobby for single player
            GameStateSystem.SetState(f, GameState.Pregame);
        }
    }
    
    public override void Update(Frame f)
    {
        var expiredThisFrame = f.Global->clock.IsRunning(f) == false && 
                              f.Global->clock.TargetFrame == f.Number;
                              
        if (expiredThisFrame)
        {
            f.Global->clock = FrameTimer.None;
            GameStateSystem.SetState(f, GameState.Pregame);
        }
    }
}
```

### UI Timer Display

**File: `/Assets/Scripts/UI/LobbyTimer.cs`**

```csharp
public unsafe class LobbyTimer : MonoBehaviour
{
    private void Update()
    {
        if (QuantumRunner.Default == null) return;
        
        var f = QuantumRunner.Default.Game.Frames.Verified;
        if (f.Global->CurrentState != GameState.Lobby) return;
        
        var clock = f.Global->clock.RemainingSeconds(f);
        var value = clock.AsInt;
        
        InterfaceManager.Instance.sessionWaitingText.text = $"Match starting in {value:00}";
    }
}
```

## Player Data Management

### Custom Player Properties

```csharp
public class PlayerCustomization
{
    public string nickname;
    public Color32 primaryColor;
    public Color32 secondaryColor;
    public Color32 trailColor;
}

void SendData()
{
    runtimePlayer.PlayerNickname = LocalData.nickname;
    
    // Convert Unity colors to Quantum format
    Color32 c;
    c = LocalData.primaryColor; 
    runtimePlayer.primaryColor = new ColorRGBA(c.r, c.g, c.b);
    
    c = LocalData.secondaryColor; 
    runtimePlayer.secondaryColor = new ColorRGBA(c.r, c.g, c.b);
    
    c = LocalData.trailColor; 
    runtimePlayer.trailColor = new ColorRGBA(c.r, c.g, c.b);
    
    QuantumRunner.Default.Game.AddPlayer(runtimePlayer);
}
```

## Room State Management

### Player Join/Leave Handling

```csharp
void IInRoomCallbacks.OnPlayerEnteredRoom(Player newPlayer)
{
    Log($"Player {newPlayer} entered the room");
    OnRealtimePlayerJoined?.Invoke(newPlayer);
    
    // Update lobby UI
    UpdateLobbyPlayerList();
    
    // Reset lobby timer if needed
    if (ShouldResetTimer())
    {
        ResetLobbyCountdown();
    }
}

void IInRoomCallbacks.OnPlayerLeftRoom(Player otherPlayer)
{
    Log($"Player {otherPlayer} left the room");
    OnRealtimePlayerLeft?.Invoke(otherPlayer);
    
    // Check if we still have enough players
    if (Client.CurrentRoom.PlayerCount < 2)
    {
        ShowWaitingForPlayersMessage();
    }
}
```

## Game Start Synchronization

### Event-Based Start System

```csharp
public static void SendStartGameEvent()
{
    Client.OpRaiseEvent(0, null, new RaiseEventArgs() 
    { 
        Receivers = ReceiverGroup.All 
    }, SendOptions.SendReliable);
}

void IOnEventCallback.OnEvent(EventData photonEvent)
{
    if (photonEvent.Code == 0)
    {
        StartQuantumGame();
    }
}

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

## UI Integration

### Lobby Status Display

```csharp
public class LobbyUIManager : MonoBehaviour
{
    [SerializeField] private Text statusText;
    [SerializeField] private GameObject elevatorObj;
    [SerializeField] private PlayerSlotUI[] playerSlots;
    
    void Start()
    {
        Matchmaker.OnRealtimeJoinedRoom += OnJoinedRoom;
        Matchmaker.OnRealtimePlayerJoined += OnPlayerJoined;
        Matchmaker.OnRealtimePlayerLeft += OnPlayerLeft;
    }
    
    void OnJoinedRoom()
    {
        elevatorObj.SetActive(true);
        UpdatePlayerList();
        
        // Start ambient effects
        AudioManager.LerpVolume(AudioManager.Instance.crowdSource, 1f, 0.5f);
        AudioManager.SetSnapshot("Lobby", 0.5f);
    }
    
    void UpdatePlayerList()
    {
        var room = Matchmaker.Client?.CurrentRoom;
        if (room == null) return;
        
        for (int i = 0; i < playerSlots.Length; i++)
        {
            if (i < room.PlayerCount)
            {
                var player = room.Players.Values.ElementAt(i);
                playerSlots[i].SetPlayer(player.NickName);
                playerSlots[i].gameObject.SetActive(true);
            }
            else
            {
                playerSlots[i].gameObject.SetActive(false);
            }
        }
    }
}
```

## Disconnection Handling

### Clean Disconnection Flow

```csharp
public void OnDisconnected(DisconnectCause cause)
{
    LogWarning($"Disconnected: {cause}");
    QuantumRunner.ShutdownAll();
    
    // Clean up lobby state
    InterfaceManager.Instance.elevatorObj.SetActive(false);
    AudioManager.LerpVolume(AudioManager.Instance.crowdSource, 0f, 0.5f);
    AudioManager.SetSnapshot("Default", 0.5f);
    
    if (CameraController.Instance) 
        CameraController.Instance.Effects.Unblur(0);
        
    // Return to menu
    UnityEngine.SceneManagement.SceneManager.LoadScene(menuScene);
    
    if (!isRequeueing)
    {
        UIScreen.activeScreen.BackTo(InterfaceManager.Instance.mainMenuScreen);
        UIScreen.Focus(InterfaceManager.Instance.playmodeScreen);
    }
}
```

## Re-queuing System

### Automatic Re-queue

```csharp
public class RequeueManager : MonoBehaviour
{
    private bool isRequeueing = false;
    
    public void InitiateRequeue()
    {
        isRequeueing = true;
        
        // Disconnect from current room
        Matchmaker.Disconnect();
        
        // Wait and reconnect
        StartCoroutine(RequeueCoroutine());
    }
    
    private IEnumerator RequeueCoroutine()
    {
        yield return new WaitForSeconds(2f);
        
        // Show requeue UI
        ShowRequeueStatus("Finding new match...");
        
        // Connect to new room
        Matchmaker.Connect((status) =>
        {
            UpdateRequeueStatus(status);
            
            if (status.State == Matchmaker.State.JoinedRoom)
            {
                isRequeueing = false;
                HideRequeueStatus();
            }
        });
    }
}
```

## Arena Selection

### Map Configuration

```csharp
public class ArenaSelector : MonoBehaviour
{
    [SerializeField] private ArenaConfig[] availableArenas;
    private int selectedArenaIndex = 0;
    
    public void SelectArena(int index)
    {
        selectedArenaIndex = index;
        
        // Update runtime config
        var config = Matchmaker.Instance.runtimeConfig;
        config.Map = availableArenas[index].MapAsset;
        
        // Update room properties if master
        if (Matchmaker.Client?.LocalPlayer.IsMasterClient == true)
        {
            var props = new Hashtable
            {
                ["SelectedArena"] = index,
                ["ArenaName"] = availableArenas[index].Name
            };
            
            Matchmaker.Client.CurrentRoom.SetCustomProperties(props);
        }
    }
}
```

## Best Practices

1. **Use frame timers** for synchronized countdowns
2. **Handle single-player differently** - skip lobby phase
3. **Update UI immediately** on player join/leave
4. **Clean up resources** on disconnection
5. **Implement re-queue functionality** for better UX
6. **Show connection status** throughout the process
7. **Test with various player counts** and network conditions
8. **Use events for game start** synchronization

## Common Patterns

### Quick Play Implementation

```csharp
public void QuickPlay()
{
    // Set default configuration
    runtimeConfig.Seed = UnityEngine.Random.Range(int.MinValue, int.MaxValue);
    
    // Connect with status callback
    Matchmaker.Connect((status) =>
    {
        switch (status.State)
        {
            case Matchmaker.State.ConnectingToServer:
                ShowStatus("Finding server...");
                break;
                
            case Matchmaker.State.ConnectingToRoom:
                ShowStatus("Joining arena...");
                break;
                
            case Matchmaker.State.JoinedRoom:
                ShowStatus("Waiting for players...");
                break;
                
            case Matchmaker.State.GameStarted:
                HideStatus();
                break;
                
            case Matchmaker.State.Failed:
                ShowError("Connection failed");
                break;
        }
    });
}
```

### Private Match Creation

```csharp
public void CreatePrivateMatch(string matchCode)
{
    var joinArgs = new JoinRandomRoomArgs
    {
        ExpectedMaxPlayers = maxPlayers
    };
    
    var roomOptions = new RoomOptions
    {
        IsVisible = false,
        MaxPlayers = maxPlayers,
        RoomName = matchCode,
        CustomRoomProperties = new Hashtable
        {
            ["IsPrivate"] = true,
            ["HostName"] = LocalData.nickname
        }
    };
    
    Client.OpCreateRoom(new EnterRoomArgs
    {
        RoomOptions = roomOptions
    });
}
```

This comprehensive lobby system provides smooth matchmaking and game initialization for Motor Dome's vehicle combat gameplay.
