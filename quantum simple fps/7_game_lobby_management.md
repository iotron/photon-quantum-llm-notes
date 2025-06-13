# Game Lobby Management - Quantum Simple FPS

## Overview

Quantum Simple FPS implements a **minimalist lobby system** using the standard Quantum Menu framework with FPS-specific optimizations. The lobby focuses on quick match formation for competitive first-person shooter gameplay with tactical team-based modes.

## Lobby Architecture

### 1. **FPS-Optimized Menu System**
- Extended QuantumMenuConnectionBehaviourSDK
- Custom UI state management
- Focus on competitive matchmaking
- Team formation support

### 2. **Simplified User Flow**
```
Main Menu → Connect → Quick Match/Server Browser → Team Selection → Game
                    ↓
                Create Match → Configure Settings → Wait for Players
```

## Core Components

### Custom Menu Implementation
```csharp
namespace SimpleFPS
{
    public class MenuUI : QuantumMenuConnectionBehaviourSDK
    {
        [SerializeField]
        private GameObject[] _menuObjects;
        
        private bool _isBusy;
        private bool _isConnected;
        
        public override async Task<ConnectResult> ConnectAsync(QuantumMenuConnectArgs connectionArgs)
        {
            _isBusy = true;
            
            // FPS-specific connection setup
            ConfigureFPSSettings();
            
            ConnectResult result = await base.ConnectAsync(connectionArgs);
            
            _isBusy = false;
            
            return result;
        }
    }
}
```

### FPS Match Configuration
```csharp
public class FPSMatchSettings
{
    public enum GameMode
    {
        TeamDeathmatch,
        Elimination,
        CaptureTheFlag,
        SearchAndDestroy,
        FreeForAll
    }
    
    public GameMode Mode = GameMode.TeamDeathmatch;
    public int MaxPlayers = 10; // 5v5
    public int RoundTime = 180; // 3 minutes
    public int RoundLimit = 15; // First to 8
    public bool FriendlyFire = false;
    public string MapName = "de_dust";
}
```

## Lobby Flow

### 1. **Quick Match System**
```csharp
public class FPSQuickMatch : MonoBehaviourPunCallbacks
{
    [SerializeField] private FPSMatchSettings preferredSettings;
    
    public void FindMatch()
    {
        var expectedProperties = new Hashtable
        {
            ["Mode"] = preferredSettings.Mode.ToString(),
            ["SkillRange"] = GetSkillRange(),
            ["Region"] = PhotonNetwork.CloudRegion
        };
        
        // Try to join existing match
        PhotonNetwork.JoinRandomRoom(expectedProperties, 10, MatchmakingMode.FillRoom);
    }
    
    public override void OnJoinRandomFailed(short returnCode, string message)
    {
        // Create new competitive match
        CreateCompetitiveMatch();
    }
}
```

### 2. **Team Formation**
```csharp
public class TeamManager : MonoBehaviourPunCallbacks
{
    public enum Team { None, TeamA, TeamB, Spectator }
    
    private Dictionary<int, Team> playerTeams = new Dictionary<int, Team>();
    
    public void AssignPlayerToTeam(Player player)
    {
        // Auto-balance teams
        int teamACount = playerTeams.Count(kvp => kvp.Value == Team.TeamA);
        int teamBCount = playerTeams.Count(kvp => kvp.Value == Team.TeamB);
        
        Team assignedTeam = teamACount <= teamBCount ? Team.TeamA : Team.TeamB;
        
        // Sync team assignment
        var props = new Hashtable
        {
            ["Team"] = (int)assignedTeam,
            ["Ready"] = false
        };
        player.SetCustomProperties(props);
    }
    
    public void RequestTeamSwitch(Team newTeam)
    {
        if (CanSwitchToTeam(newTeam))
        {
            var props = new Hashtable { ["Team"] = (int)newTeam };
            PhotonNetwork.LocalPlayer.SetCustomProperties(props);
        }
    }
}
```

### 3. **Map Voting System**
```csharp
public class MapVotingManager : MonoBehaviourPunCallbacks
{
    [System.Serializable]
    public class MapInfo
    {
        public string MapName;
        public string DisplayName;
        public Sprite Preview;
        public GameMode[] SupportedModes;
    }
    
    public MapInfo[] AvailableMaps;
    private Dictionary<string, int> mapVotes = new Dictionary<string, int>();
    
    public void VoteForMap(string mapName)
    {
        var props = new Hashtable { ["MapVote"] = mapName };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
    
    public string GetWinningMap()
    {
        RecalculateVotes();
        return mapVotes.OrderByDescending(kvp => kvp.Value).First().Key;
    }
}
```

