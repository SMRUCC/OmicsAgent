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
        Return $"为 LIMMA 差异分析设计计划，包括以下内容：
1. 表达矩阵多因素 ANOVA 检验
2. 使用 limma 进行总体 F 检验
3. 使用 limma 进行两两比对差异分析（基于模块 3 的比对设计）
4. 时间序列数据：将时间作为协变量纳入，消除时间效应后进行差异分析
5. 代谢组数据：计算 VIP 值（VIP > {_config.Analysis.MetaboliteVipCutoff} 阈值）
6. 默认阈值：pvalue < 0.05，不设 logFC 阈值，按 |logFC| 降序取 top {_config.Analysis.DiffTopCount} 个分子

# 上下游衔接说明
- 上游输入：读取模块 1 预处理后的表达矩阵（tmp/ 目录下，文件名以 'preprocessed_' 开头）
- 上游输入：读取模块 3 的比对设计（tables/comparison_design.csv，若缺失则读取 {$"{_context.AnalysisDir}/design.json"} 文件）
- 下游输出：差异分析结果表（前缀 'limma_'）将作为模块 5(KEGG 富集分析) 的输入分子列表，供模块 10(表格) 和模块 11(报告) 引用

# 实现要求
- 读取 tmp/ 目录中预处理后的表达矩阵（文件名以 'preprocessed_' 开头）
- 读取样本信息表和比对设计（tables/comparison_design.csv，若缺失则从 {$"{_context.AnalysisDir}/design.json"} 文件读取）
- 执行多因素 ANOVA 检验
- 使用 limma 执行总体 F 检验
- 对比对设计中的每个比对执行 limma 两两比较
- 时间序列数据：在设计矩阵中将时间作为协变量
- 代谢组数据：使用 mixOmics 计算 VIP 值（必须应用 VIP > {_config.Analysis.MetaboliteVipCutoff} 过滤）
- 应用阈值：pvalue < 0.05，VIP > {_config.Analysis.MetaboliteVipCutoff}（代谢组），不设 logFC 阈值
- pvalue/VIP 过滤后，按 |logFC| 降序取 top {_config.Analysis.DiffTopCount} 个分子
- 生成以下图形（PNG + PDF，300 dpi，英文标签）：
  - 各比对的火山图（标注 top 5 差异分子名称）
  - 文氏图（展示各比对间差异分子的重叠情况）
  - 差异分子热图：
    * 列 = 样本，按样本分组排序
    * 行 = 分子，层次聚类
    * 颜色块标注分子分类（来自注释表的 'class' 或 'category' 列）
    * 显示分子名称和样本名称
- 将差异分析结果表保存为 CSV 到 tables/ 目录

# 绘图要求
- 使用 ggplot2、ggvenn、pheatmap/ComplexHeatmap
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）"
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
