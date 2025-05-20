# Bot Customization and Configuration

This document details how to configure and customize bots in the twin stick shooter game through various asset types and configuration options.

## Configuration Asset Types

The twin stick shooter uses several asset types to configure bot behavior:

1. **EntityPrototype**: Defines the base character prototype
2. **AIConfig**: Configures sensors and general AI behavior
3. **HFSMRoot**: Defines the decision-making structure
4. **AIBlackboardInitializer**: Sets initial memory values
5. **NavMeshAgentConfig**: Configures pathfinding behavior

These assets allow designers to create varied bot behaviors without modifying code.

## Bot Prototype Configuration

```csharp
[CreateAssetMenu(menuName = "Quantum/EntityPrototype/Bot")]
public class BotPrototype : EntityPrototype
{
    public DynamicAssetRef<NavMeshAgentConfig> NavMeshAgentConfig;
    public AssetRef BlackboardInitializer;
    public AssetRef HFSMRoot;
    public DynamicAssetRef<AIConfig> AIConfig;
    
    [Header("Character Properties")]
    public CharacterClass CharacterClass;
    public FP MovementSpeed = FP._5;
    public FP RotationSpeed = FP._720; // degrees per second
    public FP MaxHealth = FP._100;
    
    [Header("Combat Properties")]
    public AssetRef BasicAttackData;
    public AssetRef SpecialAttackData;
    public FP AttackRange = FP._4;
    public FP AttackCooldown = FP._0_5;
    public FP SpecialAttackCooldown = FP._8;
    
    public override unsafe EntityRef Create(Frame frame)
    {
        EntityRef entity = frame.Create();
        
        // Add basic components
        frame.Add<Transform2D>(entity);
        frame.Add<PhysicsCollider2D>(entity);
        frame.Add<Character>(entity, out var character);
        character->CharacterClass = CharacterClass;
        
        frame.Add<Health>(entity, out var health);
        health->MaxHealth = MaxHealth;
        health->CurrentHealth = MaxHealth;
        
        frame.Add<TeamInfo>(entity);
        frame.Add<PlayerLink>(entity);
        
        // Add movement components
        frame.Add<KCC>(entity, out var kcc);
        kcc->MaxSpeed = MovementSpeed;
        
        // Add combat components
        frame.Add<AttackComponent>(entity, out var attackComponent);
        attackComponent->BasicAttackData = BasicAttackData;
        attackComponent->SpecialAttackData = SpecialAttackData;
        attackComponent->AttackRange = AttackRange;
        attackComponent->AttackCooldown = AttackCooldown;
        attackComponent->SpecialAttackCooldown = SpecialAttackCooldown;
        
        // Add bot components
        frame.Add<Bot>(entity, out var bot);
        bot->NavMeshAgentConfig = NavMeshAgentConfig;
        bot->BlackboardInitializer = BlackboardInitializer;
        bot->HFSMRoot = HFSMRoot;
        bot->AIConfig = AIConfig;
        bot->IsActive = false;
        
        frame.Add<AISteering>(entity, out var aiSteering);
        aiSteering->LerpFactor = FP._5;
        aiSteering->MainSteeringWeight = FP._1;
        aiSteering->MaxEvasionDuration = FP._1;
        
        return entity;
    }
}
```

The BotPrototype asset allows designers to configure:
1. Basic navigation settings
2. Character class and properties
3. Combat capabilities and ranges
4. AI component references

## AIConfig Configuration

```csharp
[CreateAssetMenu(menuName = "Quantum/AI/AIConfig")]
public class AIConfig : AssetObject
{
    [Header("Sensors")]
    public Sensor[] SensorsInstances;
    
    [Header("Difficulty")]
    public int DifficultyLevel = 1; // 0-3, where 3 is hardest
    
    [Header("Detection")]
    public FP SightRange = FP._10;
    public FP FieldOfView = FP._120; // In degrees
    
    [Header("Combat")]
    public FP OptimalCombatDistance = FP._5;
    public FP AttackProbability = FP._0_75;
    public FP DodgeProbability = FP._0_50;
    
    [Header("Behavior")]
    public FP AggressionFactor = FP._0_5; // 0.0 to 1.0
    public FP SelfPreservationFactor = FP._0_5; // 0.0 to 1.0
    public FP ObjectiveFocusFactor = FP._0_5; // 0.0 to 1.0
    
    public T GetSensor<T>() where T : Sensor
    {
        foreach (var sensor in SensorsInstances)
        {
            if (sensor is T typedSensor)
            {
                return typedSensor;
            }
        }
        
        return null;
    }
}
```

