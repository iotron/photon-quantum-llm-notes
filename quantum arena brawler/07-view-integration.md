# View Integration

This document explains how the Quantum Arena Brawler integrates the Unity view layer with the Quantum simulation.

## View-Simulation Separation

The Quantum framework is designed with a clear separation between:
- **Simulation**: The deterministic game state and logic in Quantum
- **View**: The visual representation in Unity

This separation is crucial for deterministic multiplayer, as it allows the simulation to run identically on all clients while the view can be tailored to each client's display needs.

## Core Integration Components

### Entity Views

Entity views are the primary bridge between Quantum entities and Unity GameObjects:

```csharp
public class PlayerViewController : QuantumEntityView
{
    [SerializeField] private Transform _ballFollowTransform;
    [SerializeField] private Animator _animator;
    
    // Animation parameters
    private static readonly int IsRunning = Animator.StringToHash("IsRunning");
    private static readonly int IsHoldingBall = Animator.StringToHash("IsHoldingBall");
    
    public Transform BallFollowTransform => _ballFollowTransform;
    
    // Called by the Quantum engine when the entity's transform updates
    protected override void ApplyTransform(ref UpdatePositionParameter param)
    {
        // Apply base transform update from Quantum
        base.ApplyTransform(ref param);
        
        // Get additional data from the simulation
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        
        if (frame.Unsafe.TryGetPointer<PlayerStatus>(EntityRef, out var playerStatus))
        {
            // Update animator based on simulation state
            UpdateAnimator(frame, playerStatus);
        }
    }
    
    private void UpdateAnimator(Frame frame, PlayerStatus* playerStatus)
    {
        CharacterController3D* kcc = frame.Unsafe.GetPointer<CharacterController3D>(EntityRef);
        
        // Update animation parameters based on simulation state
        _animator.SetBool(IsRunning, kcc->Velocity.XZ.SqrMagnitude > FP._0_10 && kcc->Grounded);
        _animator.SetBool(IsHoldingBall, playerStatus->IsHoldingBall());
    }
}
```

### Event Handling

Events are used for one-way communication from simulation to view:

```csharp
public class PlayerViewEventHandler : MonoBehaviour, IQuantumEventListener
{
    private Dictionary<EntityRef, PlayerViewController> _playerViews = new Dictionary<EntityRef, PlayerViewController>();
    
    public void OnInit(QuantumGame game)
    {
        // Register for Quantum events
        game.EventDispatcher.Subscribe(this);
    }
    
    // Called when a player view is created
    public void RegisterPlayerView(EntityRef entityRef, PlayerViewController playerView)
    {
        _playerViews[entityRef] = playerView;
    }
    
    // Event handlers for various player events
    public void OnEvent(OnPlayerJumped e)
    {
        if (_playerViews.TryGetValue(e.PlayerEntityRef, out var playerView))
        {
            playerView.OnPlayerJumped();
        }
    }
    
    public void OnEvent(OnPlayerThrewBall e)
    {
        if (_playerViews.TryGetValue(e.PlayerEntityRef, out var playerView))
        {
            playerView.OnPlayerThrewBall();
        }
    }
}
```

### Entity View Factory

The `EntityViewFactory` creates and destroys view objects for Quantum entities:

```csharp
public class ArenaEntityViewFactory : EntityViewFactory
{
    [SerializeField] private PlayerViewController _playerViewPrefab;
    [SerializeField] private BallEntityView _ballViewPrefab;
    
    public override EntityView CreateEntityView(EntityRef entityRef)
    {
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        
        // Player view
        if (frame.Has<PlayerStatus>(entityRef))
        {
            PlayerViewController playerView = Instantiate(_playerViewPrefab);
            playerView.Setup(entityRef);
            return playerView;
        }
        
        // Ball view
        if (frame.Has<BallStatus>(entityRef))
        {
            BallEntityView ballView = Instantiate(_ballViewPrefab);
            ballView.Setup(entityRef);
            return ballView;
        }
        
        return null;
    }
}
```

## Special View Features

### Ball Space Interpolation

The ball uses special interpolation for smooth transitions when held by players:

```csharp
public class BallEntityView : QuantumEntityView
{
    [SerializeField] private float _spaceTransitionSpeed = 4f;
    
    private EntityRef _holdingPlayerEntityRef;
    private float _interpolationSpaceAlpha;
    private Vector3 _lastRealPosition;
    private Vector3 _lastAnimationPosition;
    
    public void UpdateSpaceInterpolation()
    {
        bool isBallHeldByPlayer = _holdingPlayerEntityRef != default;
        
        // Update interpolation alpha
        float deltaChange = _spaceTransitionSpeed * Time.deltaTime;
        _interpolationSpaceAlpha = Mathf.Clamp01(
            isBallHeldByPlayer ? 
            _interpolationSpaceAlpha + deltaChange : 
            _interpolationSpaceAlpha - deltaChange);
        
        if (isBallHeldByPlayer)
        {
            // Get animation position from player
            PlayerViewController player = PlayersManager.Instance.GetPlayer(_holdingPlayerEntityRef);
            _lastAnimationPosition = player.BallFollowTransform.position;
        }
        else
        {
            // Track real position from simulation
            _lastRealPosition = transform.position;
        }
        
        // Interpolate position
        if (_interpolationSpaceAlpha > 0f)
        {
            transform.position = Vector3.Lerp(_lastRealPosition, _lastAnimationPosition, _interpolationSpaceAlpha);
        }
    }
}
```

### Input Integration

The game bridges Unity's Input System to Quantum's input structure:

```csharp
public class LocalInputProvider : MonoBehaviour
{
    [SerializeField] private PlayerInput _playerInput;
    private InputActionMap _gameplayActions;
    
    private Vector2 _moveDirection;
    private Vector2 _aimDirection;
    private bool _jumpPressed;
    private bool _firePressed;
    
    // Called by Quantum to get the current input state
    public void OnInput(QuantumGame game, QuantumDemoInputTopDown* data)
    {
        // Convert from Unity input to Quantum input
        data->MoveDirection = new FPVector2(_moveDirection.x, _moveDirection.y);
        data->AimDirection = new FPVector2(_aimDirection.x, _aimDirection.y);
        
        // Set button states
        SetButton(game, ref data->Jump, _jumpPressed);
        SetButton(game, ref data->Fire, _firePressed);
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

### Game State Events

The game state changes are synchronized through events:

```csharp
public class GameStateViewController : MonoBehaviour, IQuantumEventListener
{
    [SerializeField] private GameObject _startingUI;
    [SerializeField] private GameObject _runningUI;
    [SerializeField] private GameObject _goalScoredUI;
    
    public void OnEvent(OnGameStarting e)
    {
        _startingUI.SetActive(true);
        _runningUI.SetActive(false);
        _goalScoredUI.SetActive(false);
    }
    
    public void OnEvent(OnGameRunning e)
    {
        _startingUI.SetActive(false);
        _runningUI.SetActive(true);
        _goalScoredUI.SetActive(false);
    }
    
    public void OnEvent(OnGoalScored e)
    {
        _startingUI.SetActive(false);
        _runningUI.SetActive(false);
        _goalScoredUI.SetActive(true);
    }
}
```

## Visual Effects System

The game uses a separate system to manage visual effects triggered by simulation events:

```csharp
public class VisualEffectsManager : MonoBehaviour, IQuantumEventListener
{
    [SerializeField] private ParticleSystem _dashEffectPrefab;
    [SerializeField] private ParticleSystem _throwEffectPrefab;
    
    public void OnEvent(OnPlayerDashed e)
    {
        // Create visual effect at player position
        Frame frame = QuantumRunner.Default.Game.Frames.Predicted;
        if (frame.TryGet<Transform3D>(e.PlayerEntityRef, out var transform))
        {
            Vector3 position = transform.Position.ToUnityVector3();
            ParticleSystem effect = Instantiate(_dashEffectPrefab, position, Quaternion.identity);
            
            // Destroy after duration
            Destroy(effect.gameObject, effect.main.duration);
        }
    }
    
    public void OnEvent(OnPlayerThrewBall e)
    {
        // Similar effect creation for throw events
    }
}
```

## Conclusion

The view integration layer in the Quantum Arena Brawler carefully separates deterministic simulation from visual presentation. Key aspects include:

1. **Entity Views**: Direct mapping between Quantum entities and Unity GameObjects
2. **Event System**: One-way communication from simulation to view
3. **Input Provider**: Translating Unity input into Quantum format
4. **Visual Effects**: Non-gameplay visuals triggered by simulation events
5. **Ball Interpolation**: Smooth transitions between physics and animation states

This separation ensures that the simulation remains deterministic across all clients while still allowing for rich visual presentation unique to each player's view.
