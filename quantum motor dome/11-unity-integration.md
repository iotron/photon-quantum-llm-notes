# Quantum Motor Dome Unity Integration

This document explains how the Quantum simulation is integrated with Unity in the Quantum Motor Dome project, covering entity visualization, event handling, input processing, UI, camera systems, and audio.

## Integration Architecture

Quantum Motor Dome follows Quantum's standard integration pattern:

```
Simulation (Quantum) → Events → View (Unity)
             ↑           ↓
             └─ Input ───┘
```

Key integration points:
1. **Entity Views**: Unity GameObjects that represent Quantum entities
2. **Event Handlers**: Unity components that respond to Quantum events
3. **Input Providers**: Unity components that capture input and send it to Quantum
4. **UI Controllers**: Unity components that display game state information
5. **Camera Controller**: Unity component that follows the player's ship

## Entity View System

### QuantumEntityView Component

The base entity view system uses Quantum's `EntityView` component to link Unity GameObjects to Quantum entities:

```csharp
// This is a simplified representation of Quantum's EntityView
public class QuantumEntityView : MonoBehaviour
{
    public EntityRef EntityRef { get; set; }
    private List<IEntityViewComponent> viewComponents = new List<IEntityViewComponent>();

    public void OnEntityInstantiated(EntityRef entityRef)
    {
        EntityRef = entityRef;
        
        // Initialize view components
        foreach (var component in GetComponentsInChildren<IEntityViewComponent>(true))
        {
            viewComponents.Add(component);
            component.Initialize(entityRef);
        }
    }
    
    public void OnEntityDestroyed()
    {
        foreach (var component in viewComponents)
        {
            component.OnEntityDestroyed();
        }
    }
    
    public static QuantumEntityView FindEntityView(EntityRef entityRef)
    {
        // Implementation...
    }
}
```

### ShipView Component

The `ShipView` component handles the visual representation of ships:

