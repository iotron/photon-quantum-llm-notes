# Bot Behavior Tuning and Customization

## Bot Difficulty Levels

The Quantum Racer game implements different bot difficulty levels through parameter tuning rather than algorithmic changes. This is accomplished by creating multiple `BotConfig` assets with different parameter sets.

### Example Bot Configurations

#### Basic Bot (Easy Difficulty)
```csharp
// Easy difficulty bot
public class BotBasic : BotConfig {
    public BotBasic() {
        MaxSpeed = 7;                             // Lower maximum speed
        RacelineSpeedFactor = FP._0_75;           // Follows raceline at 75% recorded speed
        LookAhead = FP._0_25;                     // Short look-ahead distance
        SmoothLookAhead = false;                  // No smooth interpolation
        RadiansSlowdownThreshold = FP.PiOver3;    // Slows down more in turns
        SlowdownFactor = FP._0_60;                // Significant slowdown in turns
        UseDirectionToNext = false;               // Follows exact raceline positions
    }
}
```

#### Mid-Level Bot (Medium Difficulty)
```csharp
// Medium difficulty bot
public class BotMid : BotConfig {
    public BotMid() {
        MaxSpeed = 9;                             // Moderate maximum speed
        RacelineSpeedFactor = FP._0_85;           // Follows raceline at 85% recorded speed
        LookAhead = FP._0_40;                     // Moderate look-ahead distance
        SmoothLookAhead = true;                   // Uses smooth interpolation for turns
        RadiansSlowdownThreshold = FP.PiOver4;    // Moderate turn slowdown threshold
        SlowdownFactor = FP._0_70;                // Moderate slowdown in turns
        UseDirectionToNext = false;               // Follows raceline positions
    }
}
```

#### Fast Bot (Hard Difficulty)
```csharp
// Hard difficulty bot
public class BotFast : BotConfig {
    public BotFast() {
        MaxSpeed = 12;                            // High maximum speed
        RacelineSpeedFactor = FP._0_95;           // Follows raceline at 95% recorded speed
        LookAhead = FP._0_60;                     // Longer look-ahead distance
        SmoothLookAhead = true;                   // Uses smooth interpolation for turns
        RadiansSlowdownThreshold = FP.PiOver6;    // Only slows on sharp turns
        SlowdownFactor = FP._0_80;                // Minor slowdown in turns
        UseDirectionToNext = true;                // Uses direct line to next point
    }
}
```

## Key Behavioral Parameters

### Speed Control Parameters
| Parameter | Description | Effect |
|-----------|-------------|--------|
| `MaxSpeed` | Base maximum speed | Higher values make bots faster overall |
| `RacelineSpeedFactor` | Speed multiplier relative to recorded raceline | Higher values make bots follow raceline at closer to intended speed |

### Navigation Parameters
| Parameter | Description | Effect |
|-----------|-------------|--------|
| `LookAhead` | Distance to look ahead on raceline | Higher values make bots anticipate turns earlier |
| `SmoothLookAhead` | Whether to interpolate between current and look-ahead points | When true, creates smoother cornering |
| `UseDirectionToNext` | Whether to aim directly at next point | When true, can create more aggressive corner cutting |

### Turn Behavior Parameters
| Parameter | Description | Effect |
|-----------|-------------|--------|
| `RadiansSlowdownThreshold` | Angle at which to start slowing down | Lower values make bots slow down in gentler turns |
| `SlowdownFactor` | Speed multiplier when turning | Lower values create more cautious cornering |

### Collision Avoidance Parameters
| Parameter | Description | Effect |
|-----------|-------------|--------|
| `OverlapRelativeOffset` | Offset to aim for when avoiding cars | Adjusts where bots try to pass other cars |
| `OverlapDistance` | Distance at which to start avoiding cars | Higher values make bots avoid cars from further away |

## Bot Personalities Through Parameter Combinations

Different "personalities" can be created by combining parameter adjustments:

### Aggressive Racer
```csharp
public class BotAggressive : BotConfig {
    public BotAggressive() {
        MaxSpeed = 13;                           // Very high speed
        RacelineSpeedFactor = FP._1_00;          // Full speed on raceline
        RadiansSlowdownThreshold = FP.PiOver8;   // Only slows on very sharp turns
        SlowdownFactor = FP._0_85;               // Minimal slowdown
        OverlapDistance = 2;                     // Close overtaking
    }
}
```

### Defensive Racer
```csharp
public class BotDefensive : BotConfig {
    public BotDefensive() {
        MaxSpeed = 10;                           // Moderate speed
        RacelineSpeedFactor = FP._0_90;          // 90% speed on raceline
        RadiansSlowdownThreshold = FP.PiOver3;   // Slows on gentle turns
        SlowdownFactor = FP._0_65;               // Significant slowdown
        OverlapDistance = 4;                     // Avoids cars from further away
    }
}
```

### Technical Racer
```csharp
public class BotTechnical : BotConfig {
    public BotTechnical() {
        MaxSpeed = 11;                           // Good speed
        RacelineSpeedFactor = FP._0_95;          // 95% speed on raceline
        LookAhead = FP._0_80;                    // Very long look-ahead
        SmoothLookAhead = true;                  // Smooth interpolation
        UseDirectionToNext = false;              // Precise raceline following
    }
}
```

## Raceline Configuration

The quality of bot behavior is heavily influenced by the quality of the recorded racelines. For optimal results:

1. **Multiple Racelines**: Create several different racelines for each track:
   - A central safe line for conservative bots
   - An aggressive line that maximizes corner cutting for fast bots
   - Alternative lines for overtaking

2. **Consistent Speed Recording**: Ensure the speeds recorded in the raceline are consistent and realistic:
   - Record racelines using an experienced player
   - Start recording after lap 1 to ensure the driver is familiar with the track
   - Maintain a consistent driving style throughout the recording session

3. **Appropriate Sampling Density**: Set the `distanceInterval` in the `RacelineRecorder` appropriately:
   - Too large: Insufficient detail on corners
   - Too small: Unnecessarily high memory usage and potentially jerky movement
   - Recommended: 3-5 units for most tracks

## Dynamic Bot Behavior Adjustment

For more advanced implementations, the bot system can be extended to dynamically adjust behavior:

```csharp
// Example of dynamic difficulty scaling
public void UpdateBot(Frame f, ref BotSystem.Filter filter) {
    // Get player's position
    var playerRank = GetPlayerRanking(f);
    
    // Dynamically adjust bot performance based on player position
    if (playerRank == 1) {
        // Player is leading, make bots more challenging
        var dynamicSpeedFactor = FP.Min(FP._1_00, RacelineSpeedFactor + FP._0_10);
        var actualMaxSpeed = MaxSpeed * dynamicSpeedFactor;
        // Apply the adjusted speed...
    }
    else if (playerRank > 3) {
        // Player is behind, make bots slightly easier
        var dynamicSpeedFactor = FP.Max(FP._0_75, RacelineSpeedFactor - FP._0_05);
        var actualMaxSpeed = MaxSpeed * dynamicSpeedFactor;
        // Apply the adjusted speed...
    }
    
    // Continue with normal bot update...
}
```

This rubber-banding technique can help maintain competitive races regardless of player skill level.

## Debug Visualization

The bot system includes debug visualization capabilities that are essential when tuning and testing bot behavior:

```csharp
if (Debug) {
    // Color-code speed status
    ColorRGBA speedColor = ColorRGBA.Green;
    if (maxSpeed / referenceSpeed <= FP._0_50) {
        speedColor = ColorRGBA.Red;  // Significantly below target speed
    }
    else if (maxSpeed / referenceSpeed <= FP._0_75) {
        speedColor = ColorRGBA.Yellow;  // Moderately below target speed
    }
    
    // Draw direction vector
    Draw.Ray(filter.Transform->Position, directionToFollow.Normalized * 5, speedColor);
    
    // Draw reference position
    Draw.Circle(referencePosition, FP._0_25, ColorRGBA.Red);
}
```

This visualization helps identify:
- Where bots are slowing down unnecessarily
- How well they follow the racing line
- How they react to turns and other vehicles
- Potential issues with raceline recording

Enable debug visualization during development and testing, but disable it in release builds for performance reasons.
