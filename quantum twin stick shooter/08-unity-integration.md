# Unity Integration

This document explains how the Quantum Twin Stick Shooter integrates with Unity, focusing on the connection between the deterministic simulation and the visual representation.

## Overview

The Unity integration in Twin Stick Shooter provides:

1. **Simulation-View Separation**: Clear separation between deterministic logic and visual representation
2. **Event-Based Communication**: One-way communication from simulation to view
3. **Input Handling**: Collection of player input from Unity to Quantum
4. **Visual Feedback**: Representation of game state through animations and effects
5. **UI Elements**: Game interface showing scores, timers, and other information

## Architecture

### Separation of Concerns

```
Quantum (Simulation)  →  Events  →  Unity (View)
           ↑                           ↓
           └───────── Input ──────────┘
```

- **Simulation**: Deterministic game logic running in Quantum
- **View**: Visual representation in Unity
- **Events**: One-way communication from simulation to view
- **Input**: Player commands from Unity to simulation

## Core Unity Components

### CustomViewContext

The `CustomViewContext` serves as a central hub for view-related references:

```csharp
// From TwinStickShooter/Scripts/GameView/CustomViewContext.cs
public class CustomViewContext : MonoBehaviour
{
    public static CustomViewContext Instance;
    
    public Camera MainCamera;
    public CharacterView LocalView { get; set; }
    public HUDView HUD;
    public GameplayRoomManager RoomManager;
    
    private void Awake()
    {
        Instance = this;
    }
    
    public void OnLocalPlayerInstantiated(CharacterView view)
    {
        LocalView = view;
        
        // Setup camera to follow player
        if (MainCamera != null && MainCamera.TryGetComponent<CameraFollow>(out var cameraFollow))
        {
            cameraFollow.SetTarget(view.transform);
        }
        
        // Update HUD
        if (HUD != null)
        {
            HUD.OnLocalPlayerInstantiated(view);
        }
    }
}
```

### EntityViewLinker

The `EntityViewLinker` handles connecting Quantum entities to Unity GameObjects:

```csharp
// From TwinStickShooter/Scripts/GameView/EntityViewLinker.cs
public class EntityViewLinker : QuantumCallbacks
{
    public Dictionary<EntityRef, QuantumMonoBehaviour> EntityViews = new Dictionary<EntityRef, QuantumMonoBehaviour>();
    
    public override void OnEntityDestroyed(EntityRef entityRef)
    {
        // Remove destroyed entities from tracking
        if (EntityViews.TryGetValue(entityRef, out var view))
        {
            if (view != null)
            {
                Destroy(view.gameObject);
            }
            
            EntityViews.Remove(entityRef);
        }
    }
    
    public void RegisterView(EntityRef entityRef, QuantumMonoBehaviour view)
    {
        EntityViews[entityRef] = view;
    }
    
    public T GetView<T>(EntityRef entityRef) where T : QuantumMonoBehaviour
    {
        if (EntityViews.TryGetValue(entityRef, out var view))
        {
            return view as T;
        }
        
        return null;
    }
}
```

### QuantumInstantiator

The `QuantumInstantiator` creates Unity GameObjects for Quantum entities:

```csharp
// From TwinStickShooter/Scripts/GameView/QuantumInstantiator.cs
public class QuantumInstantiator : EntityViewParentBinder
{
    public override void OnEntityCreatedEvent(EntityView view, EntityCreatedEventArgs args)
    {
        base.OnEntityCreatedEvent(view, args);
        
        // Get entity view linker
        var entityViewLinker = QuantumCallback.Find<EntityViewLinker>();
        if (entityViewLinker != null)
        {
            entityViewLinker.RegisterView(args.EntityRef, view.GetComponent<QuantumMonoBehaviour>());
        }
        
        // If this is a character view and owned by local player
        CharacterView characterView = view.GetComponent<CharacterView>();
        if (characterView != null)
        {
            Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
            int playerRef = frame.Get<PlayerLink>(args.EntityRef).PlayerRef;
            
            if (playerRef == QuantumRunner.Default.Game.PlayerInputs.LocalInput.Player)
            {
                // Notify that local player has been instantiated
                characterView.IsLocalPlayer = true;
                CustomViewContext.Instance.OnLocalPlayerInstantiated(characterView);
                CharacterView.OnLocalPlayerInstantiated?.Invoke(characterView);
            }
        }
    }
}
```

## Character View

The `CharacterView` represents a character in Unity:

```csharp
// From TwinStickShooter/Scripts/GameView/CharacterView.cs
public class CharacterView : EntityView
{
    public static Action<CharacterView> OnLocalPlayerInstantiated;
    
    public bool IsLocalPlayer { get; set; }
    
    [Header("Visual Components")]
    public Animator animator;
    public SpriteRenderer characterSprite;
    public GameObject coinVisual;
    
    [Header("Effect Prefabs")]
    public GameObject deathEffect;
    public GameObject respawnEffect;
    public GameObject damageEffect;
    public GameObject healEffect;
    
    // Animation parameter hashes
    private int _movingHash;
    private int _attackHash;
    private int _deadHash;
    
    private Vector2 _lastPosition;
    private bool _isDead;
    
    protected override void OnAwake()
    {
        base.OnAwake();
        
        // Cache animation hashes
        _movingHash = Animator.StringToHash("IsMoving");
        _attackHash = Animator.StringToHash("Attack");
        _deadHash = Animator.StringToHash("IsDead");
        
        _lastPosition = transform.position;
    }
    
    public override void OnEntityDestroyed()
    {
        base.OnEntityDestroyed();
        
        if (IsLocalPlayer)
        {
            IsLocalPlayer = false;
            CustomViewContext.Instance.LocalView = null;
        }
    }
    
    protected override void OnEntityRender(EntityRef entityRef, Frame frame)
    {
        base.OnEntityRender(entityRef, frame);
        
        if (!frame.Exists(entityRef))
            return;
            
        // Update position and rotation
        if (frame.Has<Transform2D>(entityRef))
        {
            var transform2D = frame.Get<Transform2D>(entityRef);
            transform.position = transform2D.Position.ToUnityVector3();
            transform.rotation = Quaternion.Euler(0, 0, transform2D.Rotation.AsFloat * Mathf.Rad2Deg);
        }
        
        // Update character visuals
        if (frame.Has<Health>(entityRef))
        {
            var health = frame.Get<Health>(entityRef);
            bool isDead = health.IsDead;
            
            // State change detection
            if (_isDead != isDead)
            {
                _isDead = isDead;
                
                if (isDead)
                {
                    Instantiate(deathEffect, transform.position, Quaternion.identity);
                }
                
                animator.SetBool(_deadHash, isDead);
            }
        }
        
        // Update movement animation
        Vector2 currentPosition = transform.position;
        bool isMoving = Vector2.Distance(currentPosition, _lastPosition) > 0.01f;
        animator.SetBool(_movingHash, isMoving);
        _lastPosition = currentPosition;
        
        // Update team color
        if (frame.Has<TeamInfo>(entityRef))
        {
            var teamInfo = frame.Get<TeamInfo>(entityRef);
            characterSprite.color = GetTeamColor(teamInfo.Index);
        }
        
        // Update coin visual
        if (frame.Has<Inventory>(entityRef))
        {
            var inventory = frame.Get<Inventory>(entityRef);
            bool hasCoin = false;
            
            for (int i = 0; i < inventory.Items.Length; i++)
            {
                if (inventory.Items[i].Type == EItemType.Coin)
                {
                    hasCoin = true;
                    break;
                }
            }
            
            coinVisual.SetActive(hasCoin);
        }
    }
    
    private Color GetTeamColor(int teamIndex)
    {
        return teamIndex == 0 ? Color.blue : Color.red;
    }
    
    // Event handlers
    public void OnRespawned()
    {
        Instantiate(respawnEffect, transform.position, Quaternion.identity);
    }
    
    public void OnDamaged()
    {
        Instantiate(damageEffect, transform.position, Quaternion.identity);
    }
    
    public void OnHealed()
    {
        Instantiate(healEffect, transform.position, Quaternion.identity);
    }
    
    public void OnAttack()
    {
        animator.SetTrigger(_attackHash);
    }
}
```

## Input Handling

The `TopDownInput` component collects player input for the simulation:

```csharp
// From TwinStickShooter/Scripts/TopDownInput.cs
namespace TwinStickShooter
{
  using Photon.Deterministic;
  using Quantum;
  using UnityEngine;
  using UnityEngine.InputSystem;

  public class TopDownInput : MonoBehaviour
  {
    public FP AimSensitivity = 5;
    public CustomViewContext ViewContext;
    
    private FPVector2 _lastDirection = new FPVector2();
    private AttackPreview _attackPreview;
    private PlayerInput _playerInput;

    public bool IsInverseControl { get; set; } = false;

    private void Start()
    {
      _playerInput = GetComponent<PlayerInput>();
    }

    private void OnEnable()
    {
      CharacterView.OnLocalPlayerInstantiated += OnLocalPlayerInstantiated;
      QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
    }

    private void OnDisable()
    {
      CharacterView.OnLocalPlayerInstantiated -= OnLocalPlayerInstantiated;
    }

    private void OnLocalPlayerInstantiated(CharacterView playerView)
    {
      if (_attackPreview != null)
      {
        Destroy(_attackPreview.gameObject);
      }
      _attackPreview = ViewContext.LocalView.GetComponentInChildren<AttackPreview>(true);
      _attackPreview.transform.parent = null;
    }

    private void Update()
    {
      if (_attackPreview != null
#if UNITY_ANDROID
			&& _playerInput.actions["Fire"].IsPressed() == false
			&& _playerInput.actions["Special"].IsPressed() == false
#endif
#if UNITY_STANDALONE || UNITY_WEBGL
          && _playerInput.actions["MouseFire"].IsPressed() == false
          && _playerInput.actions["MouseSpecial"].IsPressed() == false
#endif
         )
      {
        _attackPreview.gameObject.SetActive(false);
      }
    }

    public void PollInput(CallbackPollInput callback)
    {
      Quantum.QuantumDemoInputTopDown input = new Quantum.QuantumDemoInputTopDown();

      FPVector2 directional = _playerInput.actions["Move"].ReadValue<Vector2>().ToFPVector2();
      input.MoveDirection = IsInverseControl == true ? -directional : directional;

#if UNITY_ANDROID
		input.Fire = _playerInput.actions["Fire"].IsPressed();
		input.AltFire = _playerInput.actions["Special"].IsPressed();
#endif
#if UNITY_STANDALONE || UNITY_WEBGL
      input.Fire = _playerInput.actions["MouseFire"].IsPressed();
      input.AltFire = _playerInput.actions["MouseSpecial"].IsPressed();
#endif

      if (input.Fire == true)
      {
        _lastDirection = _playerInput.actions["AimBasic"].ReadValue<Vector2>().ToFPVector2();
        _lastDirection *= AimSensitivity;
      }

      if (input.AltFire == true)
      {
        _lastDirection = _playerInput.actions["AimSpecial"].ReadValue<Vector2>().ToFPVector2();
        _lastDirection *= AimSensitivity;
      }

      FPVector2 actionVector = default;
#if UNITY_STANDALONE || UNITY_WEBGL
      if (_playerInput.currentControlScheme != null
          && _playerInput.currentControlScheme.Contains("Joystick"))
      {
        actionVector = IsInverseControl ? -_lastDirection : _lastDirection;
        input.AimDirection = actionVector;
      }
      else
      {
        actionVector = GetDirectionToMouse();
        input.AimDirection = actionVector;
      }

      if ((input.Fire == true || input.AltFire == true) && input.AimDirection != FPVector2.Zero)
      {
        _attackPreview.gameObject.SetActive(true);
        _attackPreview.UpdateAttackPreview(actionVector, input.AltFire);
      }

      callback.SetInput(input, DeterministicInputFlags.Repeatable);

#elif UNITY_ANDROID
		actionVector = IsInverseControl ? -_lastDirection : _lastDirection;
    input.AimDirection = actionVector;

		if ((input.Fire == true || input.AltFire == true) && actionVector != FPVector2.Zero)
		{
			_attackPreview.gameObject.SetActive(true);
			_attackPreview.UpdateAttackPreview(actionVector, input.AltFire);
		}
		callback.SetInput(input, DeterministicInputFlags.Repeatable);
#endif
    }

    private FPVector2 GetDirectionToMouse()
    {
      if (QuantumRunner.Default == null || QuantumRunner.Default.Game == null)
        return default;

      Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
      if (frame == null)
        return default;

      if (ViewContext.LocalView == null || frame.Exists(ViewContext.LocalView.EntityRef) == false)
        return default;
      
      FPVector2 localCharacterPosition = frame.Get<Transform2D>(ViewContext.LocalView.EntityRef).Position;

      Vector2 mousePosition = _playerInput.actions["Point"].ReadValue<Vector2>();
      Ray ray = Camera.main.ScreenPointToRay(mousePosition);
      UnityEngine.Plane plane = new UnityEngine.Plane(Vector3.up, Vector3.zero);

      if (plane.Raycast(ray, out var enter))
      {
        var dirToMouse = ray.GetPoint(enter).ToFPVector2() - localCharacterPosition;
        return dirToMouse;
      }

      return default;
    }
  }
}
```

