# UI and View Implementation

Quantum Racer 2.5D uses Quantum's view system to display game state to players. The view layer is responsible for visualizing the deterministic simulation on the client side.

## Core View Components

### RacerCameraView

The `RacerCameraView` class handles camera positioning and following the player's vehicle:

```csharp
public class RacerCameraView : QuantumEntityViewComponent<RacerCameraContext>
{
    public Vector3 Offset = new Vector3(0, 2, -4);
    public float LerpSpeed = 4;
    public bool Follow = false;
    public RacerLapUI LapUI;
    
    public override void OnActivate(Frame frame)
    {
        LapUI = GetComponent<RacerLapUI>();
        if (frame.TryGet(EntityRef, out RacerPlayerLink link) && Game.PlayerIsLocal(link.Player))
        {
            Follow = true;
            ViewContext.CurrentCameraController = this;
        }
    }

    public override void OnUpdateView()
    {
        if (Follow == false) return;
        var t = transform;
        
        // Set prediction area for optimal network performance
        Game.SetPredictionArea(transform.position.ToFPVector3(), 20);
        
        // Smoothly follow the vehicle
        var desired = t.TransformPoint(Offset);
        ViewContext.CameraHandle.position =
            Vector3.Lerp(ViewContext.CameraHandle.position, desired, Time.deltaTime * LerpSpeed);
        ViewContext.CameraHandle.LookAt(t);

        // Update speed display
        var body = PredictedFrame.Get<PhysicsBody2D>(EntityRef);
        var speed = body.Velocity.Magnitude.AsFloat * 20;
        ViewContext.SpeedLabel.text = $"{speed:0} Kmh";
    }
}
```

### RacerLapUI

The `RacerLapUI` class displays lap times and race information:

```csharp
public class RacerLapUI : QuantumEntityViewComponent<RacerCameraContext> {
    
    public bool Follow = false;
    
    public override void OnActivate(Frame frame)
    {
        if (frame.TryGet(EntityRef, out RacerPlayerLink link) && Game.PlayerIsLocal(link.Player)) 
            Follow = true;
    }
    
    public override void OnUpdateView()
    {
        if (Follow == false) return;
        
        // Display race start countdown or "Go!"
        if (PredictedFrame.TryGetSingleton<RaceManager>(out var manager))
        {
            if (manager.State == RaceState.Start)
            {
                var time = manager.RaceTime + 1;
                ViewContext.Info.text = "" + time.AsInt;
            }
            else if (manager.RaceTime < 3)
            {
                ViewContext.Info.text = "Go!";
            }
            else
            {
                ViewContext.Info.text = "";
            }
        }
        
        // Display vehicle race information
        var vehicle = PredictedFrame.Get<Racer>(EntityRef);
        var raceConfig = PredictedFrame.FindAsset<RaceConfig>(PredictedFrame.RuntimeConfig.RaceConfig);

        ViewContext.Laps.text = "" + vehicle.LapData.Laps + "/" + raceConfig.Laps;
        ViewContext.LapTime.text = "" + FormatTime(vehicle.LapData.LapTime.AsFloat);
        ViewContext.BestLap.text = "" + FormatTime(vehicle.LapData.BestLap.AsFloat);
        ViewContext.LastLap.text = "" + FormatTime(vehicle.LapData.LastLapTime.AsFloat);
        ViewContext.Position.text = "" + vehicle.Position;
    }

    private string FormatTime(float seconds)
    {
        int secondsInt = (int)seconds;
        int minutes = secondsInt / 60;
        float remainder = seconds - secondsInt;
        secondsInt = secondsInt % 60;
        return $"{minutes:00}:{secondsInt:00}:{remainder*1000:000}";
    }
}
```

### RaceUI

The `RaceUI` class displays overall race information including player positions:

```csharp
public class RaceUI : QuantumSceneViewComponent<RacerCameraContext> {
    public override void OnUpdateView()
    {
        string positions = "";
        var manager = PredictedFrame.GetOrAddSingleton<RaceManager>();
        var vehicles = PredictedFrame.ResolveList(manager.Vehicles);
        var bots = PredictedFrame.FindAsset(PredictedFrame.RuntimeConfig.Bots);

        foreach (var vehicle in vehicles)
        {
            var racer = PredictedFrame.Get<Racer>(vehicle);
            var link = PredictedFrame.Get<RacerPlayerLink>(vehicle);
            
            // Get player nickname
            string nickname = bots.Nicknames[link.Player];
            var data = PredictedFrame.GetPlayerData(link.Player);
            if (data != null)
                nickname = data.PlayerNickname;
                
            // Format display text
            if (racer.Finished)
            {
                positions += nickname + " (finished " + racer.Position + ")\n";
            }
            else
            {
                positions += nickname + " (laps: " + racer.LapData.Laps + ")\n";
            }
        }
        
        ViewContext.Positions.text = positions;
    }
}
```

### RacerLeanView

The `RacerLeanView` class visualizes vehicle lean:

```csharp
public class RacerLeanView : QuantumEntityViewComponent {
    
    public float LeanAngle = 15;
    public float LerpSpeed = 5;
    
    public override void OnUpdateView()
    {
        var racer = PredictedFrame.Get<Racer>(EntityRef);
        var leanAmount = racer.Lean;
        transform.localRotation = Quaternion.Slerp(transform.localRotation, 
                                                  Quaternion.Euler(0, 0, -leanAmount * LeanAngle), 
                                                  Time.deltaTime * LerpSpeed);
    }
}
```

