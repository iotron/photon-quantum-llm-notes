# Local Multiplayer

This document explains how the Quantum Arena Brawler implements local multiplayer with split-screen support.

## Local Players Support Overview

The Arena Brawler supports up to 4 local players on a single device. Key features include:

1. Dynamic UI and camera layout based on local player count
2. Automatic input device assignment
3. SQL lobby filtering to account for local players
4. Efficient player configuration management

## Local Player Count Management

The game tracks local player count through a custom lobby property:

```csharp
public class LocalPlayerCountManager : MonoBehaviour
{
    public const string LOCAL_PLAYERS_PROP_KEY = "LP";
    public const string TOTAL_PLAYERS_PROP_KEY = "C0";

    public static readonly TypedLobby SQL_LOBBY = new TypedLobby("customSqlLobby", LobbyType.SqlLobby);
    
    [SerializeField] private Dropdown _localPlayersCountSelector;
    private QuantumRunner _connection;
    
    public void SetConnection(QuantumRunner connection)
    {
        _connection = connection;
        
        // Set initial property
        if (_connection != null && _connection.Client.InRoom)
        {
            UpdateLocalPlayersCount();
        }
    }
    
    public void OnLocalPlayersCountChanged()
    {
        if (_connection != null && _connection.Client.InRoom)
        {
            UpdateLocalPlayersCount();
        }
    }
    
    private void UpdateLocalPlayersCount()
    {
        int localPlayersCount = _localPlayersCountSelector.GetLastSelectedLocalPlayersCount();
        
        _connection.Client.LocalPlayer.SetCustomProperties(new PhotonHashtable
        {
            { LOCAL_PLAYERS_PROP_KEY, localPlayersCount }
        });
        
        UpdateRoomTotalPlayers();
    }
    
    private void UpdateRoomTotalPlayers()
    {
        if (_connection != null && _connection.Client.InRoom && _connection.Client.LocalPlayer.IsMasterClient)
        {
            int totalPlayers = 0;
            foreach (var player in _connection.Client.CurrentRoom.Players.Values)
            {
                if (player.CustomProperties.TryGetValue(LOCAL_PLAYERS_PROP_KEY, out var localPlayersCount))
                {
                    totalPlayers += (int)localPlayersCount;
                }
            }

            _connection.Client.CurrentRoom.SetCustomProperties(new PhotonHashtable
            {
                { TOTAL_PLAYERS_PROP_KEY, totalPlayers }
            });
        }
    }
}
```

## Matchmaking With Local Players

The game uses SQL filtering to limit the total number of players in a room, accounting for local players:

```csharp
protected override void OnConnect(QuantumMenuConnectArgs connectArgs, ref MatchmakingArguments args)
{
    args.RandomMatchingType = MatchmakingMode.FillRoom;
    args.Lobby = LocalPlayerCountManager.SQL_LOBBY;
    args.CustomLobbyProperties = new string[] { LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY };
    
    int localPlayersCount = _localPlayersCountSelector.GetLastSelectedLocalPlayersCount();
    int maxPlayerCount = Input.MAX_COUNT; // 6 players maximum
    
    // Ensure we don't join rooms that would exceed the player limit
    args.SqlLobbyFilter = $"{LocalPlayerCountManager.TOTAL_PLAYERS_PROP_KEY} <= {maxPlayerCount - localPlayersCount}";
}
```

## Local Players Configuration

When the gameplay starts, a configuration prefab is instantiated based on the number of local players:

```csharp
public class LocalPlayersManager : MonoBehaviour
{
    public static LocalPlayersManager Instance { get; private set; }

    [SerializeField] private LocalPlayersConfig[] _localPlayersConfigPrefabs;
    [SerializeField] private Camera _temporaryCamera;

    private Dictionary<int, LocalPlayerAccess> _localPlayerAccessByPlayerIndices = new Dictionary<int, LocalPlayerAccess>();

    public Dictionary<int, LocalPlayerAccess>.ValueCollection LocalPlayerAccessCollection
    {
        get
        {
            if (_localPlayerAccessByPlayerIndices.Count == 0)
            {
                Initialize();
            }

            return _localPlayerAccessByPlayerIndices.Values;
        }
    }

    private void Awake()
    {
        Instance = this;
    }

    public LocalPlayerAccess InitializeLocalPlayer(PlayerViewController playerViewController)
    {
        LocalPlayerAccess localPlayerAccess = GetLocalPlayerAccess(playerViewController.PlayerRef);
        localPlayerAccess.InitializeLocalPlayer(playerViewController);

        return localPlayerAccess;
    }

    public LocalPlayerAccess GetLocalPlayerAccess(int playerIndex)
    {
        if (_localPlayerAccessByPlayerIndices.Count == 0)
        {
            Initialize();
        }

        _localPlayerAccessByPlayerIndices.TryGetValue(playerIndex, out LocalPlayerAccess localPlayerAccess);
        return localPlayerAccess;
    }

    private void Initialize()
    {
        var localPlayerIndices = QuantumRunner.Default.Game.GetLocalPlayers();
        if(localPlayerIndices.Count == 0) return;
        
        // Select the appropriate config prefab based on local player count
        LocalPlayersConfig localPlayersConfig = Instantiate(_localPlayersConfigPrefabs[localPlayerIndices.Count - 1], transform);
        
        for (int i = 0; i < localPlayerIndices.Count; i++)
        {
            LocalPlayerAccess localPlayerAccess = localPlayersConfig.GetLocalPlayerAccess(i);
            localPlayerAccess.IsMainLocalPlayer = i == 0;

            _localPlayerAccessByPlayerIndices.Add(localPlayerIndices[i], localPlayerAccess);
        }

        // Remove the temporary camera once players are set up
        Destroy(_temporaryCamera.gameObject);
    }
}
```

## Local Players Config

Each local player count has a specific configuration prefab:

```csharp
public class LocalPlayersConfig : MonoBehaviour
{
    [SerializeField] private LocalPlayerAccess[] _localPlayerAccesses;

    public LocalPlayerAccess GetLocalPlayerAccess(int localIndex)
    {
        if (localIndex < 0 || localIndex >= _localPlayerAccesses.Length)
        {
            Debug.LogError($"Invalid local player index: {localIndex}");
            return null;
        }

        return _localPlayerAccesses[localIndex];
    }
}
```

## Local Player Access

Each local player has a dedicated access component providing camera, UI, and input:

```csharp
public class LocalPlayerAccess : MonoBehaviour
{
    [SerializeField] private int _localIndex;
    [SerializeField] private Camera _camera;
    [SerializeField] private Canvas _uiCanvas;
    [SerializeField] private PlayerInput _playerInput;
    [SerializeField] private LocalPlayerUI _playerUI;
    
    public bool IsMainLocalPlayer { get; set; }
    
    private PlayerViewController _playerViewController;
    
    public void InitializeLocalPlayer(PlayerViewController playerViewController)
    {
        _playerViewController = playerViewController;
        
        // Set up Cinemachine targets to follow this player
        CinemachineTargetGroup targetGroup = GetComponentInChildren<CinemachineTargetGroup>();
        if (targetGroup != null)
        {
            // Add player to target group with high weight
            targetGroup.AddMember(playerViewController.transform, 1.0f, 2.0f);
            
            // Find ball and add with lower weight but larger radius
            BallEntityView ballView = FindObjectOfType<BallEntityView>();
            if (ballView != null)
            {
                targetGroup.AddMember(ballView.transform, 0.5f, 4.0f);
            }
            
            // Find all other players and add with low weight
            PlayerViewController[] allPlayers = FindObjectsOfType<PlayerViewController>();
            foreach (var player in allPlayers)
            {
                if (player != playerViewController)
                {
                    targetGroup.AddMember(player.transform, 0.25f, 2.0f);
                }
            }
        }
        
        // Initialize UI
        _playerUI.Initialize(playerViewController);
    }
    
    public Camera Camera => _camera;
    public Canvas UICanvas => _uiCanvas;
    public PlayerInput PlayerInput => _playerInput;
}
```

## Local Player UI

Each local player has their own UI elements:

```csharp
public class LocalPlayerUI : MonoBehaviour
{
    [SerializeField] private Image _playerIndicator;
    [SerializeField] private AbilityCooldownsUI _abilityCooldowns;
    [SerializeField] private Image _stunIndicator;
    [SerializeField] private RectTransform _scorePanel;
    
    private PlayerViewController _playerViewController;
    
    public void Initialize(PlayerViewController playerViewController)
    {
        _playerViewController = playerViewController;
        
        // Set player indicator color based on team
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(playerViewController.EntityRef);
        
        _playerIndicator.color = playerStatus->PlayerTeam == PlayerTeam.Blue ? 
            new Color(0.2f, 0.4f, 1.0f) : new Color(1.0f, 0.3f, 0.3f);
            
        // Initialize ability cooldowns UI
        _abilityCooldowns.Initialize(playerViewController.EntityRef);
    }
    
    public void Update()
    {
        if (_playerViewController == null)
        {
            return;
        }
        
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        PlayerStatus* playerStatus = frame.Unsafe.GetPointer<PlayerStatus>(_playerViewController.EntityRef);
        
        // Update stun indicator
        _stunIndicator.gameObject.SetActive(playerStatus->IsStunned());
    }
}
```

## Input Device Management

The Unity Input System package is used to automatically assign input devices to local players:

```csharp
public class InputDeviceManager : MonoBehaviour
{
    [SerializeField] private PlayerInputManager _playerInputManager;
    
    private void Start()
    {
        // Set up input device joining
        PlayerInputManager.instance.joinBehavior = PlayerJoinBehavior.JoinPlayersManually;
        
        // Get required local player count
        int localPlayerCount = QuantumRunner.Default.Game.GetLocalPlayers().Count;
        
        // Join first player with keyboard+mouse
        PlayerInput mainPlayerInput = PlayerInputManager.instance.JoinPlayer(controlScheme: "KeyboardMouse");
        
        // Join additional players with gamepads
        for (int i = 1; i < localPlayerCount; i++)
        {
            PlayerInput additionalInput = PlayerInputManager.instance.JoinPlayer(controlScheme: "Gamepad");
        }
    }
}
```

## Viewport Management

For split-screen play, the camera viewports are automatically adjusted:

```csharp
public class SplitScreenManager : MonoBehaviour
{
    [SerializeField] private GameObject _singleViewportLayout;
    [SerializeField] private GameObject _dualViewportLayout;
    [SerializeField] private GameObject _tripleViewportLayout;
    [SerializeField] private GameObject _quadViewportLayout;
    
    private void Start()
    {
        // Determine viewport layout based on local player count
        int localPlayerCount = QuantumRunner.Default.Game.GetLocalPlayers().Count;
        
        _singleViewportLayout.SetActive(localPlayerCount == 1);
        _dualViewportLayout.SetActive(localPlayerCount == 2);
        _tripleViewportLayout.SetActive(localPlayerCount == 3);
        _quadViewportLayout.SetActive(localPlayerCount == 4);
        
        // Assign cameras to viewports
        var localPlayers = LocalPlayersManager.Instance.LocalPlayerAccessCollection;
        
        if (localPlayerCount == 1)
        {
            // Full screen for one player
            SetupSinglePlayer(localPlayers);
        }
        else if (localPlayerCount == 2)
        {
            // Split screen for two players (horizontal)
            SetupTwoPlayers(localPlayers);
        }
        else if (localPlayerCount == 3)
        {
            // Custom layout for three players
            SetupThreePlayers(localPlayers);
        }
        else if (localPlayerCount == 4)
        {
            // Grid layout for four players
            SetupFourPlayers(localPlayers);
        }
    }
    
    private void SetupSinglePlayer(IEnumerable<LocalPlayerAccess> localPlayers)
    {
        foreach (var playerAccess in localPlayers)
        {
            // Full screen viewport
            playerAccess.Camera.rect = new Rect(0, 0, 1, 1);
        }
    }
    
    private void SetupTwoPlayers(IEnumerable<LocalPlayerAccess> localPlayers)
    {
        int index = 0;
        foreach (var playerAccess in localPlayers)
        {
            if (index == 0)
            {
                // Top half of screen
                playerAccess.Camera.rect = new Rect(0, 0.5f, 1, 0.5f);
            }
            else
            {
                // Bottom half of screen
                playerAccess.Camera.rect = new Rect(0, 0, 1, 0.5f);
            }
            index++;
        }
    }
    
    private void SetupThreePlayers(IEnumerable<LocalPlayerAccess> localPlayers)
    {
        int index = 0;
        foreach (var playerAccess in localPlayers)
        {
            if (index == 0)
            {
                // Top left
                playerAccess.Camera.rect = new Rect(0, 0.5f, 0.5f, 0.5f);
            }
            else if (index == 1)
            {
                // Top right
                playerAccess.Camera.rect = new Rect(0.5f, 0.5f, 0.5f, 0.5f);
            }
            else
            {
                // Bottom (full width)
                playerAccess.Camera.rect = new Rect(0, 0, 1, 0.5f);
            }
            index++;
        }
    }
    
    private void SetupFourPlayers(IEnumerable<LocalPlayerAccess> localPlayers)
    {
        int index = 0;
        foreach (var playerAccess in localPlayers)
        {
            if (index == 0)
            {
                // Top left
                playerAccess.Camera.rect = new Rect(0, 0.5f, 0.5f, 0.5f);
            }
            else if (index == 1)
            {
                // Top right
                playerAccess.Camera.rect = new Rect(0.5f, 0.5f, 0.5f, 0.5f);
            }
            else if (index == 2)
            {
                // Bottom left
                playerAccess.Camera.rect = new Rect(0, 0, 0.5f, 0.5f);
            }
            else
            {
                // Bottom right
                playerAccess.Camera.rect = new Rect(0.5f, 0, 0.5f, 0.5f);
            }
            index++;
        }
    }
}
```

