# Game Flow Management

This document explains how the Arena Brawler manages game states, scoring, and match flow.

## Game State Definition

The overall game state is managed through global variables and a state enum:

```csharp
enum GameState
{
    None, Initializing, Starting, Running, GoalScored, GameOver
}

global
{
    GameState GameState;
    CountdownTimer GameStateTimer;
    CountdownTimer MainGameTimer;
    array<int>[2] TeamScore;
}
```

The game uses several events to notify clients about state changes:

```csharp
synced event OnGameInitializing { }
synced event OnGameStarting { bool IsFirst; }
synced event OnGameRunning { }
synced event OnGoalScored { entity_ref PlayerEntityRef; PlayerTeam PlayerTeam; }
synced event OnGameOver { }
synced event OnGameRestarted { }
```

## Game System

The `GameSystem` class manages the state machine for the entire game flow:

```csharp
public unsafe class GameSystem : SystemMainThread, ISignalOnGoalScored
{
    public override void Update(Frame frame)
    {
        switch (frame.Global->GameState)
        {
            case GameState.None:
                UpdateGameState_None(frame);
                break;

            case GameState.Initializing:
                UpdateGameState_Initializing(frame);
                break;

            case GameState.Starting:
                UpdateGameState_Starting(frame);
                break;

            case GameState.Running:
                UpdateGameState_Running(frame);
                break;

            case GameState.GoalScored:
                UpdateGameState_GoalScored(frame);
                break;

            case GameState.GameOver:
                UpdateGameState_GameOver(frame);
                break;
        }
    }
    
    // State update methods...
}
```

## Game State Life Cycle

### 1. Initialization State

When the game first starts, it enters the Initialization state:

```csharp
private void UpdateGameState_None(Frame frame)
{
    ChangeGameState_Initializing(frame);
}

private void ChangeGameState_Initializing(Frame frame)
{
    GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);

    frame.Global->GameStateTimer.Start(gameSettingsData.InitializationDuration);
    frame.Global->GameState = GameState.Initializing;

    frame.Events.OnGameInitializing();
}

private void UpdateGameState_Initializing(Frame frame)
{
    frame.Global->GameStateTimer.Tick(frame.DeltaTime);
    if (frame.Global->GameStateTimer.IsDone)
    {
        ChangeGameState_Starting(frame, true);
    }
}
```

### 2. Starting State

After initialization, the game transitions to the Starting state with a countdown:

```csharp
private void ChangeGameState_Starting(Frame frame, bool isFirst)
{
    GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);

    frame.Global->GameStateTimer.Start(gameSettingsData.GameStartDuration);
    frame.Global->GameState = GameState.Starting;

    frame.Events.OnGameStarting(isFirst);
}

private void UpdateGameState_Starting(Frame frame)
{
    frame.Global->GameStateTimer.Tick(frame.DeltaTime);
    if (frame.Global->GameStateTimer.IsDone)
    {
        // Lower the team base walls
        ToggleTeamBaseStaticColliders(frame, false);
        
        // Spawn the ball
        frame.Signals.OnBallSpawned();

        // Start the match
        ChangeGameState_Running(frame);
    }
}
```

### 3. Running State

During the Running state, the game timer counts down and the main gameplay happens:

```csharp
private void ChangeGameState_Running(Frame frame)
{
    GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);

    if (frame.Global->MainGameTimer.IsDone)
    {
        frame.Global->MainGameTimer.Start(gameSettingsData.GameDuration);
    }

    frame.Global->GameState = GameState.Running;

    frame.Events.OnGameRunning();
}

private void UpdateGameState_Running(Frame frame)
{
    frame.Global->MainGameTimer.Tick(frame.DeltaTime);
    if (frame.Global->MainGameTimer.IsDone)
    {
        ChangeGameState_GameOver(frame);
    }
}
```

### 4. Goal Scored State

When a player scores a goal, the game transitions to the Goal Scored state:

