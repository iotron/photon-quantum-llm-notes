# Bot Testing and Validation

This document details the testing and validation approaches used for the bot system in the twin stick shooter game.

## Testing Overview

Testing bot AI behavior is challenging due to:
1. **Emergent behavior**: Unexpected behavior from simple rule combinations
2. **Determinism requirements**: Behavior must be consistent across clients
3. **Performance requirements**: Behavior must meet performance targets
4. **Balance requirements**: Bots must provide appropriate challenge

The twin stick shooter implements a comprehensive testing framework to address these challenges.

## Automated Test Framework

The game includes an automated test framework for bot behavior:

```csharp
public class BotTestFramework : MonoBehaviour
{
    [Header("Test Configuration")]
    public BotTestCase[] TestCases;
    public bool RunTestsOnStart = false;
    public bool AutomaticTestExecution = false;
    
    [Header("Recording")]
    public bool RecordTests = false;
    public string RecordingPath = "Assets/Tests/BotRecordings";
    
    private QuantumRunner _runner;
    private List<BotTestCase> _currentTests = new List<BotTestCase>();
    private Dictionary<BotTestCase, BotTestResult> _testResults = new Dictionary<BotTestCase, BotTestResult>();
    
    private void Start()
    {
        if (RunTestsOnStart)
        {
            StartCoroutine(RunAllTests());
        }
    }
    
    public IEnumerator RunAllTests()
    {
        Debug.Log("Starting bot test suite...");
        
        foreach (var testCase in TestCases)
        {
            yield return StartCoroutine(RunTestCase(testCase));
        }
        
        Debug.Log("Test suite completed.");
        GenerateTestReport();
    }
    
    public IEnumerator RunTestCase(BotTestCase testCase)
    {
        Debug.Log($"Running test: {testCase.TestName}");
        
        // Initialize quantum runner with test settings
        _runner = QuantumRunner.StartGame(testCase.MapGuid, testCase.GameMode, null);
        
        // Add test to current tests
        _currentTests.Add(testCase);
        
        // Setup test environment
        yield return StartCoroutine(SetupTestEnvironment(testCase));
        
        // Run test for specified duration
        float startTime = Time.time;
        while (Time.time - startTime < testCase.TestDuration)
        {
            if (testCase.TerminationCondition != null && testCase.TerminationCondition.CheckCondition(_runner.Game.Frames.Verified))
            {
                Debug.Log($"Test {testCase.TestName} terminated early due to termination condition.");
                break;
            }
            
            yield return null;
        }
        
        // Collect and evaluate results
        BotTestResult result = EvaluateTestResults(testCase);
        _testResults[testCase] = result;
        
        // Record test if enabled
        if (RecordTests)
        {
            RecordTestResults(testCase, result);
        }
        
        // Clean up
        _runner.Shutdown();
        _currentTests.Remove(testCase);
        
        Debug.Log($"Test {testCase.TestName} completed with result: {result.Success}");
        
        yield return null;
    }
    
    private IEnumerator SetupTestEnvironment(BotTestCase testCase)
    {
        // Wait for game to initialize
        while (_runner.Game == null || _runner.Game.Frames.Verified == null)
        {
            yield return null;
        }
        
        var frame = _runner.Game.Frames.Verified;
        
        // Create bots according to test configuration
        foreach (var botConfig in testCase.BotConfigurations)
        {
            EntityRef botEntity = CreateBot(frame, botConfig);
            
            // Add bot entity to test case for tracking
            testCase.BotEntities.Add(botEntity);
        }
        
        // Create test entities if needed
        foreach (var entityConfig in testCase.TestEntityConfigurations)
        {
            EntityRef entity = CreateTestEntity(frame, entityConfig);
            
            // Add entity to test case for tracking
            testCase.TestEntities.Add(entity);
        }
        
        // Allow a few frames for initialization
        for (int i = 0; i < 10; i++)
        {
            yield return null;
        }
    }
    
    private EntityRef CreateBot(Frame frame, BotConfiguration botConfig)
    {
        // Create bot based on configuration
        EntityRef botEntity = default;
        
        switch (botConfig.BotType)
        {
            case BotType.Archer:
                botEntity = BotCreator.CreateArcherBot(frame, botConfig.Position, botConfig.TeamId, botConfig.DifficultyLevel);
                break;
            case BotType.Melee:
                botEntity = BotCreator.CreateMeleeBot(frame, botConfig.Position, botConfig.TeamId, botConfig.DifficultyLevel);
                break;
            case BotType.Tank:
                botEntity = BotCreator.CreateTankBot(frame, botConfig.Position, botConfig.TeamId, botConfig.DifficultyLevel);
                break;
            // Other bot types...
        }
        
        return botEntity;
    }
    
    private EntityRef CreateTestEntity(Frame frame, TestEntityConfiguration entityConfig)
    {
        // Create test entity based on configuration
        EntityRef entity = default;
        
        switch (entityConfig.EntityType)
        {
            case TestEntityType.Target:
                entity = frame.Create(frame.FindAsset<EntityPrototype>("TargetDummy"));
                frame.Unsafe.GetPointer<Transform2D>(entity)->Position = entityConfig.Position;
                break;
            case TestEntityType.Obstacle:
                entity = frame.Create(frame.FindAsset<EntityPrototype>("Obstacle"));
                frame.Unsafe.GetPointer<Transform2D>(entity)->Position = entityConfig.Position;
                break;
            case TestEntityType.Collectible:
                entity = frame.Create(frame.FindAsset<EntityPrototype>("Collectible"));
                frame.Unsafe.GetPointer<Transform2D>(entity)->Position = entityConfig.Position;
                break;
            // Other entity types...
        }
        
        return entity;
    }
    
    private BotTestResult EvaluateTestResults(BotTestCase testCase)
    {
        BotTestResult result = new BotTestResult();
        result.TestCase = testCase;
        result.ExecutionTime = Time.time;
        
        var frame = _runner.Game.Frames.Verified;
        
        // Evaluate test conditions
        bool allConditionsMet = true;
        foreach (var condition in testCase.TestConditions)
        {
            bool conditionResult = condition.EvaluateCondition(frame, testCase.BotEntities);
            result.ConditionResults[condition] = conditionResult;
            
            if (!conditionResult)
            {
                allConditionsMet = false;
            }
        }
        
        result.Success = allConditionsMet;
        
        // Collect performance metrics
        result.PerformanceMetrics = CollectPerformanceMetrics();
        
        return result;
    }
    
    private BotPerformanceMetrics CollectPerformanceMetrics()
    {
        BotPerformanceMetrics metrics = new BotPerformanceMetrics();
        
        var frame = _runner.Game.Frames.Verified;
        
        // Count active bots
        int activeBotCount = 0;
        int totalPathLength = 0;
        int pathfindingCount = 0;
        
        var bots = frame.Filter<Bot>();
        while (bots.Next(out EntityRef entity, out Bot bot))
        {
            if (bot.IsActive == false)
                continue;
            
            activeBotCount++;
            
            if (frame.Has<NavMeshPathfinder>(entity))
            {
                var pathfinder = frame.Get<NavMeshPathfinder>(entity);
                if (pathfinder.Path.Pointer != null)
                {
                    totalPathLength += frame.ResolveList(pathfinder.Path).Count;
                    pathfindingCount++;
                }
            }
        }
        
        metrics.ActiveBotCount = activeBotCount;
        metrics.AveragePathLength = pathfindingCount > 0 ? (float)totalPathLength / pathfindingCount : 0;
        metrics.FrameRate = 1.0f / Time.deltaTime;
        
        return metrics;
    }
    
    private void RecordTestResults(BotTestCase testCase, BotTestResult result)
    {
        string filename = $"{testCase.TestName}_{System.DateTime.Now.ToString("yyyyMMdd_HHmmss")}.json";
        string path = Path.Combine(RecordingPath, filename);
        
        // Create directory if it doesn't exist
        if (!Directory.Exists(RecordingPath))
        {
            Directory.CreateDirectory(RecordingPath);
        }
        
        // Create serializable result
        BotTestResultData resultData = new BotTestResultData
        {
            TestName = testCase.TestName,
            ExecutionTime = result.ExecutionTime,
            Success = result.Success,
            ConditionResults = result.ConditionResults.ToDictionary(
                kvp => kvp.Key.ConditionName,
                kvp => kvp.Value
            ),
            PerformanceMetrics = new BotPerformanceMetricsData
            {
                ActiveBotCount = result.PerformanceMetrics.ActiveBotCount,
                AveragePathLength = result.PerformanceMetrics.AveragePathLength,
                FrameRate = result.PerformanceMetrics.FrameRate
            }
        };
        
        // Serialize to JSON
        string json = JsonUtility.ToJson(resultData, true);
        
        // Write to file
        File.WriteAllText(path, json);
        
        Debug.Log($"Test results recorded to {path}");
    }
    
    private void GenerateTestReport()
    {
        string reportPath = Path.Combine(RecordingPath, $"TestReport_{System.DateTime.Now.ToString("yyyyMMdd_HHmmss")}.html");
        
        StringBuilder report = new StringBuilder();
        report.AppendLine("<html><head><title>Bot Test Report</title>");
        report.AppendLine("<style>");
        report.AppendLine("body { font-family: Arial, sans-serif; margin: 20px; }");
        report.AppendLine("h1 { color: #333; }");
        report.AppendLine("table { border-collapse: collapse; width: 100%; }");
        report.AppendLine("th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }");
        report.AppendLine("th { background-color: #f2f2f2; }");
        report.AppendLine(".success { color: green; }");
        report.AppendLine(".failure { color: red; }");
        report.AppendLine("</style></head><body>");
        
        report.AppendLine("<h1>Bot Test Report</h1>");
        report.AppendLine($"<p>Generated on: {System.DateTime.Now}</p>");
        
        report.AppendLine("<h2>Test Results</h2>");
        report.AppendLine("<table>");
        report.AppendLine("<tr><th>Test Name</th><th>Result</th><th>Performance</th><th>Failed Conditions</th></tr>");
        
        foreach (var kvp in _testResults)
        {
            var testCase = kvp.Key;
            var result = kvp.Value;
            
            report.AppendLine("<tr>");
            report.AppendLine($"<td>{testCase.TestName}</td>");
            
            if (result.Success)
            {
                report.AppendLine("<td class='success'>PASS</td>");
            }
            else
            {
                report.AppendLine("<td class='failure'>FAIL</td>");
            }
            
            report.AppendLine($"<td>FPS: {result.PerformanceMetrics.FrameRate:F1}, Bots: {result.PerformanceMetrics.ActiveBotCount}</td>");
            
            // List failed conditions
            StringBuilder failedConditions = new StringBuilder();
            foreach (var condition in result.ConditionResults)
            {
                if (!condition.Value)
                {
                    failedConditions.AppendLine(condition.Key.ConditionName + "<br>");
                }
            }
            
            report.AppendLine($"<td>{failedConditions}</td>");
            report.AppendLine("</tr>");
        }
        
        report.AppendLine("</table>");
        
        // Add performance section
        report.AppendLine("<h2>Performance Summary</h2>");
        report.AppendLine("<table>");
        report.AppendLine("<tr><th>Metric</th><th>Average</th><th>Min</th><th>Max</th></tr>");
        
        float avgFrameRate = _testResults.Values.Average(r => r.PerformanceMetrics.FrameRate);
        float minFrameRate = _testResults.Values.Min(r => r.PerformanceMetrics.FrameRate);
        float maxFrameRate = _testResults.Values.Max(r => r.PerformanceMetrics.FrameRate);
        
        report.AppendLine("<tr>");
        report.AppendLine("<td>Frame Rate</td>");
        report.AppendLine($"<td>{avgFrameRate:F1}</td>");
        report.AppendLine($"<td>{minFrameRate:F1}</td>");
        report.AppendLine($"<td>{maxFrameRate:F1}</td>");
        report.AppendLine("</tr>");
        
        float avgPathLength = _testResults.Values.Average(r => r.PerformanceMetrics.AveragePathLength);
        float minPathLength = _testResults.Values.Min(r => r.PerformanceMetrics.AveragePathLength);
        float maxPathLength = _testResults.Values.Max(r => r.PerformanceMetrics.AveragePathLength);
        
        report.AppendLine("<tr>");
        report.AppendLine("<td>Average Path Length</td>");
        report.AppendLine($"<td>{avgPathLength:F1}</td>");
        report.AppendLine($"<td>{minPathLength:F1}</td>");
        report.AppendLine($"<td>{maxPathLength:F1}</td>");
        report.AppendLine("</tr>");
        
        report.AppendLine("</table>");
        
        report.AppendLine("</body></html>");
        
        File.WriteAllText(reportPath, report.ToString());
        
        Debug.Log($"Test report generated at {reportPath}");
    }
}
```

