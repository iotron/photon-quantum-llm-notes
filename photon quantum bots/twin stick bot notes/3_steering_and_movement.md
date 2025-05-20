# Steering and Movement System

This document explains the steering and movement system used by bots in the twin stick shooter game.

## AISteering Component Overview

The AISteering component manages all movement-related decisions for bots. It combines context steering, NavMesh-based pathfinding, and threat avoidance to create natural-looking movement.

```csharp
public unsafe partial struct AISteering
{
    public bool IsContextSteering => MainSteeringData.Field == SteeringData.STEERINGENTRYCONTEXT;
    public bool IsNavMeshSteering => MainSteeringData.Field == SteeringData.STEERINGENTRYNAVMESH;
    
    public FPVector2 CurrentDirection;
    public FP LerpFactor;
    public FP MainSteeringWeight;
    public SteeringData MainSteeringData;
    
    // Evasion-related properties
    public FP EvasionTimer;
    public FP MaxEvasionDuration;
    public int EvasionDirection;
    public FPVector2 EvasionDirectionVector;
    public bool Debug;
    
    // Methods...
}
```

The component can operate in two primary modes:
1. **Context Steering**: Direct steering towards or away from entities
2. **NavMesh Steering**: Using NavMesh pathfinding for navigation

## Core Movement Logic

### GetDesiredDirection

```csharp
public FPVector2 GetDesiredDirection(Frame frame, EntityRef agent)
{
    // First we process the main steering entry, which is either NavMesh or Context
    FPVector2 desiredDirection = ProcessSteeringEntry(frame, agent, MainSteeringData);

    // Then, we check on the memory the current avoidance stuff and add it to the desired direction
    AIMemory* aiMemory = frame.Unsafe.GetPointer<AIMemory>(agent);
    var memoryEntries = frame.ResolveList(aiMemory->MemoryEntries);
    for (int i = 0; i < memoryEntries.Count; i++)
    {
        if (memoryEntries[i].IsAvailable(frame) == true)
        {
            desiredDirection += ProcessAvoidanceFromMemory(frame, agent, memoryEntries.GetPointer(i));
        }
    }

    return desiredDirection.Normalized;
}
```

This method:
1. First processes the main steering mode (NavMesh or Context)
2. Then adds influences from all memory entries that represent threats to avoid
3. Returns the normalized combined direction

### ProcessSteeringEntry

```csharp
private FPVector2 ProcessSteeringEntry(Frame frame, EntityRef agent, SteeringData steeringData)
{
    FPVector2 desiredDirection;

    switch (steeringData.Field)
    {
        case SteeringData.STEERINGENTRYNAVMESH:
            desiredDirection = ProcessNavMeshEntry(frame, agent, steeringData.SteeringEntryNavMesh);
            break;
        case SteeringData.STEERINGENTRYCONTEXT:
            desiredDirection = ProcessCharacterEntry(frame, agent, steeringData.SteeringEntryContext);
            break;
        default:
            return default(FPVector2);
    }
    return desiredDirection * MainSteeringWeight;
}
```

This method calls the appropriate processing function based on the current steering mode and applies the main steering weight.

## Context Steering System

### ProcessCharacterEntry

```csharp
private FPVector2 ProcessCharacterEntry(Frame frame, EntityRef agent, SteeringEntryContext* entry)
{
    FPVector2 desiredDirection = default;

    FPVector2 agentPosition = frame.Unsafe.GetPointer<Transform2D>(agent)->Position;
    FPVector2 targetPosition = frame.Unsafe.GetPointer<Transform2D>(entry->CharacterRef)->Position;
    FPVector2 dirToTarget = (targetPosition - agentPosition).Normalized;

    FP distToTargetSquared = FPVector2.DistanceSquared(agentPosition, targetPosition);
    if (distToTargetSquared == 0)
        return default;

    FP runDistance = entry->RunDistance;
    FP threatDistance = entry->ThreatDistance;

    bool evasionIsCircular = false;

    if (Debug == true)
    {
        Draw.Circle(targetPosition, runDistance, ColorRGBA.Red.SetA(10));
        Draw.Circle(targetPosition, threatDistance, ColorRGBA.Green.SetA(10));
    }

    // Distance-based behavior selection
    if (distToTargetSquared < runDistance * runDistance)
    {
        // Run away from target if very close
        var hit = frame.Physics2D.Raycast(agentPosition, -dirToTarget, 3, frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics);

        if (Debug == true)
        {
            Draw.Line(agentPosition, agentPosition - dirToTarget * 3);
        }

        if (hit.HasValue == false)
        {
            // Move away from target with force inversely proportional to distance
            FP force = 1 / FPMath.Sqrt(distToTargetSquared);
            desiredDirection -= dirToTarget * force;
        }
        else
        {
            // If we can't move directly away (obstacle), move at an angle
            var angle = (FPHelpers.SignedAngle(-dirToTarget, FPVector2.Right) + 10) * FP.Deg2Rad;
            desiredDirection += new FPVector2(FPMath.Sin(angle), FPMath.Cos(angle));

            if (Debug == true)
            {
                Draw.Line(agentPosition, agentPosition + desiredDirection, ColorRGBA.Green);
            }
        }
    }
    else if (distToTargetSquared < threatDistance * threatDistance)
    {
        // In "threat range" but not too close - use circular evasion
        evasionIsCircular = true;
    }
    else
    {
        // Far away - move slightly toward the target
        desiredDirection += dirToTarget / 30;
    }

    // Add evasion behavior
    HandleEvasion(frame, agent, distToTargetSquared, ref desiredDirection, dirToTarget, evasionIsCircular);

    return desiredDirection;
}
```