## UI Implementation

The `HUDView` handles displaying game information:

```csharp
// From TwinStickShooter/Scripts/UI/HUDView.cs
public class HUDView : MonoBehaviour
{
    [Header("Panels")]
    public GameObject gameplayPanel;
    public GameObject characterSelectionPanel;
    public GameObject gameOverPanel;
    
    [Header("Team Scores")]
    public TextMeshProUGUI team1ScoreText;
    public TextMeshProUGUI team2ScoreText;
    public Image team1ScoreFill;
    public Image team2ScoreFill;
    
    [Header("Character Selection")]
    public CharacterSelectionUI characterSelectionUI;
    
    [Header("Game Over")]
    public TextMeshProUGUI winnerTeamText;
    
    [Header("Match Timer")]
    public TextMeshProUGUI matchTimerText;
    
    [Header("Player UI")]
    public GameObject healthBar;
    public Image healthFill;
    
    private CharacterView _localCharacter;
    
    private void Awake()
    {
        // Hide all panels initially
        gameplayPanel.SetActive(false);
        characterSelectionPanel.SetActive(false);
        gameOverPanel.SetActive(false);
    }
    
    private void OnEnable()
    {
        // Subscribe to game events
        QuantumEvent.Subscribe<StartCharacterSelection>(this, OnCharacterSelectionStart);
        QuantumEvent.Subscribe<CharacterSelectionComplete>(this, OnCharacterSelectionComplete);
        QuantumEvent.Subscribe<CountdownStarted>(this, OnCountdownStarted);
        QuantumEvent.Subscribe<CountdownStopped>(this, OnCountdownStopped);
        QuantumEvent.Subscribe<GameOver>(this, OnGameOver);
    }
    
    private void OnDisable()
    {
        // Unsubscribe from game events
        QuantumEvent.Unsubscribe<StartCharacterSelection>(this, OnCharacterSelectionStart);
        QuantumEvent.Unsubscribe<CharacterSelectionComplete>(this, OnCharacterSelectionComplete);
        QuantumEvent.Unsubscribe<CountdownStarted>(this, OnCountdownStarted);
        QuantumEvent.Unsubscribe<CountdownStopped>(this, OnCountdownStopped);
        QuantumEvent.Unsubscribe<GameOver>(this, OnGameOver);
    }
    
    private void Update()
    {
        // Update match timer
        if (gameplayPanel.activeSelf && QuantumRunner.Default?.Game?.Frames?.Predicted != null)
        {
            Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
            FP matchTimer = frame.Global->MatchTimer;
            FP matchDuration = frame.Global->MatchDuration;
            
            // Format time as MM:SS
            int totalSeconds = Mathf.FloorToInt(matchTimer.AsFloat);
            int minutes = totalSeconds / 60;
            int seconds = totalSeconds % 60;
            matchTimerText.text = $"{minutes:00}:{seconds:00}";
            
            // Update team scores
            UpdateTeamScores(frame);
            
            // Update player health
            UpdatePlayerHealth(frame);
        }
    }
    
    private void UpdateTeamScores(Frame frame)
    {
        byte team1Score = frame.Global->Teams[0].Score;
        byte team2Score = frame.Global->Teams[1].Score;
        
        team1ScoreText.text = team1Score.ToString();
        team2ScoreText.text = team2Score.ToString();
        
        // Update score progress bars (toward victory condition of 10 coins)
        team1ScoreFill.fillAmount = Mathf.Min(1f, team1Score / 10f);
        team2ScoreFill.fillAmount = Mathf.Min(1f, team2Score / 10f);
    }
    
    private void UpdatePlayerHealth(Frame frame)
    {
        if (_localCharacter == null || !frame.Exists(_localCharacter.EntityRef))
            return;
            
        if (frame.Has<Health>(_localCharacter.EntityRef))
        {
            var health = frame.Get<Health>(_localCharacter.EntityRef);
            FP maxHealth = AttributesHelper.GetCurrentValue(frame, _localCharacter.EntityRef, EAttributeType.Health);
            
            healthFill.fillAmount = (health.Current / maxHealth).AsFloat;
        }
    }
    
    public void OnLocalPlayerInstantiated(CharacterView characterView)
    {
        _localCharacter = characterView;
    }
    
    // Event handlers
    private void OnCharacterSelectionStart(StartCharacterSelection e)
    {
        characterSelectionPanel.SetActive(true);
        gameplayPanel.SetActive(false);
        gameOverPanel.SetActive(false);
    }
    
    private void OnCharacterSelectionComplete(CharacterSelectionComplete e)
    {
        characterSelectionPanel.SetActive(false);
    }
    
    private void OnCountdownStarted(CountdownStarted e)
    {
        // Show countdown UI...
    }
    
    private void OnCountdownStopped(CountdownStopped e)
    {
        gameplayPanel.SetActive(true);
    }
    
    private void OnGameOver(GameOver e)
    {
        gameplayPanel.SetActive(false);
        gameOverPanel.SetActive(true);
        
        winnerTeamText.text = $"Team {e.WinnerTeam + 1} Wins!";
        winnerTeamText.color = e.WinnerTeam == 0 ? Color.blue : Color.red;
    }
}
```

