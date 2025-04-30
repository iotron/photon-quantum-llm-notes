# Health System in Quantum Simple FPS

This document explains the implementation of the Health System in the Quantum Simple FPS sample project, covering health management, damage application, and player death handling.

## Health Component

The health system is built on the `Health` component defined in the Quantum DSL:

```qtn
component Health
{
    FP MaxHealth;
    FP SpawnImmortalityTime;

    [ExcludeFromPrototype]
    FP CurrentHealth;
    [ExcludeFromPrototype]
    FP ImmortalityCooldown;
}

event DamageReceived
{
    EntityRef Entity;
    FPVector3 HitPoint;
    FPVector3 HitNormal;
}
```

Key properties of the Health component:
- `MaxHealth`: Maximum health value for the entity
- `SpawnImmortalityTime`: Temporary invulnerability period after spawning
- `CurrentHealth`: Current health value (runtime)
- `ImmortalityCooldown`: Countdown for temporary invulnerability

## Health Component Extensions

The `Health` component has extensions to provide utility methods and properties:

```csharp
namespace Quantum
{
    public partial struct Health
    {
        // Properties
        public bool IsAlive => CurrentHealth > 0;
        public bool IsImmortal => ImmortalityCooldown > 0;

        // Methods
        public FP ApplyDamage(FP damage)
        {
            if (CurrentHealth <= 0)
                return 0;

            if (IsImmortal)
                return 0;

            if (damage > CurrentHealth)
            {
                damage = CurrentHealth;
            }

            CurrentHealth -= damage;

            return damage;
        }

        public bool AddHealth(FP health)
        {
            if (CurrentHealth <= 0)
                return false;
            if (CurrentHealth >= MaxHealth)
                return false;

            CurrentHealth = FPMath.Min(CurrentHealth + health, MaxHealth);

            return true;
        }

        public void StopImmortality()
        {
            ImmortalityCooldown = 0;
        }
    }
}
```

Key utility methods:
- `ApplyDamage()`: Safely reduces health by the specified amount
- `AddHealth()`: Increases health up to the maximum
- `StopImmortality()`: Ends temporary invulnerability
- `IsAlive` property: Quick check if entity is alive
- `IsImmortal` property: Check if entity is currently invulnerable

## Health System Implementation

The `HealthSystem` manages health state updates:

```csharp
namespace Quantum
{
    [Preserve]
    public unsafe class HealthSystem : SystemMainThreadFilter<HealthSystem.Filter>, 
                                       ISignalOnComponentAdded<Health>
    {
        public override void Update(Frame frame, ref Filter filter)
        {
            // Update immortality cooldown
            filter.Health->ImmortalityCooldown -= frame.DeltaTime;

            if (filter.Health->ImmortalityCooldown <= 0)
            {
                filter.Health->ImmortalityCooldown = 0;
            }
        }

        void ISignalOnComponentAdded<Health>.OnAdded(Frame frame, EntityRef entity, Health* health)
        {
            // Initialize health values when component is added
            health->CurrentHealth = health->MaxHealth;
            health->ImmortalityCooldown = health->SpawnImmortalityTime;
        }

        public struct Filter
        {
            public EntityRef Entity;
            public Health*   Health;
        }
    }
}
```

The HealthSystem is simple and focused:
1. Tracks and updates the immortality cooldown
2. Initializes health values when a Health component is added to an entity

## Damage Application

Damage is applied to entities through the `ApplyDamage` method on the Health component. This is typically called from the `WeaponsSystem` when a projectile hits an entity:

```csharp
// From WeaponsSystem.FireProjectile method
FP damageDone = health->ApplyDamage(damage);
if (damageDone > 0)
{
    damageData.TotalDamage += damageDone;

    if (health->IsAlive == false && frame.Unsafe.TryGetPointer(hit.Entity, out Player* victim))
    {
        // Signal a kill when target health reaches zero
        frame.Signals.PlayerKilled(filter.Player->PlayerRef, victim->PlayerRef, filter.Weapons->CurrentWeaponId, false);
        damageData.IsFatal = true;
    }

    // Trigger damage visual effect
    frame.Events.DamageReceived(hit.Entity, hit.Point, hit.Normal);
}
```

The damage system includes these key features:
1. Damage reduction based on body part hit (head = 2x damage, limbs = 0.5x damage)
2. Game state-based damage multipliers (e.g., double damage in final phase)
3. Immortality periods after spawning
4. Kill detection and scoring