```csharp
public unsafe class ShipView : MonoBehaviour
{
    public static ShipView Local { get; private set; }

    public AudioSource boostSrc;
    public GameObject explosionPrefab;

    public Transform pivot;
    public Transform socket;
    public Transform reconnectTarget;
    [SerializeField] LineRenderer ren;
    public Renderer[] renderers;
    public LineRenderer trailRenderer;

    public float oversteerAmount = 10;
    public float rollAmount = 45;
    public float steerVisualRate = 20;
    public float connectionSmoothSpeed = 5f;

    int trailSegs = 0;

    public EntityRef EntityRef { get; private set; }
    public PlayerRef PlayerRef { get; private set; }
    QuantumGame game;

    int? reconnectTick = null;
    bool wasBoosting = false;

    MaterialPropertyBlock prop;

    public void Initialize()
    {
        EntityRef = GetComponentInParent<QuantumEntityView>().EntityRef;
        if (EntityRef.IsValid)
        {
            PlayerRef = QuantumRunner.Default.Game.Frames.Predicted.Unsafe.GetPointer<PlayerLink>(EntityRef)->Player;
            game = QuantumRunner.Default.Game;

            QuantumEvent.Subscribe<EventPlayerDataChanged>(this, PlayerDataChangedCallback);
            QuantumEvent.Subscribe<EventPlayerVulnerable>(this, PlayerVulnerableCallback);

            if (game.PlayerIsLocal(PlayerRef))
            {
                Local = this;
                CameraController.Instance.follow = transform;
                
            }
            else
            {
                // create worldspace UI nickname
                Instantiate(InterfaceManager.Instance.worldCanvasNickname, InterfaceManager.Instance.worldCanvas.transform)
                    .SetNickname(PlayerNicknames.Get(PlayerRef))
                    .SetTarget(transform);
            }

            RuntimePlayer data = game.Frames.Verified.GetPlayerData(PlayerRef);

            prop = new();

            prop.SetFloat("_Invulnerable", 1);

            ColorRGBA c;
            c = data.primaryColor;    prop.SetColor(ResourceManager.Instance.shipMatPrimaryString, new Color32(c.R, c.G, c.B, 255));
            c = data.secondaryColor;  prop.SetColor(ResourceManager.Instance.shipMatSecondaryString, new Color32(c.R, c.G, c.B, 255));
            c = data.trailColor;      prop.SetColor(ResourceManager.Instance.shipMatTrailString, new Color32(c.R, c.G, c.B, 255));

            trailRenderer.colorGradient = new Color32(c.R, c.G, c.B, 255).ToGradient();

            foreach (Renderer ren in renderers) ren.SetPropertyBlock(prop);
        }
    }

    public void EntityDestroyed()
    {
        if (QuantumRunner.Default?.IsRunning == true)
        {
            if (Local == this)
            {
                CameraController.Instance.Effects.IsBoosting = false;
                InterfaceManager.Instance.socketIndicator.indicatorEnabled = false;
                QuantumEvent.UnsubscribeListener<EventPlayerDataChanged>(this);
                QuantumEvent.UnsubscribeListener<EventPlayerVulnerable>(this);
                Local = null;
            }
        }
        Destroy(gameObject);
    }

    private void Update()
    {
        if (reconnectTick.HasValue)
        {
            socket.rotation = Quaternion.RotateTowards(socket.rotation, pivot.rotation, 360 * Time.deltaTime);

            pivot.position = Vector3.MoveTowards(pivot.position, reconnectTarget.position, connectionSmoothSpeed * Time.deltaTime);
            pivot.rotation = Quaternion.RotateTowards(pivot.rotation, reconnectTarget.rotation, 360 * Time.deltaTime);

            return;
        }

        Ship* player = game.Frames.Predicted.Unsafe.GetPointer<Ship>(EntityRef);
        Quantum.Collections.QList<Photon.Deterministic.FPVector3> segs = game.Frames.Predicted.ResolveList(player->Segments);

        if (Local == this)
        {
            CameraController.Instance.Effects.IsBoosting = player->IsBoosting;
            InterfaceManager.Instance.boostBar.fillAmount = player->BoostAmount.AsFloat * 0.01f;
            InterfaceManager.Instance.boostPercentText.text = $"{Mathf.CeilToInt(player->BoostAmount.AsFloat)}%";
        }

        if (player->IsBoosting && !wasBoosting)     boostSrc.Play();
        else if (!player->IsBoosting && wasBoosting)    boostSrc.Stop();

        ren.positionCount = segs.Count;
        for (int i = 0; i < segs.Count; i++)
        {
            Photon.Deterministic.FPVector3* seg = segs.GetPointer(i);
            ren.SetPosition(i, seg->ToUnityVector3());
        }

        if (trailSegs <= 1 && segs.Count > 1)
        {
            // disconnect socket from ship
            socket.SetParent(transform);
        }

        trailSegs = segs.Count;

        if (trailSegs > 1)
        {
            Vector3 end = segs.GetPointer(0)->ToUnityVector3();
            Vector3 next = segs.GetPointer(1)->ToUnityVector3();
            socket.position = end;
            socket.rotation = Quaternion.LookRotation(next - end, -end);
        }
        
        Quaternion rollRot = Quaternion.AngleAxis(player->SteerAmount.AsFloat * -rollAmount, Vector3.forward);
        Quaternion oversteerRot = Quaternion.Euler(0, player->SteerAmount.AsFloat * oversteerAmount, 0);
        Quaternion tgtRot = oversteerRot * rollRot;
        Quaternion srcRot = pivot.localRotation;
        pivot.localRotation = Quaternion.RotateTowards(srcRot, tgtRot, Mathf.Sqrt(Quaternion.Angle(srcRot, tgtRot)) * steerVisualRate * Time.deltaTime);

        wasBoosting = player->IsBoosting;
    }

    void PlayerDataChangedCallback(EventPlayerDataChanged evt)
    {
        if (evt.Player == PlayerRef)
        {
            reconnectTick = evt.Tick;
            QuantumEvent.UnsubscribeListener<EventPlayerDataChanged>(this);
        }
    }

    void PlayerVulnerableCallback(EventPlayerVulnerable evt)
    {
        Debug.Log("Vulnerable", gameObject);
        prop.SetFloat("_Invulnerable", 0);
        foreach (Renderer ren in renderers) ren.SetPropertyBlock(prop);
    }
}
```

Key aspects of the ShipView component:
1. **Initialization**: Sets up colors, effects, and event subscriptions
2. **Update**: Synchronizes visual representation with simulation state
3. **Trail Rendering**: Visualizes the ship's trail using a LineRenderer
4. **Visual Effects**: Applies roll and oversteer based on steering input
5. **Boost Effects**: Manages audio and visual effects for boosting
6. **Reconnection Animation**: Handles the visual animation for trail reconnection
7. **Invulnerability Visualization**: Shows spawn protection state

