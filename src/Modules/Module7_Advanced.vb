Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 7: 进阶分析（CMeans 模糊聚类 + bnlearn 动态贝叶斯网络 + PLS-PM 因果路径）
' ============================================================================

''' <summary>
''' 进阶分析模块。
''' 
''' 分析内容：
''' 1. CMeans 模糊聚类对分子表达矩阵数据做聚类分析
''' 2. 对聚类簇中的分子做 KEGG 富集分析
''' 3. 将聚类簇的结果与 WGCNA 的共表达模块做关联分析
''' 4. 时间序列数据：进行 bnlearn 动态贝叶斯网络的构建以及后续分析
''' 5. 多组学数据且样本量足够：按不同的组学层次构建潜变量，进行 PLS-PM 因果路径分析
''' </summary>
Public Class AdvancedAnalysisModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Advanced Analysis (CMeans + Bayesian + PLS-PM)"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 7

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "advanced_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "Design a plan for advanced analysis including:
1. CMeans fuzzy clustering on the expression matrix
   - Determine optimal cluster number
   - Cluster molecules into fuzzy groups
   - KEGG enrichment for each cluster
   - Compare clusters with WGCNA modules (from module 6)
2. For time-series data with sufficient samples:
   - Build dynamic Bayesian network using bnlearn
   - Identify regulatory relationships between molecules/modules
3. For multi-omics data with sufficient samples:
   - Construct latent variables for each omics layer
   - Perform PLS-PM (Partial Least Squares Path Modeling) causal path analysis

# Implementation Requirements
- CMeans Fuzzy Clustering:
  - Read preprocessed expression matrix
  - Determine optimal cluster number (e.g., using validation indices)
  - Perform fuzzy c-means clustering using e1071 or Mfuzz
  - KEGG enrichment for each cluster
  - Compare clusters with WGCNA modules (contingency table, Fisher's exact test)
- Dynamic Bayesian Network (if time-series data):
  - Read expression matrix and time information
  - Build dynamic Bayesian network using bnlearn
  - Identify regulatory edges
  - Plot network graph
- PLS-PM (if multi-omics with sufficient samples):
  - Construct latent variables for each omics layer
  - Build path model
  - Estimate path coefficients
  - Plot path diagram

# Plot Requirements
- Use Mfuzz/e1071, bnlearn, plspm, igraph, ggplot2
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Handle missing packages gracefully
- Skip analyses that don't apply (e.g., skip bnlearn if not time-series)"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. CMeans 模糊聚类的整体结果（聚类数量、各簇的分子数量、关键簇的生物学功能）
2. 聚类簇与 WGCNA 模块的关联分析结果
3. 动态贝叶斯网络分析结果（若适用，关键调控关系）
4. PLS-PM 因果路径分析结果（若适用，组学层次间的因果路径）
5. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
6. 与前面模块分析结果的一致性和补充性"
    End Function

End Class
