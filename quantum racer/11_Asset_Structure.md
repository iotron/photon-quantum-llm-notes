# Quantum Racer 2.5D Asset Structure

This document outlines the key assets and their relationships in the Quantum Racer 2.5D game. Understanding this structure is essential for creating or modifying game content.

## Vehicle Assets

Each vehicle in the game consists of several interrelated assets:

### 1. Vehicle Config Asset
```
Assets/QuantumUser/Resources/Racer/CarSpecs/{VehicleName}Config.asset
```

The config asset defines the vehicle's handling characteristics:
- Acceleration, braking, and mass
- Maximum speed and rotation speed
- Drag and friction coefficients
- Lean effects and jump parameters
- Energy (health) values

### 2. Vehicle Prefab
```
Assets/QuantumUser/Resources/Racer/CarSpecs/{VehicleName}.prefab
```

The Unity prefab contains:
- 3D mesh models for the vehicle
- Particle systems for effects
- Audio sources for engine and collision sounds
- Visual components for lean and pitch animations

### 3. Entity Prototype
```
Assets/QuantumUser/Resources/Racer/CarSpecs/{VehicleName}EntityPrototype.qprototype
```

The Quantum prototype defines the entity's components:
- Racer component with config reference
- Transform2D and Transform2DVertical components
- PhysicsBody2D with collision properties
- RacerPlayerLink for player association

Example prototype structure:
```json
{
  "Id": "c653e58a57c5e0f4f927a3aee0a19aed",
  "Name": "BlasterEntityPrototype",
  "Components": [
    {
      "$type": "Quantum.RacerPlayerLink",
      "Player": {
        "IsValid": false,
        "Value": 0
      }
    },
    {
      "$type": "Quantum.Transform2D",
      "Position": {
        "X": 0,
        "Y": 0
      },
      "Rotation": 0
    },
    {
      "$type": "Quantum.Transform2DVertical",
      "Position": 0
    },
    {
      "$type": "Quantum.PhysicsBody2D",
      "Mass": 1.0,
      "AngularDrag": 1.0,
      "IsKinematic": false,
      "Layer": 4,
      "CollisionShape": {
        "$type": "Quantum.CircleCollider2D",
        "Center": {
          "X": 0,
          "Y": 0
        },
        "Radius": 0.5
      }
    },
    {
      "$type": "Quantum.Racer",
      "Config": "Assets/QuantumUser/Resources/Racer/CarSpecs/BlasterConfig.asset",
      "Energy": 10
    }
  ],
  "View": "Assets/QuantumUser/Resources/Racer/CarSpecs/Blaster.prefab"
}
```

## Track Assets

The track is composed of multiple assets that work together:

### 1. Quantum Map Asset
```
Assets/QuantumUser/Resources/QuantumMap.asset
```

The map asset references:
- Physics navigation data
- Static collider geometry
- The main scene to load
- User asset for spawn configuration

### 2. Spawn Config Asset
```
Assets/QuantumUser/Resources/Racer/SpawnMap1.asset
```

Defines race starting parameters:
- Base spawn position
- Grid layout configuration
- Available vehicle references
- Raceline references for AI navigation

### 3. Race Config Asset
```
Assets/QuantumUser/Resources/Racer/BasicRace.asset
```

Controls race parameters:
- Lap count for completion
- Countdown timer duration
- Collision response values
- Respawn behaviors and timers

### 4. Track Tile Prefabs
```
Assets/QuantumUser/Resources/Racer/TrackTiles/
```

Contains modular track pieces:
- Straight sections and curves
- Jumps and ramps
- Modifier trigger zones
- Decoration elements

## Modifier Assets

### 1. Modifier Config Assets
```
Assets/QuantumUser/Resources/Racer/Modifiers/{ModifierName}.asset
```

Each modifier asset defines:
- Effect magnitude and duration
- Visual effects references
- Audio effect references
- Any specific modifier behaviors

Available modifiers include:
- BoosterPatch: Speed and acceleration boost
- OilPatch: Reduced friction
- RoughtPatch: Increased friction
- JumpPad: Vertical launch
- HealthPatch: Energy restoration
- MagnetPatch: Directional force application

### 2. Modifier Prefabs
```
Assets/3rd-party/ModifierPrefabs/{ModifierName}.prefab
```

Visual representation of modifiers including:
- 3D models
- Particle effects
- Trigger colliders
- Visual feedback elements

## Bot/AI Assets

### 1. Bot Config Container
```
Assets/QuantumUser/Resources/Racer/Bots/BotConfigsDefault.asset
```

Contains:
- Array of bot difficulty configurations
- Maximum bot count settings
- Bot nicknames for display
- Bot start delay intervals

### 2. Bot Config Assets
```
Assets/QuantumUser/Resources/Racer/Bots/BotConfig_{Difficulty}.asset
```

Individual bot configurations:
- AI aggressiveness parameters
- Racing line following precision
- Lookahead distance settings
- Speed control behavior

### 3. Checkpoint Data Assets
```
Assets/QuantumUser/Resources/Racer/Bots/Raceline_{TrackName}.asset
```

Contains:
- Sequence of racing line waypoints
- Recommended speeds for each waypoint
- Reference rotation speed values
- Distance between marks for calculations

## Network and Session Assets

### 1. PhotonServerSettings
```
Assets/QuantumUser/Resources/PhotonServerSettings.asset
```

Network configuration including:
- Photon AppID for cloud connection
- Region preferences
- Server connection type
- Default session configuration

### 2. SessionConfig
```
Assets/QuantumUser/Resources/SessionConfig.asset
```

Quantum session parameters:
- Tick rate and update FPS
- Prediction and rollback frame counts
- Input delay configuration
- Snapshot and input send rates
- Player slot allocation

### 3. QuantumDefaultConfigs
```
Assets/QuantumUser/Resources/QuantumDefaultConfigs.asset
```

Core Quantum engine configuration:
- Runtime configuration default
- Dynamic DB definition
- Navigation settings
- Physics parameters

## UI Assets

### 1. Interface Prefabs
```
Assets/QuantumUser/Resources/UI/
```

Contains UI elements for:
- Main menu and lobby interface
- HUD during gameplay
- Race position display
- Lap timer interface
- Vehicle selection interface
- End race scoreboard

### 2. UI Component Assets
```
Assets/QuantumUser/Resources/UI/Components/
```

Reusable UI elements:
- Player nametags
- Minimap display
- Speed indicator
- Energy/health bar
- Item display (if applicable)

## Implementation Notes

When working with Quantum Racer assets:

1. **Entity Prototypes**: Always update both the config asset and entity prototype when changing vehicle parameters
2. **Map Configuration**: When creating a new track, ensure all checkpoint and raceline data are properly linked
3. **Asset References**: Use AssetRef<T> in code to reference proper assets by GUID
4. **Prefab Linking**: Make sure prefabs are correctly referenced in entity prototypes through the View field
5. **Bot Configuration**: Configure bot difficulty through tiered bot config assets
6. **Photon Setup**: Valid AppID must be set in PhotonServerSettings for multiplayer functionality
7. **Asset Dependencies**: Maintain proper references between interdependent assets
8. **Scene References**: Keep track of scene dependencies in the Quantum Map asset