## FPS-Specific Features

### 1. **Loadout Selection**
```csharp
public class LoadoutManager
{
    [System.Serializable]
    public class Loadout
    {
        public string Name;
        public WeaponType PrimaryWeapon;
        public WeaponType SecondaryWeapon;
        public Equipment[] Equipment;
        public Perks[] Perks;
    }
    
    public void SelectLoadout(int loadoutIndex)
    {
        var loadout = GetLoadout(loadoutIndex);
        
        var props = new Hashtable
        {
            ["Loadout"] = loadoutIndex,
            ["Primary"] = (int)loadout.PrimaryWeapon,
            ["Secondary"] = (int)loadout.SecondaryWeapon
        };
        
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
}
```

### 2. **Competitive Features**
```csharp
public class CompetitiveManager
{
    public class MatchmakingRank
    {
        public int Elo = 1000;
        public string RankName = "Silver";
        public int Wins = 0;
        public int Losses = 0;
    }
    
    public void ConfigureCompetitiveRoom()
    {
        if (PhotonNetwork.IsMasterClient)
        {
            var props = new Hashtable
            {
                ["Competitive"] = true,
                ["MinRank"] = GetMinimumRank(),
                ["MaxRank"] = GetMaximumRank(),
                ["PenaltyForLeaving"] = true
            };
            
            PhotonNetwork.CurrentRoom.SetCustomProperties(props);
        }
    }
}
```

### 3. **Warm-up Phase**
```csharp
public class WarmupManager : MonoBehaviourPunCallbacks
{
    private float warmupDuration = 60f;
    private bool isWarmupActive = true;
    
    public override void OnJoinedRoom()
    {
        if (PhotonNetwork.CurrentRoom.PlayerCount < 10)
        {
            StartWarmup();
        }
    }
    
    void StartWarmup()
    {
        isWarmupActive = true;
        
        // Enable infinite respawns
        // Disable round timer
        // Allow late joins
        
        ShowWarmupUI();
    }
    
    public override void OnPlayerEnteredRoom(Player newPlayer)
    {
        if (PhotonNetwork.CurrentRoom.PlayerCount >= 10 && isWarmupActive)
        {
            // Start countdown to real match
            StartCoroutine(EndWarmupCountdown());
        }
    }
}
```

## UI Management

### Lobby Screen Layout
```csharp
public class FPSLobbyUI : QuantumMenuUIParty
{
    [Header("FPS Elements")]
    public TeamSelectionPanel teamPanel;
    public MapVotingPanel mapVoting;
    public LoadoutPanel loadoutSelection;
    public PlayerListPanel playerList;
    public ServerInfoPanel serverInfo;
    
    protected override void OnEnable()
    {
        base.OnEnable();
        
        // Update FPS-specific UI
        RefreshTeamDisplay();
        RefreshMapVotes();
        UpdateServerInfo();
    }
    
    void RefreshTeamDisplay()
    {
        // Show team compositions
        var teamA = GetPlayersOnTeam(Team.TeamA);
        var teamB = GetPlayersOnTeam(Team.TeamB);
        
        teamPanel.UpdateTeamDisplay(teamA, teamB);
        
        // Show balance warning if needed
        if (Math.Abs(teamA.Count - teamB.Count) > 1)
        {
            ShowTeamBalanceWarning();
        }
    }
}
```

### Ready System
```csharp
public class ReadyManager : MonoBehaviourPunCallbacks
{
    private Dictionary<int, bool> playerReadyStates = new Dictionary<int, bool>();
    
    public void ToggleReady()
    {
        bool currentState = IsLocalPlayerReady();
        
        var props = new Hashtable { ["Ready"] = !currentState };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
    
    public bool CanStartMatch()
    {
        // Check team balance
        if (!AreTeamsBalanced())
            return false;
        
        // Check minimum players
        if (PhotonNetwork.CurrentRoom.PlayerCount < 4) // 2v2 minimum
            return false;
        
        // Check all players ready
        foreach (var player in PhotonNetwork.PlayerList)
        {
            if (!IsPlayerReady(player))
                return false;
        }
        
        return true;
    }
}
```

## Match Start Sequence