The AIConfig asset allows designers to configure:
1. Which sensors the bot uses
2. Difficulty level
3. Detection properties
4. Combat preferences
5. High-level behavior factors

## HFSMRoot Configuration

```csharp
[CreateAssetMenu(menuName = "Quantum/AI/HFSM/TwinStickBotHFSM")]
public class TwinStickBotHFSM : HFSMRoot
{
    [Header("Combat Nodes")]
    public bool EnableSpecialAttacks = true;
    public bool EnableDodging = true;
    
    [Header("Collect Nodes")]
    public bool EnableCollection = true;
    public bool PrioritizeHealthPickups = true;
    
    [Header("Retreat Nodes")]
    public bool EnableRetreat = true;
    public FP RetreatHealthThreshold = FP._0_25;
    
    private List<HFSMNode> _customNodes = new List<HFSMNode>();
    
    public override HFSMGraphTree BuildGraph()
    {
        HFSMGraphTree graph = new HFSMGraphTree();
        
        // Root and main states
        string rootState = graph.CreateHFSMNode("Root", null, null, null);
        string combatState = graph.CreateHFSMNode("Combat", null, null, null);
        string collectState = EnableCollection ? graph.CreateHFSMNode("Collect", null, null, null) : null;
        string retreatState = EnableRetreat ? graph.CreateHFSMNode("Retreat", null, null, null) : null;
        
        // Connect main states to root
        graph.ConnectChildToParent(rootState, combatState);
        
        if (EnableCollection)
            graph.ConnectChildToParent(rootState, collectState);
            
        if (EnableRetreat)
            graph.ConnectChildToParent(rootState, retreatState);
        
        // Set up transitions between main states
        if (EnableRetreat)
        {
            graph.CreateTransition(combatState, retreatState, "HealthLow");
            graph.CreateTransition(retreatState, combatState, "HealthRecovered");
        }
        
        if (EnableCollection)
        {
            graph.CreateTransition(combatState, collectState, "NoTargetsInRange");
            graph.CreateTransition(collectState, combatState, "TargetInRange");
        }
        
        // Create combat sub-states
        string engageState = graph.CreateNode("Engage", EngageLeaf);
        string attackState = graph.CreateNode("Attack", AttackLeaf);
        
        string specialAttackState = null;
        if (EnableSpecialAttacks)
            specialAttackState = graph.CreateNode("SpecialAttack", SpecialAttackLeaf);
            
        string dodgeState = null;
        if (EnableDodging)
            dodgeState = graph.CreateNode("Dodge", DodgeLeaf);
        
        // Connect combat sub-states
        graph.ConnectChildToParent(combatState, engageState);
        graph.ConnectChildToParent(combatState, attackState);
        
        if (EnableSpecialAttacks)
            graph.ConnectChildToParent(combatState, specialAttackState);
            
        if (EnableDodging)
            graph.ConnectChildToParent(combatState, dodgeState);
        
        // Set up combat sub-state transitions
        graph.CreateTransition(engageState, attackState, "InAttackRange");
        graph.CreateTransition(attackState, engageState, "AttackFinished");
        
        if (EnableSpecialAttacks)
        {
            graph.CreateTransition(engageState, specialAttackState, "CanUseSpecialAttack");
            graph.CreateTransition(specialAttackState, engageState, "AttackFinished");
        }
        
        if (EnableDodging)
        {
            graph.CreateTransition(engageState, dodgeState, "ShouldDodge");
            graph.CreateTransition(dodgeState, engageState, "DodgeFinished");
        }
        
        // Create and connect collection sub-states if enabled
        if (EnableCollection)
        {
            string findCollectibleState = graph.CreateNode("FindCollectible", FindCollectibleLeaf);
            string moveToCollectibleState = graph.CreateNode("MoveToCollectible", MoveToCollectibleLeaf);
            
            graph.ConnectChildToParent(collectState, findCollectibleState);
            graph.ConnectChildToParent(collectState, moveToCollectibleState);
            
            graph.CreateTransition(findCollectibleState, moveToCollectibleState, "CollectibleFound");
            graph.CreateTransition(moveToCollectibleState, findCollectibleState, "CollectibleReached");
        }
        
        // Create and connect retreat sub-states if enabled
        if (EnableRetreat)
        {
            string findCoverState = graph.CreateNode("FindCover", FindCoverLeaf);
            string moveToCoverState = graph.CreateNode("MoveToCover", MoveToCoverLeaf);
            
            graph.ConnectChildToParent(retreatState, findCoverState);
            graph.ConnectChildToParent(retreatState, moveToCoverState);
            
            graph.CreateTransition(findCoverState, moveToCoverState, "CoverFound");
            graph.CreateTransition(moveToCoverState, findCoverState, "CoverReached");
        }
        
        // Set default nodes
        graph.SetDefaultNode(rootState, combatState);
        graph.SetDefaultNode(combatState, engageState);
        
        if (EnableCollection)
            graph.SetDefaultNode(collectState, findCollectibleState);
            
        if (EnableRetreat)
            graph.SetDefaultNode(retreatState, findCoverState);
        
        return graph;
    }
    
    // Leaf node references
    private System.Type EngageLeaf => typeof(EngagementSteering);
    private System.Type AttackLeaf => typeof(HoldAttack);
    private System.Type SpecialAttackLeaf => typeof(SpecialAttack);
    private System.Type DodgeLeaf => typeof(DodgeAction);
    private System.Type FindCollectibleLeaf => typeof(SelectCollectible);
    private System.Type MoveToCollectibleLeaf => typeof(ChaseCollectible);
    private System.Type FindCoverLeaf => typeof(FindCoverSpot);
    private System.Type MoveToCoverLeaf => typeof(RunToCoverSpot);
}
```

