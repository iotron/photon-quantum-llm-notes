# Game Lobby Management - Quantum Twin Stick Shooter

> **Implementation Note**: This project uses the **standard Quantum Menu** framework without custom lobby modifications. The detailed examples below illustrate typical arcade-style patterns that could be implemented with the standard menu. Code snippets without file paths are example patterns, not actual implementations.

## Overview

Quantum Twin Stick Shooter implements a **wave-based cooperative lobby system** using the standard Quantum Menu framework, optimized for quick drop-in/drop-out multiplayer sessions. The lobby focuses on seamless player joining and difficulty scaling for arcade-style twin-stick action.

## Lobby Architecture

### 1. **Arcade-Style Quick Lobby**
- Standard Quantum Menu with minimal friction
- Drop-in/drop-out support
- Dynamic difficulty scaling
- Wave-based progression system

### 2. **Simple Flow Design**
```
Main Menu → Quick Join → Arena Selection → Ready Up → Wave 1
            ↓
        Host Game → Configure Difficulty → Wait for Players
```

## Core Components

### Lobby Configuration
```csharp
public class TwinStickLobbyConfig
{
    [System.Serializable]
    public class ArenaSettings
    {
        public string ArenaName = "Neon Arena";
        public int StartingWave = 1;
        public DifficultyMode Difficulty = DifficultyMode.Normal;
        public int MaxPlayers = 4;
        public bool FriendlyFire = false;
        public bool InfiniteWaves = false;
    }
    
    public enum DifficultyMode
    {
        Casual,     // More health, fewer enemies
        Normal,     // Balanced gameplay
        Hardcore,   // Permadeath, more enemies
        Nightmare   // Everything wants you dead
    }
}
```

### Quick Match System
```csharp
public class TwinStickQuickMatch : MonoBehaviourPunCallbacks
{
    public void QuickPlay()
    {
        // Simple join with minimal requirements
        var properties = new Hashtable
        {
            ["GameMode"] = "Survival",
            ["InProgress"] = false
        };
        
        PhotonNetwork.JoinRandomRoom(properties, 4);
    }
    
    public override void OnJoinRandomFailed(short returnCode, string message)
    {
        // Create casual room
        CreateArcadeRoom();
    }
    
    void CreateArcadeRoom()
    {
        var roomOptions = new RoomOptions
        {
            MaxPlayers = 4,
            IsOpen = true,
            IsVisible = true,
            // Allow join during gameplay
            PlayerTtl = 0,
            EmptyRoomTtl = 300000, // 5 minutes
            CustomRoomProperties = GetDefaultProperties()
        };
        
        string roomName = $"Arena_{Random.Range(1000, 9999)}";
        PhotonNetwork.CreateRoom(roomName, roomOptions);
    }
}
```

## Lobby Features

### 1. **Character Selection**
```csharp
public class CharacterSelector : MonoBehaviourPunCallbacks
{
    [System.Serializable]
    public class TwinStickCharacter
    {
        public string Name;
        public Sprite Icon;
        public Color PrimaryColor;
        public CharacterStats Stats;
        public string SpecialAbility;
    }
    
    public TwinStickCharacter[] AvailableCharacters;
    
    public void SelectCharacter(int index)
    {
        var character = AvailableCharacters[index];
        
        var props = new Hashtable
        {
            ["Character"] = index,
            ["Color"] = ColorToInt(character.PrimaryColor),
            ["Ready"] = IsReady()
        };
        
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
        UpdateCharacterPreview(character);
    }
}
```

### 2. **Arena Voting**
```csharp
public class ArenaVotingSystem : MonoBehaviourPunCallbacks
{
    [System.Serializable]
    public class Arena
    {
        public string Name;
        public string Description;
        public Sprite Preview;
        public int RecommendedPlayers;
        public string[] EnemyTypes;
    }
    
    private Dictionary<string, int> arenaVotes = new Dictionary<string, int>();
    
    public void VoteForArena(string arenaName)
    {
        var props = new Hashtable { ["ArenaVote"] = arenaName };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
        
        UpdateVoteDisplay();
    }
}
```