## Input Action Mapping

Each local player has their own input action asset to handle controls:

```csharp
// Example of the player input asset configuration
{
    "name": "PlayerControls",
    "maps": [
        {
            "name": "Gameplay",
            "id": "33b2bbd9-a108-4a8e-a00d-a6aa6c9a82c4",
            "actions": [
                {
                    "name": "Move",
                    "type": "Value",
                    "id": "26d64aad-8a1c-4b94-afe9-c0a88f1fb9b0",
                    "expectedControlType": "Vector2",
                    "processors": "",
                    "interactions": ""
                },
                {
                    "name": "Aim",
                    "type": "Value",
                    "id": "fe10e3c5-2b17-4d2f-a62a-7fa2a1e47a98",
                    "expectedControlType": "Vector2",
                    "processors": "",
                    "interactions": ""
                },
                {
                    "name": "Jump",
                    "type": "Button",
                    "id": "54b0e3f3-2f9a-4c9a-ac2d-94307a0f0098",
                    "expectedControlType": "Button",
                    "processors": "",
                    "interactions": ""
                },
                {
                    "name": "Dash",
                    "type": "Button",
                    "id": "d70aec3e-1e41-4dda-8b85-9a8ef7b43ab3",
                    "expectedControlType": "Button",
                    "processors": "",
                    "interactions": ""
                },
                {
                    "name": "Fire",
                    "type": "Button",
                    "id": "9d7bb5e2-5227-4e2a-b1c1-11de61ea2d9f",
                    "expectedControlType": "Button",
                    "processors": "",
                    "interactions": ""
                },
                {
                    "name": "AltFire",
                    "type": "Button",
                    "id": "0aa1e8cf-6a7c-4b96-87a9-e85af973e3a0",
                    "expectedControlType": "Button",
                    "processors": "",
                    "interactions": ""
                }
            ],
            "bindings": [
                // Input bindings for keyboard/mouse
                {
                    "name": "WASD",
                    "id": "ad85ff4c-1927-4e81-8872-a54e1d9c8024",
                    "path": "2DVector",
                    "interactions": "",
                    "processors": "",
                    "groups": "",
                    "action": "Move",
                    "isComposite": true,
                    "isPartOfComposite": false
                },
                {
                    "name": "up",
                    "id": "e6d73d72-ee3c-40e0-8e91-b89c11f1a15a",
                    "path": "<Keyboard>/w",
                    "interactions": "",
                    "processors": "",
                    "groups": "KeyboardMouse",
                    "action": "Move",
                    "isComposite": false,
                    "isPartOfComposite": true
                },
                // Additional keyboard bindings...
                
                // Input bindings for gamepad
                {
                    "name": "Left Stick",
                    "id": "e55e7a9a-9b5e-4af6-82e7-98f7d0b3bc81",
                    "path": "2DVector(mode=2)",
                    "interactions": "",
                    "processors": "",
                    "groups": "",
                    "action": "Move",
                    "isComposite": true,
                    "isPartOfComposite": false
                },
                {
                    "name": "up",
                    "id": "6a12da3e-d9e3-4c41-8f39-fbf8f4e9a7ce",
                    "path": "<Gamepad>/leftStick/up",
                    "interactions": "",
                    "processors": "",
                    "groups": "Gamepad",
                    "action": "Move",
                    "isComposite": false,
                    "isPartOfComposite": true
                },
                // Additional gamepad bindings...
            ]
        }
    ],
    "controlSchemes": [
        {
            "name": "KeyboardMouse",
            "bindingGroup": "KeyboardMouse",
            "devices": [
                {
                    "devicePath": "<Keyboard>",
                    "isOptional": false,
                    "isOR": false
                },
                {
                    "devicePath": "<Mouse>",
                    "isOptional": false,
                    "isOR": false
                }
            ]
        },
        {
            "name": "Gamepad",
            "bindingGroup": "Gamepad",
            "devices": [
                {
                    "devicePath": "<Gamepad>",
                    "isOptional": false,
                    "isOR": false
                }
            ]
        }
    ]
}
```