This method implements context steering by:
1. Calculating the direction and distance to the target
2. Applying different behaviors based on distance:
   - Run away if too close
   - Circular evasion at medium distance
   - Slight movement toward target at long distance
3. Adding evasion behavior for natural movement

## Evasion System

The evasion system adds randomized movement to make bots feel more lifelike.

### HandleEvasion

```csharp
private void HandleEvasion(Frame frame, EntityRef agent, FP distToTargetSquared, ref FPVector2 desiredDirection, FPVector2 dirToTarget, bool isCircular)
{
    Transform2D* agentTransform = frame.Unsafe.GetPointer<Transform2D>(agent);

    if (EvasionTimer <= 0)
    {
        DefineEvasionDirection(frame, agentTransform, dirToTarget, isCircular);
    }
    else
    {
        PerformEvasion(frame, isCircular, ref desiredDirection, dirToTarget);
    }
}
```

This method either defines a new evasion direction if the timer has expired, or continues performing the current evasion.

### DefineEvasionDirection

```csharp
private void DefineEvasionDirection(Frame frame, Transform2D* agentTransform, FPVector2 dirToTarget, bool isCircular)
{
    EvasionTimer = MaxEvasionDuration;

    if (isCircular == false)
    {
        // We re-balance the random direction based on the previous random dir so we won't repeat the same direction too much
        int randomDir = frame.RNG->NextInclusive(-2, 2) - EvasionDirection;
        if (randomDir <= -1)
        {
            EvasionDirectionVector = agentTransform->Left / 50;
            EvasionDirection = -1;
        }
        else if (randomDir >= 1)
        {
            EvasionDirectionVector = agentTransform->Right / 50;
            EvasionDirection = 1;
        }
        else
        {
            EvasionDirectionVector = default;
            EvasionDirection = 0;
        }

        if(EvasionDirection != 0)
        {
            var hit = frame.Physics2D.Raycast(agentTransform->Position, EvasionDirectionVector, 5, frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics);
            if (Debug == true)
            {
                Draw.Line(agentTransform->Position, agentTransform->Position + EvasionDirectionVector * 5);
            }
            if (hit.HasValue == true)
            {
                EvasionDirectionVector *= -1;
            }
        }
    }
    else
    {
        // When the evasion is circular, we just do a 50/50, because otherwise the Bot would stop moving
        // so we just let it always do zig-zag
        int randomDir = frame.RNG->NextInclusive(0, 1);

        FPVector2 evasionDir = default;
        FP angle = 0;
        if(randomDir == 0)
        {
            angle = (FPHelpers.SignedAngle(dirToTarget, FPVector2.Right) + 5) * FP.Deg2Rad;
        }
        else
        {
            angle = (FPHelpers.SignedAngle(dirToTarget, FPVector2.Left) - 5) * FP.Deg2Rad;
        }
        evasionDir = new FPVector2(FPMath.Sin(angle), FPMath.Cos(angle));

        var hit = frame.Physics2D.Raycast(agentTransform->Position, evasionDir, 4, frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics);
        if (Debug == true)
        {
            Draw.Line(agentTransform->Position, agentTransform->Position + evasionDir * 4);
        }
        if (hit.HasValue == true)
        {
            randomDir = randomDir == 0 ? 1 : 0;
        }

        EvasionDirection = randomDir;
    }
}
```

This method:
1. Resets the evasion timer
2. For linear evasion:
   - Chooses a direction (left, right, or none) with a bias against repeating
   - Checks for obstacles using raycasts and reverses direction if needed
3. For circular evasion:
   - Randomly chooses clockwise or counterclockwise movement
   - Calculates an appropriate angle for zigzag movement
   - Checks for obstacles and switches direction if needed

### PerformEvasion

```csharp
private void PerformEvasion(Frame frame, bool isCircular, ref FPVector2 desiredDirection, FPVector2 dirToTarget)
{
    EvasionTimer -= frame.DeltaTime;

    if (isCircular == false)
    {
        desiredDirection += EvasionDirectionVector;
    }
    else
    {
        FP angle;
        if (EvasionDirection == 0)
        {
            angle = (FPHelpers.SignedAngle(dirToTarget, FPVector2.Right) + 5) * FP.Deg2Rad;
            // Prevents it from spiraling IN the circle
            desiredDirection -= dirToTarget / FP._10;
        }
        else
        {
            angle = (FPHelpers.SignedAngle(dirToTarget, FPVector2.Left) - 5) * FP.Deg2Rad;
            // Prevents it from spiraling OUT of the circle
            desiredDirection += dirToTarget / FP._10;
        }

        desiredDirection += new FPVector2(FPMath.Sin(angle), FPMath.Cos(angle));
    }
}
```