## Event Handling

### Event Subscription System

The `EventSubscriptions` class centralizes event subscriptions:

```csharp
public class EventSubscriptions : MonoBehaviour
{
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventGameStateChanged>(this, OnGameStateChanged);
        QuantumEvent.Subscribe<EventShipSpawned>(this, OnShipSpawned);
        QuantumEvent.Subscribe<EventShipExploded>(this, OnShipExploded);
        QuantumEvent.Subscribe<EventPickupCollected>(this, OnPickupCollected);
        QuantumEvent.Subscribe<EventPlayerReconnected>(this, OnPlayerReconnected);
        QuantumEvent.Subscribe<EventPlayerKilled>(this, OnPlayerKilled);
        // Additional event subscriptions...
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventGameStateChanged>(this);
        QuantumEvent.UnsubscribeListener<EventShipSpawned>(this);
        QuantumEvent.UnsubscribeListener<EventShipExploded>(this);
        QuantumEvent.UnsubscribeListener<EventPickupCollected>(this);
        QuantumEvent.UnsubscribeListener<EventPlayerReconnected>(this);
        QuantumEvent.UnsubscribeListener<EventPlayerKilled>(this);
        // Additional event unsubscriptions...
    }
    
    private void OnGameStateChanged(EventGameStateChanged evt)
    {
        // Handle game state transitions
        // Implementation...
    }
    
    private void OnShipSpawned(EventShipSpawned evt)
    {
        // Handle ship spawning
        // Implementation...
    }
    
    // Additional event handlers...
}
```

### Game State Bridge

The `GameStateBridge` class handles game state transitions:

```csharp
public class GameStateBridge : MonoBehaviour
{
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventGameStateChanged>(this, OnGameStateChanged);
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventGameStateChanged>(this);
    }
    
    private void OnGameStateChanged(EventGameStateChanged evt)
    {
        switch (evt.NewState)
        {
            case GameState.Lobby:
                UIScreen.Focus(InterfaceManager.Instance.lobbyScreen);
                break;
            case GameState.Pregame:
                // Load map and prepare for game
                break;
            case GameState.Intro:
                InterfaceManager.Instance.ShowIntro();
                break;
            case GameState.Countdown:
                UIScreen.Focus(InterfaceManager.Instance.countdownScreen);
                break;
            case GameState.Game:
                UIScreen.Focus(InterfaceManager.Instance.hudScreen);
                break;
            case GameState.Outro:
                InterfaceManager.Instance.ShowOutro();
                break;
            case GameState.Postgame:
                UIScreen.Focus(InterfaceManager.Instance.resultsScreen);
                break;
        }
    }
}
```

## Input Processing

### LocalInput Component

The `LocalInput` component captures Unity input and sends it to Quantum:

```csharp
public class LocalInput : MonoBehaviour
{
    private void OnEnable()
    {
        QuantumCallback.Subscribe(this, (CallbackPollInput callback) => PollInput(callback));
    }

    private void Update()
    {
        if (UnityEngine.Input.GetKeyDown(KeyCode.P))
        {
            if (UIScreen.activeScreen == InterfaceManager.Instance.hudScreen)
                UIScreen.Focus(InterfaceManager.Instance.pauseScreen);
            else if (UIScreen.ScreenInHierarchy(InterfaceManager.Instance.hudScreen))
                UIScreen.activeScreen.BackTo(InterfaceManager.Instance.hudScreen);
        }
    }

    public void PollInput(CallbackPollInput callback)
    {
        Quantum.Input i = new()
        {
            steer = UnityEngine.Input.GetAxis("Horizontal").ToFP(),
            boost = UnityEngine.Input.GetButton("Boost"),
            brake = UnityEngine.Input.GetButton("Brake")
        };

        callback.SetInput(i, DeterministicInputFlags.Repeatable);
    }
}
```

Key aspects of input processing:
1. **Input Conversion**: Converts Unity input to deterministic Quantum input
2. **Input Mapping**: Maps Unity input axes to Quantum input properties
3. **UI Input Separation**: Handles UI-specific input separately from gameplay input
4. **Determinism Flag**: Uses the Repeatable flag to ensure deterministic behavior

## UI System

### InterfaceManager

The `InterfaceManager` class manages UI screens and elements:

