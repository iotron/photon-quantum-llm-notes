# Quantum Karts Unity Integration

This document explains how the Quantum simulation integrates with Unity visuals in the Quantum Karts project, covering how the deterministic game state is translated into visual representations, effects, and UI.

## Core Integration Architecture

Quantum Karts follows a strict simulation-view separation pattern:

```
Simulation (Quantum) → Events → View (Unity)
             ↑           ↓
             └─ Input ───┘
```

This architecture ensures that:
1. The simulation runs deterministically across all clients
2. Visual representation can be customized without affecting gameplay
3. Network synchronization only needs to transmit input, not visual state

## Key Integration Components

### 1. CustomViewContext

The `CustomViewContext` class extends Quantum's standard `QuantumGame` class to add game-specific functionality:

```csharp
public class CustomViewContext : QuantumUnityAdapter
{
    public QuantumCallbackHandler<EventWeaponCollected> _WeaponCollected;
    public QuantumCallbackHandler<EventWeaponUsed> _WeaponUsed;
    public QuantumCallbackHandler<EventOnBoostStart> _BoostStart;
    // Additional event handlers...
    
    public CustomViewContext(Game game) : base(game) { }
    
    public override void OnEnable()
    {
        base.OnEnable();
        
        // Register event handlers
        _WeaponCollected = new QuantumCallbackHandler<EventWeaponCollected>(
            callback: OnWeaponCollected, 
            notifyMultipleTimes: false,
            throwOnDuplicates: false
        );
        
        // Additional event registrations...
    }
    
    public override void OnDisable()
    {
        base.OnDisable();
        
        // Unregister event handlers
        _WeaponCollected = null;
        _WeaponUsed = null;
        // Additional event cleanup...
    }
    
    // Event handler methods
    private void OnWeaponCollected(EventWeaponCollected evt)
    {
        // Handle event
    }
    
    // Additional event handlers...
}
```

### 2. EntityViewComponent

All visual representations use the `QuantumEntityViewComponent` base class:

```csharp
public abstract class QuantumEntityViewComponent<TContext> : MonoBehaviour, IQuantumEntityView<TContext> 
    where TContext : CustomViewContext
{
    public EntityRef EntityRef { get; set; }
    public TContext Game { get; set; }
    
    public virtual void OnActivate(Frame frame) { }
    public virtual void OnDeactivate() { }
    public virtual void OnUpdate(Frame frame) { }
}
```

### 3. Visual Kart Spawner

The `VisualKartSpawner` creates the visual representation of karts:

```csharp
public unsafe class VisualKartSpawner : QuantumEntityViewComponent<CustomViewContext>
{
    public override void OnActivate(Frame frame)
    {
        if (frame.Unsafe.TryGetPointer(EntityRef, out Kart* kart))
        {
            KartVisuals visuals = frame.FindAsset(kart->VisualAsset);
            GameObject visualKart = Instantiate(visuals.KartPrefab, transform);

            visualKart.transform.localPosition = visuals.LocalOffset;

            var kartView = visualKart.GetComponent<KartViewController>();
            kartView.Initialize(Game);

            PlayerName nameDisplay = GetComponentInChildren<PlayerName>();

            if (LocalPlayerManager.Instance.LocalPlayerKartView == kartView)
            {
                nameDisplay.gameObject.SetActive(false);
            }
            else
            {
                nameDisplay.SetName(kartView.DriverName);
            }
        }
        else
        {
            Debug.Log("kart comp not found");
        }
    }
}
```

### 4. KartViewController

The `KartViewController` manages the visual aspects of a kart:

```csharp
public unsafe class KartViewController : MonoBehaviour
{
    [SerializeField] private Transform kartModel;
    [SerializeField] private Transform[] wheels;
    [SerializeField] private ParticleSystem[] driftParticles;
    [SerializeField] private TrailRenderer[] driftTrails;
    [SerializeField] private ParticleSystem exhaustSystem;
    [SerializeField] private AudioSource engineSound;
    [SerializeField] private AudioSource driftSound;
    [SerializeField] private AudioSource boostSound;
    
    private EntityRef _entityRef;
    private CustomViewContext _game;
    private bool _isDrifting;
    private int _driftBoostLevel;
    private bool _isBoosting;
    private string _driverName;
    
    public string DriverName => _driverName;
    
    public void Initialize(CustomViewContext game)
    {
        _game = game;
        _entityRef = transform.parent.GetComponent<QuantumEntityView>().EntityRef;
        
        // Subscribe to events
        QuantumCallback.Subscribe(this, (EventDriftStarted evt) => OnDriftStarted(evt));
        QuantumCallback.Subscribe(this, (EventDriftEnded evt) => OnDriftEnded(evt));
        QuantumCallback.Subscribe(this, (EventDriftBoostCharged evt) => OnDriftBoostCharged(evt));
        QuantumCallback.Subscribe(this, (EventOnBoostStart evt) => OnBoostStarted(evt));
        QuantumCallback.Subscribe(this, (EventKartHit evt) => OnKartHit(evt));
        
        // Set driver name based on player or AI
        if (_game.Frames.Verified.TryGetPointer(_entityRef, out PlayerLink* link))
        {
            _driverName = _game.PlayerNames.GetPlayerName(link->Player);
        }
        else if (_game.Frames.Verified.TryGetPointer(_entityRef, out AIDriver* ai))
        {
            var settings = _game.Frames.Verified.FindAsset(ai->SettingsRef);
            _driverName = $"AI {ai->AIIndex + 1}";
        }
        else
        {
            _driverName = "Unknown";
        }
    }
    
    private void Update()
    {
        if (_game == null || _game.Frames.Verified == null)
            return;
            
        // Update visual elements based on simulation state
        UpdateVelocityBasedEffects();
        UpdateWheelVisuals();
        UpdateEngineSound();
    }
    
    private void UpdateVelocityBasedEffects()
    {
        if (_game.Frames.Verified.TryGetPointer(_entityRef, out Kart* kart))
        {
            // Update effects based on speed
            FP speed = kart->GetNormalizedSpeed(_game.Frames.Verified);
            
            // Update engine pitch based on speed
            engineSound.pitch = 0.8f + speed.AsFloat * 0.7f;
            
            // Update exhaust particles based on speed and boost
            var emission = exhaustSystem.emission;
            emission.rateOverTime = (speed.AsFloat * 50) + (_isBoosting ? 100 : 0);
        }
    }
    
    private void UpdateWheelVisuals()
    {
        if (_game.Frames.Verified.TryGetPointer(_entityRef, out Wheels* wheelComp))
        {
            // Update wheel positions and rotations based on suspension
            for (int i = 0; i < wheels.Length && i < wheelComp->WheelStatuses.Length; i++)
            {
                var status = wheelComp->WheelStatuses.GetPointer(i)->Value;
                wheels[i].localPosition = new Vector3(
                    wheels[i].localPosition.x,
                    status.Grounded ? -status.SuspensionCompression.AsFloat * 0.1f : 0,
                    wheels[i].localPosition.z
                );
                
                // Rotate wheel based on speed
                wheels[i].Rotate(Vector3.right, 
                    _game.Frames.Verified.TryGetPointer(_entityRef, out Kart* kart) ? 
                    kart->Velocity.Magnitude.AsFloat * 10 * Time.deltaTime : 0);
            }
        }
    }
    
    private void UpdateEngineSound()
    {
        if (_game.Frames.Verified.TryGetPointer(_entityRef, out Kart* kart))
        {
            // Update engine volume based on speed and proximity to camera
            float distance = Vector3.Distance(Camera.main.transform.position, transform.position);
            float volume = Mathf.Lerp(0.1f, 1.0f, Mathf.Clamp01(10 / distance));
            engineSound.volume = volume * (0.5f + kart->GetNormalizedSpeed(_game.Frames.Verified).AsFloat * 0.5f);
        }
    }
    
    // Event handlers
    private void OnDriftStarted(EventDriftStarted evt)
    {
        if (evt.Entity != _entityRef) return;
        
        _isDrifting = true;
        _driftBoostLevel = 0;
        
        // Activate drift particles and sound
        foreach (var particle in driftParticles)
        {
            particle.Play();
        }
        
        foreach (var trail in driftTrails)
        {
            trail.emitting = true;
        }
        
        driftSound.Play();
    }
    
    private void OnDriftEnded(EventDriftEnded evt)
    {
        if (evt.Entity != _entityRef) return;
        
        _isDrifting = false;
        
        // Deactivate drift effects
        foreach (var particle in driftParticles)
        {
            particle.Stop();
        }
        
        foreach (var trail in driftTrails)
        {
            trail.emitting = false;
        }
        
        driftSound.Stop();
    }
    
    private void OnDriftBoostCharged(EventDriftBoostCharged evt)
    {
        if (evt.Entity != _entityRef) return;
        
        _driftBoostLevel = evt.BoostLevel;
        
        // Update drift particle color based on boost level
        Color boostColor = Color.white;
        switch (_driftBoostLevel)
        {
            case 1: boostColor = Color.blue; break;
            case 2: boostColor = Color.yellow; break;
            case 3: boostColor = Color.red; break;
        }
        
        foreach (var particle in driftParticles)
        {
            var main = particle.main;
            main.startColor = boostColor;
        }
        
        foreach (var trail in driftTrails)
        {
            trail.startColor = boostColor;
        }
    }
    
    private void OnBoostStarted(EventOnBoostStart evt)
    {
        if (evt.Entity != _entityRef) return;
        
        _isBoosting = true;
        
        // Get boost config
        var boostConfig = _game.Frames.Verified.FindAsset<BoostConfig>(evt.KartBoost.CurrentBoost);
        
        // Play boost sound
        boostSound.Play();
        
        // Update exhaust color
        var main = exhaustSystem.main;
        main.startColor = boostConfig.ExhaustColor;
        
        // Schedule boost end
        StartCoroutine(EndBoostAfter(boostConfig.Duration.AsFloat));
    }
    
    private IEnumerator EndBoostAfter(float duration)
    {
        yield return new WaitForSeconds(duration);
        _isBoosting = false;
        
        // Reset exhaust color
        var main = exhaustSystem.main;
        main.startColor = Color.white;
    }
    
    private void OnKartHit(EventKartHit evt)
    {
        if (evt.Entity != _entityRef) return;
        
        // Play hit effects
        // Shake camera if local player
        if (LocalPlayerManager.Instance.LocalPlayerKartView == this)
        {
            CameraShake.Instance.ShakeCamera(evt.Damage.AsFloat * 0.5f);
        }
    }
}
```