```csharp
public void OnGoalScored(Frame frame, EntityRef playerEntityRef, PlayerTeam playerTeam)
{
    // Remove the ball
    DespawnBalls(frame);

    // Increment team score
    frame.Global->TeamScore[(int)playerTeam]++;

    // Change state
    ChangeGameState_GoalScored(frame, playerEntityRef, playerTeam);
}

private void ChangeGameState_GoalScored(Frame frame, EntityRef playerEntityRef, PlayerTeam playerTeam)
{
    GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);

    frame.Global->GameStateTimer.Start(gameSettingsData.GoalDuration);
    frame.Global->GameState = GameState.GoalScored;

    frame.Events.OnGoalScored(playerEntityRef, playerTeam);
}

private void UpdateGameState_GoalScored(Frame frame)
{
    frame.Global->GameStateTimer.Tick(frame.DeltaTime);
    if (frame.Global->GameStateTimer.IsDone)
    {
        // Reset players to starting positions
        RespawnPlayers(frame);
        
        // Raise team base walls
        ToggleTeamBaseStaticColliders(frame, true);

        // Reset for next point
        ChangeGameState_Starting(frame, false);
    }
}
```

### 5. Game Over State

When the game timer expires, the game transitions to the Game Over state:

```csharp
private void ChangeGameState_GameOver(Frame frame)
{
    GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);

    frame.Global->GameStateTimer.Start(gameSettingsData.GameOverDuration);
    frame.Global->GameState = GameState.GameOver;

    frame.Events.OnGameOver();
}

private void UpdateGameState_GameOver(Frame frame)
{
    frame.Global->GameStateTimer.Tick(frame.DeltaTime);
    if (frame.Global->GameStateTimer.IsDone)
    {
        // Clean up
        DespawnBalls(frame);
        RespawnPlayers(frame);
        ToggleTeamBaseStaticColliders(frame, true);

        // Reset scores
        frame.Global->TeamScore[0] = 0;
        frame.Global->TeamScore[1] = 0;

        frame.Events.OnGameRestarted();

        // Start a new game
        ChangeGameState_Starting(frame, true);
    }
}
```

## Helper Methods

The `GameSystem` includes several helper methods for common operations:

```csharp
private void DespawnBalls(Frame frame)
{
    foreach (var (ballEntityRef, _) in frame.Unsafe.GetComponentBlockIterator<BallStatus>())
    {
        frame.Signals.OnBallDespawned(ballEntityRef);
    }
}

private void RespawnPlayers(Frame frame)
{
    foreach (var (playerEntityRef, _) in frame.Unsafe.GetComponentBlockIterator<PlayerStatus>())
    {
        frame.Signals.OnPlayerRespawned(playerEntityRef, true);
    }
}

private void ToggleTeamBaseStaticColliders(Frame frame, bool enabled)
{
    var filtered = frame.Filter<TeamBaseWallStaticColliderTag, StaticColliderLink>();
    while (filtered.Next(out _, out _, out var wallColliderLink))
    {
        frame.Physics3D.SetStaticColliderEnabled(wallColliderLink.StaticColliderIndex, enabled);
    }
}
```

## Goal Detection

The game uses a separate `GoalSystem` to detect when a ball enters a goal:

```csharp
public unsafe class GoalSystem : SystemMainThreadFilter<GoalSystem.Filter>
{
    public struct Filter
    {
        public EntityRef EntityRef;
        public GoalAreaCollider* GoalAreaCollider;
        public Transform3D* Transform;
    }

    public override void Update(Frame frame, ref Filter filter)
    {
        // Early out if not in running state
        if (frame.Global->GameState != GameState.Running)
        {
            return;
        }

        // Create goal detection shape
        Shape3D goalShape = Shape3D.CreateBox(filter.GoalAreaCollider->GoalAreaSize);
        
        // Get game settings
        GameSettingsData gameSettingsData = frame.FindAsset<GameSettingsData>(frame.RuntimeConfig.GameSettingsData.Id);
        
        // Check for ball overlaps
        HitCollection3D hitCollection = frame.Physics3D.OverlapShape(
            filter.Transform->Position, 
            filter.Transform->Rotation, 
            goalShape, 
            gameSettingsData.BallLayerMask);

        // Process hits
        for (int i = 0; i < hitCollection.Count; i++)
        {
            EntityRef ballEntityRef = hitCollection[i].Entity;
            
            // Get the last player to touch the ball
            EntityRef scoringPlayerEntityRef = GetLastTouchingPlayer(frame, ballEntityRef);
            
            if (scoringPlayerEntityRef != default)
            {
                PlayerStatus* scorerStatus = frame.Unsafe.GetPointer<PlayerStatus>(scoringPlayerEntityRef);
                PlayerTeam scoringTeam = scorerStatus->PlayerTeam;
                
                // Check if this is the opposing team's goal
                if (scoringTeam != filter.GoalAreaCollider->TeamOwner)
                {
                    // Score a goal for the scoring team
                    frame.Signals.OnGoalScored(scoringPlayerEntityRef, scoringTeam);
                    break;
                }
            }
        }
    }
    
    private EntityRef GetLastTouchingPlayer(Frame frame, EntityRef ballEntityRef)
    {
        BallStatus* ballStatus = frame.Unsafe.GetPointer<BallStatus>(ballEntityRef);
        
        // If ball is currently held, use that player
        if (ballStatus->IsHeldByPlayer)
        {
            return ballStatus->HoldingPlayerEntityRef;
        }
        
        // If ball has a catch timeout, use that player
        if (ballStatus->CatchTimeoutTimer.IsRunning)
        {
            // Find the actual entity for this player
            var filtered = frame.Filter<PlayerStatus>();
            while (filtered.Next(out var playerEntityRef, out var playerStatus))
            {
                if (playerStatus->PlayerRef == ballStatus->CatchTimeoutPlayerRef)
                {
                    return playerEntityRef;
                }
            }
        }
        
        // No last touching player found
        return default;
    }
}
```

## Goal Area Collider

Goal areas are defined with a `GoalAreaCollider` component:

```csharp
component GoalAreaCollider
{
    FPVector3 GoalAreaSize;
    PlayerTeam TeamOwner;
}
```

And configured via a data asset:

```csharp
[CreateAssetMenu(menuName = "Quantum/Arena Brawler/Goal Area Collider Data")]
public class GoalAreaColliderData : AssetObject
{
    public FPVector3 GoalAreaSize = new FPVector3(3, 2, 1);
    public PlayerTeam TeamOwner;
}
```

## Game Settings Configuration

All timing and duration parameters are defined in the `GameSettingsData` asset:

```csharp
[CreateAssetMenu(menuName = "Quantum/Arena Brawler/Game Settings Data")]
public class GameSettingsData : AssetObject
{
    [Header("Game State Durations")]
    public FP InitializationDuration = 1;
    public FP GameStartDuration = 3;
    public FP GameDuration = 180;     // 3 minutes
    public FP GoalDuration = 5;
    public FP GameOverDuration = 10;
    
    [Header("Player Settings")]
    public FP RespawnDuration = 3;
    
    [Header("Physics Layers")]
    public PhysicsLayers PlayerLayerMask;
    public PhysicsLayers BallLayerMask;
    public PhysicsLayers ArenaLayerMask;
}
```

## Unity-Side Event Handling

On the Unity side, the game state events are handled to update UI and visual elements:

```csharp
public class GameStateManager : MonoBehaviour, IQuantumEventListener
{
    [SerializeField] private GameObject _initializingUI;
    [SerializeField] private GameObject _startingUI;
    [SerializeField] private GameObject _runningUI;
    [SerializeField] private GameObject _goalScoredUI;
    [SerializeField] private GameObject _gameOverUI;
    
    [SerializeField] private Text _countdownText;
    [SerializeField] private Text _gameTimerText;
    [SerializeField] private Text _blueTeamScoreText;
    [SerializeField] private Text _redTeamScoreText;
    
    public void OnInit(QuantumGame game)
    {
        // Register for Quantum events
        game.EventDispatcher.Subscribe(this);
    }
    
    public void OnDestroy()
    {
        if (QuantumRunner.Default?.Game != null)
        {
            QuantumRunner.Default.Game.EventDispatcher.Unsubscribe(this);
        }
    }
    
    public void Update()
    {
        if (QuantumRunner.Default?.Game?.Frames?.Predicted == null)
        {
            return;
        }
        
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        
        // Update timer display based on current state
        switch (frame.Global->GameState)
        {
            case GameState.Starting:
                _countdownText.text = Mathf.CeilToInt((float)frame.Global->GameStateTimer.TimeLeft).ToString();
                break;
                
            case GameState.Running:
                UpdateGameTimer(frame);
                UpdateScores(frame);
                break;
        }
    }
    
    private void UpdateGameTimer(Frame frame)
    {
        int minutes = Mathf.FloorToInt((float)frame.Global->MainGameTimer.TimeLeft / 60f);
        int seconds = Mathf.FloorToInt((float)frame.Global->MainGameTimer.TimeLeft) % 60;
        
        _gameTimerText.text = $"{minutes:00}:{seconds:00}";
    }
    
    private void UpdateScores(Frame frame)
    {
        _blueTeamScoreText.text = frame.Global->TeamScore[0].ToString();
        _redTeamScoreText.text = frame.Global->TeamScore[1].ToString();
    }
    
    // Event handlers for game state changes
    public void OnEvent(OnGameInitializing e)
    {
        ShowStateUI(GameState.Initializing);
    }
    
    public void OnEvent(OnGameStarting e)
    {
        ShowStateUI(GameState.Starting);
        
        if (e.IsFirst)
        {
            // Play game start animation/sound
            AudioManager.Instance.PlaySound("GameStart");
        }
    }
    
    public void OnEvent(OnGameRunning e)
    {
        ShowStateUI(GameState.Running);
        
        // Play match start sound
        AudioManager.Instance.PlaySound("MatchStart");
    }
    
    public void OnEvent(OnGoalScored e)
    {
        ShowStateUI(GameState.GoalScored);
        
        // Show goal scoring animation
        GoalEffectsManager.Instance.PlayGoalEffect(e.PlayerTeam);
        
        // Play goal sound
        AudioManager.Instance.PlaySound("GoalScored");
    }
    
    public void OnEvent(OnGameOver e)
    {
        ShowStateUI(GameState.GameOver);
        
        // Determine winner and show appropriate UI
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        int blueScore = frame.Global->TeamScore[0];
        int redScore = frame.Global->TeamScore[1];
        
        if (blueScore > redScore)
        {
            GameOverUIManager.Instance.ShowWinner(PlayerTeam.Blue);
        }
        else if (redScore > blueScore)
        {
            GameOverUIManager.Instance.ShowWinner(PlayerTeam.Red);
        }
        else
        {
            GameOverUIManager.Instance.ShowDraw();
        }
        
        // Play game over sound
        AudioManager.Instance.PlaySound("GameOver");
    }
    
    private void ShowStateUI(GameState state)
    {
        _initializingUI.SetActive(state == GameState.Initializing);
        _startingUI.SetActive(state == GameState.Starting);
        _runningUI.SetActive(state == GameState.Running);
        _goalScoredUI.SetActive(state == GameState.GoalScored);
        _gameOverUI.SetActive(state == GameState.GameOver);
    }
}
```

## Static Collider Management

Team base walls are managed via static colliders that are toggled on/off during different game states:

```csharp
public class StaticColliderLinkBaker : MonoBehaviour
{
    [SerializeField] private bool _isTeamBaseWall;
    [SerializeField] private PlayerTeam _teamOwner;
    
    private int _staticColliderIndex = -1;
    
    // Called by the Quantum Map3D baking process
    public void OnBakeStaticCollider(int staticColliderIndex)
    {
        _staticColliderIndex = staticColliderIndex;
    }
    
    // Called by the Quantum EntityPrototypeBuilder during entity creation
    public void OnEntityCreated(EntityRef entityRef)
    {
        if (_staticColliderIndex < 0)
        {
            return;
        }
        
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        
        // Add static collider link component
        frame.Add<StaticColliderLink>(entityRef);
        frame.Unsafe.GetPointer<StaticColliderLink>(entityRef)->StaticColliderIndex = _staticColliderIndex;
        
        // Add team base wall tag if needed
        if (_isTeamBaseWall)
        {
            frame.Add<TeamBaseWallStaticColliderTag>(entityRef);
        }
    }
}
```

This system allows the walls around team bases to be raised during the Starting state (preventing players from moving) and lowered during the Running state (allowing free movement).