```csharp
public class InterfaceManager : MonoBehaviour
{
    public static InterfaceManager Instance { get; private set; }
    
    [Header("UI Screens")]
    public UIScreen lobbyScreen;
    public UIScreen countdownScreen;
    public UIScreen hudScreen;
    public UIScreen pauseScreen;
    public UIScreen resultsScreen;
    
    [Header("HUD Elements")]
    public Image boostBar;
    public Text boostPercentText;
    public SocketIndicator socketIndicator;
    public GameObject worldCanvas;
    public WorldSpaceNickname worldCanvasNickname;
    
    [Header("Intro/Outro")]
    public IntroSequence introSequence;
    public OutroSequence outroSequence;
    
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
    
    public void ShowIntro()
    {
        introSequence.Play();
    }
    
    public void ShowOutro()
    {
        outroSequence.Play();
    }
    
    // Additional methods...
}
```

### UIScreen System

The `UIScreen` class handles screen transitions:

```csharp
public class UIScreen : MonoBehaviour
{
    public static UIScreen activeScreen { get; private set; }
    
    [SerializeField] private UIScreen parentScreen;
    [SerializeField] private bool hideOnStart = true;
    
    private void Start()
    {
        if (hideOnStart)
        {
            gameObject.SetActive(false);
        }
    }
    
    public static void Focus(UIScreen screen)
    {
        if (activeScreen != null)
        {
            activeScreen.gameObject.SetActive(false);
        }
        
        screen.gameObject.SetActive(true);
        activeScreen = screen;
    }
    
    public void BackTo(UIScreen targetScreen)
    {
        Focus(targetScreen);
    }
    
    public static bool ScreenInHierarchy(UIScreen screen)
    {
        UIScreen current = activeScreen;
        while (current != null)
        {
            if (current == screen)
            {
                return true;
            }
            current = current.parentScreen;
        }
        return false;
    }
}
```

### Scoreboard UI

The `ScoreboardUI` class displays player scores:

```csharp
public class ScoreboardUI : MonoBehaviour
{
    [SerializeField] private GameObject scoreEntryPrefab;
    [SerializeField] private Transform scoreboardContainer;
    
    private Dictionary<PlayerRef, ScoreEntry> scoreEntries = new Dictionary<PlayerRef, ScoreEntry>();
    
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventPlayerScoreChanged>(this, OnPlayerScoreChanged);
        QuantumEvent.Subscribe<EventPlayerKilled>(this, OnPlayerKilled);
        QuantumEvent.Subscribe<EventPlayerReconnected>(this, OnPlayerReconnected);
        QuantumEvent.Subscribe<EventGameResults>(this, OnGameResults);
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventPlayerScoreChanged>(this);
        QuantumEvent.UnsubscribeListener<EventPlayerKilled>(this);
        QuantumEvent.UnsubscribeListener<EventPlayerReconnected>(this);
        QuantumEvent.UnsubscribeListener<EventGameResults>(this);
    }
    
    private void OnPlayerScoreChanged(EventPlayerScoreChanged evt)
    {
        UpdateScore(evt.Player);
    }
    
    private void OnPlayerKilled(EventPlayerKilled evt)
    {
        UpdateScore(evt.Killer);
    }
    
    private void OnPlayerReconnected(EventPlayerReconnected evt)
    {
        // Find player ref from entity
        QuantumRunner.Default.Game.Frames.Verified.TryGetComponent<PlayerLink>(
            evt.Entity, out var playerLink);
        
        if (playerLink != null)
        {
            UpdateScore(playerLink.Player);
        }
    }
    
    private void OnGameResults(EventGameResults evt)
    {
        // Update final results
        // Implementation...
    }
    
    private void UpdateScore(PlayerRef player)
    {
        // Get player score from Quantum
        var game = QuantumRunner.Default.Game;
        game.Frames.Verified.Global.playerData.TryGetValue(
            player, out var playerData);
        
        // Update UI
        if (scoreEntries.TryGetValue(player, out var entry))
        {
            entry.UpdateScore(playerData.points);
        }
        else
        {
            // Create new score entry
            var newEntry = Instantiate(scoreEntryPrefab, scoreboardContainer).GetComponent<ScoreEntry>();
            newEntry.Initialize(player, playerData.points);
            scoreEntries[player] = newEntry;
        }
        
        // Sort scoreboard by score
        SortScoreboard();
    }
    
    private void SortScoreboard()
    {
        // Sort children by score
        var entries = scoreboardContainer.GetComponentsInChildren<ScoreEntry>()
            .OrderByDescending(e => e.Score)
            .ToList();
            
        // Update sibling indices to reorder
        for (int i = 0; i < entries.Count; i++)
        {
            entries[i].transform.SetSiblingIndex(i);
        }
    }
}
```

