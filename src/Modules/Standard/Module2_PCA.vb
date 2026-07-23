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
        Return "为总体样本分析设计计划，包括以下内容：
1. PCA（主成分分析）- 提取 PC1、PC2、PC3 得分
2. PLSDA（偏最小二乘判别分析）
3. OPLSDA（正交偏最小二乘判别分析）
4. 表达矩阵总体 F 检验
5. 多因素 ANOVA 检验

每项分析均需：
- 计算样本在各主成分上的得分
- 计算各样本到其组别质心的加权欧氏距离（按方差解释率加权）
- 采用置换检验评估组内距离是否显著小于组间距离
- 生成散点图，按样本分组着色，按元数据使用不同形状标记，并叠加置信椭圆
- 将得分表保存为 CSV
- 生成阶段性总结文本

# 上下游衔接说明
- 上游输入：读取模块 1 预处理后的表达矩阵（tmp/ 目录下，文件名以 'preprocessed_' 开头）
- 读取样本信息表获取分组标签
- 下游输出：分析结果供模块 4(LIMMA) 参考数据质量，供模块 11(报告) 引用

# 实现要求
- 读取 tmp/ 目录中预处理后的表达矩阵（文件名以 'preprocessed_' 开头）
- 读取样本信息表获取分组标签
- 使用 prcomp 或 FactoMineR 执行 PCA
- 使用 mixOmics 执行 PLSDA
- 使用 ropls 执行 OPLSDA
- 计算各样本到组别质心的加权欧氏距离（按方差解释率加权）
- 执行置换检验（n=1000）比较组内距离与组间距离
- 执行总体 F 检验和多因素 ANOVA
- 计算样本在各主成分上的得分
- 生成散点图，按样本分组着色，按元数据使用不同形状标记，并叠加置信椭圆
- 将得分表保存为 CSV
- 生成数据质量评估文本文件

# 绘图要求
- 使用 ggplot2 绘制出版级质量图形
- 各组别使用区分色（如 RColorBrewer 或 viridis 配色）
- 添加置信椭圆（stat_ellipse）
- 添加样本标签
- 同时保存 PNG（300 dpi）和 PDF 两种格式
- 所有文字标签使用英文

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）"
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
