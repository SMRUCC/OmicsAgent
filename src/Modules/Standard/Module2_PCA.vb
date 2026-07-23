Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 2: 总体样本 PCA/PLSDA/OPLSDA 分析
' ============================================================================

''' <summary>
''' 总体样本 PCA/PLSDA/OPLSDA 分析模块。
''' 
''' 分析内容：
''' 1. PCA 主成分分析
''' 2. PLSDA 偏最小二乘判别分析
''' 3. OPLSDA 正交偏最小二乘判别分析
''' 4. 表达矩阵总体 F 检验
''' 5. 表达矩阵总体多因素 ANOVA 检验
''' 
''' 基于 PCA 结果计算各样本到组别质心的加权欧氏距离作为组内离散度，
''' 采用置换检验判断组内距离是否显著小于组间距离，评估数据重复性质量。
''' </summary>
Public Class PCAAnalysisModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "PCA/PLSDA/OPLSDA Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 2

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "pca_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "Design a plan for overall sample analysis including:
1. PCA (Principal Component Analysis) - extract PC1, PC2, PC3 scores
2. PLSDA (Partial Least Squares Discriminant Analysis)
3. OPLSDA (Orthogonal PLS-DA)
4. Overall F-test on expression matrix
5. Multi-factor ANOVA test

For each analysis:
- Calculate sample scores on principal components
- Compute weighted Euclidean distance from each sample to its group centroid (weighted by variance explained)
- Use permutation test to assess if intra-group distance is significantly smaller than inter-group distance
- Generate scatter plots with confidence ellipses, colored by sample group, with different shapes for metadata
- Save score tables as CSV
- Generate stage conclusion text

# Implementation Requirements
- Read the preprocessed expression matrix from tmp/ (files starting with 'preprocessed_')
- Read the sample info table to get group labels
- Perform PCA using prcomp or FactoMineR
- Perform PLSDA using mixOmics
- Perform OPLSDA using ropls
- Compute weighted Euclidean distance from each sample to group centroid (weighted by variance explained)
- Perform permutation test (n=1000) for intra-group vs inter-group distance
- Perform overall F-test and multi-factor ANOVA
- Calculate sample scores on principal components
- Generate scatter plots with confidence ellipses, colored by sample group, with different shapes for metadata
- Save score tables as CSV
- Generate a quality assessment text file

# Plot Requirements
- Use ggplot2 with publication-quality theme
- Use distinct colors for groups (e.g., RColorBrewer or viridis)
- Add confidence ellipses (stat_ellipse)
- Add sample labels
- Save both PNG (300 dpi) and PDF versions
- All text labels in English

# Important Notes
- Handle missing packages gracefully (install if missing)"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. PCA/PLSDA/OPLSDA 分析的整体结果
2. 各组别在主成分上的分离情况
3. 模型解释率（R2X, R2Y, Q2）
4. 置换检验结果，组内离散度与组间离散度的比较
5. 数据重复性质量评估
6. F 检验和 ANOVA 检验的总体结果
7. 与用户研究主题的生物学关联性说明
8. 若数据质量不佳，给出明确的警告信息"
    End Function

End Class
