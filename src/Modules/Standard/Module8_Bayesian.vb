Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 8: 动态贝叶斯网络分析（bnlearn）
' ============================================================================

''' <summary>
''' 动态贝叶斯网络分析模块。
''' 
''' 分析内容：
''' 1. 时间序列数据：进行 bnlearn 动态贝叶斯网络的构建以及后续分析
''' 2. 识别分子/模块之间的调控关系
''' </summary>
Public Class BayesianNetworkModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Dynamic Bayesian Network Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 8

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "bayesian_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    ''' <summary>多组学场景下的贝叶斯网络补充要求</summary>
    Private Function MultiOmicsSection() As String
        If Not _context.IsMultiOmics Then
            Return ""
        End If

        Dim order As String = _context.Datasets.Select(Function(d) $"[{d.Id}] {d.DisplayName}（{d.OmicsType}）").JoinBy(" -> ")

        Return $"
# 多组学网络构建要求（重要）
- 本模块在多组学场景下的目标是构建**跨组学层间**的调控网络，而不是各组学各自建一张网络
- 各组学矩阵的样本列已统一为 subject_id（共 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个共有个体），
  按列名对齐后可直接把多个组学的节点放进同一张网络
- 节点选择：为控制网络规模与保证可解释性，每个组学只纳入关键分子
  （如差异分子、WGCNA 模块特征基因、聚类簇中心），并在计划中说明筛选依据
- **每个节点必须标注其组学来源**（建议节点名采用 '<组学id>:<分子id>' 的形式），
  绘图时按组学来源对节点着色
- 可依据中心法则设定层间先验顺序作为网络结构的白/黑名单约束：{order}
  若该顺序不符合实际生物学背景，请在计划中说明并给出更合理的顺序
- 重点关注跨组学的边（即起点与终点属于不同组学的调控边），这些边是多组学分析的核心产出
- 结果需分别统计组学内部边与跨组学边的数量
"
    End Function

    Protected Overrides Function GeneratePlanPromptText() As String
        Return $"为动态贝叶斯网络分析设计计划，使用 bnlearn R 包。
本分析适用于具有充足样本量的时间序列数据。
{MultiOmicsSection()}
# 上下游衔接说明
- 上游输入：{PreprocessedInputHint()}
- 上游输入：读取样本信息表中的时间信息
- 上游输入（可选）：读取模块 6(WGCNA) 或模块 7(CMeans) 的模块/聚类结果
- 下游输出：调控网络结果供模块 {If(_context.IsMultiOmics, "10(跨组学整合)、", "")}11(表格) 和模块 12(报告) 引用

# 实现要求
- 动态贝叶斯网络（仅时间序列数据）：
  - 按上方「上游输入」所列路径读取表达矩阵和时间信息
  - 使用 bnlearn 构建动态贝叶斯网络
  - 识别调控边
  - 绘制网络图

# 绘图要求
- 使用 bnlearn、igraph、ggplot2
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）
- 若数据非时间序列则跳过本分析
- 重点识别分子/模块之间的关键调控关系"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Dim items As String = "1. 动态贝叶斯网络分析结果（若适用，关键调控关系）
2. 分子/模块之间的调控网络拓扑特征
3. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
4. 与前面模块分析结果的一致性和补充性"

        If _context.IsMultiOmics Then
            items &= "
5. 跨组学调控边的数量与占比（区分组学内部边与跨组学边）
6. 识别出的关键跨组学调控关系，及其在中心法则框架下的生物学解读"
        End If

        Return items
    End Function

End Class