### 3. **Difficulty Scaling**
```csharp
public class DifficultyManager : MonoBehaviourPunCallbacks
{
    public void SetDifficulty(DifficultyMode mode)
    {
        if (PhotonNetwork.IsMasterClient)
        {
            float enemyMultiplier = GetEnemyMultiplier(mode);
            float healthMultiplier = GetHealthMultiplier(mode);
            
            var props = new Hashtable
            {
                ["Difficulty"] = mode.ToString(),
                ["EnemyMult"] = enemyMultiplier,
                ["HealthMult"] = healthMultiplier,
                ["FriendlyFire"] = mode >= DifficultyMode.Hardcore
            };
            
            PhotonNetwork.CurrentRoom.SetCustomProperties(props);
        }
    }
    
    public void ScaleToPlayerCount()
    {
        int playerCount = PhotonNetwork.CurrentRoom.PlayerCount;
        float scaleFactor = 0.75f + (playerCount * 0.25f); // 1x for 1 player, 1.75x for 4
        
        var props = new Hashtable { ["PlayerScale"] = scaleFactor };
        PhotonNetwork.CurrentRoom.SetCustomProperties(props);
    }
}
```

## Lobby UI

### Simple Party Screen
```csharp
public class TwinStickPartyUI : QuantumMenuUIParty
{
    [Header("Twin Stick Elements")]
    public Transform playerSlots;
    public GameObject playerSlotPrefab;
    public ArenaPreview arenaDisplay;
    public DifficultySelector difficultyPanel;
    public WaveProgressDisplay waveInfo;
    
    protected override void OnEnable()
    {
        base.OnEnable();
        RefreshLobbyDisplay();
    }
    
    void RefreshLobbyDisplay()
    {
        // Update player slots
        UpdatePlayerSlots();
        
        // Show current settings
        DisplayArenaInfo();
        UpdateDifficultyDisplay();
        
        // Ready button
        UpdateReadyButton();
    }
    
    void UpdatePlayerSlots()
    {
        // Clear existing
        foreach (Transform child in playerSlots)
            Destroy(child.gameObject);
        
        // Create slot for each player
        for (int i = 0; i < 4; i++)
        {
            var slot = Instantiate(playerSlotPrefab, playerSlots);
            
            if (i < PhotonNetwork.PlayerList.Length)
            {
                var player = PhotonNetwork.PlayerList[i];
                slot.GetComponent<PlayerSlotUI>().SetPlayer(player);
            }
            else
            {
                slot.GetComponent<PlayerSlotUI>().SetEmpty();
            }
        }
    }
}
```

### Ready System
```csharp
public class SimpleReadySystem : MonoBehaviourPunCallbacks
{
    private float autoStartDelay = 30f;
    private Coroutine autoStartCoroutine;
    
    public void ToggleReady()
    {
        bool isReady = !IsLocalPlayerReady();
        
        var props = new Hashtable { ["Ready"] = isReady };
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
        
        CheckReadyStatus();
    }
    
    void CheckReadyStatus()
    {
        int readyCount = 0;
        int totalPlayers = PhotonNetwork.CurrentRoom.PlayerCount;
        
        foreach (var player in PhotonNetwork.PlayerList)
        {
            if (player.CustomProperties.TryGetValue("Ready", out object ready) && (bool)ready)
                readyCount++;
        }
        
        // Start if all ready or timeout
        if (readyCount == totalPlayers && totalPlayers >= 1)
        {
            if (PhotonNetwork.IsMasterClient)
                StartGame();
        }
        else if (readyCount > 0 && autoStartCoroutine == null)
        {
            autoStartCoroutine = StartCoroutine(AutoStartTimer());
        }
    }
}
```

## Drop-In/Drop-Out System

