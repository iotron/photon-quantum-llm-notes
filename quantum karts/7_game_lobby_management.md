# Game Lobby Management - Quantum Karts

## Overview

Quantum Karts implements a **traditional online multiplayer lobby** system using the Quantum Menu framework. It features a pre-game lobby where players can customize their karts, select tracks, and wait for other players before starting the race.

## Lobby Architecture

### 1. **Quantum Menu Integration**
- Built on top of QuantumMenuUIMain
- Extends standard lobby with kart-specific features
- Photon Realtime backend for matchmaking

### 2. **Lobby States**
- **Main Menu**: Initial connection and mode selection
- **Kart Selection**: Pre-game customization lobby
- **Waiting Room**: Final countdown before race
- **In-Game**: Active race session

## Key Components

### KartSelector System
```csharp
public class KartSelector : MonoBehaviour
{
    public GameObject[] kartPrefabs;
    public Material[] kartMaterials;
    private int selectedKartIndex = 0;
    private int selectedColorIndex = 0;
    
    public void SelectKart(int index)
    {
        selectedKartIndex = index;
        UpdateKartPreview();
        SyncSelectionToLobby();
    }
    
    private void SyncSelectionToLobby()
    {
        var properties = new ExitGames.Client.Photon.Hashtable
        {
            ["KartType"] = selectedKartIndex,
            ["KartColor"] = selectedColorIndex
        };
        PhotonNetwork.LocalPlayer.SetCustomProperties(properties);
    }
}
```

### Track Voting System
- **Democratic Selection**: Players vote for preferred track
- **Host Override**: Room master can force selection
- **Random Fallback**: Tie-breaker mechanism

## Lobby Flow

### 1. **Connection Phase**
```csharp
// Handled by QuantumMenuConnection
- Connect to Photon Cloud
- Authenticate player
- Join lobby pool
```

### 2. **Matchmaking**
```csharp
// Quick Match
PhotonNetwork.JoinRandomRoom(roomProperties, maxPlayers);

// Create Room
var roomOptions = new RoomOptions
{
    MaxPlayers = 8,
    IsVisible = true,
    CustomRoomProperties = new Hashtable
    {
        ["Track"] = "Circuit_01",
        ["GameMode"] = "Race"
    }
};
PhotonNetwork.CreateRoom(roomName, roomOptions);
```

### 3. **Pre-Race Lobby**
- **Player List Display**
  - Names and ready status
  - Kart selections visible
  - Connection quality indicators

- **Customization Options**
  - Kart model selection
  - Color/skin choices
  - Player name display

- **Ready System**
  - Individual ready toggles
  - Auto-start when all ready
  - Countdown timer option

## Implementation Details

### Lobby UI Structure
```csharp
public class KartLobbyUI : QuantumMenuUIScreen
{
    [Header("Player List")]
    public Transform playerListContainer;
    public GameObject playerEntryPrefab;
    
    [Header("Kart Selection")]
    public KartSelector kartSelector;
    public Button readyButton;
    
    [Header("Track Selection")]
    public TrackVotingPanel trackVoting;
    
    protected override void OnRoomUpdated()
    {
        RefreshPlayerList();
        UpdateReadyStates();
        CheckStartConditions();
    }
}
```

### Player Synchronization
```csharp
public class LobbyPlayerData
{
    public string PlayerName;
    public int KartIndex;
    public int ColorIndex;
    public bool IsReady;
    public float Ping;
    
    public void SyncToPhoton()
    {
        var props = new Hashtable
        {
            ["Kart"] = KartIndex,
            ["Color"] = ColorIndex,
            ["Ready"] = IsReady
        };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
}
```

## Ready System

### Ready State Management
```csharp
public class ReadyManager : MonoBehaviourPunCallbacks
{
    private Dictionary<int, bool> playerReadyStates = new Dictionary<int, bool>();
    
    public void ToggleReady()
    {
        bool newState = !IsLocalPlayerReady();
        var props = new Hashtable { ["Ready"] = newState };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
    
    public override void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        if (changedProps.ContainsKey("Ready"))
        {
            playerReadyStates[targetPlayer.ActorNumber] = (bool)changedProps["Ready"];
            CheckAllPlayersReady();
        }
    }
    
    private void CheckAllPlayersReady()
    {
        if (PhotonNetwork.IsMasterClient && AllPlayersReady())
        {
            StartCountdown();
        }
    }
}
```

