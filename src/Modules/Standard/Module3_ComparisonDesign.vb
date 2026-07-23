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

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "Based on the user's research topic and the available sample groups (from sample_info column in sample metadata), design differential analysis comparison groups:
1. Identify all available sample groups
2. Design biologically meaningful comparison pairs that align with the research topic
3. For time-series data, design comparisons across time points within each group
4. Consider both pairwise comparisons and multi-group comparisons
5. For multi-omics data, design consistent comparisons across omics layers

The comparison design should be deeply aligned with the known biological mechanisms related to the user's research topic.
Reference the kb.json knowledge base for biological insights.

# Implementation Requirements
- Create a data frame containing the comparison design
- Columns: comparison_name, treatment_group, control_group, biological_rationale, expected_findings
- Save the design as CSV to tables/comparison_design.csv
- Generate a summary visualization showing the comparison structure"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 差异比对设计的整体思路
2. 每个比对组别的生物学依据
3. 比对设计与用户研究主题的生物学机制相关性
4. 预期能够获得的生物学发现
5. 比对设计的合理性论证（参考 kb.json 中的生物学知识）"
    End Function

End Class