## Racer Camera Context

The `RacerCameraContext` class provides shared access to UI elements:

```csharp
public class RacerCameraContext : QuantumSceneViewContext {
    public Transform CameraHandle;
    public RacerCameraView CurrentCameraController;
    
    // UI elements
    public TextMeshProUGUI LapTime;
    public TextMeshProUGUI BestLap;
    public TextMeshProUGUI LastLap;
    public TextMeshProUGUI Laps;
    public TextMeshProUGUI Position;
    public TextMeshProUGUI SpeedLabel;
    public TextMeshProUGUI Info;
    public TextMeshProUGUI Positions;
    
    // Other visual elements
    public Image HealthUI;
}
```

## Other View Components

### CarSelectorButton

Allows players to select their vehicle:

```csharp
public class CarSelectorButton : MonoBehaviour {
    public int CarIndex = 0;
    public Button Button;
    
    private void Start() {
        Button.onClick.AddListener(OnClick);
    }
    
    private void OnClick() {
        var data = QuantumRunner.Default.Game.GetPlayerData(QuantumRunner.Default.Game.LocalPlayerIndex);
        data.PlayerCar = CarIndex;
    }
}
```

### RacerSFX

Handles sound effects for the vehicle:

```csharp
public class RacerSFX : QuantumEntityViewComponent, ISignalOnJump, ISignalOnJumpLand, ISignalOnDeath, ISignalOnRespawn, ISignalOnBump, ISignalOnVehicleBump {
    
    public AudioSource EngineSound;
    public AudioSource EffectsSource;
    
    public AudioClip JumpSound;
    public AudioClip LandSound;
    public AudioClip DeathSound;
    public AudioClip RespawnSound;
    public AudioClip BumpSound;
    public AudioClip CarBumpSound;
    
    public override void OnUpdateView() {
        if (EngineSound != null) {
            var racer = PredictedFrame.Get<Racer>(EntityRef);
            var body = PredictedFrame.Get<PhysicsBody2D>(EntityRef);
            
            // Engine sound pitch based on speed
            var speed = body.Velocity.Magnitude.AsFloat;
            var normalizedSpeed = Mathf.Clamp01(speed / 10f);
            EngineSound.pitch = Mathf.Lerp(0.8f, 1.5f, normalizedSpeed);
            EngineSound.volume = Mathf.Lerp(0.2f, 1.0f, normalizedSpeed);
        }
    }
    
    public void OnJump(Frame frame, Jump e) {
        if (e.Entity == EntityRef && EffectsSource != null && JumpSound != null) {
            EffectsSource.PlayOneShot(JumpSound);
        }
    }
    
    public void OnJumpLand(Frame frame, JumpLand e) {
        if (e.Entity == EntityRef && EffectsSource != null && LandSound != null) {
            EffectsSource.PlayOneShot(LandSound);
        }
    }
    
    public void OnDeath(Frame frame, Death e) {
        if (e.Entity == EntityRef && EffectsSource != null && DeathSound != null) {
            EffectsSource.PlayOneShot(DeathSound);
        }
    }
    
    public void OnRespawn(Frame frame, Respawn e) {
        if (e.Entity == EntityRef && EffectsSource != null && RespawnSound != null) {
            EffectsSource.PlayOneShot(RespawnSound);
        }
    }
    
    public void OnBump(Frame frame, Bump e) {
        if (e.Entity == EntityRef && EffectsSource != null && BumpSound != null) {
            EffectsSource.PlayOneShot(BumpSound);
        }
    }
    
    public void OnVehicleBump(Frame frame, VehicleBump e) {
        if (e.Entity == EntityRef && EffectsSource != null && CarBumpSound != null) {
            EffectsSource.PlayOneShot(CarBumpSound);
        }
    }
}
```

### SpectateSwitcher

Allows spectating different vehicles:

```csharp
public class SpectateSwitcher : QuantumSceneViewComponent<RacerCameraContext> {
    public int CurrentSpectateIndex = 0;
    
    private void Update() {
        if (Input.GetKeyDown(KeyCode.Tab)) {
            SwitchSpectateTarget();
        }
    }
    
    private void SwitchSpectateTarget() {
        if (!PredictedFrame.TryGetSingleton<RaceManager>(out var manager)) return;
        
        var vehicles = PredictedFrame.ResolveList(manager.Vehicles);
        if (vehicles.Count == 0) return;
        
        CurrentSpectateIndex = (CurrentSpectateIndex + 1) % vehicles.Count;
        var entityView = QuantumRunner.Default.Game.GetEntityView(vehicles[CurrentSpectateIndex]);
        
        if (entityView != null) {
            var cameraView = entityView.GetComponent<RacerCameraView>();
            if (cameraView != null) {
                if (ViewContext.CurrentCameraController != null) {
                    ViewContext.CurrentCameraController.Follow = false;
                }
                
                cameraView.Follow = true;
                ViewContext.CurrentCameraController = cameraView;
                ViewContext.CurrentCameraController.LapUI.Follow = true;
            }
        }
    }
}
```

## Implementation Notes

- Uses Quantum's view component system for frame interpolation
- Separates game logic (simulation) from presentation
- Uses predicted frames for smoother experience
- Supports local and networked play
- Compatible with Unity's UI system
- Provides visual feedback for game events
- Supports spectator mode for watching other players