### 5. LocalInput

The `LocalInput` class captures Unity input and sends it to Quantum:

```csharp
public class LocalInput : MonoBehaviour
{
    private void Start()
    {
        QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
    }

    public void PollInput(CallbackPollInput callback)
    {
        Quantum.Input input = new Quantum.Input();

        // Note: Use GetButton not GetButtonDown/Up Quantum calculates up/down itself.
        input.Drift = UnityEngine.Input.GetButton("Jump");
        input.Powerup = UnityEngine.Input.GetButton("Fire1");
        input.Respawn = UnityEngine.Input.GetKey(KeyCode.R);

        var x = UnityEngine.Input.GetAxis("Horizontal");
        var y = UnityEngine.Input.GetAxis("Vertical");

        // Input that is passed into the simulation needs to be deterministic that's why it's converted to FPVector2.
        input.Direction = new Vector2(x, y).ToFPVector2();

        callback.SetInput(input, DeterministicInputFlags.Repeatable);
    }
}
```

## Event-Based Communication

### 1. Event Registration

Events are defined in Quantum and subscribed to in Unity:

```csharp
// In a MonoBehaviour
private void OnEnable()
{
    // Subscribe to events
    _driftStartedCallback = QuantumCallback.Subscribe<EventDriftStarted>(this, OnDriftStarted);
    _boostStartCallback = QuantumCallback.Subscribe<EventOnBoostStart>(this, OnBoostStarted);
    _raceStateChangedCallback = QuantumCallback.Subscribe<EventOnRaceStateChanged>(this, OnRaceStateChanged);
}

private void OnDisable()
{
    // Unsubscribe from events
    if (_driftStartedCallback != null)
    {
        _driftStartedCallback.Dispose();
        _driftStartedCallback = null;
    }
    
    // Additional cleanup...
}
```