This method:
1. Decrements the evasion timer
2. For linear evasion, simply adds the evasion vector to the desired direction
3. For circular evasion:
   - Applies an angled movement
   - Adds slight radial correction to prevent spiraling

## NavMesh Steering

### ProcessNavMeshEntry

```csharp
private FPVector2 ProcessNavMeshEntry(Frame frame, EntityRef agent, SteeringEntryNavMesh* entry)
{
    // The direction generated for the nav mesh entry is done on the NavMesh callback, that's why
    // we don't need to calculate it here, just retrieve it as is
    return entry->NavMeshDirection;
}
```

This method simply returns the direction calculated by the NavMesh system, which is updated through the `OnNavMeshMoveAgent` callback.

## Threat Avoidance

### ProcessAreaAvoidance

```csharp
private FPVector2 ProcessAreaAvoidance(Frame frame, EntityRef agent, MemoryDataAreaAvoidance* entry)
{
    FPVector2 desiredDirection = default;

    FPVector2 agentPosition = frame.Unsafe.GetPointer<Transform2D>(agent)->Position;
    FPVector2 targetPosition = frame.Unsafe.GetPointer<Transform2D>(entry->Entity)->Position;
    FPVector2 dirToTarget = (targetPosition - agentPosition).Normalized;

    FP distToTargetSquared = FPVector2.DistanceSquared(agentPosition, targetPosition);
    FP runDistance = entry->RunDistance;

    if (Debug == true)
    {
        Draw.Circle(targetPosition, runDistance, ColorRGBA.Red.SetA(10));
    }

    if (distToTargetSquared < runDistance * runDistance)
    {
        var hit = frame.Physics2D.Raycast(agentPosition, -dirToTarget, 3, frame.Layers.GetLayerMask("Static"), QueryOptions.HitStatics);

        if (Debug == true)
        {
            Draw.Line(agentPosition, agentPosition - dirToTarget * 3);
        }

        if (hit.HasValue == false)
        {
            desiredDirection -= dirToTarget;
        }
        else
        {
            var angle = (FPHelpers.SignedAngle(-dirToTarget, FPVector2.Right) + 10) * FP.Deg2Rad;
            desiredDirection += new FPVector2(FPMath.Sin(angle), FPMath.Cos(angle));

            if (Debug == true)
            {
                Draw.Line(agentPosition, agentPosition + desiredDirection, ColorRGBA.Green);
            }
        }
    }

    return desiredDirection * entry->Weight;
}
```

This method creates a repulsion force from threat areas, such as enemy characters or attacks:
1. If the agent is within the run distance of the threat:
   - Try to move directly away from the threat
   - If blocked by an obstacle, move at an angle
2. Return the direction scaled by the threat's weight

### ProcessLineAvoidance

```csharp
private FPVector2 ProcessLineAvoidance(Frame frame, EntityRef agent, MemoryDataLineAvoidance* entry)
{
    FPVector2 runawayDirection = default;

    // Run to the perpendicular direction considering the attack
    Transform2D attackerTransform = frame.Get<Transform2D>(entry->Entity);
    FPVector2 dir = frame.Get<Transform2D>(agent).Position - frame.Get<Transform2D>(entry->Entity).Position;
    runawayDirection.X = attackerTransform.Up.Y;
    runawayDirection.Y = -attackerTransform.Up.X;

    if (FPVector2.RadiansSigned(dir.Normalized, attackerTransform.Up) < 0)
    {
        runawayDirection *= -1;
    }

    runawayDirection *= 2;

    if (Debug == true)
    {
        var agentPos = frame.Get<Transform2D>(agent).Position;
        Draw.Line(agentPos, agentPos + runawayDirection, ColorRGBA.Blue);
    }

    return runawayDirection * entry->Weight;
}
```

This method handles avoidance of linear threats, such as projectiles:
1. Calculates a direction perpendicular to the attack direction
2. Chooses the perpendicular that moves away from the attacker
3. Returns the direction scaled by the threat's weight

## Steering Mode Switching

The AISteering component can switch between context and NavMesh steering:

```csharp
public void SetContextSteeringEntry(Frame frame, EntityRef agentRef, EntityRef characterRef, FP runDistance, FP threatDistance)
{
    MainSteeringData.SteeringEntryContext->SetData(characterRef, runDistance, threatDistance);
}

public void SetNavMeshSteeringEntry(Frame frame, EntityRef agentRef)
{
    // Touch the pointer getter just so it changes the union "type"
    MainSteeringData.SteeringEntryNavMesh->NavMeshDirection = default;
}
```

These methods allow HFSM states to change the steering mode based on the current situation.

## Integration with Movement System

The final steering direction is applied to the bot's Input component by the AISystem:

```csharp
filter.Bot->Input.MoveDirection = filter.AISteering->CurrentDirection;
```

This direction is then used by the standard movement system, which processes bot input just like player input. This ensures consistent movement behavior between bots and players.
