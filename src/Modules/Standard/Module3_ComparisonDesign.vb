Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 3: 设计差异分析的比对组别
' ============================================================================

''' <summary>
''' 差异分析比对组别设计模块。
''' 
''' 根据用户的研究主题设计差异分析的比对组别，这些组别应该深入契合
''' 用户当前研究主题已知相关的生物学机制。会参考 kb.json 中的生物学知识
''' 生成阶段性研究总结文件，阐述差异比对设计的生物学依据、分析目的、
''' 与用户研究主题的生物学机制相关性等。
''' </summary>
Public Class ComparisonDesignModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Comparison Group Design"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 3

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "comparison_"
        End Get
    End Property

    Protected Overrides ReadOnly Property NeedsPlantSteps As Boolean
        Get
            Return False
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GetPlantJSONTemplate() As String
        Return $"。且计划 JSON 中必须定义 'comparisons' 字段：{{
  ""module_name"": ""Comparison Group Design"",
  ""goal"": ""<简要描述比对设计的依据>"",
  ""input_files"": [""<输入文件路径>""],
  ""output_files"": [""<预期输出文件路径>""],
  ""execution_steps"": [{{""action"": ""<当前步骤操作的描述>"", ""goal"": ""<当前步骤的目标...>""}}, ...],
  ""comparisons"": [
    {{
      ""name"": ""<比对名称，如 'disease_vs_control'>"",
      ""treatment"": ""<处理组名称>"",
      ""control"": ""<对照组名称>"",
      ""biological_rationale"": ""<此比对具有生物学意义的原因>"",
      ""expected_findings"": ""<预期可获得的生物学发现>""
    }}
  ],
  ""notes"": ""<需要特别注意的事项>""
}}"
    End Function

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "根据用户研究主题和可用样本分组（来自样本信息表中的 sample_info 列），设计差异分析比对组别：
1. 识别所有可用的样本分组
2. 设计与研究主题契合的、具有生物学意义的比对组对
3. 对于时间序列数据，设计各组内不同时间点之间的比对
4. 兼顾两两比对和多组比对
5. 对于多组学数据，在各组学层面设计一致的比对方案

比对设计应与用户研究主题相关的已知生物学机制深度契合。
参考 kb.json 知识库获取生物学见解。

# 上下游衔接说明
- 上游输入：读取样本信息表中的分组信息，参考模块 1 预处理后的数据
- 下游输出：比对设计结果（design.json + tables/comparison_design.csv）将作为模块 4(LIMMA) 和模块 5(KEGG GSVA 差异分析) 的比对方案依据

# 实现要求
- 创建包含比对设计的数据框
- 列名：comparison_name, treatment_group, control_group, biological_rationale, expected_findings
- 将比对设计保存为 CSV 到 tables/comparison_design.csv
- 生成展示比对结构的可视化图"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 差异比对设计的整体思路
2. 每个比对组别的生物学依据
3. 比对设计与用户研究主题的生物学机制相关性
4. 预期能够获得的生物学发现
5. 比对设计的合理性论证（参考 kb.json 中的生物学知识）"
    End Function

End Class