## Health Pickups

Health can be restored through pickups:

```qtn
struct HealthPickup
{
    FP Heal;
}
```

The pickup system handles health restoration:

```csharp
// From PickupSystem.Update method
if (filter.Pickup->Settings.IsHealth)
{
    var healthPickup = filter.Pickup->Settings.Health;
    
    if (frame.Unsafe.TryGetPointer<Health>(overlapEntity, out var health))
    {
        if (health->AddHealth(healthPickup.Heal))
        {
            // Apply pickup cooldown
            filter.Pickup->Cooldown = filter.Pickup->PickupCooldown;
            
            // Trigger pickup event
            frame.Events.HealthPickedUp(filter.Entity, overlapEntity);
        }
    }
}
```

## Death Handling

When a player's health reaches zero, several systems are triggered:

1. **Kill Signal**: The `PlayerKilled` signal is sent by the WeaponsSystem

```csharp
frame.Signals.PlayerKilled(filter.Player->PlayerRef, victim->PlayerRef, filter.Weapons->CurrentWeaponId, false);
```

2. **Score Update**: The GameplaySystem handles the signal and updates statistics

```csharp
void ISignalPlayerKilled.PlayerKilled(Frame frame, PlayerRef killerPlayerRef, PlayerRef victimPlayerRef, byte weaponType, QBoolean isCriticalKill)
{
    var gameplay = frame.Unsafe.GetPointerSingleton<Gameplay>();
    var players = frame.ResolveDictionary(gameplay->PlayerData);

    // Update statistics of the killer player
    if (players.TryGetValue(killerPlayerRef, out PlayerData killerData))
    {
        killerData.Kills++;
        killerData.LastKillFrame = frame.Number;
        players[killerPlayerRef] = killerData;
    }

    // Update statistics of the victim player
    if (players.TryGetValue(victimPlayerRef, out PlayerData playerData))
    {
        playerData.Deaths++;
        playerData.IsAlive = false;
        playerData.RespawnTimer = gameplay->PlayerRespawnTime;
        players[victimPlayerRef] = playerData;
    }

    frame.Events.PlayerKilled(killerPlayerRef, victimPlayerRef, weaponType, isCriticalKill);

    gameplay->RecalculateStatisticPositions(frame);
}
```

3. **Respawn Timer**: The GameplaySystem starts a respawn timer for the killed player

4. **Visual Effects**: The `PlayerKilled` event is sent to the view layer for death animations

## Player Respawning

Respawning is handled by the GameplaySystem:

```csharp
public void TryRespawnPlayers(Frame frame)
{
    var players = frame.ResolveDictionary(PlayerData);
    foreach (var playerPair in players)
    {
        var playerData = playerPair.Value;
        if (playerData.RespawnTimer <= 0)
            continue;

        playerData.RespawnTimer -= frame.DeltaTime;
        players[playerData.PlayerRef] = playerData;

        if (playerData.RespawnTimer <= 0)
        {
            RespawnPlayer(frame, playerPair.Key);
        }
    }
}

private void RespawnPlayer(Frame frame, PlayerRef playerRef)
{
    var players = frame.ResolveDictionary(PlayerData);

    // Despawn old player object if it exists
    var playerEntity = frame.GetPlayerEntity(playerRef);
    if (playerEntity.IsValid)
    {
        frame.Destroy(playerEntity);
    }

    // Don't spawn for disconnected clients
    if (players.TryGetValue(playerRef, out PlayerData playerData) == false || 
        playerData.IsConnected == false)
        return;

    // Update player data
    playerData.IsAlive = true;
    players[playerRef] = playerData;

    // Create new player entity
    var runtimePlayer = frame.GetPlayerData(playerRef);
    playerEntity = frame.Create(runtimePlayer.PlayerAvatar);

    // Link entity to player
    frame.AddOrGet<Player>(playerEntity, out var player);
    player->PlayerRef = playerRef;

    // Set spawn position
    var playerTransform = frame.Unsafe.GetPointer<Transform3D>(playerEntity);
    SpawnPointData spawnPoint = GetSpawnPoint(frame);
    playerTransform->Position = spawnPoint.Position;
    playerTransform->Rotation = spawnPoint.Rotation;

    // Initialize look rotation
    var playerKCC = frame.Unsafe.GetPointer<KCC>(playerEntity);
    playerKCC->SetLookRotation(spawnPoint.Rotation.AsEuler.XY);
}
```