## Local Input Provider

The game bridges Unity's Input System to Quantum's input structure:

```csharp
public class LocalInputProvider : MonoBehaviour
{
    [SerializeField] private PlayerInput _playerInput;
    private InputActionMap _gameplayActions;
    
    private Vector2 _moveDirection;
    private Vector2 _aimDirection;
    private bool _jumpPressed;
    private bool _dashPressed;
    private bool _firePressed;
    private bool _altFirePressed;
    
    private void Awake()
    {
        _gameplayActions = _playerInput.actions.FindActionMap("Gameplay");
        
        // Set up input callbacks
        _gameplayActions["Move"].performed += ctx => _moveDirection = ctx.ReadValue<Vector2>();
        _gameplayActions["Move"].canceled += ctx => _moveDirection = Vector2.zero;
        
        _gameplayActions["Aim"].performed += ctx => _aimDirection = ctx.ReadValue<Vector2>();
        _gameplayActions["Aim"].canceled += ctx => _aimDirection = Vector2.zero;
        
        _gameplayActions["Jump"].performed += ctx => _jumpPressed = true;
        _gameplayActions["Jump"].canceled += ctx => _jumpPressed = false;
        
        _gameplayActions["Dash"].performed += ctx => _dashPressed = true;
        _gameplayActions["Dash"].canceled += ctx => _dashPressed = false;
        
        _gameplayActions["Fire"].performed += ctx => _firePressed = true;
        _gameplayActions["Fire"].canceled += ctx => _firePressed = false;
        
        _gameplayActions["AltFire"].performed += ctx => _altFirePressed = true;
        _gameplayActions["AltFire"].canceled += ctx => _altFirePressed = false;
    }
    
    private void OnEnable()
    {
        _gameplayActions.Enable();
    }
    
    private void OnDisable()
    {
        _gameplayActions.Disable();
    }
    
    // Called by Quantum to get the current input state
    public void OnInput(QuantumGame game, QuantumDemoInputTopDown* data)
    {
        // Convert from Unity input to Quantum input
        data->MoveDirection = new FPVector2(_moveDirection.x, _moveDirection.y);
        data->AimDirection = new FPVector2(_aimDirection.x, _aimDirection.y);
        
        // Handle aim direction on keyboard/mouse
        if (_playerInput.currentControlScheme == "KeyboardMouse")
        {
            // Use mouse position for aiming
            Vector3 mousePos = Input.mousePosition;
            Vector3 worldPos = _playerInput.GetComponent<LocalPlayerAccess>().Camera.ScreenToWorldPoint(new Vector3(mousePos.x, mousePos.y, 10f));
            
            Vector3 playerPos = transform.position;
            Vector3 aimDir = (worldPos - playerPos).normalized;
            
            data->AimDirection = new FPVector2(aimDir.x, aimDir.z);
        }
        
        // Set button states
        SetButton(game, ref data->Jump, _jumpPressed);
        SetButton(game, ref data->Dash, _dashPressed);
        SetButton(game, ref data->Fire, _firePressed);
        SetButton(game, ref data->AltFire, _altFirePressed);
    }
    
    private void SetButton(QuantumGame game, ref Photon.Deterministic.BitSet button, bool pressed)
    {
        if (pressed)
        {
            button.Push(game.Frames.Predicted);
        }
        else
        {
            button.Clear(game.Frames.Predicted);
        }
    }
}
```

## Input Registration

The game registers input providers for each local player:

```csharp
public class LocalInputRegistration : MonoBehaviour
{
    private void Start()
    {
        if (QuantumRunner.Default == null)
        {
            return;
        }
        
        // Get local player indices
        var localPlayerIndices = QuantumRunner.Default.Game.GetLocalPlayers();
        
        // Get input providers
        LocalInputProvider[] inputProviders = FindObjectsOfType<LocalInputProvider>();
        
        // Register each input provider
        for (int i = 0; i < Mathf.Min(localPlayerIndices.Count, inputProviders.Length); i++)
        {
            int playerIndex = localPlayerIndices[i];
            LocalInputProvider inputProvider = inputProviders[i];
            
            // Register with Quantum
            QuantumRunner.Default.Game.SetInput(playerIndex, inputProvider.OnInput);
        }
    }
}
```

## Shared UI Elements

While each player has their own UI, some elements are shared across all local players:

```csharp
public class SharedUIManager : MonoBehaviour
{
    [SerializeField] private GameObject _pauseMenu;
    [SerializeField] private Text _gameTimerText;
    [SerializeField] private Text _blueTeamScoreText;
    [SerializeField] private Text _redTeamScoreText;
    
    private void Update()
    {
        if (QuantumRunner.Default?.Game?.Frames?.Predicted == null)
        {
            return;
        }
        
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        
        // Update shared score display
        _blueTeamScoreText.text = frame.Global->TeamScore[0].ToString();
        _redTeamScoreText.text = frame.Global->TeamScore[1].ToString();
        
        // Update shared timer
        if (frame.Global->GameState == GameState.Running)
        {
            int minutes = Mathf.FloorToInt((float)frame.Global->MainGameTimer.TimeLeft / 60f);
            int seconds = Mathf.FloorToInt((float)frame.Global->MainGameTimer.TimeLeft) % 60;
            
            _gameTimerText.text = $"{minutes:00}:{seconds:00}";
        }
    }
    
    public void OnPauseButtonPressed()
    {
        _pauseMenu.SetActive(true);
        Time.timeScale = 0f;
    }
    
    public void OnResumeButtonPressed()
    {
        _pauseMenu.SetActive(false);
        Time.timeScale = 1f;
    }
}
```

## Camera Target Group

Each player's camera uses Cinemachine's TargetGroup to dynamically frame the action:

```csharp
public class CameraTargetManager : MonoBehaviour
{
    [SerializeField] private float _playerWeight = 1.0f;
    [SerializeField] private float _playerRadius = 2.0f;
    [SerializeField] private float _ballWeight = 0.5f;
    [SerializeField] private float _ballRadius = 4.0f;
    [SerializeField] private float _otherPlayerWeight = 0.25f;
    [SerializeField] private float _otherPlayerRadius = 2.0f;
    
    private CinemachineTargetGroup _targetGroup;
    private PlayerViewController _player;
    private BallEntityView _ball;
    
    public void Initialize(PlayerViewController player)
    {
        _targetGroup = GetComponent<CinemachineTargetGroup>();
        _player = player;
        
        // Add player as primary target
        _targetGroup.AddMember(player.transform, _playerWeight, _playerRadius);
        
        // Find and add ball
        _ball = FindObjectOfType<BallEntityView>();
        if (_ball != null)
        {
            _targetGroup.AddMember(_ball.transform, _ballWeight, _ballRadius);
        }
        
        // Find and add other players with less weight
        PlayerViewController[] allPlayers = FindObjectsOfType<PlayerViewController>();
        foreach (var otherPlayer in allPlayers)
        {
            if (otherPlayer != player)
            {
                _targetGroup.AddMember(otherPlayer.transform, _otherPlayerWeight, _otherPlayerRadius);
            }
        }
    }
    
    private void Update()
    {
        // Dynamically adjust ball weight based on proximity to player
        if (_ball != null && _player != null)
        {
            float distance = Vector3.Distance(_ball.transform.position, _player.transform.position);
            float normalizedDistance = Mathf.Clamp01(distance / 20f); // 20 units max distance for scaling
            
            // Increase weight as ball gets farther from player
            float dynamicWeight = Mathf.Lerp(_ballWeight, _ballWeight * 2f, normalizedDistance);
            
            // Update the target group member (assumes ball is member index 1)
            _targetGroup.m_Targets[1].weight = dynamicWeight;
        }
    }
}
```

This dynamic camera system keeps the action framed appropriately even with multiple players, creating a compelling split-screen experience.