## Event Handling

The `QuantumCallbacks` implementation processes simulation events:

```csharp
// From TwinStickShooter/Scripts/GameView/GameEventsHandler.cs
public class GameEventsHandler : QuantumCallbacks
{
    public override void OnGameEvent(GameEventData eventData)
    {
        // Handle game events from the simulation
        EntityViewLinker entityViewLinker = FindObjectOfType<EntityViewLinker>();
        if (entityViewLinker == null)
            return;
            
        switch (eventData.EventName)
        {
            case "CharacterDefeated":
                {
                    // No specific handler needed, handled by CharacterView in OnEntityRender
                }
                break;
                
            case "CharacterRespawned":
                {
                    EntityRef characterRef = (EntityRef)eventData.Data;
                    CharacterView view = entityViewLinker.GetView<CharacterView>(characterRef);
                    
                    if (view != null)
                    {
                        view.OnRespawned();
                    }
                }
                break;
                
            case "CharacterDamaged":
                {
                    var data = (CharacterDamaged)eventData.Data;
                    CharacterView view = entityViewLinker.GetView<CharacterView>(data.target);
                    
                    if (view != null)
                    {
                        view.OnDamaged();
                    }
                }
                break;
                
            case "CharacterHealed":
                {
                    EntityRef characterRef = (EntityRef)eventData.Data;
                    CharacterView view = entityViewLinker.GetView<CharacterView>(characterRef);
                    
                    if (view != null)
                    {
                        view.OnHealed();
                    }
                }
                break;
                
            case "CharacterSkill":
                {
                    EntityRef characterRef = (EntityRef)eventData.Data;
                    CharacterView view = entityViewLinker.GetView<CharacterView>(characterRef);
                    
                    if (view != null)
                    {
                        view.OnAttack();
                    }
                }
                break;
                
            case "SkillAction":
                {
                    AssetRef skillDataRef = (AssetRef)eventData.Data;
                    PlaySkillEffect(skillDataRef);
                }
                break;
                
            case "CoinCollected":
                {
                    EntityRef characterRef = (EntityRef)eventData.Data;
                    PlaySound("coin_pickup");
                }
                break;
        }
    }
    
    private void PlaySkillEffect(AssetRef skillDataRef)
    {
        // Play visual and audio effects for skills
        if (QuantumRunner.Default?.Game?.AssetDatabase?.GetAsset(skillDataRef) is SkillData skillData)
        {
            // Play SFX
            if (skillData.SFX != null)
            {
                AudioManager.Instance.PlaySound(skillData.SFX.name);
            }
        }
    }
    
    private void PlaySound(string soundName)
    {
        AudioManager.Instance.PlaySound(soundName);
    }
}
```

## Camera Follow

The `CameraFollow` script handles following the player:

```csharp
// From TwinStickShooter/Scripts/GameView/CameraFollow.cs
public class CameraFollow : MonoBehaviour
{
    public Transform target;
    public float smoothTime = 0.3f;
    public Vector3 offset = new Vector3(0, 10, -5);
    
    private Vector3 velocity = Vector3.zero;
    
    public void SetTarget(Transform newTarget)
    {
        target = newTarget;
    }
    
    private void LateUpdate()
    {
        if (target == null)
            return;
            
        // Calculate target position
        Vector3 targetPosition = target.position + offset;
        
        // Smoothly move camera to target position
        transform.position = Vector3.SmoothDamp(transform.position, targetPosition, ref velocity, smoothTime);
        
        // Keep camera looking at target
        transform.LookAt(target);
    }
}
```

## Attack Preview

The `AttackPreview` script visualizes attack trajectories:

