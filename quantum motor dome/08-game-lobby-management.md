# Game Lobby Management - Quantum Motor Dome

Quantum Motor Dome implements a unique **automatic matchmaking system** without a traditional lobby interface. Players are instantly matched and placed into games through a custom Matchmaker system.

## Matchmaking Architecture

### Instant Matchmaking System

The game uses a custom Matchmaker that automatically connects players without a visible lobby:

**File: `/Assets/Scripts/Matchmaker.cs`** ✓

```csharp
public class Matchmaker : QuantumCallbacks, IConnectionCallbacks, IMatchmakingCallbacks, IInRoomCallbacks, IOnEventCallback
{
    public static Matchmaker Instance { get; private set; }
    public static RealtimeClient Client { get; private set; }

    [SerializeField] byte maxPlayers = 6;
    [SerializeField] RuntimeConfig runtimeConfig;
    [SerializeField] RuntimePlayer runtimePlayer;

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
            Log("Joining a room");
        }
    }
}
```

## Connection Flow

### 1. Automatic Connection Process

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

### 2. Room Creation and Joining

The system automatically tries to join an existing room or creates a new one:

```csharp
void IMatchmakingCallbacks.OnJoinedRoom()
{
    onStatusUpdated?.Invoke(new ConnectionStatus("Joined Room", State.JoinedRoom));
    Log("Joined room");
    OnRealtimeJoinedRoom?.Invoke();
    StartQuantumGame();
}
```

## Player Data Configuration

### Runtime Player Setup

Player customization data is sent when joining:

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

## Game Start Synchronization

### Quantum Game Initialization

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

## Connection States

### State Management

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

    public ConnectionStatus(string msg, State state)
    {
        Message = msg;
        State = state;
    }
}
```

## UI Integration

### Elevator Metaphor

The game uses an elevator visual metaphor during matchmaking:

```csharp
// In InterfaceManager
public GameObject elevatorObj;

// Activated during matchmaking
InterfaceManager.Instance.elevatorObj.SetActive(true);

// Deactivated on disconnect
InterfaceManager.Instance.elevatorObj.SetActive(false);
```

## Error Handling

### Disconnection Management

```csharp
public void OnDisconnected(DisconnectCause cause)
{
    LogWarning($"Disconnected: {cause}");
    QuantumRunner.ShutdownAll();
    
    InterfaceManager.Instance.elevatorObj.SetActive(false);
    AudioManager.LerpVolume(AudioManager.Instance.crowdSource, 0f, 0.5f);
    AudioManager.SetSnapshot("Default", 0.5f);
    
    if (CameraController.Instance) 
        CameraController.Instance.Effects.Unblur(0);
        
    UnityEngine.SceneManagement.SceneManager.LoadScene(menuScene);

    if (!isRequeueing)
    {
        UIScreen.activeScreen.BackTo(InterfaceManager.Instance.mainMenuScreen);
        UIScreen.Focus(InterfaceManager.Instance.playmodeScreen);
    }
}
```

## Requeue System

### Automatic Rejoin

The system supports automatic requeuing for seamless gameplay:

```csharp
public static bool isRequeueing = false;

// Triggered when players want to play again
// Maintains connection and finds new match
```

## Best Practices

1. **No Manual Room Selection** - Players cannot choose specific rooms
2. **Instant Matchmaking** - Reduces waiting time
3. **Automatic Balancing** - Fills rooms evenly
4. **Simple Player Customization** - Colors and nickname only
5. **Robust Error Handling** - Graceful disconnection recovery
6. **Visual Feedback** - Elevator animation during matchmaking

## Unique Features

1. **Zero-Lobby Design**
   - No room browser
   - No waiting screen with player list
   - Immediate game placement

2. **Elevator Visualization**
   - Thematic matchmaking animation
   - Masks loading/connection time
   - Provides progress feedback

3. **Seamless Requeue**
   - Quick return to matchmaking
   - Maintains settings between matches

## Common Patterns

### Quick Play Implementation

```csharp
// Simple one-click play
public void OnPlayButtonClicked()
{
    Matchmaker.Connect((status) =>
    {
        UpdateUIWithStatus(status);
        
        if (status.State == State.GameStarted)
        {
            HideMenuUI();
        }
    });
}
```

This automatic matchmaking system makes Quantum Motor Dome ideal for quick, arcade-style multiplayer sessions where players want to jump straight into the action.