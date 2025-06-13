# Game Lobby Management - Quantum Platform Shooter

## Overview

Quantum Platform Shooter implements the **standard Quantum Menu framework** with minimal customization, focusing on quick matchmaking for 2D platform combat. The lobby system prioritizes simplicity and fast game starts for competitive platform shooter matches.

## Lobby Architecture

### 1. **Standard Quantum Menu Implementation**
- Uses default QuantumMenuUIMain screens
- Minimal custom configuration
- Focus on core multiplayer functionality

### 2. **Simplified Flow**
- **Main Menu**: Quick play or create room
- **Party Screen**: Basic player list
- **Loading**: Transition to game
- **In-Game**: Pause menu overlay

## Key Components

### Menu Configuration
```csharp
// QuantumMenuConfig.asset settings
public class PlatformShooterMenuConfig
{
    public int MaxPlayers = 4;
    public float ConnectionTimeout = 30f;
    public bool AutoStartWhenFull = true;
    public string DefaultGameMode = "Deathmatch";
}
```

### Custom Menu Plugin
```csharp
public class QuantumMenuToggleGameObjectPlugin : QuantumMenuScreenPlugin
{
    public GameObject[] HideObjects;
    public GameObject[] ShowObjects;
    
    public override void Show(QuantumMenuUIScreen screen)
    {
        // Simple UI state management
        foreach (var go in HideObjects)
            go.SetActive(false);
            
        foreach (var go in ShowObjects)
            go.SetActive(true);
    }
}
```

## Lobby Flow

### 1. **Quick Match System**
```csharp
public class QuickMatchHandler : MonoBehaviourPunCallbacks
{
    public void OnQuickPlayClicked()
    {
        // Simple random room join
        var expectedProperties = new Hashtable
        {
            ["GameMode"] = "Deathmatch",
            ["MapRotation"] = true
        };
        
        PhotonNetwork.JoinRandomRoom(expectedProperties, maxPlayers);
    }
    
    public override void OnJoinRandomFailed(short returnCode, string message)
    {
        // Auto-create if no rooms available
        CreateDefaultRoom();
    }
}
```

### 2. **Room Creation**
```csharp
void CreateDefaultRoom()
{
    var roomOptions = new RoomOptions
    {
        MaxPlayers = 4,
        IsVisible = true,
        IsOpen = true,
        CustomRoomProperties = new Hashtable
        {
            ["Map"] = GetRandomMap(),
            ["GameMode"] = "Deathmatch",
            ["TimeLimit"] = 300, // 5 minutes
            ["ScoreLimit"] = 20
        },
        CustomRoomPropertiesForLobby = new[] { "Map", "GameMode" }
    };
    
    string roomName = $"Room_{Random.Range(1000, 9999)}";
    PhotonNetwork.CreateRoom(roomName, roomOptions);
}
```

### 3. **Minimal Party Screen**
- Player names display
- Basic ready status
- Map preview
- Start game button (host only)

## Platform Shooter Specific Features

### 1. **Character Selection**
```csharp
public class CharacterSelector : MonoBehaviourPunCallbacks
{
    [System.Serializable]
    public class CharacterData
    {
        public string Name;
        public Sprite Icon;
        public int CharacterIndex;
        public string Abilities;
    }
    
    public CharacterData[] AvailableCharacters;
    private int selectedCharacter = 0;
    
    public void SelectCharacter(int index)
    {
        selectedCharacter = index;
        
        // Sync selection
        var props = new Hashtable { ["Character"] = index };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
}
```

### 2. **Map Rotation**
```csharp
public class MapRotationManager
{
    private string[] maps = { "Factory", "Jungle", "SpaceStation", "Castle" };
    private int currentMapIndex = 0;
    
    public string GetNextMap()
    {
        currentMapIndex = (currentMapIndex + 1) % maps.Length;
        return maps[currentMapIndex];
    }
    
    public void SyncMapSelection()
    {
        if (PhotonNetwork.IsMasterClient)
        {
            var props = new Hashtable { ["NextMap"] = GetNextMap() };
            PhotonNetwork.CurrentRoom.SetCustomProperties(props);
        }
    }
}
```

### 3. **Game Mode Selection**
```csharp
public enum GameMode
{
    Deathmatch,
    TeamDeathmatch,
    CaptureTheFlag,
    KingOfTheHill,
    Survival
}

public class GameModeManager
{
    public void SetGameMode(GameMode mode)
    {
        var settings = GetModeSettings(mode);
        
        var props = new Hashtable
        {
            ["GameMode"] = mode.ToString(),
            ["TeamPlay"] = settings.IsTeamBased,
            ["RespawnTime"] = settings.RespawnDelay,
            ["ObjectiveCount"] = settings.Objectives
        };
        
        PhotonNetwork.CurrentRoom.SetCustomProperties(props);
    }
}
```

## Simplified UI System

### Party Screen Layout
```csharp
public class PlatformShooterPartyUI : QuantumMenuUIParty
{
    [Header("Custom Elements")]
    public Transform playerListContainer;
    public GameObject playerEntryPrefab;
    public Text mapNameText;
    public Image mapPreview;
    public Text gameModeText;
    public Button startButton;
    
    protected override void OnEnable()
    {
        base.OnEnable();
        RefreshUI();
    }
    
    void RefreshUI()
    {
        // Update player list
        UpdatePlayerList();
        
        // Show current settings
        UpdateMapDisplay();
        UpdateGameModeDisplay();
        
        // Host controls
        startButton.gameObject.SetActive(PhotonNetwork.IsMasterClient);
    }
}
```