```csharp
// From TwinStickShooter/Scripts/GameView/AttackPreview.cs
public class AttackPreview : MonoBehaviour
{
    public SpriteRenderer basicAttackSprite;
    public SpriteRenderer specialAttackSprite;
    
    public void UpdateAttackPreview(FPVector2 direction, bool isSpecial)
    {
        // Hide both previews
        basicAttackSprite.gameObject.SetActive(false);
        specialAttackSprite.gameObject.SetActive(false);
        
        // Show appropriate preview
        if (isSpecial)
        {
            specialAttackSprite.gameObject.SetActive(true);
            UpdatePreviewTransform(specialAttackSprite.transform, direction);
        }
        else
        {
            basicAttackSprite.gameObject.SetActive(true);
            UpdatePreviewTransform(basicAttackSprite.transform, direction);
        }
    }
    
    private void UpdatePreviewTransform(Transform previewTransform, FPVector2 direction)
    {
        // Get character position from view context
        if (CustomViewContext.Instance.LocalView == null)
            return;
            
        // Position preview at character position
        Vector3 characterPosition = CustomViewContext.Instance.LocalView.transform.position;
        previewTransform.position = characterPosition;
        
        // Calculate direction angle
        float angle = Mathf.Atan2(direction.Y.AsFloat, direction.X.AsFloat) * Mathf.Rad2Deg;
        previewTransform.rotation = Quaternion.Euler(0, 0, angle);
    }
}
```

## GameplayRoomManager

The `GameplayRoomManager` handles the Photon Room connection:

```csharp
// From TwinStickShooter/Scripts/GameplayRoomManager.cs
public class GameplayRoomManager : MonoBehaviour, IConnectionCallbacks, IMatchmakingCallbacks
{
    public string gameVersion = "1.0";
    public byte maxPlayersPerRoom = 4;
    public GameObject connectingCanvas;
    public TextMeshProUGUI statusText;
    
    private void Awake()
    {
        // Configure Photon
        PhotonAppSettings.Instance.AppSettings.AppVersion = gameVersion;
        
        // Connect to Photon
        if (!PhotonNetwork.IsConnected)
        {
            connectingCanvas.SetActive(true);
            statusText.text = "Connecting to Photon...";
            PhotonNetwork.AddCallbackTarget(this);
            PhotonNetwork.ConnectUsingSettings();
        }
        else
        {
            connectingCanvas.SetActive(false);
        }
    }
    
    public void OnConnected()
    {
        statusText.text = "Connected to Photon!";
    }
    
    public void OnConnectedToMaster()
    {
        statusText.text = "Connected to Master. Joining Room...";
        
        // Join random room or create one
        PhotonNetwork.JoinRandomRoom();
    }
    
    public void OnJoinedRoom()
    {
        statusText.text = $"Joined Room: {PhotonNetwork.CurrentRoom.Name}";
        connectingCanvas.SetActive(false);
        
        // Start the game once min players joined
        StartGame();
    }
    
    public void OnJoinRandomFailed(short returnCode, string message)
    {
        statusText.text = "Creating new room...";
        
        // Create a new room
        RoomOptions roomOptions = new RoomOptions();
        roomOptions.MaxPlayers = maxPlayersPerRoom;
        PhotonNetwork.CreateRoom(null, roomOptions);
    }
    
    private void StartGame()
    {
        // Start Quantum game
        var config = RuntimeConfig.FromByteArray(Resources.Load<TextAsset>("RuntimeConfig").bytes);
        var runner = QuantumRunner.StartGame("", config, null, PhotonNetwork.LocalPlayer.ActorNumber - 1);
    }
    
    // Other IConnectionCallbacks and IMatchmakingCallbacks methods...
}
```

## Best Practices

1. **Clear Separation**: Keep a clear separation between simulation and visualization
2. **Event-Based Communication**: Use events for one-way communication from simulation to view
3. **Input Collection**: Gather input in Unity and pass to Quantum simulation
4. **Frame Rendering**: Update visuals based on simulation frame data
5. **Central View Context**: Use a central context to reference important view components
6. **Entity-GameObject Mapping**: Maintain clear mapping between simulation entities and Unity GameObjects
7. **Platform-Specific Code**: Use preprocessor directives for platform-specific input handling

## Implementation Notes

1. The simulation runs in Quantum using deterministic physics
2. Unity handles visualization, input collection, and UI
3. Events communicate state changes from simulation to view
4. Input flows from Unity to Quantum simulation
5. EntityView components update GameObject transforms based on simulation state
6. Custom components handle specific visualization needs
7. NetworkView components synchronize player input across the network