## Test Cases and Conditions

Test cases define specific scenarios to verify bot behavior:

```csharp
[System.Serializable]
public class BotTestCase
{
    public string TestName;
    public string Description;
    public AssetGuid MapGuid;
    public string GameMode;
    public float TestDuration = 30.0f;
    
    public BotConfiguration[] BotConfigurations;
    public TestEntityConfiguration[] TestEntityConfigurations;
    public BotTestCondition[] TestConditions;
    public BotTestTerminationCondition TerminationCondition;
    
    [HideInInspector]
    public List<EntityRef> BotEntities = new List<EntityRef>();
    [HideInInspector]
    public List<EntityRef> TestEntities = new List<EntityRef>();
}

[System.Serializable]
public class BotConfiguration
{
    public BotType BotType;
    public FPVector2 Position;
    public int TeamId;
    public int DifficultyLevel;
}

[System.Serializable]
public class TestEntityConfiguration
{
    public TestEntityType EntityType;
    public FPVector2 Position;
}

[System.Serializable]
public abstract class BotTestCondition
{
    public string ConditionName;
    
    public abstract bool EvaluateCondition(Frame frame, List<EntityRef> botEntities);
}

[System.Serializable]
public abstract class BotTestTerminationCondition
{
    public abstract bool CheckCondition(Frame frame);
}
```

