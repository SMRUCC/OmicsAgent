Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 6: 生物学性状关联分析（WGCNA）
' ============================================================================

''' <summary>
''' 生物学性状关联分析模块（WGCNA）。
''' 
''' 分析内容：
''' 1. 默认按 MAD 值降序排序取 top 20000 个分子做 WGCNA 分析
''' 2. 根据用户研究主题和样本分组信息、元数据信息构建 WGCNA 的生物表型关联性状数据
''' 3. 多组学数据：可将下游组学数据的 GSVA 分析结果作为表型数据，
'''    与上游组学数据的分子表达数据做关联分析
''' 4. 共表达模块与生物学性状值的线性回归分析
''' 5. 共表达模块分子的 KEGG 功能富集分析
''' </summary>
Public Class WGCNAModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "WGCNA Trait Association Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 6

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "wgcna_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "Design a plan for WGCNA analysis including:
1. Select top 20000 molecules by MAD (Median Absolute Deviation) descending
2. Construct WGCNA co-expression network
   - Determine soft threshold power
   - Build network and identify modules
   - Calculate module eigengenes
3. Build biological trait data:
   - Use sample metadata (group, line, time, etc.) as traits
   - For multi-omics: use downstream omics GSVA scores as traits for upstream omics
4. Correlate modules with biological traits
5. Linear regression analysis of modules vs trait values
6. KEGG enrichment analysis of module molecules

# Implementation Requirements
- Read preprocessed expression matrix from tmp/
- Select top 20000 molecules by MAD descending (or all if fewer)
- Determine soft threshold power using pickSoftThreshold
- Build WGCNA network:
  - Block-wise network construction
  - Module identification
  - Module eigengene calculation
- Build trait data from sample metadata:
  - Numeric encoding of group, line, time columns
  - For multi-omics: load GSVA scores from module 5 as traits
- Correlate module eigengenes with traits (Pearson correlation + pvalue)
- Perform linear regression of modules vs significant traits
- Perform KEGG enrichment for each module's molecules
- Generate the following plots (PNG + PDF, 300 dpi, English labels):
  - Soft threshold power selection plot
  - Module dendrogram (cluster tree)
  - Module-trait correlation heatmap
  - Module eigengene bar plot
  - Hub gene network visualization (for top modules)
  - KEGG enrichment dot plot for each significant module
- Save module results, module-trait correlations, KEGG enrichment as CSV

# Plot Requirements
- Use WGCNA, ggplot2, ComplexHeatmap, clusterProfiler
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Handle missing packages gracefully
- WGCNA can be memory-intensive, use blocks if needed"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. WGCNA 网络构建的整体情况（soft threshold power、模块数量、模块大小分布）
2. 模块与生物学性状的关联分析结果（哪些模块与哪些性状显著相关）
3. 关键模块的生物学功能（KEGG 富集结果，参考 kb.json 知识库）
4. Hub 基因/分子的识别
5. 多组学关联分析结果（若适用）
6. 共表达模块与生物学性状的线性回归分析结果
7. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关"
    End Function

End Class