When a player respawns:
1. The old player entity is destroyed
2. A new entity is created from the player's avatar prototype
3. The new entity is linked to the player
4. The player is positioned at a spawn point
5. The health component is initialized with full health and temporary immortality

## Health View Integration

The Unity-side view code visualizes health and damage:

```csharp
namespace QuantumDemo
{
    public class HealthView : QuantumEntityViewComponent
    {
        // References
        public Animator Animator;
        public ParticleSystem BloodEffect;
        public AudioSource HitSound;
        public AudioSource DeathSound;
        
        // Animation parameter hashes
        private static readonly int IsDead = Animator.StringToHash("IsDead");
        
        // UI elements
        public Slider HealthBar;
        public Image DamageOverlay;
        
        // Previous health value for detecting changes
        private FP _lastHealth;
        
        // Local player reference
        private bool _isLocalPlayer;
        
        public override void OnActivate(Frame frame)
        {
            var player = frame.Get<Player>(EntityRef);
            _isLocalPlayer = Game.PlayerIsLocal(player.PlayerRef);
            
            // Only show UI for local player
            if (HealthBar != null)
            {
                HealthBar.gameObject.SetActive(_isLocalPlayer);
            }
            
            if (DamageOverlay != null)
            {
                DamageOverlay.gameObject.SetActive(_isLocalPlayer);
            }
            
            // Subscribe to damage events
            QuantumEvent.Subscribe<EventDamageReceived>(this, OnDamageReceived);
        }
        
        public override void OnDeactivate()
        {
            QuantumEvent.Unsubscribe<EventDamageReceived>(this, OnDamageReceived);
        }
        
        public override void OnUpdateView()
        {
            var frame = VerifiedFrame;
            if (frame == null) return;
            
            if (!frame.TryGet(EntityRef, out Health health))
                return;
                
            // Update death state
            Animator.SetBool(IsDead, !health.IsAlive);
            
            // Update health bar for local player
            if (_isLocalPlayer && HealthBar != null)
            {
                HealthBar.value = health.CurrentHealth.AsFloat / health.MaxHealth.AsFloat;
                
                // Fade damage overlay based on health
                if (DamageOverlay != null)
                {
                    float targetAlpha = 1.0f - (health.CurrentHealth.AsFloat / health.MaxHealth.AsFloat);
                    Color color = DamageOverlay.color;
                    color.a = Mathf.Lerp(0.0f, 0.8f, targetAlpha);
                    DamageOverlay.color = color;
                }
            }
            
            // Detect health decrease for non-local players
            if (!_isLocalPlayer && health.CurrentHealth < _lastHealth)
            {
                // Play hit effect
                BloodEffect.Play();
                HitSound.Play();
            }
            
            _lastHealth = health.CurrentHealth;
        }
        
        private void OnDamageReceived(EventDamageReceived e)
        {
            if (e.Entity != EntityRef)
                return;
                
            // Play hit effects
            BloodEffect.transform.position = e.HitPoint.ToUnityVector3();
            BloodEffect.Play();
            
            // Play appropriate sound
            if (!VerifiedFrame.TryGet(EntityRef, out Health health))
                return;
                
            if (health.IsAlive)
            {
                HitSound.Play();
            }
            else
            {
                DeathSound.Play();
            }
        }
    }
}
```

Key aspects of the health visualization:
1. Different handling for local vs. remote players
2. Health bar and damage overlay for local player
3. Blood effects and sounds for all players
4. Separate sounds for hits vs. deaths
5. Animation updates based on alive/dead state

## Best Practices for FPS Health Implementation

1. **Immortality periods**: Temporary invulnerability after spawning prevents spawn-killing
2. **Health clamping**: Ensure health stays within valid ranges
3. **Death detection**: Signal player death to trigger respawn and scoring
4. **Health feedback**: Visual feedback for damage and healing
5. **Local player UI**: Only show health UI elements for the local player
6. **Cancellable immortality**: Option to end immortality when player starts shooting
7. **Damage modifiers**: Different damage based on body part hit
8. **Clean separation**: Health logic separated from visual representation
9. **Health restoration**: Pickups that restore health without exceeding maximum
10. **Respawn system**: Clean player recreation after death

These practices ensure consistent health management across all clients while providing appropriate visual feedback to players. The health system is designed to be fair and deterministic, with special attention to gameplay feel through features like temporary spawn protection.