### Example Test Conditions

```csharp
// Test if bot reaches target position
[System.Serializable]
public class ReachPositionCondition : BotTestCondition
{
    public FPVector2 TargetPosition;
    public FP MaxDistance = FP._1;
    public float TimeLimit = 10.0f;
    
    private float _startTime;
    private bool _hasStarted = false;
    
    public override bool EvaluateCondition(Frame frame, List<EntityRef> botEntities)
    {
        if (!_hasStarted)
        {
            _startTime = Time.time;
            _hasStarted = true;
        }
        
        // Check if time limit has been exceeded
        if (Time.time - _startTime > TimeLimit)
        {
            return false;
        }
        
        // Check if any bot has reached the target position
        foreach (var botEntity in botEntities)
        {
            if (!frame.Exists(botEntity) || !frame.Has<Transform2D>(botEntity))
                continue;
            
            FPVector2 botPosition = frame.Get<Transform2D>(botEntity).Position;
            FP distanceSquared = FPVector2.DistanceSquared(botPosition, TargetPosition);
            
            if (distanceSquared <= MaxDistance * MaxDistance)
            {
                return true;
            }
        }
        
        return false;
    }
}

// Test if bot defeats target
[System.Serializable]
public class DefeatTargetCondition : BotTestCondition
{
    public int TargetEntityIndex; // Index in TestEntities
    public float TimeLimit = 15.0f;
    
    private float _startTime;
    private bool _hasStarted = false;
    
    public override bool EvaluateCondition(Frame frame, List<EntityRef> botEntities)
    {
        if (!_hasStarted)
        {
            _startTime = Time.time;
            _hasStarted = true;
        }
        
        // Check if time limit has been exceeded
        if (Time.time - _startTime > TimeLimit)
        {
            return false;
        }
        
        // Get target entity
        if (TargetEntityIndex < 0 || TargetEntityIndex >= TestCase.TestEntities.Count)
            return false;
            
        EntityRef targetEntity = TestCase.TestEntities[TargetEntityIndex];
        
        // Check if target is defeated (has Health and IsDead)
        if (frame.Exists(targetEntity) && frame.Has<Health>(targetEntity))
        {
            Health health = frame.Get<Health>(targetEntity);
            return health.IsDead;
        }
        
        return false;
    }
}

// Test if bot uses a specific ability
[System.Serializable]
public class UseAbilityCondition : BotTestCondition
{
    public string AbilityName;
    public float TimeLimit = 10.0f;
    
    private float _startTime;
    private bool _hasStarted = false;
    private bool _abilityUsed = false;
    
    public override bool EvaluateCondition(Frame frame, List<EntityRef> botEntities)
    {
        if (!_hasStarted)
        {
            _startTime = Time.time;
            _hasStarted = true;
            
            // Register event listener for ability use
            frame.Events.OnAbilityUsed += OnAbilityUsed;
        }
        
        // Check if time limit has been exceeded
        if (Time.time - _startTime > TimeLimit)
        {
            // Unregister event listener
            frame.Events.OnAbilityUsed -= OnAbilityUsed;
            return _abilityUsed;
        }
        
        return _abilityUsed;
    }
    
    private void OnAbilityUsed(Frame frame, EntityRef entity, string abilityName)
    {
        // Check if this ability was used by one of our bots
        if (TestCase.BotEntities.Contains(entity) && abilityName == AbilityName)
        {
            _abilityUsed = true;
            
            // Unregister event listener
            frame.Events.OnAbilityUsed -= OnAbilityUsed;
        }
    }
}

// Test if bot maintains minimum distance from target
[System.Serializable]
public class MaintainDistanceCondition : BotTestCondition
{
    public int TargetEntityIndex; // Index in TestEntities
    public FP MinDistance = FP._5;
    public float TimeLimit = 10.0f;
    public float RequiredPercentage = 0.8f; // Bot must maintain distance for 80% of the time
    
    private float _startTime;
    private bool _hasStarted = false;
    private float _totalTime = 0.0f;
    private float _validTime = 0.0f;
    
    public override bool EvaluateCondition(Frame frame, List<EntityRef> botEntities)
    {
        if (!_hasStarted)
        {
            _startTime = Time.time;
            _hasStarted = true;
        }
        
        // Update times
        float currentTime = Time.time;
        float deltaTime = currentTime - (_startTime + _totalTime);
        _totalTime += deltaTime;
        
        // Check if time limit has been exceeded
        if (_totalTime >= TimeLimit)
        {
            return _validTime / _totalTime >= RequiredPercentage;
        }
        
        // Get target entity
        if (TargetEntityIndex < 0 || TargetEntityIndex >= TestCase.TestEntities.Count)
            return false;
            
        EntityRef targetEntity = TestCase.TestEntities[TargetEntityIndex];
        
        if (!frame.Exists(targetEntity) || !frame.Has<Transform2D>(targetEntity))
            return false;
        
        FPVector2 targetPosition = frame.Get<Transform2D>(targetEntity).Position;
        
        // Check if bots maintain distance
        bool allBotsValid = true;
        foreach (var botEntity in botEntities)
        {
            if (!frame.Exists(botEntity) || !frame.Has<Transform2D>(botEntity))
            {
                allBotsValid = false;
                break;
            }
            
            FPVector2 botPosition = frame.Get<Transform2D>(botEntity).Position;
            FP distanceSquared = FPVector2.DistanceSquared(botPosition, targetPosition);
            
            if (distanceSquared < MinDistance * MinDistance)
            {
                allBotsValid = false;
                break;
            }
        }
        
        if (allBotsValid)
        {
            _validTime += deltaTime;
        }
        
        return _validTime / _totalTime >= RequiredPercentage;
    }
}
```

