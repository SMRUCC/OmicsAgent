Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 4: LIMMA 差异比较分析
' ============================================================================

''' <summary>
''' LIMMA 差异比较分析模块。
''' 
''' 分析内容：
''' 1. 多因素 ANOVA 检验
''' 2. limma 总体 F 检验
''' 3. limma 两两比较差异分析
''' 4. 时间序列数据：将时间因素作为协变量，消除时间因素做差异分析
''' 5. 火山图（显示 top5 差异分子名称）
''' 6. 文氏图（不同比较间的差异内容）
''' 7. 差异分子热图（列按样本分组排序，行做层次聚类，颜色块标记分子分类）
''' 
''' 默认按 pvalue &lt; 0.05 判断显著差异，代谢组数据增加 VIP > 1 条件。
''' 默认不考虑 logFC 阈值过滤，按 pvalue 和 VIP 筛选后，对剩余分子按 |logFC| 降序排序，
''' 取一定数量的 top 分子做差异分析结果。
''' </summary>
Public Class LimmaDiffModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "LIMMA Differential Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 4

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "limma_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return $"Design a plan for LIMMA differential analysis including:
1. Multi-factor ANOVA test on expression matrix
2. Overall F-test using limma
3. Pairwise comparisons using limma (based on comparison design from module 3)
4. For time-series data: include time as covariate, perform differential analysis with time effect removed
5. For metabolomics data: include VIP value calculation (VIP > {_config.Analysis.MetaboliteVipCutoff} threshold)
6. Default thresholds: pvalue < 0.05, no logFC cutoff, take top {_config.Analysis.DiffTopCount} molecules by |logFC| descending

# Implementation Requirements
- Read preprocessed expression matrix from tmp/ (files starting with 'preprocessed_')
- Read sample info table and comparison design from tables/comparison_design.csv
- Perform multi-factor ANOVA test
- Perform overall F-test using limma
- Perform pairwise limma comparisons for each comparison in the design
- For time-series data: include time as covariate in the design matrix
- For metabolomics data: calculate VIP values using mixOmics (must apply VIP > {_config.Analysis.MetaboliteVipCutoff} filter)
- Apply thresholds: pvalue < 0.05, VIP > {_config.Analysis.MetaboliteVipCutoff} (for metabolomics), no logFC cutoff
- Take top {_config.Analysis.DiffTopCount} molecules by |logFC| descending after pvalue/VIP filtering
- Generate the following plots (PNG + PDF, 300 dpi, English labels):
  - Volcano plots for each comparison (show top 5 differential molecule names)
  - Venn diagrams showing overlap of differential molecules across comparisons
  - Heatmaps of differential molecules:
    * Columns = samples, sorted by sample group
    * Rows = molecules, hierarchical clustering
    * Color blocks annotating molecule categories (from annotation table 'class' or 'category' column)
    * Display molecule names and sample names
- Save differential result tables as CSV in tables/ directory

# Plot Requirements
- Use ggplot2, ggvenn, pheatmap/ComplexHeatmap
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Handle missing packages gracefully"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 差异分析的整体结果（每个比较组的差异分子数量：上调、下调、总数）
2. 不同比较组之间差异分子的重叠情况（文氏图结果）
3. 关键差异分子的生物学功能（参考 kb.json 知识库和分子注释表）
4. 差异分子热图所展示的样本聚类模式
5. 差异分析结果与用户研究主题的生物学机制关联性
6. 不同比较组之间的规律性发现
7. 时间序列数据中时间效应的影响"
    End Function

End Class
