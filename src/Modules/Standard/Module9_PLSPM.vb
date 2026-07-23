Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 9: PLS-PM 因果路径分析
' ============================================================================

''' <summary>
''' PLS-PM 因果路径分析模块。
''' 
''' 分析内容：
''' 1. 多组学数据且样本量足够：按不同的组学层次构建潜变量
''' 2. 进行 PLS-PM 因果路径分析
''' </summary>
Public Class PLSPMAnalysisModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "PLS-PM Causal Path Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 9

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "plspm_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "Design a plan for PLS-PM (Partial Least Squares Path Modeling) causal path analysis.
This analysis applies to multi-omics data with sufficient samples.

# Implementation Requirements
- PLS-PM (if multi-omics with sufficient samples):
  - Construct latent variables for each omics layer
  - Build path model
  - Estimate path coefficients
  - Plot path diagram

# Plot Requirements
- Use plspm, igraph, ggplot2
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Handle missing packages gracefully
- Skip this analysis if the data is single-omics or sample size is insufficient
- Focus on causal relationships between omics layers"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. PLS-PM 因果路径分析结果（若适用，组学层次间的因果路径）
2. 各组学层次潜变量的构建情况及路径系数
3. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
4. 与前面模块分析结果的一致性和补充性"
    End Function

End Class