### Countdown System
```csharp
public class LobbyCountdown : MonoBehaviour
{
    private float countdownTime = 5f;
    private bool isCountingDown = false;
    
    public void StartCountdown()
    {
        if (PhotonNetwork.IsMasterClient)
        {
            photonView.RPC("BeginCountdown", RpcTarget.All, countdownTime);
        }
    }
    
    [PunRPC]
    private void BeginCountdown(float duration)
    {
        isCountingDown = true;
        StartCoroutine(CountdownCoroutine(duration));
    }
    
    private IEnumerator CountdownCoroutine(float duration)
    {
        while (duration > 0)
        {
            UpdateCountdownUI(duration);
            yield return new WaitForSeconds(1f);
            duration--;
        }
        
        LaunchGame();
    }
}
```

## Room Properties

### Custom Room Settings
```csharp
public static class KartRoomProperties
{
    public const string TRACK_NAME = "track";
    public const string GAME_MODE = "mode";
    public const string LAP_COUNT = "laps";
    public const string AI_COUNT = "ai_count";
    public const string POWER_UPS = "powerups";
    
    public static Hashtable GetDefaultProperties()
    {
        return new Hashtable
        {
            [TRACK_NAME] = "Circuit_01",
            [GAME_MODE] = "Race",
            [LAP_COUNT] = 3,
            [AI_COUNT] = 0,
            [POWER_UPS] = true
        };
    }
}
```

### Track Selection
```csharp
public class TrackSelector : MonoBehaviourPunCallbacks
{
    private Dictionary<string, int> trackVotes = new Dictionary<string, int>();
    
    public void VoteForTrack(string trackId)
    {
        var props = new Hashtable { ["VotedTrack"] = trackId };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
    
    public override void OnPlayerPropertiesUpdate(Player targetPlayer, Hashtable changedProps)
    {
        if (changedProps.ContainsKey("VotedTrack"))
        {
            RecalculateVotes();
            UpdateTrackSelectionUI();
        }
    }
    
    private string GetWinningTrack()
    {
        return trackVotes.OrderByDescending(kvp => kvp.Value).First().Key;
    }
}
```

## Transition to Game

### Launch Sequence
1. **Final Synchronization**
   ```csharp
   // Ensure all player data is synced
   PhotonNetwork.SendAllOutgoingCommands();
   ```

2. **Scene Loading**
   ```csharp
   if (PhotonNetwork.IsMasterClient)
   {
       PhotonNetwork.LoadLevel(selectedTrack);
   }
   ```

3. **Quantum Game Start**
   ```csharp
   // In game scene
   var config = new QuantumKartsConfig
   {
       TrackId = (string)PhotonNetwork.CurrentRoom.CustomProperties["track"],
       LapCount = (int)PhotonNetwork.CurrentRoom.CustomProperties["laps"]
   };
   StartQuantumGame(config);
   ```

## Best Practices

### 1. **Network Efficiency**
- Batch property updates
- Use custom properties sparingly
- Implement update throttling

### 2. **User Experience**
- Show loading states clearly
- Provide feedback for all actions
- Handle edge cases gracefully

### 3. **Lobby Features**
- Quick join options
- Friend invites
- Spectator support

## Error Handling

### Connection Issues
```csharp
public override void OnDisconnected(DisconnectCause cause)
{
    switch (cause)
    {
        case DisconnectCause.ServerTimeout:
            ShowError("Connection timed out");
            break;
        case DisconnectCause.MaxCcuReached:
            ShowError("Server is full");
            break;
        default:
            ShowError($"Disconnected: {cause}");
            break;
    }
    
    ReturnToMainMenu();
}
```

### Lobby State Recovery
```csharp
public class LobbyStateRecovery
{
    public void SaveLobbyState()
    {
        // Save current selections
        PlayerPrefs.SetInt("LastKart", selectedKart);
        PlayerPrefs.SetInt("LastColor", selectedColor);
        PlayerPrefs.SetString("LastRoom", PhotonNetwork.CurrentRoom.Name);
    }
    
    public void AttemptRejoin()
    {
        string lastRoom = PlayerPrefs.GetString("LastRoom");
        if (!string.IsNullOrEmpty(lastRoom))
        {
            PhotonNetwork.RejoinRoom(lastRoom);
        }
    }
}
```

## Advanced Features

### 1. **AI Opponents**
- Fill empty slots with bots
- Adjustable difficulty
- Remove when players join

### 2. **Tournament Mode**
- Multi-race championships
- Point tracking
- Bracket systems

### 3. **Custom Game Modes**
- Time trials
- Battle modes
- Elimination races

## Integration Points

- **Quantum Menu**: Base framework
- **Photon Realtime**: Networking layer
- **Unity UI**: Interface components
- **Quantum Game**: Simulation start