### 2. Event Implementation

Events are triggered in Quantum and handled in Unity:

```csharp
// In Quantum (simulation)
public void StartBoost(Frame f, AssetRef<BoostConfig> config, EntityRef kartEntity)
{
    BoostConfig boost = f.FindAsset(config);
    CurrentBoost = config;
    TimeRemaining = boost.Duration;

    f.Events.OnBoostStart(kartEntity, this);
}

// In Unity (view)
private void OnBoostStarted(EventOnBoostStart evt)
{
    if (evt.Entity != _entityRef) return;
    
    // Play visual and audio effects
    _isBoosting = true;
    var boostConfig = _game.Frames.Verified.FindAsset<BoostConfig>(evt.KartBoost.CurrentBoost);
    boostSound.Play();
    
    var main = exhaustSystem.main;
    main.startColor = boostConfig.ExhaustColor;
}
```

## Asset References

Assets are shared between Quantum and Unity through AssetDBs:

### 1. Quantum Asset Definition

```csharp
public unsafe partial class KartVisuals : AssetObject
{
    public GameObject KartPrefab;
    public Vector3 LocalOffset;
    public AudioClip EngineSound;
    public AudioClip DriftSound;
    public AudioClip BoostSound;
}
```

### 2. Unity Asset Reference

```csharp
public unsafe class VisualKartSpawner : QuantumEntityViewComponent<CustomViewContext>
{
    public override void OnActivate(Frame frame)
    {
        if (frame.Unsafe.TryGetPointer(EntityRef, out Kart* kart))
        {
            KartVisuals visuals = frame.FindAsset(kart->VisualAsset);
            GameObject visualKart = Instantiate(visuals.KartPrefab, transform);
            
            // Use asset references to configure the view
            visualKart.transform.localPosition = visuals.LocalOffset;
        }
    }
}
```

## UI Integration

### 1. Race HUD

The race UI is updated based on Quantum state:

```csharp
public unsafe class RaceHUD : MonoBehaviour
{
    [SerializeField] private Text lapCounter;
    [SerializeField] private Text positionText;
    [SerializeField] private Text timerText;
    [SerializeField] private Text countdownText;
    [SerializeField] private GameObject raceStartPanel;
    [SerializeField] private GameObject raceFinishPanel;
    
    private QuantumCallback<EventOnRaceStateChanged> _raceStateCallback;
    private QuantumCallback<EventOnCountdownUpdated> _countdownCallback;
    private QuantumCallback<EventOnPositionsUpdated> _positionsCallback;
    
    private void OnEnable()
    {
        _raceStateCallback = QuantumCallback.Subscribe<EventOnRaceStateChanged>(this, OnRaceStateChanged);
        _countdownCallback = QuantumCallback.Subscribe<EventOnCountdownUpdated>(this, OnCountdownUpdated);
        _positionsCallback = QuantumCallback.Subscribe<EventOnPositionsUpdated>(this, OnPositionsUpdated);
    }
    
    private void OnDisable()
    {
        if (_raceStateCallback != null)
        {
            _raceStateCallback.Dispose();
            _raceStateCallback = null;
        }
        
        // Additional cleanup...
    }
    
    private void Update()
    {
        UpdateRaceTime();
    }
    
    private void UpdateRaceTime()
    {
        var game = QuantumRunner.Default.Game;
        if (game?.Frames.Verified == null) return;
        
        if (game.Frames.Verified.TryGetPointerSingleton(out Race* race))
        {
            if (race->CurrentRaceState == RaceState.InProgress)
            {
                float raceTime = game.Frames.Verified.Time.AsFloat;
                int minutes = Mathf.FloorToInt(raceTime / 60);
                int seconds = Mathf.FloorToInt(raceTime % 60);
                int milliseconds = Mathf.FloorToInt((raceTime * 100) % 100);
                
                timerText.text = $"{minutes:00}:{seconds:00}:{milliseconds:00}";
            }
        }
    }
    
    private void OnRaceStateChanged(EventOnRaceStateChanged evt)
    {
        switch (evt.NewState)
        {
            case RaceState.Waiting:
                raceStartPanel.SetActive(true);
                raceFinishPanel.SetActive(false);
                countdownText.gameObject.SetActive(false);
                break;
                
            case RaceState.Countdown:
                raceStartPanel.SetActive(false);
                countdownText.gameObject.SetActive(true);
                break;
                
            case RaceState.InProgress:
                countdownText.gameObject.SetActive(false);
                break;
                
            case RaceState.Finished:
                raceFinishPanel.SetActive(true);
                ShowRaceResults();
                break;
        }
    }
    
    private void OnCountdownUpdated(EventOnCountdownUpdated evt)
    {
        countdownText.text = Mathf.CeilToInt(evt.RemainingTime.AsFloat).ToString();
    }
    
    private void OnPositionsUpdated(EventOnPositionsUpdated evt)
    {
        UpdatePlayerUI();
    }
    
    private void UpdatePlayerUI()
    {
        var game = QuantumRunner.Default.Game;
        if (game?.Frames.Verified == null) return;
        
        EntityRef localKartEntity = LocalPlayerManager.Instance.LocalPlayerKartEntity;
        
        if (game.Frames.Verified.TryGetPointer(localKartEntity, out RaceProgress* progress))
        {
            // Update lap counter
            lapCounter.text = $"LAP {progress->CurrentLap}/{progress->TotalLaps}";
            
            // Update position
            positionText.text = FormatPosition(progress->CurrentPosition);
        }
    }
    
    private string FormatPosition(sbyte position)
    {
        string suffix;
        switch (position)
        {
            case 1: suffix = "ST"; break;
            case 2: suffix = "ND"; break;
            case 3: suffix = "RD"; break;
            default: suffix = "TH"; break;
        }
        
        return $"{position}{suffix}";
    }
    
    private void ShowRaceResults()
    {
        // Implement race results UI population
    }
}
```

### 2. Minimap

A minimap shows kart positions on the track:

```csharp
public unsafe class MinimapController : MonoBehaviour
{
    [SerializeField] private RectTransform minimapContainer;
    [SerializeField] private GameObject kartIconPrefab;
    [SerializeField] private Color playerIconColor = Color.green;
    [SerializeField] private Color aiIconColor = Color.red;
    
    private Dictionary<EntityRef, RectTransform> _kartIcons = new Dictionary<EntityRef, RectTransform>();
    private Vector2 _mapScale = new Vector2(10, 10); // Scale factor for converting world to minimap coords
    
    private void Update()
    {
        UpdateKartIcons();
    }
    
    private void UpdateKartIcons()
    {
        var game = QuantumRunner.Default.Game;
        if (game?.Frames.Verified == null) return;
        
        // Create icons for any new karts
        foreach (var (entity, kart) in game.Frames.Verified.Unsafe.GetComponentBlockIterator<Kart>())
        {
            if (!_kartIcons.ContainsKey(entity))
            {
                CreateKartIcon(entity);
            }
        }
        
        // Update positions for all karts
        foreach (var kvp in _kartIcons)
        {
            if (game.Frames.Verified.TryGetPointer(kvp.Key, out Transform3D* transform))
            {
                // Convert world position to minimap coordinates
                Vector2 minimapPos = new Vector2(
                    transform->Position.X.AsFloat * _mapScale.x,
                    transform->Position.Z.AsFloat * _mapScale.y
                );
                
                kvp.Value.anchoredPosition = minimapPos;
                
                // Rotate icon to match kart direction
                float angle = Mathf.Atan2(transform->Forward.X.AsFloat, transform->Forward.Z.AsFloat) * Mathf.Rad2Deg;
                kvp.Value.rotation = Quaternion.Euler(0, 0, -angle);
            }
        }
    }
    
    private void CreateKartIcon(EntityRef entity)
    {
        var game = QuantumRunner.Default.Game;
        
        // Create icon
        GameObject iconObj = Instantiate(kartIconPrefab, minimapContainer);
        RectTransform iconTransform = iconObj.GetComponent<RectTransform>();
        _kartIcons[entity] = iconTransform;
        
        // Set color based on player vs AI
        Image iconImage = iconObj.GetComponent<Image>();
        
        bool isPlayer = game.Frames.Verified.TryGetPointer(entity, out PlayerLink* playerLink);
        bool isLocalPlayer = isPlayer && entity == LocalPlayerManager.Instance.LocalPlayerKartEntity;
        
        if (isLocalPlayer)
        {
            iconImage.color = playerIconColor;
            iconTransform.SetAsLastSibling(); // Draw on top
            iconTransform.localScale = Vector3.one * 1.5f; // Make larger
        }
        else if (isPlayer)
        {
            iconImage.color = new Color(0, 0.7f, 1);
        }
        else
        {
            iconImage.color = aiIconColor;
        }
    }
}
```