### Mid-Game Joining
```csharp
public class DropInManager : MonoBehaviourPunCallbacks
{
    public override void OnPlayerEnteredRoom(Player newPlayer)
    {
        if (IsGameInProgress())
        {
            // Add player to current wave
            SpawnPlayerMidGame(newPlayer);
            
            // Scale difficulty
            AdjustDifficultyForNewPlayer();
            
            // Show join notification
            ShowPlayerJoinedNotification(newPlayer);
        }
    }
    
    void SpawnPlayerMidGame(Player player)
    {
        // Wait for next safe spawn window
        StartCoroutine(WaitForSafeSpawn(player));
    }
    
    IEnumerator WaitForSafeSpawn(Player player)
    {
        // Wait for wave transition or safe moment
        yield return new WaitUntil(() => IsSafeToSpawn());
        
        // Spawn with invulnerability
        SpawnPlayerWithProtection(player);
    }
}
```

### Player Leaving
```csharp
public override void OnPlayerLeftRoom(Player otherPlayer)
{
    if (IsGameInProgress())
    {
        // Convert to AI if needed
        if (ShouldConvertToAI())
        {
            ConvertPlayerToAI(otherPlayer);
        }
        
        // Adjust difficulty
        RecalculateDifficulty();
        
        // Check if should continue
        if (PhotonNetwork.CurrentRoom.PlayerCount == 0)
        {
            EndGameSession();
        }
    }
}
```

## Wave Management

### Wave Configuration
```csharp
public class WaveManager : MonoBehaviourPunCallbacks
{
    [System.Serializable]
    public class WaveConfig
    {
        public int WaveNumber;
        public int BaseEnemyCount;
        public float SpawnRate;
        public string[] EnemyTypes;
        public float Duration;
        public bool HasBoss;
    }
    
    public void ConfigureWave(int waveNumber)
    {
        if (PhotonNetwork.IsMasterClient)
        {
            var config = GenerateWaveConfig(waveNumber);
            
            // Scale for players
            config.BaseEnemyCount = Mathf.RoundToInt(
                config.BaseEnemyCount * GetPlayerScaling()
            );
            
            var props = new Hashtable
            {
                ["CurrentWave"] = waveNumber,
                ["EnemyCount"] = config.BaseEnemyCount,
                ["WaveStartTime"] = PhotonNetwork.ServerTimestamp
            };
            
            PhotonNetwork.CurrentRoom.SetCustomProperties(props);
        }
    }
}
```

### Progression System
```csharp
public class ProgressionManager
{
    public void SaveWaveProgress(int waveReached)
    {
        // Local save
        int bestWave = PlayerPrefs.GetInt("BestWave", 0);
        if (waveReached > bestWave)
        {
            PlayerPrefs.SetInt("BestWave", waveReached);
        }
        
        // Update player stats
        var props = new Hashtable
        {
            ["HighestWave"] = bestWave,
            ["TotalWaves"] = PlayerPrefs.GetInt("TotalWaves", 0) + waveReached
        };
        
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
}
```

## Quick Start Features

### Instant Action
```csharp
public class InstantPlayManager : MonoBehaviourPunCallbacks
{
    public void PlayNow()
    {
        // Skip all menus, jump into action
        StartCoroutine(InstantPlaySequence());
    }
    
    IEnumerator InstantPlaySequence()
    {
        // Quick connect
        if (!PhotonNetwork.IsConnected)
        {
            PhotonNetwork.ConnectUsingSettings();
            yield return new WaitUntil(() => PhotonNetwork.IsConnectedAndReady);
        }
        
        // Join any available game
        PhotonNetwork.JoinRandomRoom();
    }
    
    public override void OnJoinRandomFailed(short returnCode, string message)
    {
        // Create and start immediately
        CreateInstantRoom();
    }
    
    void CreateInstantRoom()
    {
        var roomOptions = new RoomOptions
        {
            MaxPlayers = 4,
            CustomRoomProperties = new Hashtable
            {
                ["AutoStart"] = true,
                ["Arena"] = "Random",
                ["Difficulty"] = "Normal"
            }
        };
        
        PhotonNetwork.CreateRoom(null, roomOptions);
    }
}
```