### Player List Management
```csharp
void UpdatePlayerList()
{
    // Clear existing
    foreach (Transform child in playerListContainer)
        Destroy(child.gameObject);
    
    // Create entries
    foreach (var player in PhotonNetwork.PlayerList)
    {
        var entry = Instantiate(playerEntryPrefab, playerListContainer);
        var display = entry.GetComponent<PlayerDisplay>();
        
        display.SetPlayer(player);
        display.ShowCharacterIcon(GetCharacterIcon(player));
        display.SetReadyStatus(IsPlayerReady(player));
    }
}
```

## Fast Start System

### Auto-Start Logic
```csharp
public class AutoStartManager : MonoBehaviourPunCallbacks
{
    private float autoStartDelay = 5f;
    private Coroutine autoStartCoroutine;
    
    public override void OnPlayerEnteredRoom(Player newPlayer)
    {
        CheckAutoStart();
    }
    
    void CheckAutoStart()
    {
        if (PhotonNetwork.IsMasterClient)
        {
            if (PhotonNetwork.CurrentRoom.PlayerCount == PhotonNetwork.CurrentRoom.MaxPlayers)
            {
                // Start countdown when full
                autoStartCoroutine = StartCoroutine(AutoStartCountdown());
            }
        }
    }
    
    IEnumerator AutoStartCountdown()
    {
        float timer = autoStartDelay;
        
        while (timer > 0)
        {
            UpdateCountdownUI(timer);
            yield return new WaitForSeconds(1f);
            timer--;
            
            // Cancel if player leaves
            if (PhotonNetwork.CurrentRoom.PlayerCount < PhotonNetwork.CurrentRoom.MaxPlayers)
            {
                CancelCountdown();
                yield break;
            }
        }
        
        StartGame();
    }
}
```

### Immediate Game Launch
```csharp
public void StartGame()
{
    if (PhotonNetwork.IsMasterClient)
    {
        // Close room to new players
        PhotonNetwork.CurrentRoom.IsOpen = false;
        
        // Load game scene
        PhotonNetwork.LoadLevel("PlatformShooterGameplay");
    }
}
```

## Match Settings

### Room Properties
```csharp
public static class PlatformShooterRoomProperties
{
    // Game settings
    public const string GAME_MODE = "gm";
    public const string MAP_NAME = "map";
    public const string TIME_LIMIT = "time";
    public const string SCORE_LIMIT = "score";
    
    // Match state
    public const string MATCH_STARTED = "started";
    public const string CURRENT_ROUND = "round";
    
    // Player settings
    public const string FRIENDLY_FIRE = "ff";
    public const string RESPAWN_TIME = "respawn";
    public const string POWER_UPS_ENABLED = "powerups";
}
```

### Default Configurations
```csharp
public class DefaultMatchSettings
{
    public static Hashtable GetDefaultDeathmatch()
    {
        return new Hashtable
        {
            [PlatformShooterRoomProperties.GAME_MODE] = "Deathmatch",
            [PlatformShooterRoomProperties.TIME_LIMIT] = 300,
            [PlatformShooterRoomProperties.SCORE_LIMIT] = 20,
            [PlatformShooterRoomProperties.RESPAWN_TIME] = 3,
            [PlatformShooterRoomProperties.POWER_UPS_ENABLED] = true
        };
    }
}
```

## Transition to Gameplay

### Scene Loading
```csharp
public override void OnJoinedRoom()
{
    // Minimal setup
    Debug.Log($"Joined room: {PhotonNetwork.CurrentRoom.Name}");
    
    // If game already started, catch up
    if (PhotonNetwork.CurrentRoom.CustomProperties.ContainsKey("InProgress"))
    {
        LoadGameScene();
    }
}

void LoadGameScene()
{
    // Ensure all players load together
    if (PhotonNetwork.IsMasterClient)
    {
        PhotonNetwork.LoadLevel("PlatformShooterGameplay");
    }
}
```

## Best Practices

### 1. **Keep It Simple**
- Minimal UI screens
- Quick navigation
- Clear visual feedback

### 2. **Fast Matchmaking**
- One-click quick play
- Auto-start when full
- Sensible defaults

### 3. **Platform Shooter Focus**
- Character abilities visible
- Map previews
- Game mode clarity

## Error Handling

### Connection Failures
```csharp
public override void OnDisconnected(DisconnectCause cause)
{
    // Simple error display
    string message = cause switch
    {
        DisconnectCause.ServerTimeout => "Connection timed out",
        DisconnectCause.MaxCcuReached => "Server is full",
        _ => "Connection lost"
    };
    
    ShowErrorPopup(message);
    ReturnToMainMenu();
}
```

### Recovery Options
```csharp
public void HandleMatchmakingError()
{
    // Offer simple options
    ShowDialog(
        "Unable to find a match",
        "Create Room", () => CreateDefaultRoom(),
        "Try Again", () => OnQuickPlayClicked(),
        "Cancel", () => ReturnToMainMenu()
    );
}
```

## Mobile Optimization

### Touch-Friendly UI
- Large buttons
- Clear touch targets
- Simplified controls

### Performance
- Lightweight lobby scenes
- Minimal network traffic
- Quick transitions

## Integration Points

- **Quantum Menu**: Base framework
- **Photon Realtime**: Networking
- **Platform Shooter Systems**: Character/map data
- **Unity UI**: Simple interface

## Debugging

### Simple Debug Display
```csharp
void OnGUI()
{
    if (!Debug.isDebugBuild) return;
    
    GUILayout.Label($"Room: {PhotonNetwork.CurrentRoom?.Name ?? "None"}");
    GUILayout.Label($"Players: {PhotonNetwork.CurrentRoom?.PlayerCount ?? 0}");
    GUILayout.Label($"Mode: {PhotonNetwork.CurrentRoom?.CustomProperties["GameMode"]}");
}
```