## Test Results

The test framework collects detailed results:

```csharp
public class BotTestResult
{
    public BotTestCase TestCase;
    public float ExecutionTime;
    public bool Success;
    public Dictionary<BotTestCondition, bool> ConditionResults = new Dictionary<BotTestCondition, bool>();
    public BotPerformanceMetrics PerformanceMetrics;
}

public class BotPerformanceMetrics
{
    public int ActiveBotCount;
    public float AveragePathLength;
    public float FrameRate;
    // Other metrics...
}

// Serializable versions for JSON storage
[System.Serializable]
public class BotTestResultData
{
    public string TestName;
    public float ExecutionTime;
    public bool Success;
    public Dictionary<string, bool> ConditionResults;
    public BotPerformanceMetricsData PerformanceMetrics;
}

[System.Serializable]
public class BotPerformanceMetricsData
{
    public int ActiveBotCount;
    public float AveragePathLength;
    public float FrameRate;
    // Other metrics...
}
```

## Example Test Scenarios

### Basic Movement Test

```csharp
[CreateAssetMenu(menuName = "Quantum/Tests/MovementTest")]
public class MovementTestCase : BotTestCase
{
    public void OnEnable()
    {
        TestName = "Basic Movement Test";
        Description = "Tests if bot can navigate to a target position using pathfinding";
        TestDuration = 15.0f;
        
        // Configure test
        BotConfigurations = new BotConfiguration[]
        {
            new BotConfiguration
            {
                BotType = BotType.Archer,
                Position = new FPVector2(FP._0, FP._0),
                TeamId = 0,
                DifficultyLevel = 1
            }
        };
        
        // Define target position
        FPVector2 targetPosition = new FPVector2(FP._10, FP._10);
        
        // Add test entities
        TestEntityConfigurations = new TestEntityConfiguration[]
        {
            new TestEntityConfiguration
            {
                EntityType = TestEntityType.Target,
                Position = targetPosition
            }
        };
        
        // Define test conditions
        TestConditions = new BotTestCondition[]
        {
            new ReachPositionCondition
            {
                ConditionName = "Reach Target Position",
                TargetPosition = targetPosition,
                MaxDistance = FP._1,
                TimeLimit = 10.0f
            }
        };
        
        // Define termination condition
        TerminationCondition = new TimeBasedTermination
        {
            TimeLimit = 15.0f
        };
    }
}
```

### Combat Test

```csharp
[CreateAssetMenu(menuName = "Quantum/Tests/ArcherCombatTest")]
public class ArcherCombatTestCase : BotTestCase
{
    public void OnEnable()
    {
        TestName = "Archer Combat Test";
        Description = "Tests if archer bot maintains proper distance and defeats target";
        TestDuration = 30.0f;
        
        // Configure test
        BotConfigurations = new BotConfiguration[]
        {
            new BotConfiguration
            {
                BotType = BotType.Archer,
                Position = new FPVector2(FP._0, FP._0),
                TeamId = 0,
                DifficultyLevel = 2
            }
        };
        
        // Add test entities
        TestEntityConfigurations = new TestEntityConfiguration[]
        {
            new TestEntityConfiguration
            {
                EntityType = TestEntityType.Target,
                Position = new FPVector2(FP._10, FP._10)
            }
        };
        
        // Define test conditions
        TestConditions = new BotTestCondition[]
        {
            new MaintainDistanceCondition
            {
                ConditionName = "Maintain Optimal Distance",
                TargetEntityIndex = 0,
                MinDistance = FP._5,
                TimeLimit = 20.0f,
                RequiredPercentage = 0.7f
            },
            new UseAbilityCondition
            {
                ConditionName = "Use Special Attack",
                AbilityName = "ArcherSpecialAttack",
                TimeLimit = 25.0f
            },
            new DefeatTargetCondition
            {
                ConditionName = "Defeat Target",
                TargetEntityIndex = 0,
                TimeLimit = 30.0f
            }
        };
        
        // Define termination condition
        TerminationCondition = new EntityDeathTermination
        {
            EntityIndex = 0,
            IsTestEntity = true
        };
    }
}
```

### Team Coordination Test

```csharp
[CreateAssetMenu(menuName = "Quantum/Tests/TeamCoordinationTest")]
public class TeamCoordinationTestCase : BotTestCase
{
    public void OnEnable()
    {
        TestName = "Team Coordination Test";
        Description = "Tests if bots can coordinate attacks on targets";
        TestDuration = 45.0f;
        
        // Configure test
        BotConfigurations = new BotConfiguration[]
        {
            new BotConfiguration
            {
                BotType = BotType.Archer,
                Position = new FPVector2(FP._0, FP._0),
                TeamId = 0,
                DifficultyLevel = 2
            },
            new BotConfiguration
            {
                BotType = BotType.Melee,
                Position = new FPVector2(FP._2, FP._0),
                TeamId = 0,
                DifficultyLevel = 2
            }
        };
        
        // Add test entities
        TestEntityConfigurations = new TestEntityConfiguration[]
        {
            new TestEntityConfiguration
            {
                EntityType = TestEntityType.Target,
                Position = new FPVector2(FP._10, FP._10)
            },
            new TestEntityConfiguration
            {
                EntityType = TestEntityType.Obstacle,
                Position = new FPVector2(FP._5, FP._5)
            }
        };
        
        // Define test conditions
        TestConditions = new BotTestCondition[]
        {
            new RoleDivisionCondition
            {
                ConditionName = "Proper Role Division",
                MeleeBotIndex = 1,
                ArcherBotIndex = 0,
                TargetEntityIndex = 0,
                TimeLimit = 30.0f
            },
            new DefeatTargetCondition
            {
                ConditionName = "Defeat Target",
                TargetEntityIndex = 0,
                TimeLimit = 45.0f
            }
        };
        
        // Define termination condition
        TerminationCondition = new EntityDeathTermination
        {
            EntityIndex = 0,
            IsTestEntity = true
        };
    }
}

// Custom condition to test role division
public class RoleDivisionCondition : BotTestCondition
{
    public int MeleeBotIndex;
    public int ArcherBotIndex;
    public int TargetEntityIndex;
    public float TimeLimit = 30.0f;
    public FP ExpectedMeleeDistance = FP._2;
    public FP ExpectedArcherDistance = FP._8;
    public float RequiredPercentage = 0.6f;
    
    private float _startTime;
    private bool _hasStarted = false;
    private float _totalTime = 0.0f;
    private float _validTime = 0.0f;
    
    public override bool EvaluateCondition(Frame frame, List<EntityRef> botEntities)
    {
        if (!_hasStarted)
        {
            _startTime = Time.time;
            _hasStarted = true;
        }
        
        // Update times
        float currentTime = Time.time;
        float deltaTime = currentTime - (_startTime + _totalTime);
        _totalTime += deltaTime;
        
        // Check if time limit has been exceeded
        if (_totalTime >= TimeLimit)
        {
            return _validTime / _totalTime >= RequiredPercentage;
        }
        
        // Get entities
        if (MeleeBotIndex < 0 || MeleeBotIndex >= botEntities.Count ||
            ArcherBotIndex < 0 || ArcherBotIndex >= botEntities.Count ||
            TargetEntityIndex < 0 || TargetEntityIndex >= TestCase.TestEntities.Count)
            return false;
            
        EntityRef meleeBot = botEntities[MeleeBotIndex];
        EntityRef archerBot = botEntities[ArcherBotIndex];
        EntityRef targetEntity = TestCase.TestEntities[TargetEntityIndex];
        
        if (!frame.Exists(meleeBot) || !frame.Has<Transform2D>(meleeBot) ||
            !frame.Exists(archerBot) || !frame.Has<Transform2D>(archerBot) ||
            !frame.Exists(targetEntity) || !frame.Has<Transform2D>(targetEntity))
            return false;
        
        // Get positions
        FPVector2 meleePosition = frame.Get<Transform2D>(meleeBot).Position;
        FPVector2 archerPosition = frame.Get<Transform2D>(archerBot).Position;
        FPVector2 targetPosition = frame.Get<Transform2D>(targetEntity).Position;
        
        // Calculate distances
        FP meleeDistanceSquared = FPVector2.DistanceSquared(meleePosition, targetPosition);
        FP archerDistanceSquared = FPVector2.DistanceSquared(archerPosition, targetPosition);
        
        // Check if roles are properly maintained
        bool rolesValid = 
            meleeDistanceSquared <= ExpectedMeleeDistance * ExpectedMeleeDistance * FP._2 && // Melee is close
            archerDistanceSquared >= ExpectedArcherDistance * ExpectedArcherDistance * FP._0_5; // Archer is far
        
        if (rolesValid)
        {
            _validTime += deltaTime;
        }
        
        return _validTime / _totalTime >= RequiredPercentage;
    }
}
```