The HFSMRoot asset allows designers to configure:
1. Which behavior nodes are enabled
2. Transition thresholds
3. Behavior priorities
4. Custom node parameters

## AIBlackboardInitializer Configuration

```csharp
[CreateAssetMenu(menuName = "Quantum/AI/BlackboardInitializer")]
public class AIBlackboardInitializer : AssetObject
{
    [Serializable]
    public struct InitializerEntry
    {
        public string Key;
        public BlackboardEntryType Type;
        public string StringValue;
        public int IntValue;
        public float FloatValue;
        public bool BoolValue;
        public AssetRef AssetRefValue;
    }
    
    public enum BlackboardEntryType
    {
        Boolean,
        Integer,
        Float,
        String,
        AssetRef
    }
    
    public InitializerEntry[] Entries;
    
    [Serializable]
    public struct TacticalPreference
    {
        public string Name;
        [Range(0f, 1f)]
        public float Weight;
    }
    
    [Header("Tactical Preferences")]
    public TacticalPreference[] TacticalPreferences;
    
    [Header("Combat Parameters")]
    public float AggressionLevel = 0.5f;
    public float DefensivenessLevel = 0.5f;
    public float SpecialAttackThreshold = 0.7f; // Higher = less likely to use special attacks
    
    [Header("Collection Parameters")]
    public float CollectibleValueThreshold = 0.3f;
    public float HealthPickupPriority = 1.0f;
    public float PowerupPriority = 0.8f;
    public float CoinPriority = 0.5f;
    
    public static void InitializeBlackboard(Frame frame, AIBlackboardComponent* blackboard, AIBlackboardInitializer initializer)
    {
        // Initialize from entries
        foreach (var entry in initializer.Entries)
        {
            switch (entry.Type)
            {
                case BlackboardEntryType.Boolean:
                    blackboard->Set(entry.Key, entry.BoolValue);
                    break;
                case BlackboardEntryType.Integer:
                    blackboard->Set(entry.Key, entry.IntValue);
                    break;
                case BlackboardEntryType.Float:
                    blackboard->Set(entry.Key, FPMath.FloatToFP(entry.FloatValue));
                    break;
                case BlackboardEntryType.String:
                    // String handling would require a different approach
                    break;
                case BlackboardEntryType.AssetRef:
                    blackboard->Set(entry.Key, entry.AssetRefValue);
                    break;
            }
        }
        
        // Initialize tactical preferences
        foreach (var preference in initializer.TacticalPreferences)
        {
            blackboard->Set("TacticalWeight_" + preference.Name, FPMath.FloatToFP(preference.Weight));
        }
        
        // Initialize combat parameters
        blackboard->Set("AggressionLevel", FPMath.FloatToFP(initializer.AggressionLevel));
        blackboard->Set("DefensivenessLevel", FPMath.FloatToFP(initializer.DefensivenessLevel));
        blackboard->Set("SpecialAttackThreshold", FPMath.FloatToFP(initializer.SpecialAttackThreshold));
        
        // Initialize collection parameters
        blackboard->Set("CollectibleValueThreshold", FPMath.FloatToFP(initializer.CollectibleValueThreshold));
        blackboard->Set("HealthPickupPriority", FPMath.FloatToFP(initializer.HealthPickupPriority));
        blackboard->Set("PowerupPriority", FPMath.FloatToFP(initializer.PowerupPriority));
        blackboard->Set("CoinPriority", FPMath.FloatToFP(initializer.CoinPriority));
    }
}
```

