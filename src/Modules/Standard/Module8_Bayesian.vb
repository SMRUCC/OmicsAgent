Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 8: 动态贝叶斯网络分析（bnlearn）
' ============================================================================

''' <summary>
''' 动态贝叶斯网络分析模块。
''' 
''' 分析内容：
''' 1. 时间序列数据：进行 bnlearn 动态贝叶斯网络的构建以及后续分析
''' 2. 识别分子/模块之间的调控关系
''' </summary>
Public Class BayesianNetworkModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Dynamic Bayesian Network Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 8

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "bayesian_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "Design a plan for dynamic Bayesian network analysis using bnlearn.
This analysis applies to time-series data with sufficient samples.

# Implementation Requirements
- Dynamic Bayesian Network (if time-series data):
  - Read expression matrix and time information
  - Build dynamic Bayesian network using bnlearn
  - Identify regulatory edges
  - Plot network graph

# Plot Requirements
- Use bnlearn, igraph, ggplot2
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Handle missing packages gracefully
- Skip this analysis if the data is not time-series
- Identify key regulatory relationships between molecules/modules"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 动态贝叶斯网络分析结果（若适用，关键调控关系）
2. 分子/模块之间的调控网络拓扑特征
3. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
4. 与前面模块分析结果的一致性和补充性"
    End Function

End Class