## Camera System

### CameraController

The `CameraController` class manages the camera's movement and effects:

```csharp
public class CameraController : MonoBehaviour
{
    public static CameraController Instance { get; private set; }
    
    public Transform follow;
    public CameraEffects Effects { get; private set; }
    
    [SerializeField] private Vector3 offset = new Vector3(0, 5, -8);
    [SerializeField] private float followSpeed = 5f;
    [SerializeField] private float rotationSpeed = 2f;
    [SerializeField] private float lookAheadFactor = 0.5f;
    
    private Vector3 velocity;
    
    private void Awake()
    {
        if (Instance == null)
        {
            Instance = this;
            Effects = GetComponent<CameraEffects>();
        }
        else
        {
            Destroy(gameObject);
        }
    }
    
    private void LateUpdate()
    {
        if (follow == null) return;
        
        // Get target position with offset
        Vector3 targetPosition = follow.position + follow.TransformDirection(offset);
        
        // Look ahead based on ship velocity
        if (ShipView.Local != null)
        {
            var ship = QuantumRunner.Default.Game.Frames.Predicted.Unsafe.GetPointer<Ship>(ShipView.Local.EntityRef);
            Vector3 velocity = ship->Velocity.ToUnityVector3();
            targetPosition += velocity * lookAheadFactor;
        }
        
        // Smooth follow
        transform.position = Vector3.SmoothDamp(transform.position, targetPosition, ref velocity, 1f / followSpeed);
        
        // Look at target
        Vector3 lookDirection = follow.position - transform.position;
        Quaternion targetRotation = Quaternion.LookRotation(lookDirection);
        transform.rotation = Quaternion.Slerp(transform.rotation, targetRotation, rotationSpeed * Time.deltaTime);
    }
}
```

### CameraEffects

The `CameraEffects` class handles camera visual effects:

```csharp
public class CameraEffects : MonoBehaviour
{
    [SerializeField] private PostProcessVolume postProcessVolume;
    
    private bool isBoosting;
    public bool IsBoosting
    {
        get => isBoosting;
        set
        {
            if (isBoosting != value)
            {
                isBoosting = value;
                UpdateEffects();
            }
        }
    }
    
    [SerializeField] private float boostFOVIncrease = 10f;
    [SerializeField] private float boostBloomIntensity = 1.5f;
    [SerializeField] private float normalBloomIntensity = 1f;
    
    private Camera cam;
    private float baseFOV;
    private Bloom bloom;
    
    private void Awake()
    {
        cam = GetComponent<Camera>();
        baseFOV = cam.fieldOfView;
        postProcessVolume.profile.TryGetSettings(out bloom);
    }
    
    private void UpdateEffects()
    {
        // Adjust FOV for boost effect
        LeanTween.cancel(gameObject);
        if (isBoosting)
        {
            LeanTween.value(gameObject, cam.fieldOfView, baseFOV + boostFOVIncrease, 0.2f)
                .setOnUpdate((float val) => cam.fieldOfView = val);
            
            LeanTween.value(gameObject, bloom.intensity.value, boostBloomIntensity, 0.2f)
                .setOnUpdate((float val) => bloom.intensity.value = val);
        }
        else
        {
            LeanTween.value(gameObject, cam.fieldOfView, baseFOV, 0.2f)
                .setOnUpdate((float val) => cam.fieldOfView = val);
                
            LeanTween.value(gameObject, bloom.intensity.value, normalBloomIntensity, 0.2f)
                .setOnUpdate((float val) => bloom.intensity.value = val);
        }
    }
    
    public void ShakeCamera(float intensity)
    {
        // Implementation of camera shake effect
        // ...
    }
}
```

## Audio System

### AudioManager

The `AudioManager` class manages game audio:

```csharp
public class AudioManager : MonoBehaviour
{
    public static AudioManager Instance { get; private set; }
    
    [Header("Music")]
    [SerializeField] private AudioClip menuMusic;
    [SerializeField] private AudioClip gameMusic;
    [SerializeField] private AudioClip resultMusic;
    
    [Header("Sound Effects")]
    [SerializeField] private AudioClip countdownSound;
    [SerializeField] private AudioClip explosionSound;
    [SerializeField] private AudioClip reconnectSound;
    [SerializeField] private AudioClip pickupSound;
    
    private AudioSource musicSource;
    private AudioSource sfxSource;
    
    private void Awake()
    {
        if (Instance == null)
        {
            Instance = this;
            DontDestroyOnLoad(gameObject);
            
            // Create audio sources
            musicSource = gameObject.AddComponent<AudioSource>();
            musicSource.loop = true;
            
            sfxSource = gameObject.AddComponent<AudioSource>();
        }
        else
        {
            Destroy(gameObject);
        }
    }
    
    private void OnEnable()
    {
        QuantumEvent.Subscribe<EventGameStateChanged>(this, OnGameStateChanged);
        QuantumEvent.Subscribe<EventShipExploded>(this, OnShipExploded);
        QuantumEvent.Subscribe<EventPlayerReconnected>(this, OnPlayerReconnected);
        QuantumEvent.Subscribe<EventPickupCollected>(this, OnPickupCollected);
    }
    
    private void OnDisable()
    {
        QuantumEvent.UnsubscribeListener<EventGameStateChanged>(this);
        QuantumEvent.UnsubscribeListener<EventShipExploded>(this);
        QuantumEvent.UnsubscribeListener<EventPlayerReconnected>(this);
        QuantumEvent.UnsubscribeListener<EventPickupCollected>(this);
    }
    
    private void OnGameStateChanged(EventGameStateChanged evt)
    {
        switch (evt.NewState)
        {
            case GameState.Lobby:
            case GameState.Pregame:
                PlayMusic(menuMusic);
                break;
            case GameState.Countdown:
            case GameState.Game:
                PlayMusic(gameMusic);
                break;
            case GameState.Postgame:
                PlayMusic(resultMusic);
                break;
        }
    }
    
    private void OnShipExploded(EventShipExploded evt)
    {
        QuantumEntityView view = QuantumEntityView.FindEntityView(evt.Entity);
        if (view != null)
        {
            PlaySFXAtPosition(explosionSound, view.transform.position);
        }
    }
    
    private void OnPlayerReconnected(EventPlayerReconnected evt)
    {
        QuantumEntityView view = QuantumEntityView.FindEntityView(evt.Entity);
        if (view != null)
        {
            PlaySFXAtPosition(reconnectSound, view.transform.position);
        }
    }
    
    private void OnPickupCollected(EventPickupCollected evt)
    {
        QuantumEntityView view = QuantumEntityView.FindEntityView(evt.Entity);
        if (view != null)
        {
            PlaySFXAtPosition(pickupSound, view.transform.position);
        }
    }
    
    public void PlayMusic(AudioClip clip)
    {
        if (musicSource.clip != clip)
        {
            musicSource.clip = clip;
            musicSource.Play();
        }
    }
    
    public void PlaySFX(AudioClip clip)
    {
        sfxSource.PlayOneShot(clip);
    }
    
    public void PlaySFXAtPosition(AudioClip clip, Vector3 position)
    {
        AudioSource.PlayClipAtPoint(clip, position);
    }
}
```

## Visual Effects System

### PickupView

The `PickupView` component handles pickup visualization:

```csharp
public class PickupView : MonoBehaviour
{
    public float rotationSpeed = 50f;
    public float bounceHeight = 0.3f;
    public float bounceSpeed = 2f;
    
    private Vector3 startPosition;
    
    private void Start()
    {
        startPosition = transform.localPosition;
    }
    
    private void Update()
    {
        // Rotate pickup
        transform.Rotate(Vector3.up, rotationSpeed * Time.deltaTime);
        
        // Bounce pickup
        float bounce = Mathf.Sin(Time.time * bounceSpeed) * bounceHeight;
        transform.localPosition = startPosition + Vector3.up * bounce;
    }
}
```

### ExplosionEffect

The `ExplosionEffect` component manages explosion visuals:

```csharp
public class ExplosionEffect : MonoBehaviour
{
    [SerializeField] private ParticleSystem explosionParticles;
    [SerializeField] private Light explosionLight;
    [SerializeField] private float duration = 2f;
    
    private void Start()
    {
        // Start explosion effect
        explosionParticles.Play();
        
        // Create light pulse effect
        LeanTween.value(gameObject, explosionLight.intensity, 0, duration)
            .setEaseOutExpo()
            .setOnUpdate((float val) => explosionLight.intensity = val)
            .setOnComplete(() => Destroy(gameObject));
    }
}
```