The AIBlackboardInitializer asset allows designers to configure:
1. Initial blackboard values
2. Tactical preferences
3. Combat parameters
4. Collection priorities

## NavMeshAgentConfig Configuration

```csharp
[CreateAssetMenu(menuName = "Quantum/AI/NavMeshAgentConfig")]
public class NavMeshAgentConfig : AssetObject
{
    [Header("Pathfinding")]
    public FP PathRefreshRate = FP._0_25;
    public FP MaxPathLength = FP._50;
    public int MaxPathNodes = 30;
    
    [Header("Movement")]
    public FP StoppingDistance = FP._0_5;
    public FP SlowingDistance = FP._2;
    public FP MaxAcceleration = FP._10;
    public FP MaxSpeed = FP._5;
    
    [Header("Avoidance")]
    public bool EnableAvoidance = true;
    public FP AvoidanceRadius = FP._1;
    public FP AvoidanceWeight = FP._1;
}
```

The NavMeshAgentConfig asset allows designers to configure:
1. Pathfinding parameters
2. Movement behavior
3. Avoidance properties

## Combining Assets for Bot Types

Different bot types can be created by combining these assets in various ways:

```csharp
// Create an aggressive melee bot
public static EntityRef CreateAggressiveMeleeBot(Frame frame, FPVector2 position, int teamId)
{
    var botPrototype = frame.FindAsset<BotPrototype>("AggressiveMeleeBot");
    EntityRef bot = frame.Create(botPrototype);
    
    // Set position
    frame.Unsafe.GetPointer<Transform2D>(bot)->Position = position;
    
    // Set team
    frame.Unsafe.GetPointer<TeamInfo>(bot)->Index = teamId;
    
    // Activate bot
    AISetupHelper.Botify(frame, bot);
    
    return bot;
}

// Create a cautious ranged bot
public static EntityRef CreateCautiousRangedBot(Frame frame, FPVector2 position, int teamId)
{
    var botPrototype = frame.FindAsset<BotPrototype>("CautiousRangedBot");
    EntityRef bot = frame.Create(botPrototype);
    
    // Set position
    frame.Unsafe.GetPointer<Transform2D>(bot)->Position = position;
    
    // Set team
    frame.Unsafe.GetPointer<TeamInfo>(bot)->Index = teamId;
    
    // Activate bot
    AISetupHelper.Botify(frame, bot);
    
    return bot;
}
```

