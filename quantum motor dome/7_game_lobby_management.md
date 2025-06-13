# Game Lobby Management - Quantum Motor Dome

## Overview

Quantum Motor Dome implements a **timer-based competitive lobby system** with custom matchmaking logic. Unlike traditional lobbies, it features automatic game starts, dynamic player joining, and an elevator-themed waiting area that builds anticipation.

## Unique Lobby Design

### 1. **Elevator Concept**
- Players enter an "elevator" while matchmaking
- Visual/audio effects create atmosphere
- Countdown timer visible to all players
- Automatic launch when timer expires

### 2. **Core Features**
- **No Ready Button**: Games start automatically
- **Join-In-Progress**: Players can join mid-countdown
- **Flexible Player Count**: 2-6 players supported
- **Quick Requeue**: Seamless return to matchmaking

## Architecture

### Matchmaker System
```csharp
public class Matchmaker : QuantumCallbacks, IConnectionCallbacks, 
                          IMatchmakingCallbacks, IInRoomCallbacks, IOnEventCallback
{
    public static Matchmaker Instance { get; private set; }
    
    [SerializeField] byte maxPlayers = 6;
    [SerializeField] RuntimeConfig runtimeConfig;
    [SerializeField] RuntimePlayer runtimePlayer;
    
    public static event System.Action OnQuantumGameStart;
    public static event System.Action OnRealtimeJoinedRoom;
    public static event System.Action<Player> OnRealtimePlayerJoined;
    public static event System.Action<Player> OnRealtimePlayerLeft;
}
```

### Connection States
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
```

## Lobby Flow

### 1. **Connection Phase**
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
}
```

### 2. **Automatic Room Join**
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
    
    // Automatically join or create room
    Client.OpJoinRandomOrCreateRoom(joinRandomParams, enterRoomParams);
}
```

### 3. **Elevator Lobby Experience**
```csharp
public class ElevatorLobbyController : MonoBehaviour
{
    [SerializeField] float countdownDuration = 15f;
    [SerializeField] GameObject elevatorDoors;
    [SerializeField] AudioSource elevatorMusic;
    
    private float timeRemaining;
    private bool isCountingDown;
    
    void OnEnable()
    {
        Matchmaker.OnRealtimeJoinedRoom += StartElevatorSequence;
        Matchmaker.OnRealtimePlayerJoined += OnPlayerEntered;
    }
    
    void StartElevatorSequence()
    {
        // Close elevator doors
        AnimateDoorsClose();
        
        // Start ambient music/sounds
        elevatorMusic.Play();
        AudioManager.SetSnapshot("Elevator", 0.5f);
        
        // Begin countdown
        timeRemaining = countdownDuration;
        isCountingDown = true;
    }
    
    void Update()
    {
        if (isCountingDown)
        {
            timeRemaining -= Time.deltaTime;
            UpdateCountdownUI(timeRemaining);
            
            if (timeRemaining <= 0)
            {
                LaunchGame();
            }
        }
    }
}
```

## Timer-Based Matchmaking

### Countdown System
```csharp
public class LobbyTimer : MonoBehaviourPunCallbacks
{
    private float lobbyDuration = 15f;
    private float currentTime;
    private bool isMasterTimer;
    
    public override void OnJoinedRoom()
    {
        if (PhotonNetwork.IsMasterClient)
        {
            // Initialize room timer
            var props = new Hashtable
            {
                ["StartTime"] = PhotonNetwork.ServerTimestamp,
                ["Duration"] = lobbyDuration
            };
            PhotonNetwork.CurrentRoom.SetCustomProperties(props);
            isMasterTimer = true;
        }
        else
        {
            // Sync with existing timer
            SyncWithRoomTimer();
        }
    }
    
    void SyncWithRoomTimer()
    {
        if (PhotonNetwork.CurrentRoom.CustomProperties.TryGetValue("StartTime", out object startTime))
        {
            int elapsedTime = PhotonNetwork.ServerTimestamp - (int)startTime;
            currentTime = lobbyDuration - (elapsedTime / 1000f);
        }
    }
}
```

### Dynamic Player Management
```csharp
public class DynamicLobbyManager
{
    private List<Player> activePlayers = new List<Player>();
    private int minPlayers = 2;
    
