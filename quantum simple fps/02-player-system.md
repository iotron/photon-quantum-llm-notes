# Player System in Quantum Simple FPS

This document explains how the Player System is implemented in the Quantum Simple FPS sample project, covering player entity management, movement, and character control.

## Player Component

The player system is built on the `Player` component defined in the Quantum DSL:

```qtn
component Player
{
    FP MoveSpeed;
    FP JumpForce;
    FP CameraOffset;

    [HideInInspector]
    PlayerRef PlayerRef;
}
```

Key properties of the Player component:
- `MoveSpeed`: Base movement speed of the character
- `JumpForce`: Upward force applied when jumping
- `CameraOffset`: Height offset for the camera/eye position
- `PlayerRef`: Reference to the player's network identity

Additionally, players use several standard Quantum components:
- `Transform3D`: Position and rotation in 3D space
- `KCC`: Kinematic Character Controller for movement and physics
- `PhysicsCollider3D`: For collision detection
- `Health`: Health and damage handling
- `Weapons`: Weapon inventory and management

## Player System Implementation

The `PlayerSystem` processes player input and controls the character:

```csharp
namespace Quantum
{
    [Preserve]
    public unsafe class PlayerSystem : SystemMainThreadFilter<PlayerSystem.Filter>
    {
        public override void Update(Frame frame, ref Filter filter)
        {
            var player = filter.Player;
            if (player->PlayerRef.IsValid == false)
                return;

            var kcc = filter.KCC;

            var gameplay = frame.Unsafe.GetPointerSingleton<Gameplay>();
            if (gameplay->State == EGameplayState.Finished)
            {
                kcc->SetInputDirection(FPVector3.Zero);
                return;
            }

            var input = frame.GetPlayerInput(player->PlayerRef);

            if (filter.Health->IsAlive)
            {
                // Apply look rotation from input
                kcc->AddLookRotation(input->LookRotationDelta.X, input->LookRotationDelta.Y);
                
                // Convert input direction to world space based on current look direction
                kcc->SetInputDirection(kcc->Data.TransformRotation * input->MoveDirection.XOY);
                kcc->SetKinematicSpeed(player->MoveSpeed);

                // Process jump input
                if (input->Jump.WasPressed && kcc->IsGrounded)
                {
                    kcc->Jump(FPVector3.Up * player->JumpForce);
                }
            }
            else
            {
                // Dead players don't move
                kcc->SetInputDirection(FPVector3.Zero);
            }
        }

        public struct Filter
        {
            public EntityRef Entity;
            public Player*   Player;
            public Health*   Health;
            public KCC*      KCC;
        }
    }
}
```

Key aspects of this system:
1. Uses a filter to process only entities with Player, Health, and KCC components
2. Gets input from the player's network identity
3. Processes input differently based on player state (alive/dead)
4. Delegates actual movement to the KCC system

## Movement Processor

The actual movement physics is handled by the `MoveProcessor` which extends Quantum's KCC system:

```csharp
namespace Quantum
{
    public unsafe class MoveProcessor : KCCProcessor, IBeforeMove, IAfterMoveStep
    {
        public FP UpGravity = 15;
        public FP DownGravity = 25;
        public FP GroundAcceleration = 55;
        public FP GroundDeceleration = 25;
        public FP AirAcceleration = 25;
        public FP AirDeceleration = FP._1 + FP._0_20 + FP._0_10;

        public void BeforeMove(KCCContext context, KCCProcessorInfo processorInfo)
        {
            KCCData data = context.KCC->Data;

            // Configure physics settings
            data.MaxGroundAngle = 60;
            data.MaxWallAngle   = 5;
            data.MaxHangAngle   = 30;

            // Apply asymmetric gravity (faster falling than rising)
            data.Gravity = new FPVector3(0, data.RealVelocity.Y >= 0 ? -UpGravity : -DownGravity, 0);

            // Set up dynamic velocity handling
            EnvironmentProcessor.SetDynamicVelocity(context, ref data, 1, GroundDeceleration, AirDeceleration);

            FP acceleration;

            if (data.InputDirection == FPVector3.Zero)
            {
                // No desired move velocity - we are stopping
                acceleration = data.IsGrounded ? GroundDeceleration : AirDeceleration;
            }
            else
            {
                // Moving in a direction - use appropriate acceleration
                acceleration = data.IsGrounded ? GroundAcceleration : AirAcceleration;
            }

            // Apply smooth acceleration
            data.KinematicVelocity = FPVector3.Lerp(
                data.KinematicVelocity, 
                data.InputDirection * data.KinematicSpeed, 
                acceleration * context.Frame.DeltaTime
            );

            context.KCC->Data = data;
        }

        public void AfterMoveStep(KCCContext context, KCCProcessorInfo processorInfo, KCCOverlapInfo overlapInfo)
        {
            // Handle collision response and step up/down logic
            EnvironmentProcessor.ProcessAfterMoveStep(context, processorInfo, overlapInfo);
        }
    }
}
```

Key aspects of the movement processor:
1. Implements `IBeforeMove` and `IAfterMoveStep` interfaces to hook into the KCC pipeline
2. Uses asymmetric gravity for better game feel (fall faster than rise)
3. Applies different acceleration/deceleration values based on state (grounded/air)
4. Uses smooth lerping for acceleration rather than instant velocity changes
5. Delegates environment collision handling to the built-in `EnvironmentProcessor`

## KCC Context Extensions

The `KCCContext` class is extended to implement custom collision filtering based on player health:

```csharp
namespace Quantum
{
    public unsafe partial class KCCContext
    {
        partial void PrepareUserContext()
        {
            ResolveCollision = ResolvePlayerCollision;
        }

        /// <summary>
        /// Custom collision resolution that ignores collisions between players
        /// when one or both are dead.
        /// </summary>
        private bool ResolvePlayerCollision(KCCContext context, Hit3D hit)
        {
            if (context.Entity.IsValid && hit.Entity.IsValid && 
                context.Frame.TryGet(context.Entity, out Health health) && 
                context.Frame.TryGet(hit.Entity, out Health otherHealth))
            {
                return health.IsAlive && otherHealth.IsAlive;
            }

            return true;
        }
    }
}
```

This extension ensures that:
1. Dead players can't block living players
2. Living players can move through dead players
3. All other collisions work normally

## Player Spawning

Player spawning is handled by the `Gameplay` system:

```csharp
private void RespawnPlayer(Frame frame, PlayerRef playerRef)
{
    var players = frame.ResolveDictionary(PlayerData);

    // Despawn old player object if it exists
    var playerEntity = frame.GetPlayerEntity(playerRef);
    if (playerEntity.IsValid)
    {
        frame.Destroy(playerEntity);
    }

    // Don't spawn disconnected players
    if (players.TryGetValue(playerRef, out PlayerData playerData) == false || 
        playerData.IsConnected == false)
        return;

    // Update player data
    playerData.IsAlive = true;
    players[playerRef] = playerData;

    // Get player avatar from runtime player data
    var runtimePlayer = frame.GetPlayerData(playerRef);
    playerEntity = frame.Create(runtimePlayer.PlayerAvatar);

    // Link entity to player
    frame.AddOrGet<Player>(playerEntity, out var player);
    player->PlayerRef = playerRef;

    // Set spawn position and rotation
    var playerTransform = frame.Unsafe.GetPointer<Transform3D>(playerEntity);
    SpawnPointData spawnPoint = GetSpawnPoint(frame);
    playerTransform->Position = spawnPoint.Position;
    playerTransform->Rotation = spawnPoint.Rotation;

    // Initialize look rotation
    var playerKCC = frame.Unsafe.GetPointer<KCC>(playerEntity);
    playerKCC->SetLookRotation(spawnPoint.Rotation.AsEuler.XY);
}
```

Key aspects of player spawning:
1. Destroys any existing player entity for the same player
2. Creates a new entity from the player prototype
3. Links the entity to the player's network identity
4. Places the player at a spawn point
5. Initializes look rotation based on spawn point orientation

## Player View Integration

The Unity-side view code uses an entity view component:

```csharp
namespace QuantumDemo
{
    public class CharacterView : QuantumEntityViewComponent
    {
        // References to child objects
        public Transform CameraRoot;
        public Transform ModelRoot;
        public Animator Animator;
        
        // Animation parameter hashes
        private static readonly int IsRunning = Animator.StringToHash("IsRunning");
        private static readonly int IsJumping = Animator.StringToHash("IsJumping");
        private static readonly int IsDead = Animator.StringToHash("IsDead");
        
        // Interpolation settings
        public float PositionInterpolationSpeed = 15.0f;
        public float RotationInterpolationSpeed = 15.0f;
        
        private Transform _transform;
        private bool _isLocalPlayer;
        
        public override void OnActivate(Frame frame)
        {
            _transform = transform;
            
            // Check if this is the local player
            var player = frame.Get<Player>(EntityRef);
            _isLocalPlayer = frame.PlayerIsLocal(player.PlayerRef);
            
            // Set up local player camera
            if (_isLocalPlayer)
            {
                // Activate first-person camera
                CameraRoot.gameObject.SetActive(true);
                
                // Hide local player model in first-person view
                ModelRoot.gameObject.SetActive(false);
            }
        }
        
        public override void OnUpdateView()
        {
            var frame = VerifiedFrame;
            if (frame == null) return;
            
            // Get entity components
            var transform3D = frame.Get<Transform3D>(EntityRef);
            var kcc = frame.Get<KCC>(EntityRef);
            var health = frame.Get<Health>(EntityRef);
            
            // Update transform
            _transform.position = Vector3.Lerp(
                _transform.position, 
                transform3D.Position.ToUnityVector3(), 
                Time.deltaTime * PositionInterpolationSpeed
            );
            
            // Update animation parameters
            if (Animator != null)
            {
                Animator.SetBool(IsRunning, kcc.InputDirection.SqrMagnitude > 0.01f);
                Animator.SetBool(IsJumping, !kcc.IsGrounded);
                Animator.SetBool(IsDead, !health.IsAlive);
            }
            
            // For non-local players, update model rotation
            if (!_isLocalPlayer)
            {
                Quaternion targetRotation = transform3D.Rotation.ToUnityQuaternion();
                ModelRoot.rotation = Quaternion.Slerp(
                    ModelRoot.rotation, 
                    targetRotation, 
                    Time.deltaTime * RotationInterpolationSpeed
                );
            }
        }
    }
}
```

Key aspects of the view integration:
1. Different handling for local vs. remote players
2. Smooth interpolation of position and rotation
3. Animation updates based on simulation state
4. First-person camera activation for local player
5. Third-person model shown only for remote players

## Best Practices for FPS Player Implementation

1. **Separate input and physics**: Use a dedicated system to process input and delegate physics to KCC
2. **Use asymmetric gravity**: Faster falling than rising creates better game feel
3. **Smooth acceleration**: Use lerping for smoother movement
4. **Handle player states**: Different behavior for alive/dead states
5. **Custom collision filtering**: Allow players to move through dead bodies
6. **Spawn point management**: Avoid spawning at recently used points
7. **Different local/remote views**: Special handling for the local player's view
8. **Interpolated movement**: Smooth visual movement between simulation steps

These practices ensure responsive player control with deterministic behavior across all clients, while providing suitable visual representation for both local and remote players.