## Continuous Integration

The bot testing framework integrates with CI/CD pipelines:

```csharp
public class BotTestCI : MonoBehaviour
{
    [Header("CI Configuration")]
    public string TestResultsPath = "TestResults";
    public bool RunOnCI = true;
    public bool ExitOnCompletion = true;
    
    [Header("Test Cases")]
    public BotTestCase[] TestCases;
    
    private BotTestFramework _testFramework;
    
    private void Start()
    {
        if (RunOnCI && IsCIEnvironment())
        {
            // Configure test framework
            _testFramework = gameObject.AddComponent<BotTestFramework>();
            _testFramework.TestCases = TestCases;
            _testFramework.RecordTests = true;
            _testFramework.RecordingPath = TestResultsPath;
            
            // Run tests
            StartCoroutine(RunTests());
        }
    }
    
    private IEnumerator RunTests()
    {
        yield return StartCoroutine(_testFramework.RunAllTests());
        
        // Generate summary for CI
        GenerateCISummary();
        
        // Exit with appropriate code
        if (ExitOnCompletion)
        {
            bool allTestsPassed = true;
            
            foreach (var result in _testFramework.GetTestResults())
            {
                if (!result.Value.Success)
                {
                    allTestsPassed = false;
                    break;
                }
            }
            
            #if UNITY_EDITOR
            UnityEditor.EditorApplication.isPlaying = false;
            #else
            Application.Quit(allTestsPassed ? 0 : 1);
            #endif
        }
    }
    
    private void GenerateCISummary()
    {
        string summaryPath = Path.Combine(TestResultsPath, "summary.json");
        
        var summary = new Dictionary<string, bool>();
        
        foreach (var result in _testFramework.GetTestResults())
        {
            summary[result.Key.TestName] = result.Value.Success;
        }
        
        string json = JsonUtility.ToJson(new { TestResults = summary }, true);
        File.WriteAllText(summaryPath, json);
    }
    
    private bool IsCIEnvironment()
    {
        // Check for common CI environment variables
        return !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("CI")) ||
               !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GITHUB_ACTIONS")) ||
               !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("JENKINS_URL")) ||
               !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("TRAVIS")) ||
               !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("CIRCLECI"));
    }
}
```

## Replaying and Analyzing Test Results

The twin stick shooter includes tools for replaying and analyzing test results:

```csharp
public class BotTestAnalyzer : MonoBehaviour
{
    [Header("Test Analysis")]
    public string TestResultsPath = "Assets/Tests/BotRecordings";
    public string TestToAnalyze;
    
    [Header("Visualization")]
    public bool ShowPaths = true;
    public bool ShowTargeting = true;
    public bool ShowAttacks = true;
    
    private BotTestResultData _testResult;
    private QuantumRunner _runner;
    private Dictionary<int, LineRenderer> _pathVisualizers = new Dictionary<int, LineRenderer>();
    private Dictionary<int, LineRenderer> _targetingVisualizers = new Dictionary<int, LineRenderer>();
    
    public void LoadTest(string testName)
    {
        string[] files = Directory.GetFiles(TestResultsPath, $"{testName}_*.json");
        
        if (files.Length == 0)
        {
            Debug.LogError($"No test results found for test: {testName}");
            return;
        }
        
        // Load the most recent test result
        string mostRecentFile = files.OrderByDescending(f => File.GetLastWriteTime(f)).First();
        string json = File.ReadAllText(mostRecentFile);
        
        _testResult = JsonUtility.FromJson<BotTestResultData>(json);
        
        // Load the test case
        BotTestCase testCase = Resources.Load<BotTestCase>($"TestCases/{testName}");
        
        if (testCase == null)
        {
            Debug.LogError($"Test case not found: {testName}");
            return;
        }
        
        // Initialize quantum runner with test settings
        _runner = QuantumRunner.StartGame(testCase.MapGuid, testCase.GameMode, null);
        
        StartCoroutine(SetupTest(testCase));
    }
    
    private IEnumerator SetupTest(BotTestCase testCase)
    {
        // Wait for game to initialize
        while (_runner.Game == null || _runner.Game.Frames.Verified == null)
        {
            yield return null;
        }
        
        var frame = _runner.Game.Frames.Verified;
        
        // Create bots and test entities
        foreach (var botConfig in testCase.BotConfigurations)
        {
            EntityRef botEntity = CreateBot(frame, botConfig);
            testCase.BotEntities.Add(botEntity);
            
            // Create visualizers
            CreateVisualizers(botEntity.Id);
        }
        
        foreach (var entityConfig in testCase.TestEntityConfigurations)
        {
            EntityRef entity = CreateTestEntity(frame, entityConfig);
            testCase.TestEntities.Add(entity);
        }
        
        Debug.Log($"Test setup complete: {testCase.TestName}");
    }
    
    private void CreateVisualizers(int entityId)
    {
        if (ShowPaths)
        {
            GameObject pathObj = new GameObject($"Path_{entityId}");
            LineRenderer pathLine = pathObj.AddComponent<LineRenderer>();
            pathLine.startWidth = 0.1f;
            pathLine.endWidth = 0.1f;
            pathLine.material = new Material(Shader.Find("Sprites/Default"));
            pathLine.startColor = Color.blue;
            pathLine.endColor = Color.blue;
            
            _pathVisualizers[entityId] = pathLine;
        }
        
        if (ShowTargeting)
        {
            GameObject targetObj = new GameObject($"Target_{entityId}");
            LineRenderer targetLine = targetObj.AddComponent<LineRenderer>();
            targetLine.startWidth = 0.1f;
            targetLine.endWidth = 0.1f;
            targetLine.material = new Material(Shader.Find("Sprites/Default"));
            targetLine.startColor = Color.red;
            targetLine.endColor = Color.red;
            
            _targetingVisualizers[entityId] = targetLine;
        }
    }
    
    private void Update()
    {
        if (_runner == null || _runner.Game == null || _runner.Game.Frames.Verified == null)
            return;
        
        var frame = _runner.Game.Frames.Verified;
        
        // Update visualizers
        var bots = frame.Filter<Bot, Transform2D>();
        while (bots.Next(out EntityRef entity, out Bot bot, out Transform2D transform))
        {
            // Update path visualizer
            if (ShowPaths && _pathVisualizers.TryGetValue(entity.Id, out LineRenderer pathLine))
            {
                if (frame.Has<NavMeshPathfinder>(entity))
                {
                    var pathfinder = frame.Get<NavMeshPathfinder>(entity);
                    if (pathfinder.Path.Pointer != null)
                    {
                        var path = frame.ResolveList(pathfinder.Path);
                        
                        Vector3[] positions = new Vector3[path.Count + 1];
                        positions[0] = transform.Position.ToUnityVector3();
                        
                        for (int i = 0; i < path.Count; i++)
                        {
                            positions[i + 1] = path[i].Position.ToUnityVector3();
                        }
                        
                        pathLine.positionCount = positions.Length;
                        pathLine.SetPositions(positions);
                    }
                    else
                    {
                        pathLine.positionCount = 0;
                    }
                }
            }
            
            // Update targeting visualizer
            if (ShowTargeting && _targetingVisualizers.TryGetValue(entity.Id, out LineRenderer targetLine))
            {
                if (frame.Has<AIBlackboardComponent>(entity))
                {
                    var blackboard = frame.Get<AIBlackboardComponent>(entity);
                    
                    if (blackboard.Has("TargetEntity"))
                    {
                        EntityRef targetEntity = blackboard.Get<EntityRef>("TargetEntity");
                        
                        if (frame.Exists(targetEntity) && frame.Has<Transform2D>(targetEntity))
                        {
                            Vector3 botPosition = transform.Position.ToUnityVector3();
                            Vector3 targetPosition = frame.Get<Transform2D>(targetEntity).Position.ToUnityVector3();
                            
                            targetLine.positionCount = 2;
                            targetLine.SetPosition(0, botPosition);
                            targetLine.SetPosition(1, targetPosition);
                        }
                        else
                        {
                            targetLine.positionCount = 0;
                        }
                    }
                    else
                    {
                        targetLine.positionCount = 0;
                    }
                }
            }
        }
    }
    
    private void OnGUI()
    {
        if (_testResult == null)
            return;
        
        // Display test information
        GUILayout.BeginArea(new Rect(10, 10, 300, Screen.height - 20));
        
        GUILayout.Label($"Test: {_testResult.TestName}", new GUIStyle { fontSize = 18, fontStyle = FontStyle.Bold });
        GUILayout.Label($"Result: {(_testResult.Success ? "PASS" : "FAIL")}", new GUIStyle { fontSize = 16, fontStyle = FontStyle.Bold, normal = { textColor = _testResult.Success ? Color.green : Color.red } });
        
        GUILayout.Space(10);
        
        GUILayout.Label("Conditions:", new GUIStyle { fontSize = 14, fontStyle = FontStyle.Bold });
        foreach (var condition in _testResult.ConditionResults)
        {
            GUILayout.Label($"• {condition.Key}: {(condition.Value ? "PASS" : "FAIL")}", new GUIStyle { normal = { textColor = condition.Value ? Color.green : Color.red } });
        }
        
        GUILayout.Space(10);
        
        GUILayout.Label("Performance:", new GUIStyle { fontSize = 14, fontStyle = FontStyle.Bold });
        GUILayout.Label($"• Frame Rate: {_testResult.PerformanceMetrics.FrameRate:F1} FPS");
        GUILayout.Label($"• Bot Count: {_testResult.PerformanceMetrics.ActiveBotCount}");
        GUILayout.Label($"• Avg Path Length: {_testResult.PerformanceMetrics.AveragePathLength:F1}");
        
        GUILayout.EndArea();
    }
}
```

## Regression Testing

The twin stick shooter includes a regression testing framework for bot behavior:

```csharp
public class BotRegressionTester : MonoBehaviour
{
    [Header("Regression Testing")]
    public string BaselinePath = "Assets/Tests/Baselines";
    public string CurrentResultsPath = "Assets/Tests/BotRecordings";
    public bool RunOnStart = false;
    
    [Header("Test Cases")]
    public BotTestCase[] TestCases;
    
    private BotTestFramework _testFramework;
    
    private void Start()
    {
        if (RunOnStart)
        {
            StartCoroutine(RunRegressionTests());
        }
    }
    
    public IEnumerator RunRegressionTests()
    {
        // Run current tests
        _testFramework = gameObject.AddComponent<BotTestFramework>();
        _testFramework.TestCases = TestCases;
        _testFramework.RecordTests = true;
        _testFramework.RecordingPath = CurrentResultsPath;
        
        yield return StartCoroutine(_testFramework.RunAllTests());
        
        // Compare with baselines
        CompareWithBaselines();
    }
    
    private void CompareWithBaselines()
    {
        StringBuilder report = new StringBuilder();
        report.AppendLine("# Bot Regression Test Report");
        report.AppendLine($"Generated on: {System.DateTime.Now}");
        report.AppendLine();
        
        bool anyRegressions = false;
        
        foreach (var testCase in TestCases)
        {
            // Find baseline
            string baselineFile = Path.Combine(BaselinePath, $"{testCase.TestName}_baseline.json");
            
            if (!File.Exists(baselineFile))
            {
                report.AppendLine($"## {testCase.TestName}: NO BASELINE");
                continue;
            }
            
            // Find current result
            string[] resultFiles = Directory.GetFiles(CurrentResultsPath, $"{testCase.TestName}_*.json");
            
            if (resultFiles.Length == 0)
            {
                report.AppendLine($"## {testCase.TestName}: NO CURRENT RESULT");
                continue;
            }
            
            string currentFile = resultFiles.OrderByDescending(f => File.GetLastWriteTime(f)).First();
            
            // Load both results
            string baselineJson = File.ReadAllText(baselineFile);
            string currentJson = File.ReadAllText(currentFile);
            
            BotTestResultData baseline = JsonUtility.FromJson<BotTestResultData>(baselineJson);
            BotTestResultData current = JsonUtility.FromJson<BotTestResultData>(currentJson);
            
            // Compare results
            report.AppendLine($"## {testCase.TestName}");
            report.AppendLine($"- Baseline: {(baseline.Success ? "PASS" : "FAIL")}");
            report.AppendLine($"- Current: {(current.Success ? "PASS" : "FAIL")}");
            
            bool regression = baseline.Success && !current.Success;
            bool improvement = !baseline.Success && current.Success;
            
            if (regression)
            {
                anyRegressions = true;
                report.AppendLine($"- **REGRESSION DETECTED**");
            }
            else if (improvement)
            {
                report.AppendLine($"- **IMPROVEMENT DETECTED**");
            }
            else
            {
                report.AppendLine($"- Status: UNCHANGED");
            }
            
            report.AppendLine();
            
            // Compare conditions
            report.AppendLine("### Condition Comparison");
            report.AppendLine("| Condition | Baseline | Current | Change |");
            report.AppendLine("|-----------|----------|---------|--------|");
            
            foreach (var condition in baseline.ConditionResults.Keys)
            {
                bool baselineResult = baseline.ConditionResults[condition];
                bool currentResult = current.ConditionResults.ContainsKey(condition) ? 
                    current.ConditionResults[condition] : false;
                
                string change = "UNCHANGED";
                if (baselineResult && !currentResult)
                {
                    change = "**REGRESSION**";
                    anyRegressions = true;
                }
                else if (!baselineResult && currentResult)
                {
                    change = "**IMPROVEMENT**";
                }
                
                report.AppendLine($"| {condition} | {baselineResult} | {currentResult} | {change} |");
            }
            
            report.AppendLine();
            
            // Compare performance
            report.AppendLine("### Performance Comparison");
            report.AppendLine("| Metric | Baseline | Current | Change |");
            report.AppendLine("|--------|----------|---------|--------|");
            
            float frameRateChange = current.PerformanceMetrics.FrameRate - baseline.PerformanceMetrics.FrameRate;
            string frameRateChangeStr = $"{frameRateChange:+0.0;-0.0;0.0}";
            
            // Flag significant performance regressions
            if (frameRateChange < -5.0f && current.PerformanceMetrics.FrameRate < 30.0f)
            {
                frameRateChangeStr = $"**{frameRateChangeStr} (SIGNIFICANT)**";
                anyRegressions = true;
            }
            
            report.AppendLine($"| Frame Rate | {baseline.PerformanceMetrics.FrameRate:F1} | {current.PerformanceMetrics.FrameRate:F1} | {frameRateChangeStr} |");
            
            float pathLengthChange = current.PerformanceMetrics.AveragePathLength - baseline.PerformanceMetrics.AveragePathLength;
            string pathLengthChangeStr = $"{pathLengthChange:+0.0;-0.0;0.0}";
            
            report.AppendLine($"| Avg Path Length | {baseline.PerformanceMetrics.AveragePathLength:F1} | {current.PerformanceMetrics.AveragePathLength:F1} | {pathLengthChangeStr} |");
            
            report.AppendLine();
        }
        
        string reportPath = Path.Combine(CurrentResultsPath, $"regression_report_{System.DateTime.Now.ToString("yyyyMMdd_HHmmss")}.md");
        File.WriteAllText(reportPath, report.ToString());
        
        Debug.Log($"Regression report generated at {reportPath}");
        
        if (anyRegressions)
        {
            Debug.LogError("REGRESSIONS DETECTED! See regression report for details.");
        }
    }
    
    [MenuItem("Quantum/AI/Set Current Results as Baseline")]
    public static void SetCurrentResultsAsBaseline()
    {
        string currentResultsPath = "Assets/Tests/BotRecordings";
        string baselinePath = "Assets/Tests/Baselines";
        
        // Create baseline directory if it doesn't exist
        if (!Directory.Exists(baselinePath))
        {
            Directory.CreateDirectory(baselinePath);
        }
        
        // Find all test results
        Dictionary<string, string> latestResults = new Dictionary<string, string>();
        
        foreach (string file in Directory.GetFiles(currentResultsPath, "*.json"))
        {
            string filename = Path.GetFileName(file);
            
            // Skip regression reports
            if (filename.StartsWith("regression_report_"))
                continue;
                
            // Extract test name
            int underscore = filename.IndexOf('_');
            if (underscore <= 0)
                continue;
                
            string testName = filename.Substring(0, underscore);
            
            // Check if this is the latest result for this test
            if (!latestResults.ContainsKey(testName) || 
                File.GetLastWriteTime(file) > File.GetLastWriteTime(latestResults[testName]))
            {
                latestResults[testName] = file;
            }
        }
        
        // Copy latest results to baseline
        foreach (var kvp in latestResults)
        {
            string testName = kvp.Key;
            string sourceFile = kvp.Value;
            string destFile = Path.Combine(baselinePath, $"{testName}_baseline.json");
            
            File.Copy(sourceFile, destFile, true);
            Debug.Log($"Updated baseline for test: {testName}");
        }
        
        Debug.Log("Baselines updated successfully!");
    }
}
```

## Randomized Testing

The twin stick shooter includes randomized testing to find edge cases:

```csharp
public class BotRandomizedTester : MonoBehaviour
{
    [Header("Randomized Testing")]
    public int NumRandomTests = 10;
    public string ResultsPath = "Assets/Tests/RandomTests";
    
    [Header("Test Parameters")]
    public BotType[] BotTypes;
    public int MinBotsPerTest = 1;
    public int MaxBotsPerTest = 5;
    public AssetGuid MapGuid;
    public string GameMode;
    
    private BotTestFramework _testFramework;
    
    public IEnumerator RunRandomizedTests()
    {
        Debug.Log($"Starting {NumRandomTests} randomized tests...");
        
        _testFramework = gameObject.AddComponent<BotTestFramework>();
        _testFramework.RecordTests = true;
        _testFramework.RecordingPath = ResultsPath;
        
        // Create random test cases
        _testFramework.TestCases = new BotTestCase[NumRandomTests];
        for (int i = 0; i < NumRandomTests; i++)
        {
            _testFramework.TestCases[i] = GenerateRandomTestCase(i);
        }
        
        yield return StartCoroutine(_testFramework.RunAllTests());
        
        Debug.Log("Randomized testing completed.");
    }
    
    private BotTestCase GenerateRandomTestCase(int testIndex)
    {
        BotTestCase testCase = ScriptableObject.CreateInstance<BotTestCase>();
        
        // Basic test info
        testCase.TestName = $"RandomTest_{testIndex}";
        testCase.Description = $"Randomly generated test case #{testIndex}";
        testCase.MapGuid = MapGuid;
        testCase.GameMode = GameMode;
        testCase.TestDuration = UnityEngine.Random.Range(15f, 60f);
        
        // Generate random bots
        int numBots = UnityEngine.Random.Range(MinBotsPerTest, MaxBotsPerTest + 1);
        testCase.BotConfigurations = new BotConfiguration[numBots];
        
        for (int i = 0; i < numBots; i++)
        {
            testCase.BotConfigurations[i] = new BotConfiguration
            {
                BotType = BotTypes[UnityEngine.Random.Range(0, BotTypes.Length)],
                Position = new FPVector2(
                    FPMath.FloatToFP(UnityEngine.Random.Range(-10f, 10f)),
                    FPMath.FloatToFP(UnityEngine.Random.Range(-10f, 10f))
                ),
                TeamId = UnityEngine.Random.Range(0, 2),
                DifficultyLevel = UnityEngine.Random.Range(0, 4)
            };
        }
        
        // Generate random test entities
        int numEntities = UnityEngine.Random.Range(1, 5);
        testCase.TestEntityConfigurations = new TestEntityConfiguration[numEntities];
        
        for (int i = 0; i < numEntities; i++)
        {
            TestEntityType entityType = (TestEntityType)UnityEngine.Random.Range(0, 3); // 0=Target, 1=Obstacle, 2=Collectible
            
            testCase.TestEntityConfigurations[i] = new TestEntityConfiguration
            {
                EntityType = entityType,
                Position = new FPVector2(
                    FPMath.FloatToFP(UnityEngine.Random.Range(-10f, 10f)),
                    FPMath.FloatToFP(UnityEngine.Random.Range(-10f, 10f))
                )
            };
        }
        
        // Generate random test conditions
        int numConditions = UnityEngine.Random.Range(1, 4);
        List<BotTestCondition> conditions = new List<BotTestCondition>();
        
        for (int i = 0; i < numConditions; i++)
        {
            int conditionType = UnityEngine.Random.Range(0, 4); // 0=Reach, 1=Defeat, 2=UseAbility, 3=MaintainDistance
            
            switch (conditionType)
            {
                case 0: // ReachPositionCondition
                    conditions.Add(new ReachPositionCondition
                    {
                        ConditionName = $"ReachPosition_{i}",
                        TargetPosition = new FPVector2(
                            FPMath.FloatToFP(UnityEngine.Random.Range(-10f, 10f)),
                            FPMath.FloatToFP(UnityEngine.Random.Range(-10f, 10f))
                        ),
                        MaxDistance = FPMath.FloatToFP(UnityEngine.Random.Range(0.5f, 2f)),
                        TimeLimit = UnityEngine.Random.Range(10f, testCase.TestDuration)
                    });
                    break;
                    
                case 1: // DefeatTargetCondition
                    if (testCase.TestEntityConfigurations.Any(e => e.EntityType == TestEntityType.Target))
                    {
                        int targetIndex = Array.FindIndex(testCase.TestEntityConfigurations, e => e.EntityType == TestEntityType.Target);
                        conditions.Add(new DefeatTargetCondition
                        {
                            ConditionName = $"DefeatTarget_{i}",
                            TargetEntityIndex = targetIndex,
                            TimeLimit = UnityEngine.Random.Range(10f, testCase.TestDuration)
                        });
                    }
                    break;
                    
                case 2: // UseAbilityCondition
                    string[] abilities = { "BasicAttack", "SpecialAttack" };
                    conditions.Add(new UseAbilityCondition
                    {
                        ConditionName = $"UseAbility_{i}",
                        AbilityName = abilities[UnityEngine.Random.Range(0, abilities.Length)],
                        TimeLimit = UnityEngine.Random.Range(10f, testCase.TestDuration)
                    });
                    break;
                    
                case 3: // MaintainDistanceCondition
                    if (testCase.TestEntityConfigurations.Any(e => e.EntityType == TestEntityType.Target))
                    {
                        int targetIndex = Array.FindIndex(testCase.TestEntityConfigurations, e => e.EntityType == TestEntityType.Target);
                        conditions.Add(new MaintainDistanceCondition
                        {
                            ConditionName = $"MaintainDistance_{i}",
                            TargetEntityIndex = targetIndex,
                            MinDistance = FPMath.FloatToFP(UnityEngine.Random.Range(3f, 8f)),
                            TimeLimit = UnityEngine.Random.Range(10f, testCase.TestDuration),
                            RequiredPercentage = UnityEngine.Random.Range(0.5f, 0.8f)
                        });
                    }
                    break;
            }
        }
        
        testCase.TestConditions = conditions.ToArray();
        
        // Set termination condition
        int terminationType = UnityEngine.Random.Range(0, 2); // 0=Time, 1=EntityDeath
        
        if (terminationType == 0 || !testCase.TestEntityConfigurations.Any(e => e.EntityType == TestEntityType.Target))
        {
            testCase.TerminationCondition = new TimeBasedTermination
            {
                TimeLimit = testCase.TestDuration
            };
        }
        else
        {
            int targetIndex = Array.FindIndex(testCase.TestEntityConfigurations, e => e.EntityType == TestEntityType.Target);
            testCase.TerminationCondition = new EntityDeathTermination
            {
                EntityIndex = targetIndex,
                IsTestEntity = true
            };
        }
        
        return testCase;
    }
}
```

These testing tools provide a comprehensive framework for validating and improving bot behavior in the twin stick shooter game. By combining automated testing, regression testing, and randomized testing, developers can ensure that bots behave as expected and identify issues early in the development process.