## Camera System

A camera system follows the player's kart:

```csharp
public class KartCameraController : MonoBehaviour
{
    [SerializeField] private Vector3 offset = new Vector3(0, 3, -6);
    [SerializeField] private float smoothTime = 0.2f;
    [SerializeField] private float lookAheadFactor = 0.5f;
    [SerializeField] private float tiltFactor = 0.1f;
    
    private Transform _target;
    private Vector3 _currentVelocity;
    private Rigidbody _targetRigidbody;
    
    private void Start()
    {
        // Subscribe to local player setup
        LocalPlayerManager.OnLocalPlayerKartSet += HandleLocalPlayerSet;
    }
    
    private void HandleLocalPlayerSet(KartViewController kartView)
    {
        _target = kartView.transform;
        _targetRigidbody = _target.GetComponentInParent<Rigidbody>();
    }
    
    private void LateUpdate()
    {
        if (_target == null) return;
        
        // Calculate target position with look-ahead
        Vector3 lookAheadPos = Vector3.zero;
        if (_targetRigidbody != null)
        {
            lookAheadPos = _targetRigidbody.velocity * lookAheadFactor;
            lookAheadPos.y = 0; // Only look ahead on XZ plane
        }
        
        Vector3 targetPos = _target.position + _target.TransformDirection(offset) + lookAheadPos;
        
        // Smooth position
        transform.position = Vector3.SmoothDamp(transform.position, targetPos, ref _currentVelocity, smoothTime);
        
        // Calculate rotation with tilt
        float tilt = 0;
        if (_targetRigidbody != null)
        {
            // Add tilt based on lateral velocity
            Vector3 localVel = _target.InverseTransformDirection(_targetRigidbody.velocity);
            tilt = -localVel.x * tiltFactor;
        }
        
        // Look at target with tilt
        Quaternion targetRotation = Quaternion.LookRotation(_target.position - transform.position, Vector3.up);
        targetRotation *= Quaternion.Euler(0, 0, tilt);
        transform.rotation = targetRotation;
    }
}
```

## Particle and Audio Effects

Special effects are synchronized with simulation events:

```csharp
public unsafe class KartEffectsController : MonoBehaviour
{
    [SerializeField] private ParticleSystem[] wheelSmoke;
    [SerializeField] private ParticleSystem[] driftSparks;
    [SerializeField] private ParticleSystem boostTrail;
    [SerializeField] private AudioSource skidSound;
    
    private EntityRef _entityRef;
    private CustomViewContext _game;
    
    public void Initialize(CustomViewContext game, EntityRef entityRef)
    {
        _game = game;
        _entityRef = entityRef;
    }
    
    private void Update()
    {
        if (_game == null || _game.Frames.Verified == null)
            return;
            
        UpdateWheelEffects();
    }
    
    private void UpdateWheelEffects()
    {
        if (_game.Frames.Verified.TryGetPointer(_entityRef, out Kart* kart))
        {
            // Update wheel smoke based on sideways speed
            bool shouldEmitSmoke = kart->SidewaysSpeedSqr > FP._5;
            
            foreach (var smoke in wheelSmoke)
            {
                var emission = smoke.emission;
                emission.enabled = shouldEmitSmoke;
            }
            
            // Update skid sound
            if (shouldEmitSmoke && !skidSound.isPlaying)
            {
                skidSound.Play();
            }
            else if (!shouldEmitSmoke && skidSound.isPlaying)
            {
                skidSound.Stop();
            }
        }
    }
    
    public void OnDriftStarted()
    {
        foreach (var spark in driftSparks)
        {
            spark.Play();
        }
    }
    
    public void OnDriftEnded()
    {
        foreach (var spark in driftSparks)
        {
            spark.Stop();
        }
    }
    
    public void OnBoostStarted(Color boostColor, float duration)
    {
        var main = boostTrail.main;
        main.startColor = boostColor;
        main.duration = duration;
        boostTrail.Play();
    }
}
```

## Map Loading

Maps are loaded from Quantum assets:

```csharp
public unsafe class MapLoader : MonoBehaviour
{
    [SerializeField] private Transform mapContainer;
    
    public void LoadMap(AssetRef<RaceTrackAsset> trackAssetRef)
    {
        var game = QuantumRunner.Default.Game;
        if (game == null) return;
        
        // Clear existing map
        foreach (Transform child in mapContainer)
        {
            Destroy(child.gameObject);
        }
        
        // Load new map
        var trackAsset = game.FindAsset<RaceTrackAsset>(trackAssetRef);
        if (trackAsset == null) return;
        
        // Instantiate map prefab
        Instantiate(trackAsset.MapPrefab, mapContainer);
        
        // Notify map loaded
        game.Events.OnMapLoaded(trackAsset.MapName);
    }
}
```

## Local Player Management

A singleton manages references to the local player:

```csharp
public class LocalPlayerManager : MonoBehaviour
{
    public static LocalPlayerManager Instance { get; private set; }
    
    public EntityRef LocalPlayerKartEntity { get; private set; }
    public KartViewController LocalPlayerKartView { get; private set; }
    
    public static event Action<KartViewController> OnLocalPlayerKartSet;
    
    private void Awake()
    {
        if (Instance == null)
        {
            Instance = this;
        }
        else
        {
            Destroy(gameObject);
        }
    }
    
    public void SetLocalPlayerKart(EntityRef entity, KartViewController view)
    {
        LocalPlayerKartEntity = entity;
        LocalPlayerKartView = view;
        
        OnLocalPlayerKartSet?.Invoke(view);
    }
}
```

## Network Integration

Network synchronization is handled by Quantum:

```csharp
public class NetworkManager : MonoBehaviour
{
    public static NetworkManager Instance { get; private set; }
    
    [SerializeField] private byte maxPlayers = 8;
    [SerializeField] private string gameVersion = "1.0";
    
    private void Awake()
    {
        if (Instance == null)
        {
            Instance = this;
            DontDestroyOnLoad(gameObject);
        }
        else
        {
            Destroy(gameObject);
        }
    }
    
    public void StartHost()
    {
        var config = GetQuantumConfig();
        var param = new QuantumRunner.StartParameters();
        param.GameMode = Photon.Deterministic.DeterministicGameMode.Host;
        param.LocalPlayer = CreatePlayerData();
        param.RuntimeConfig = GetRuntimeConfig();
        
        QuantumRunner.StartGame(config, param);
    }
    
    public void JoinRoom(string roomName)
    {
        var config = GetQuantumConfig();
        var param = new QuantumRunner.StartParameters();
        param.GameMode = Photon.Deterministic.DeterministicGameMode.Client;
        param.LocalPlayer = CreatePlayerData();
        param.RuntimeConfig = GetRuntimeConfig();
        param.RoomName = roomName;
        
        QuantumRunner.StartGame(config, param);
    }
    
    private RuntimeConfigContainer GetRuntimeConfig()
    {
        var container = new RuntimeConfigContainer();
        
        // Set race-specific config
        container.RaceSettings = SelectedTrack.RaceSettingsAsset;
        container.AICount = SelectedGameMode.AICount;
        container.DriverCount = SelectedGameMode.TotalDrivers;
        container.CountdownTime = 3;
        container.FinishingTime = 30;
        container.FillWithAI = true;
        
        return container;
    }
    
    private RuntimePlayer CreatePlayerData()
    {
        RuntimePlayer player = new RuntimePlayer();
        
        // Set player-specific data
        player.KartStats = SelectedKart.StatsAsset;
        player.KartVisuals = SelectedKart.VisualsAsset;
        player.PlayerName = PlayerPrefs.GetString("PlayerName", "Player");
        
        return player;
    }
}
```