    void OnPlayerEnteredRoom(Player newPlayer)
    {
        activePlayers.Add(newPlayer);
        
        // Update UI immediately
        RefreshPlayerList();
        ShowPlayerJoinedNotification(newPlayer);
        
        // Check if we should accelerate countdown
        if (activePlayers.Count >= maxPlayers)
        {
            AccelerateCountdown(3f); // Start in 3 seconds
        }
    }
    
    void OnPlayerLeftRoom(Player otherPlayer)
    {
        activePlayers.Remove(otherPlayer);
        
        // Check if we still have enough players
        if (activePlayers.Count < minPlayers && isCountingDown)
        {
            PauseCountdown();
            ShowWaitingForPlayersMessage();
        }
    }
}
```

## Player Data Synchronization

### Runtime Player Configuration
```csharp
void SendData()
{
    runtimePlayer.PlayerNickname = LocalData.nickname;
    
    // Sync player customization
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

### Customization System
```csharp
public class PlayerCustomization
{
    public struct CustomizationData
    {
        public string Nickname;
        public Color32 PrimaryColor;
        public Color32 SecondaryColor;
        public Color32 TrailColor;
        public int VehicleType;
    }
    
    public void ApplyCustomization(CustomizationData data)
    {
        // Save locally
        LocalData.nickname = data.Nickname;
        LocalData.primaryColor = data.PrimaryColor;
        LocalData.secondaryColor = data.SecondaryColor;
        LocalData.trailColor = data.TrailColor;
        
        // Sync to network
        var props = new Hashtable
        {
            ["nick"] = data.Nickname,
            ["colors"] = SerializeColors(data)
        };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
}
```

## UI Management

### Elevator Interface
```csharp
public class ElevatorLobbyUI : MonoBehaviour
{
    [Header("Player Display")]
    public Transform playerListContainer;
    public GameObject playerEntryPrefab;
    
    [Header("Timer Display")]
    public TextMeshProUGUI countdownText;
    public Image countdownFillBar;
    
    [Header("Status Messages")]
    public GameObject waitingForPlayersPanel;
    public TextMeshProUGUI statusMessage;
    
    void RefreshPlayerList()
    {
        // Clear existing entries
        foreach (Transform child in playerListContainer)
        {
            Destroy(child.gameObject);
        }
        
        // Create entry for each player
        foreach (var player in PhotonNetwork.PlayerList)
        {
            var entry = Instantiate(playerEntryPrefab, playerListContainer);
            var playerUI = entry.GetComponent<PlayerLobbyEntry>();
            
            playerUI.SetPlayerData(player);
            playerUI.AnimateEntry(); // Slide-in effect
        }
    }
}
```

### Visual Effects
```csharp
public class LobbyVisualEffects : MonoBehaviour
{
    [SerializeField] CameraController cameraController;
    [SerializeField] Light[] elevatorLights;
    [SerializeField] ParticleSystem steamEffect;
    
    public void OnLobbyEntered()
    {
        // Camera effects
        cameraController.Effects.Blur(0.5f);
        
        // Lighting ambiance
        foreach (var light in elevatorLights)
        {
            DOTween.To(() => light.intensity, 
                      x => light.intensity = x, 
                      0.5f, 1f).SetLoops(-1, LoopType.Yoyo);
        }
        
        // Atmospheric effects
        steamEffect.Play();
    }
    
    public void OnCountdownNearEnd(float timeRemaining)
    {
        if (timeRemaining < 5f)
        {
            // Intensify effects
            float intensity = 1f - (timeRemaining / 5f);
            cameraController.ShakeCamera(intensity * 0.2f);
            
            // Flash lights
            if (timeRemaining < 1f)
            {
                FlashLights();
            }
        }
    }
}
```

## Game Launch

### Transition Sequence
```csharp
void LaunchGame()
{
    // Visual transition
    StartCoroutine(LaunchSequence());
}

IEnumerator LaunchSequence()
{
    // 1. Dramatic countdown finish
    UIEffects.FlashScreen(Color.white, 0.2f);
    AudioManager.PlayOneShot("LaunchSound");
    
    // 2. Open elevator doors
    yield return AnimateDoorsOpen(1f);
    
    // 3. Start Quantum game
    StartQuantumGame();
    
    // 4. Fade to game
    yield return new WaitForSeconds(0.5f);
    SceneLoader.LoadGameScene();
}

static void StartQuantumGame()
{
    SessionRunner.Arguments arguments = new SessionRunner.Arguments()
    {
        RuntimeConfig = Instance.runtimeConfig,
        GameMode = DeterministicGameMode.Multiplayer,
        PlayerCount = Client.CurrentRoom.MaxPlayers,
        ClientId = Client.LocalPlayer.UserId,
        Communicator = new QuantumNetworkCommunicator(Client),
        SessionConfig = QuantumDeterministicSessionConfigAsset.DefaultConfig,
    };
    
    QuantumRunner.StartGame(arguments);
}
```

## Requeue System

### Quick Requeue
```csharp
public class RequeueMechanism
{
    public static bool isRequeueing = false;
    
    public void InitiateRequeue()
    {
        isRequeueing = true;
        
        // Maintain connection
        if (PhotonNetwork.InRoom)
        {
            PhotonNetwork.LeaveRoom(false); // Don't disconnect from master
        }
        
        // Immediate rejoin
        StartCoroutine(RequeuSequence());
    }
    
    IEnumerator RequeuSequence()
    {
        // Brief pause for cleanup
        yield return new WaitForSeconds(0.5f);
        
        // Rejoin matchmaking
        JoinRandomRoomArgs args = new JoinRandomRoomArgs();
        Client.OpJoinRandomOrCreateRoom(args, GetRoomOptions());
        
        isRequeueing = false;
    }
}
```

## Best Practices

### 1. **Timer Management**
- Sync timers across all clients
- Handle late joiners properly
- Account for network delays

### 2. **Player Experience**
- Clear visual feedback
- Atmospheric audio design
- Smooth transitions

### 3. **Edge Cases**
- Handle disconnects during countdown
- Manage minimum player requirements
- Support spectator mode

## Advanced Features

### 1. **Skill-Based Rooms**
```csharp
public void JoinSkillBasedRoom()
{
    var expectedProperties = new Hashtable
    {
        ["SkillLevel"] = GetPlayerSkillBracket(),
        ["GameMode"] = "Competitive"
    };
    
    PhotonNetwork.JoinRandomRoom(expectedProperties, maxPlayers);
}
```

### 2. **Tournament Mode**
```csharp
public class TournamentLobby
{
    public void CreateTournamentRoom(int roundNumber)
    {
        var roomOptions = new RoomOptions
        {
            MaxPlayers = 6,
            CustomRoomProperties = new Hashtable
            {
                ["Tournament"] = true,
                ["Round"] = roundNumber,
                ["AutoStart"] = false // Manual start for tournaments
            }
        };
        
        PhotonNetwork.CreateRoom($"Tournament_R{roundNumber}", roomOptions);
    }
}
```

### 3. **Dynamic Lobby Duration**
```csharp
public void AdjustLobbyTimer()
{
    // Shorter timer for more players
    float duration = PhotonNetwork.CurrentRoom.PlayerCount switch
    {
        >= 5 => 10f,
        >= 3 => 15f,
        _ => 20f
    };
    
    UpdateRoomTimer(duration);
}
```

## Debugging

### Lobby State Monitor
```csharp
void OnGUI()
{
    if (!Debug.isDebugBuild) return;
    
    GUILayout.Label($"Lobby State: {currentState}");
    GUILayout.Label($"Players: {PhotonNetwork.CurrentRoom?.PlayerCount ?? 0}/{maxPlayers}");
    GUILayout.Label($"Time Remaining: {timeRemaining:F1}s");
    GUILayout.Label($"Is Master: {PhotonNetwork.IsMasterClient}");
    
    if (GUILayout.Button("Force Start"))
    {
        SendStartGameEvent();
    }
}
```