## Bot Difficulty Scaling

Bots can be scaled by difficulty level to provide appropriate challenge:

```csharp
public static void AdjustBotForDifficulty(Frame frame, EntityRef bot, int difficultyLevel)
{
    // Get AI config
    var hfsmAgent = frame.Get<HFSMAgent>(bot);
    var aiConfig = frame.FindAsset<AIConfig>(hfsmAgent.Config.Id);
    
    // Override the config's difficulty level
    // Note: This would normally be done by duplicating/modifying the asset
    // This is shown for illustration only
    aiConfig.DifficultyLevel = difficultyLevel;
    
    // Adjust aim accuracy based on difficulty
    FP aimAccuracy;
    switch (difficultyLevel)
    {
        case 0: // Beginner
            aimAccuracy = FP._0_25;
            break;
        case 1: // Easy
            aimAccuracy = FP._0_50;
            break;
        case 2: // Medium
            aimAccuracy = FP._0_75;
            break;
        case 3: // Hard
            aimAccuracy = FP._0_95;
            break;
        default:
            aimAccuracy = FP._0_50;
            break;
    }
    
    // Update the blackboard with the aim accuracy
    AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(bot);
    blackboard->Set("AimAccuracy", aimAccuracy);
    
    // Adjust reaction time
    FP reactionTime;
    switch (difficultyLevel)
    {
        case 0: // Beginner
            reactionTime = FP._1_5;
            break;
        case 1: // Easy
            reactionTime = FP._1_0;
            break;
        case 2: // Medium
            reactionTime = FP._0_5;
            break;
        case 3: // Hard
            reactionTime = FP._0_1;
            break;
        default:
            reactionTime = FP._1_0;
            break;
    }
    
    blackboard->Set("ReactionTime", reactionTime);
}
```

## Runtime Bot Customization

Bots can be customized at runtime for specific scenarios:

```csharp
public static void CustomizeBotForScenario(Frame frame, EntityRef bot, string scenarioType)
{
    // Get components
    AIBlackboardComponent* blackboard = frame.Unsafe.GetPointer<AIBlackboardComponent>(bot);
    
    switch (scenarioType)
    {
        case "Aggressive":
            blackboard->Set("AggressionLevel", FP._0_9);
            blackboard->Set("DefensivenessLevel", FP._0_1);
            blackboard->Set("TacticalWeight_Attack", FP._0_9);
            blackboard->Set("TacticalWeight_Retreat", FP._0_1);
            break;
            
        case "Defensive":
            blackboard->Set("AggressionLevel", FP._0_1);
            blackboard->Set("DefensivenessLevel", FP._0_9);
            blackboard->Set("TacticalWeight_Attack", FP._0_1);
            blackboard->Set("TacticalWeight_Retreat", FP._0_9);
            break;
            
        case "Balanced":
            blackboard->Set("AggressionLevel", FP._0_5);
            blackboard->Set("DefensivenessLevel", FP._0_5);
            blackboard->Set("TacticalWeight_Attack", FP._0_5);
            blackboard->Set("TacticalWeight_Retreat", FP._0_5);
            break;
            
        case "Collector":
            blackboard->Set("CollectibleValueThreshold", FP._0_1);
            blackboard->Set("TacticalWeight_Collect", FP._0_9);
            break;
            
        case "Berserker":
            blackboard->Set("AggressionLevel", FP._1_0);
            blackboard->Set("DefensivenessLevel", FP._0_0);
            blackboard->Set("TacticalWeight_Attack", FP._1_0);
            blackboard->Set("SpecialAttackThreshold", FP._0_1);
            break;
    }
}
```

## Editor Integration for Bot Configuration

The twin stick shooter includes custom editors for bot configuration:

```csharp
[CustomEditor(typeof(BotPrototype))]
public class BotPrototypeEditor : Editor
{
    private SerializedProperty _navMeshAgentConfig;
    private SerializedProperty _blackboardInitializer;
    private SerializedProperty _hfsmRoot;
    private SerializedProperty _aiConfig;
    private SerializedProperty _characterClass;
    private SerializedProperty _movementSpeed;
    private SerializedProperty _rotationSpeed;
    private SerializedProperty _maxHealth;
    private SerializedProperty _basicAttackData;
    private SerializedProperty _specialAttackData;
    private SerializedProperty _attackRange;
    private SerializedProperty _attackCooldown;
    private SerializedProperty _specialAttackCooldown;
    
    private bool _showCharacterProperties = true;
    private bool _showCombatProperties = true;
    
    private void OnEnable()
    {
        _navMeshAgentConfig = serializedObject.FindProperty("NavMeshAgentConfig");
        _blackboardInitializer = serializedObject.FindProperty("BlackboardInitializer");
        _hfsmRoot = serializedObject.FindProperty("HFSMRoot");
        _aiConfig = serializedObject.FindProperty("AIConfig");
        _characterClass = serializedObject.FindProperty("CharacterClass");
        _movementSpeed = serializedObject.FindProperty("MovementSpeed");
        _rotationSpeed = serializedObject.FindProperty("RotationSpeed");
        _maxHealth = serializedObject.FindProperty("MaxHealth");
        _basicAttackData = serializedObject.FindProperty("BasicAttackData");
        _specialAttackData = serializedObject.FindProperty("SpecialAttackData");
        _attackRange = serializedObject.FindProperty("AttackRange");
        _attackCooldown = serializedObject.FindProperty("AttackCooldown");
        _specialAttackCooldown = serializedObject.FindProperty("SpecialAttackCooldown");
    }
    
    public override void OnInspectorGUI()
    {
        serializedObject.Update();
        
        EditorGUILayout.LabelField("Bot AI Configuration", EditorStyles.boldLabel);
        EditorGUILayout.PropertyField(_navMeshAgentConfig);
        EditorGUILayout.PropertyField(_blackboardInitializer);
        EditorGUILayout.PropertyField(_hfsmRoot);
        EditorGUILayout.PropertyField(_aiConfig);
        
        EditorGUILayout.Space();
        
        _showCharacterProperties = EditorGUILayout.Foldout(_showCharacterProperties, "Character Properties", true);
        if (_showCharacterProperties)
        {
            EditorGUI.indentLevel++;
            EditorGUILayout.PropertyField(_characterClass);
            EditorGUILayout.PropertyField(_movementSpeed);
            EditorGUILayout.PropertyField(_rotationSpeed);
            EditorGUILayout.PropertyField(_maxHealth);
            EditorGUI.indentLevel--;
        }
        
        EditorGUILayout.Space();
        
        _showCombatProperties = EditorGUILayout.Foldout(_showCombatProperties, "Combat Properties", true);
        if (_showCombatProperties)
        {
            EditorGUI.indentLevel++;
            EditorGUILayout.PropertyField(_basicAttackData);
            EditorGUILayout.PropertyField(_specialAttackData);
            EditorGUILayout.PropertyField(_attackRange);
            EditorGUILayout.PropertyField(_attackCooldown);
            EditorGUILayout.PropertyField(_specialAttackCooldown);
            EditorGUI.indentLevel--;
        }
        
        serializedObject.ApplyModifiedProperties();
    }
}
```

## Predefined Bot Templates

The game includes predefined bot templates for common archetypes:

```csharp
[Serializable]
public class BotTemplateList : ScriptableObject
{
    [Serializable]
    public class BotTemplate
    {
        public string Name;
        public BotPrototype Prototype;
        [TextArea(3, 5)]
        public string Description;
    }
    
    public BotTemplate[] Templates;
}

// Defined templates might include:
// - Melee Aggressive
// - Melee Defensive
// - Ranged Kiter
// - Ranged Sniper
// - Support Healer
// - Tactical Archer
// - Mobile Scout
// - Tank Bruiser
```

These templates provide starting points for bot configuration and can be customized for specific needs.

By using these configuration assets, designers can create a wide variety of bot behaviors without changing code, enabling rich gameplay experiences with diverse AI opponents.