## Resource Management

### ResourceManager

The `ResourceManager` class manages shared resources:

```csharp
public class ResourceManager : MonoBehaviour
{
    public static ResourceManager Instance { get; private set; }
    
    [Header("Ship Materials")]
    public string shipMatPrimaryString = "_PrimaryColor";
    public string shipMatSecondaryString = "_SecondaryColor";
    public string shipMatTrailString = "_TrailColor";
    
    [Header("Prefabs")]
    public GameObject explosionPrefab;
    public GameObject reconnectEffectPrefab;
    public GameObject boostPickupPrefab;
    public GameObject trailPickupPrefab;
    
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
}
```

## Map Loading System

### SceneLoader

The `SceneLoader` class handles Unity scene loading:

```csharp
public class SceneLoader : MonoBehaviour
{
    [SerializeField] private string menuSceneName = "Menu";
    [SerializeField] private string gameSceneName = "Game";
    
    public void LoadMenuScene()
    {
        SceneManager.LoadScene(menuSceneName);
    }
    
    public void LoadGameScene()
    {
        SceneManager.LoadScene(gameSceneName);
    }
}
```

### Map Visualization

The game visualizes the spherical map using a simple sphere mesh with shader effects:

```csharp
public class MapVisualizer : MonoBehaviour
{
    [SerializeField] private MeshRenderer sphereRenderer;
    [SerializeField] private Material mapMaterial;
    [SerializeField] private float rotationSpeed = 1f;
    
    private void Start()
    {
        sphereRenderer.material = mapMaterial;
    }
    
    private void Update()
    {
        // Slowly rotate the map for visual interest
        transform.Rotate(Vector3.up, rotationSpeed * Time.deltaTime);
    }
    
    public void SetMapColors(Color primaryColor, Color secondaryColor)
    {
        mapMaterial.SetColor("_PrimaryColor", primaryColor);
        mapMaterial.SetColor("_SecondaryColor", secondaryColor);
    }
}
```

## Integration with Quantum Runner

The `World` class integrates with Quantum's runner:

```csharp
public class World : MonoBehaviour
{
    [SerializeField] private RuntimeConfigContainer defaultConfig;
    
    private QuantumRunnerCallbacks callbacks;
    
    private void Awake()
    {
        // Create callbacks container
        callbacks = new QuantumRunnerCallbacks();
        
        // Register quantum callbacks
        QuantumCallback.Subscribe(this, (CallbackGameStarted callback) => OnGameStarted());
        QuantumCallback.Subscribe(this, (CallbackGameDestroyed callback) => OnGameDestroyed());
    }
    
    public void StartGame(RuntimeConfigContainer config = null)
    {
        if (QuantumRunner.Default?.IsRunning == true)
        {
            QuantumRunner.ShutdownAll();
        }
        
        if (config == null)
        {
            config = defaultConfig;
        }
        
        var startParams = new QuantumRunner.StartParameters
        {
            GameMode = DeterministicGameMode.Spectator,
            RuntimeConfig = config,
            InitialFrame = null,
            PlayerCount = config.DriverCount,
            LocalPlayer = LocalData.CreateLocalPlayerData()
        };
        
        QuantumRunner.StartGame(startParams);
    }
    
    private void OnGameStarted()
    {
        // Game started initialization
        // Implementation...
    }
    
    private void OnGameDestroyed()
    {
        // Cleanup
        // Implementation...
    }
}
```

## Best Practices

1. **Separation of Concerns**: Keep Unity visualization code separate from Quantum simulation logic
2. **Event-Based Communication**: Use events for clean communication from Quantum to Unity
3. **Local Player Handling**: Identify and handle the local player's ship differently
4. **Resource Management**: Use singleton managers for shared resources
5. **Performance Optimization**: Use object pooling and LOD for better performance
6. **Predictive Visualization**: Use predicted frames for visualization to reduce perceived latency
7. **Visual Feedback**: Provide clear visual feedback for gameplay events
8. **Audio Integration**: Link audio effects to simulation events
9. **Consistent Event Handling**: Subscribe to events systematically and unsubscribe when disabled
10. **Camera Effects**: Use camera effects to enhance gameplay feel