## Optimization Techniques

Several techniques optimize the Unity integration:

### 1. Entity Pooling

```csharp
public class EntityViewPool : MonoBehaviour
{
    [SerializeField] private GameObject prefab;
    [SerializeField] private int poolSize = 10;
    
    private Queue<GameObject> _pool = new Queue<GameObject>();
    
    private void Awake()
    {
        // Pre-instantiate objects
        for (int i = 0; i < poolSize; i++)
        {
            var obj = Instantiate(prefab, transform);
            obj.SetActive(false);
            _pool.Enqueue(obj);
        }
    }
    
    public GameObject Get()
    {
        if (_pool.Count > 0)
        {
            var obj = _pool.Dequeue();
            obj.SetActive(true);
            return obj;
        }
        else
        {
            // Create new object if pool is empty
            return Instantiate(prefab);
        }
    }
    
    public void Return(GameObject obj)
    {
        obj.SetActive(false);
        obj.transform.SetParent(transform);
        _pool.Enqueue(obj);
    }
}
```

### 2. Culling and LOD

```csharp
public class KartViewLOD : MonoBehaviour
{
    [SerializeField] private GameObject highDetailModel;
    [SerializeField] private GameObject lowDetailModel;
    [SerializeField] private ParticleSystem[] highDetailEffects;
    [SerializeField] private float lodDistance = 50f;
    
    private Transform _cameraTransform;
    
    private void Start()
    {
        _cameraTransform = Camera.main.transform;
    }
    
    private void Update()
    {
        float distance = Vector3.Distance(transform.position, _cameraTransform.position);
        
        bool useHighDetail = distance < lodDistance;
        
        highDetailModel.SetActive(useHighDetail);
        lowDetailModel.SetActive(!useHighDetail);
        
        foreach (var effect in highDetailEffects)
        {
            var emission = effect.emission;
            emission.enabled = useHighDetail;
        }
    }
}
```

### 3. Event Batching

```csharp
public class EventBatcher
{
    public const int BatchInterval = 5; // Process events every 5 frames
    private int _frameCounter = 0;
    
    private Queue<Action> _pendingEvents = new Queue<Action>();
    
    public void AddEvent(Action action)
    {
        _pendingEvents.Enqueue(action);
    }
    
    public void Update()
    {
        _frameCounter++;
        
        if (_frameCounter >= BatchInterval)
        {
            _frameCounter = 0;
            
            int eventCount = _pendingEvents.Count;
            for (int i = 0; i < eventCount; i++)
            {
                _pendingEvents.Dequeue()?.Invoke();
            }
        }
    }
}
```

## Best Practices

1. **Strict Separation**: Keep simulation and view code completely separate
2. **Event-Based Communication**: Use events for simulation-to-view communication
3. **Reusable Components**: Create modular, reusable view components
4. **Asset References**: Use asset references to share data between simulation and view
5. **Optimization**: Implement pooling, LOD, and culling for performance
6. **Clean Subscriptions**: Always unsubscribe from events when components are disabled
7. **Local Player Identification**: Have a central manager for the local player references
8. **Customization**: Keep visuals configurable through assets and prefabs
