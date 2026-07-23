Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 5: KEGG 生物学功能分析（富集 + GSVA）
' ============================================================================

''' <summary>
''' KEGG 生物学功能分析模块。
''' 
''' 分析内容：
''' 1. 基于差异分析结果，使用 kegg id 进行富集分析
''' 2. GSVA 分析，并按相同组别设计进行差异分析
''' 3. 富集结果条形图（按 KEGG 大分类分组）
''' 4. GSVA 总体热图（列=样本按分组排序，行=KEGG 通路按大分类分组+层次聚类+聚类树）
''' 5. GSVA 差异分析火山图、得分图
''' </summary>
Public Class KeggFunctionModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "KEGG Functional Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 5

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "kegg_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "Design a plan for KEGG functional analysis including:
1. KEGG pathway enrichment analysis using differential molecules (from module 4)
   - Use KEGG background XML/JSON files in the data/ directory
   - Use clusterProfiler or similar packages
2. GSVA (Gene Set Variation Analysis) on the expression matrix
   - Use KEGG pathways as gene sets
   - Apply the same comparison design as differential analysis
3. Visualization:
   - Enrichment bar plot grouped by KEGG category
   - GSVA heatmap (columns = samples sorted by group, rows = KEGG pathways grouped by category with hierarchical clustering and dendrogram)
   - GSVA differential analysis volcano plot and score plot

# Implementation Requirements
- Read differential analysis results from module 4 (tables/ directory)
- Read KEGG background data from data/ directory (XML or JSON files)
- Perform KEGG pathway enrichment analysis using clusterProfiler
- Perform GSVA analysis using GSVA package
- Perform differential analysis on GSVA scores using limma (same comparison design)
- Generate the following plots (PNG + PDF, 300 dpi, English labels):
  - Enrichment bar plot:
    * Bar plot of enriched pathways
    * Grouped by KEGG large category (Metabolism, Genetic Information Processing, etc.)
    * Color by category, size by gene count
  - GSVA heatmap:
    * Columns = samples, sorted by sample group
    * Rows = KEGG pathways
    * Group rows by KEGG large category
    * Hierarchical clustering within each category
    * Draw dendrogram on the left side for each category
  - GSVA differential volcano plot
  - GSVA score plot for top differential pathways
- Save enrichment and GSVA result tables as CSV

# Plot Requirements
- Use ggplot2, ComplexHeatmap, clusterProfiler, GSVA
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Handle missing packages gracefully"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. KEGG 富集分析的整体结果（显著富集的通路数量、分类分布）
2. 关键富集通路的生物学意义（参考 kb.json 知识库）
3. GSVA 分析结果（通路得分在不同组别间的差异）
4. GSVA 差异分析结果（差异显著的通路）
5. 通路得分热图所展示的样本聚类模式
6. 生物学通路分析结果如何支持用户的研究主题
7. 与差异分析结果的关联性"
    End Function

End Class