### Pre-Match Flow
```csharp
public class MatchStartSequence : MonoBehaviourPunCallbacks
{
    IEnumerator StartMatchSequence()
    {
        // 1. Lock teams
        LockTeamChanges();
        
        // 2. Final map selection
        string selectedMap = mapVoting.GetWinningMap();
        SetMatchMap(selectedMap);
        
        // 3. Countdown
        yield return StartCoroutine(ShowCountdown(10));
        
        // 4. Load game scene
        if (PhotonNetwork.IsMasterClient)
        {
            PhotonNetwork.CurrentRoom.IsOpen = false;
            PhotonNetwork.LoadLevel(selectedMap);
        }
    }
}
```

### Connection Quality Requirements
```csharp
public class FPSConnectionQuality : MonoBehaviour
{
    private const int MAX_ACCEPTABLE_PING = 150;
    
    void CheckConnectionQuality()
    {
        int ping = PhotonNetwork.GetPing();
        
        if (ping > MAX_ACCEPTABLE_PING)
        {
            ShowHighPingWarning(ping);
            
            // Optionally restrict competitive play
            if (IsCompetitiveMode())
            {
                DisableCompetitiveQueue();
            }
        }
    }
}
```

## Server Browser

### Custom Server List
```csharp
public class ServerBrowser : MonoBehaviourPunCallbacks
{
    [SerializeField] private Transform serverListContent;
    [SerializeField] private GameObject serverEntryPrefab;
    
    public void RefreshServerList()
    {
        // Get room list from lobby
        if (!PhotonNetwork.InLobby)
        {
            PhotonNetwork.JoinLobby();
        }
    }
    
    public override void OnRoomListUpdate(List<RoomInfo> roomList)
    {
        // Clear old entries
        ClearServerList();
        
        // Filter and sort rooms
        var filteredRooms = roomList
            .Where(room => !room.RemovedFromList && room.IsOpen)
            .OrderBy(room => room.PlayerCount)
            .ThenBy(room => GetPingToRegion(room));
        
        // Create UI entries
        foreach (var room in filteredRooms)
        {
            CreateServerEntry(room);
        }
    }
}
```

## Best Practices

### 1. **Competitive Integrity**
- Skill-based matchmaking
- Anti-cheat considerations
- Penalty for leaving matches

### 2. **Performance Focus**
- Low-latency requirements
- Tick rate optimization
- Client prediction support

### 3. **Communication Tools**
- Team voice chat setup
- Quick communication wheel
- Tactical markers

## Error Handling

### Connection Issues
```csharp
public override void OnDisconnected(DisconnectCause cause)
{
    // Handle FPS-specific disconnects
    switch (cause)
    {
        case DisconnectCause.ClientTimeout:
            if (WasInCompetitiveMatch())
            {
                ApplyCompetitivePenalty();
                ShowReconnectOption();
            }
            break;
            
        case DisconnectCause.ServerTimeout:
            ShowServerIssueMessage();
            AttemptServerReconnect();
            break;
    }
}
```

### Match Integrity
```csharp
public class MatchIntegrityChecker
{
    public void ValidateMatch()
    {
        // Check for team balance
        if (!AreTeamsBalanced())
        {
            PauseMatchStart();
            RequestTeamBalance();
        }
        
        // Check for suspicious stats
        foreach (var player in PhotonNetwork.PlayerList)
        {
            if (HasSuspiciousStats(player))
            {
                FlagForReview(player);
            }
        }
    }
}
```

## Integration Points

- **Quantum Menu**: Base framework
- **FPS Systems**: Weapon/loadout data
- **Anti-Cheat**: Client validation
- **Voice Chat**: Team communication
- **Replay System**: Match recording

## Debugging

### FPS Debug Panel
```csharp
void OnGUI()
{
    if (!Debug.isDebugBuild) return;
    
    GUILayout.BeginArea(new Rect(10, 10, 300, 400));
    GUILayout.Label($"=== FPS Debug ===");
    GUILayout.Label($"Ping: {PhotonNetwork.GetPing()}ms");
    GUILayout.Label($"Team A: {GetTeamCount(Team.TeamA)}");
    GUILayout.Label($"Team B: {GetTeamCount(Team.TeamB)}");
    GUILayout.Label($"Ready: {GetReadyCount()}/{PhotonNetwork.CurrentRoom.PlayerCount}");
    GUILayout.Label($"Map: {GetCurrentMapVote()}");
    
    if (GUILayout.Button("Force Balance Teams"))
    {
        ForceTeamBalance();
    }
    
    if (GUILayout.Button("Skip Warmup"))
    {
        SkipWarmupPhase();
    }
    
    GUILayout.EndArea();
}
```
