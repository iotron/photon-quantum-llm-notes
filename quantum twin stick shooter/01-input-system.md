# Input System

This document explains how the Twin Stick Shooter handles player input and AI control, showing the unified input system that allows seamless switching between player and bot control.

## Input Architecture

The input system in Quantum Twin Stick Shooter follows a unified approach:

1. **Input Definition**: The same `QuantumDemoInputTopDown` structure is used for both player input and bot AI
2. **Input Collection**: Player input is collected on the Unity side and sent to Quantum
3. **Input Application**: The `InputSystem` applies inputs to characters, regardless of source
4. **Automatic Bot Substitution**: When players disconnect, the system seamlessly transfers control to a bot

## Input Structure

The input structure is defined in the DSL:

```csharp
// From Input.qtn
component InputContainer
{
    [HideInInspector] QuantumDemoInputTopDown Input;
}
```

The `QuantumDemoInputTopDown` structure contains:

```csharp
// Generated from Quantum's input system
struct QuantumDemoInputTopDown
{
    FPVector2 MoveDirection;  // Normalized movement direction
    FPVector2 AimDirection;   // Direction for aiming/firing
    Boolean Fire;             // Primary attack button
    Boolean AltFire;          // Secondary attack button
}
```

## Input System Implementation

The Quantum `InputSystem` handles applying input to characters:

```csharp
[Preserve]
public unsafe class InputSystem : SystemMainThreadFilter<InputSystem.Filter>, ISignalOnToggleControllers
{
    public struct Filter
    {
        public EntityRef Entity;
        public Transform2D* Transform;
        public Character* Character;
        public InputContainer* InputContainer;
    }

    // This system deals with getting the Input structure from the appropriate place
    // The input can either come from a Player with GetPlayerInput, or from a Bot
    public override void Update(Frame frame, ref Filter filter)
    {
        if (frame.Global->ControllersEnabled == false)
            return;

        int playerRef = frame.Get<PlayerLink>(filter.Entity).PlayerRef;
        bool controlledByBot = IsControlledByAI(frame, filter, playerRef);

        if (controlledByBot == false)
        {
            filter.InputContainer->Input = *frame.GetPlayerInput(playerRef);
        }
        else
        {
            filter.InputContainer->Input = frame.Get<Bot>(filter.Entity).Input;
        }
    }

    // Enable/disable input, used to pause characters when the game is starting/over
    public void OnToggleControllers(Frame frame, QBoolean value)
    {
        frame.Global->ControllersEnabled = value;
    }

    private bool IsControlledByAI(Frame frame, Filter filter, int playerRef)
    {
        // If the player is not connected, we turn it into a bot
        bool playerNotPresent = frame.GetPlayerInputFlags(playerRef).HasFlag(DeterministicInputFlags.PlayerNotPresent) == true;
        if (playerNotPresent == true && frame.Get<Bot>(filter.Entity).IsActive == false)
        {
            if (frame.IsVerified)
            {
                AISetupHelper.Botify(frame, filter.Entity);
            }
        }

        if (frame.TryGet(filter.Entity, out Bot bot) == false)
            return false;

        if(bot.IsActive == false)
        {
            return false;
        }
        return true;
    }
}
```

## Unity Input Collection

On the Unity side, a `TopDownInput` component collects player input and sends it to Quantum:

```csharp
public class TopDownInput : MonoBehaviour
{
    public FP AimSensitivity = 5;
    public CustomViewContext ViewContext;
    
    private FPVector2 _lastDirection = new FPVector2();
    private AttackPreview _attackPreview;
    private PlayerInput _playerInput;

    // Called by Quantum to collect input
    public void PollInput(CallbackPollInput callback)
    {
        Quantum.QuantumDemoInputTopDown input = new Quantum.QuantumDemoInputTopDown();

        // Read movement input from InputSystem
        FPVector2 directional = _playerInput.actions["Move"].ReadValue<Vector2>().ToFPVector2();
        input.MoveDirection = IsInverseControl == true ? -directional : directional;

        // Read firing inputs
#if UNITY_STANDALONE || UNITY_WEBGL
        input.Fire = _playerInput.actions["MouseFire"].IsPressed();
        input.AltFire = _playerInput.actions["MouseSpecial"].IsPressed();
#elif UNITY_ANDROID
        input.Fire = _playerInput.actions["Fire"].IsPressed();
        input.AltFire = _playerInput.actions["Special"].IsPressed();
#endif

        // Handle aim direction calculation
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

        // Calculate final aim direction based on control scheme
        FPVector2 actionVector = default;
#if UNITY_STANDALONE || UNITY_WEBGL
        if (_playerInput.currentControlScheme != null && _playerInput.currentControlScheme.Contains("Joystick"))
        {
            actionVector = IsInverseControl ? -_lastDirection : _lastDirection;
        }
        else
        {
            actionVector = GetDirectionToMouse();
        }
        input.AimDirection = actionVector;
#elif UNITY_ANDROID
        actionVector = IsInverseControl ? -_lastDirection : _lastDirection;
        input.AimDirection = actionVector;
#endif

        // Show attack preview if aiming
        if ((input.Fire == true || input.AltFire == true) && input.AimDirection != FPVector2.Zero)
        {
            _attackPreview.gameObject.SetActive(true);
            _attackPreview.UpdateAttackPreview(actionVector, input.AltFire);
        }

        // Send input to Quantum
        callback.SetInput(input, DeterministicInputFlags.Repeatable);
    }

    // Calculate direction from character to mouse position
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
```

