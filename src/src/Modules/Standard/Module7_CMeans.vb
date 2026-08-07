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

    ''' <summary>多组学场景下的模糊聚类补充要求</summary>
    Private Function MultiOmicsSection() As String
        If Not _context.IsMultiOmics Then
            Return ""
        End If

        Return "
# 多组学聚类要求（重要）
- 每个组学必须**分别独立**做 CMeans 聚类，各自确定最优聚类数，
  不要把不同组学的分子放进同一个聚类空间（量纲与分子数量级差异会使聚类失去意义）
- 聚类结果文件带上组学标识，如 'cmeans_<组学id>_clusters.csv'
- 在各组学分别聚类完成后，额外做一次跨组学的表达趋势对比：
  - 各组学矩阵的样本列已统一为 subject_id，可直接按列名对齐
  - 把每个聚类簇的簇中心（cluster centroid）按 subject_id 提取为趋势向量
  - 计算不同组学聚类簇之间簇中心趋势的相关性，找出跨组学趋势一致的簇对
  - 绘制跨组学簇中心趋势对比图，用于展示不同组学层次上的协同变化模式
- 与 WGCNA 模块的关联对比，须在同一组学内部进行（即某组学的聚类簇 vs 同一组学的 WGCNA 模块）
"
    End Function

    Protected Overrides Function GeneratePlanPromptText() As String
        Return $"为 CMeans 模糊聚类分析设计计划，包括以下内容：
1. 对表达矩阵进行 CMeans 模糊聚类
   - 确定最优聚类数
   - 将分子聚类为模糊分组
   - 对每个聚类簇进行 KEGG 富集分析
   - 将聚类簇与 WGCNA 模块（来自模块 6）进行关联对比
{MultiOmicsSection()}
# 上下游衔接说明
- 上游输入：{PreprocessedInputHint()}
- 上游输入：读取模块 6 的 WGCNA 模块划分结果（用于关联对比）
- 下游输出：聚类结果供模块 {If(_context.IsMultiOmics, "12(跨组学整合)、", "")}13(Spearman+MIC 关联网络)、14(表格) 和模块 15(报告) 引用

# 实现要求
- CMeans 模糊聚类：
  - 按上方「上游输入」所列路径读取预处理后的表达矩阵
  - 确定最优聚类数（如使用验证指标）
  - 使用 e1071 或 Mfuzz 执行模糊 c-means 聚类
  - 对每个聚类簇进行 KEGG 富集分析
  - 将聚类簇与 WGCNA 模块进行关联对比（列联表、Fisher 精确检验）

# 绘图要求
- 使用 Mfuzz/e1071、clusterProfiler、ggplot2、ComplexHeatmap
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）
- 不适用的分析步骤可跳过"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Dim items As String = "1. CMeans 模糊聚类的整体结果（聚类数量、各簇的分子数量、关键簇的生物学功能）
2. 聚类簇与 WGCNA 模块的关联分析结果
3. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
4. 与前面模块分析结果的一致性和补充性"

        If _context.IsMultiOmics Then
            items &= "
5. 逐个组学分别报告聚类结果（须标明组学来源）
6. 跨组学趋势一致的聚类簇对，及其所提示的多组学协同变化模式"
        End If

        Return items
    End Function

End Class