### Lobby Shortcuts
```csharp
public class LobbyShortcuts : MonoBehaviour
{
    void Update()
    {
        if (PhotonNetwork.InRoom && !IsGameStarted())
        {
            // Quick ready
            if (Input.GetKeyDown(KeyCode.Space))
            {
                ToggleReady();
            }
            
            // Vote for default arena
            if (Input.GetKeyDown(KeyCode.Return))
            {
                VoteDefaultArena();
            }
            
            // Start with bots
            if (Input.GetKeyDown(KeyCode.B) && PhotonNetwork.IsMasterClient)
            {
                FillWithBots();
                StartGame();
            }
        }
    }
}
```

## Social Features

### Emote System
```csharp
public class EmoteManager : MonoBehaviourPunCallbacks
{
    public enum Emote
    {
        Wave, ThumbsUp, Dance, Taunt, Help, Thanks
    }
    
    public void SendEmote(Emote emote)
    {
        photonView.RPC("PlayEmote", RpcTarget.All, (int)emote);
    }
    
    [PunRPC]
    void PlayEmote(int emoteId)
    {
        // Play emote animation
        GetComponent<Animator>().SetTrigger($"Emote_{(Emote)emoteId}");
        
        // Show emote bubble
        ShowEmoteBubble((Emote)emoteId);
    }
}
```

### Score Tracking
```csharp
public class ScoreManager : MonoBehaviourPunCallbacks
{
    public void UpdatePlayerScore(int points)
    {
        int currentScore = GetPlayerScore(PhotonNetwork.LocalPlayer);
        
        var props = new Hashtable
        {
            ["Score"] = currentScore + points,
            ["Kills"] = GetPlayerKills() + 1,
            ["Wave"] = GetCurrentWave()
        };
        
        PhotonNetwork.LocalPlayer.SetCustomProperties(props);
    }
    
    public void DisplayScoreboard()
    {
        var sortedPlayers = PhotonNetwork.PlayerList
            .OrderByDescending(p => GetPlayerScore(p))
            .ToList();
        
        UpdateScoreboardUI(sortedPlayers);
    }
}
```

## Best Practices

### 1. **Accessibility**
- Simple controls display
- Color-blind friendly options
- Difficulty options for all skill levels

### 2. **Quick Sessions**
- Fast matchmaking
- Minimal waiting time
- Drop-in gameplay

### 3. **Social Play**
- Encourage cooperation
- Shared objectives
- Team score emphasis

## Error Handling

### Connection Recovery
```csharp
public override void OnDisconnected(DisconnectCause cause)
{
    switch (cause)
    {
        case DisconnectCause.DisconnectByClientLogic:
            // Intentional disconnect
            ReturnToMainMenu();
            break;
            
        default:
            // Try quick reconnect
            ShowReconnectDialog();
            AttemptQuickReconnect();
            break;
    }
}

void AttemptQuickReconnect()
{
    // Save progress
    SaveCurrentProgress();
    
    // Try to rejoin
    StartCoroutine(QuickReconnectSequence());
}
```

## Integration Points

- **Quantum Menu**: Base framework
- **Wave System**: Enemy spawning
- **Power-up System**: Item distribution
- **Leaderboards**: High score tracking

## Debugging

### Lobby Debug Panel
```csharp
void OnGUI()
{
    if (!Debug.isDebugBuild) return;
    
    GUILayout.BeginArea(new Rect(10, 10, 250, 300));
    GUILayout.Label("=== Twin Stick Debug ===");
    
    if (PhotonNetwork.InRoom)
    {
        GUILayout.Label($"Players: {PhotonNetwork.CurrentRoom.PlayerCount}");
        GUILayout.Label($"Wave: {GetCurrentWave()}");
        GUILayout.Label($"Difficulty: {GetDifficulty()}");
        
        if (GUILayout.Button("Start Wave"))
        {
            ForceStartWave();
        }
        
        if (GUILayout.Button("Add Bot"))
        {
            AddBotPlayer();
        }
        
        if (GUILayout.Button("Skip to Boss"))
        {
            SkipToBossWave();
        }
    }
    
    GUILayout.EndArea();
}
```
