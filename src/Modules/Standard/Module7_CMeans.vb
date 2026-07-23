Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 7: CMeans 模糊聚类分析
' ============================================================================

''' <summary>
''' CMeans 模糊聚类分析模块。
''' 
''' 分析内容：
''' 1. CMeans 模糊聚类对分子表达矩阵数据做聚类分析
''' 2. 对聚类簇中的分子做 KEGG 富集分析
''' 3. 将聚类簇的结果与 WGCNA 的共表达模块做关联分析
''' </summary>
Public Class CMeansAnalysisModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "CMeans Fuzzy Clustering Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 7

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "cmeans_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "Design a plan for CMeans fuzzy clustering analysis including:
1. CMeans fuzzy clustering on the expression matrix
   - Determine optimal cluster number
   - Cluster molecules into fuzzy groups
   - KEGG enrichment for each cluster
   - Compare clusters with WGCNA modules (from module 6)

# Implementation Requirements
- CMeans Fuzzy Clustering:
  - Read preprocessed expression matrix
  - Determine optimal cluster number (e.g., using validation indices)
  - Perform fuzzy c-means clustering using e1071 or Mfuzz
  - KEGG enrichment for each cluster
  - Compare clusters with WGCNA modules (contingency table, Fisher's exact test)

# Plot Requirements
- Use Mfuzz/e1071, clusterProfiler, ggplot2, ComplexHeatmap
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Handle missing packages gracefully
- Skip analyses that don't apply"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. CMeans 模糊聚类的整体结果（聚类数量、各簇的分子数量、关键簇的生物学功能）
2. 聚类簇与 WGCNA 模块的关联分析结果
3. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
4. 与前面模块分析结果的一致性和补充性"
    End Function

End Class
