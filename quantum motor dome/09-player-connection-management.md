# Player Connection Management - Quantum Motor Dome

> **Implementation Note**: Motor Dome uses a custom `Matchmaker.cs` class that handles all connection management, replacing the standard Quantum Menu connection system.

Quantum Motor Dome implements player connection management through its custom Matchmaker system, which provides automatic matchmaking and seamless connection handling.

## Core Implementation

### Matchmaker Architecture

**File: `/Assets/Scripts/Matchmaker.cs`** ✓

```csharp
public class Matchmaker : QuantumCallbacks, IConnectionCallbacks, IMatchmakingCallbacks, IInRoomCallbacks, IOnEventCallback
{
    public static Matchmaker Instance { get; private set; }
    public static RealtimeClient Client { get; private set; }

    public static event System.Action OnQuantumGameStart;
    public static event System.Action OnRealtimeJoinedRoom;
    public static event System.Action<Player> OnRealtimePlayerJoined;
    public static event System.Action<Player> OnRealtimePlayerLeft;
}
```

## Connection Flow

### 1. Initial Connection

```csharp
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
        onStatusUpdated = null;
    }
}
```

### 2. Automatic Room Joining

Once connected to master server, the system automatically finds or creates a room:

```csharp
void IConnectionCallbacks.OnConnectedToMaster()
{
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

    Client.OpJoinRandomOrCreateRoom(joinRandomParams, enterRoomParams);
}
```

## Player Events

### Player Joined

```csharp
void IInRoomCallbacks.OnPlayerEnteredRoom(Player newPlayer)
{
    Log($"Player {newPlayer} entered the room");
    OnRealtimePlayerJoined?.Invoke(newPlayer);
}
```

### Player Left

```csharp
void IInRoomCallbacks.OnPlayerLeftRoom(Player otherPlayer)
{
    Log($"Player {otherPlayer} left the room");
    OnRealtimePlayerLeft?.Invoke(otherPlayer);
}
```

## Connection States

```csharp
public enum State
{
    Undefined = 0,
    ConnectingToServer,
    ConnectingToRoom,
    JoinedRoom,
    GameStarted,
    Failed = -1
}

public struct ConnectionStatus
{
    public string Message { get; }
    public State State { get; }
}
```

## Player Data Management

### Sending Player Data

When the game scene loads, player customization data is sent:

```csharp
void SendData()
{
    runtimePlayer.PlayerNickname = LocalData.nickname;

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

## Disconnection Handling

### Graceful Disconnection

```csharp
public void OnDisconnected(DisconnectCause cause)
{
    LogWarning($"Disconnected: {cause}");
    QuantumRunner.ShutdownAll();
    
    // Clean up game state
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

### Manual Disconnection

```csharp
public static void Disconnect()
{
    QuantumRunner.ShutdownAll();
    Debug.Log("Shutdown");
    Client.Disconnect();
}
```

## Requeue System

The system supports automatic requeuing for continuous play:

```csharp
public static bool isRequeueing = false;

// When requeuing, the disconnection doesn't return to main menu
// Instead, it maintains the connection for the next match
```

## Quantum Game Integration

### Starting Quantum

When a room is joined, Quantum is automatically started:

```csharp
void IMatchmakingCallbacks.OnJoinedRoom()
{
    onStatusUpdated?.Invoke(new ConnectionStatus("Joined Room", State.JoinedRoom));
    Log("Joined room");
    OnRealtimeJoinedRoom?.Invoke();
    StartQuantumGame();
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

## Event System

### Custom Events

The Matchmaker can handle custom Photon events:

```csharp
void IOnEventCallback.OnEvent(EventData photonEvent)
{
    if (photonEvent.Code == 0)
    {
        StartQuantumGame();
    }
}

public static void SendStartGameEvent()
{
    Client.OpRaiseEvent(0, null, new RaiseEventArgs() { Receivers = ReceiverGroup.All }, SendOptions.SendReliable);
}
```

## Best Practices

1. **Automatic Everything** - No manual room selection needed
2. **Quick Reconnection** - Use the requeue system
3. **Clean Disconnection** - Always shut down Quantum properly
4. **Event-Driven Updates** - Subscribe to Matchmaker events
5. **Simple Player Data** - Only send necessary customization

## Integration Points

- **LocalData.cs** - Stores player preferences
- **InterfaceManager** - UI state management
- **AudioManager** - Audio feedback
- **CameraController** - Visual effects

This streamlined connection system makes Quantum Motor Dome perfect for quick arcade sessions with minimal setup.