## Bot Input Generation

For bots, input is generated through the AI system:

```csharp
// In AISystem.cs
private void HandleContextSteering(Frame frame, Filter filter)
{
    // Process the final desired direction
    FPVector2 desiredDirection = filter.AISteering->GetDesiredDirection(frame, filter.Entity);

    // Lerp the current value towards the desired one so it doesn't turn too sudden
    filter.AISteering->CurrentDirection = FPVector2.MoveTowards(filter.AISteering->CurrentDirection, desiredDirection,
        frame.DeltaTime * filter.AISteering->LerpFactor);

    // Assign movement direction to the bot's input structure
    filter.Bot->Input.MoveDirection = filter.AISteering->CurrentDirection;
    
    // Aim direction and firing inputs are set by behavior tree actions
}
```

## Player to Bot Transition

When a player disconnects, the system automatically converts their character to a bot:

```csharp
// In InputSystem.cs, IsControlledByAI method
bool playerNotPresent = frame.GetPlayerInputFlags(playerRef).HasFlag(DeterministicInputFlags.PlayerNotPresent) == true;
if (playerNotPresent == true && frame.Get<Bot>(filter.Entity).IsActive == false)
{
    if (frame.IsVerified)
    {
        AISetupHelper.Botify(frame, filter.Entity);
    }
}
```

The `AISetupHelper.Botify` method:

```csharp
// From AISetupHelper.cs
public static void Botify(Frame frame, EntityRef entity)
{
    // 1. Set bot component as active
    Bot* bot = frame.Unsafe.GetPointer<Bot>(entity);
    bot->IsActive = true;

    // 2. Setup HFSM brain for AI
    AIConfig aiConfig = frame.FindAsset<AIConfig>(frame.RuntimeConfig.DefaultBotConfig.Id);
    HFSMRoot hfsmRoot = frame.FindAsset<HFSMRoot>(aiConfig.HFSM.Id);
    HFSMData* hfsmData = frame.Unsafe.AddOrGetPointer<HFSMData>(entity);
    hfsmData->Root = hfsmRoot;
    HFSMManager.Init(frame, hfsmData, entity, hfsmRoot);
    
    // 3. Initialize memory for AI
    AIMemory* aiMemory = frame.Unsafe.AddOrGetPointer<AIMemory>(entity);
    aiMemory->Initialize();
    
    // 4. Setup navigation agent
    frame.Unsafe.AddComponent<NavMeshPathfinder>(entity);
    frame.Unsafe.AddComponent<NavMeshSteeringAgent>(entity);
    NavMeshPathfinder* pathfinder = frame.Unsafe.GetPointer<NavMeshPathfinder>(entity);
    pathfinder->Settings = aiConfig.NavMeshPathfinderSettings;
    
    // 5. Add AI steering component for movement control
    AISteering* aiSteering = frame.Unsafe.AddOrGetPointer<AISteering>(entity);
    aiSteering->Initialize();
}
```

## Best Practices

1. **Unified Input Structure**: Use the same input structure for both player and AI control
2. **Seamless Transition**: Design systems to handle player-to-bot transitions without disruption
3. **Input Abstraction**: Keep the character movement and abilities systems decoupled from input source
4. **Platform Adaptation**: Handle multiple input methods (mouse/keyboard, touch, gamepad)
5. **Prediction Handling**: Use `DeterministicInputFlags.Repeatable` for inputs to work with predict/rollback

## Implementation Notes

1. The `QuantumDemoInputTopDown` structure provides a minimal but complete set of inputs for twin-stick shooter gameplay
2. The same input structure is used for both AI-controlled and player-controlled characters
3. The `InputSystem` doesn't care about the source of input (player or AI)
4. Movement and aiming inputs use normalized FPVector2 values for consistency
5. The Unity Input System package is used for input collection on the client side