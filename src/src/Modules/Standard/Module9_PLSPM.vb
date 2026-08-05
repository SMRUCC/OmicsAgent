Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 9: PLS-PM 因果路径分析
' ============================================================================

''' <summary>
''' PLS-PM 因果路径分析模块。
''' 
''' 分析内容：
''' 1. 多组学数据且样本量足够：按不同的组学层次构建潜变量
''' 2. 进行 PLS-PM 因果路径分析
''' </summary>
Public Class PLSPMAnalysisModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "PLS-PM Causal Path Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 9

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "plspm_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        ' PLS-PM 的建模对象是「组学层次之间」的因果路径，本质上要求存在两个及以上的组学层次。
        ' 单组学场景下不具备建模前提，此处直接给出明确的跳过指令，
        ' 而不是让 LLM 自行判断——后者容易勉强构造出没有生物学意义的路径模型。
        If Not _context.IsMultiOmics Then
            Return $"本次为**单组学**分析，只有一个组学数据集：{_context.Datasets.FirstOrDefault?.DisplayName}。

PLS-PM（偏最小二乘路径建模）的建模对象是不同组学层次之间的因果路径，
需要至少两个组学层次才能构建有意义的路径模型，因此本模块在单组学场景下不适用。

# 你的任务
请直接跳过本模块的分析，生成一个不做任何实质计算的最简计划，并在结论中说明：
本次分析为单组学数据，不具备构建跨组学层次因果路径模型的前提条件，故跳过 PLS-PM 分析。

不要为了执行本模块而把单个组学人为拆分成多个伪层次，那样得到的路径系数没有生物学意义。"
        End If

        Dim datasets = _context.Datasets
        Dim blocks As String = datasets _
            .Select(Function(d) $"  - [{d.Id}] {d.DisplayName}（{d.OmicsType}）：tmp/{d.PreprocessedFileName}") _
            .JoinBy(vbLf)

        Dim pathOrder As String = datasets.Select(Function(d) $"[{d.Id}]").JoinBy(" -> ")

        Return $"为 PLS-PM（偏最小二乘路径建模）因果路径分析设计计划。
本次为多组学分析，共 {datasets.Count} 个组学层次，具备构建跨组学因果路径模型的前提。

# 潜变量分块（每个组学对应一个潜变量块）
{blocks}

# 样本对齐前提
- 各组学矩阵的样本列名已统一为 subject_id，共有个体 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个
- 构建潜变量时必须只使用这批共有个体，且各块的观测顺序必须严格按 subject_id 对齐后再建模
- PLS-PM 要求各数据块行数一致且行序对应，请在建模前显式做一次 subject_id 排序与校验

# 上下游衔接说明
- 上游输入：{PreprocessedInputHint()}
- 上游输入（可选）：读取模块 5(KEGG GSVA) 或模块 6(WGCNA 模块特征基因) 的结果作为潜变量的观测变量
- 下游输出：因果路径分析结果供模块 12(跨组学整合)、13(表格) 和模块 14(报告) 引用

# 实现要求
- 为每个组学层次构建潜变量块
  - 直接使用分子表达量作为观测变量时，需先做变量筛选（如差异分子或高变分子）以控制块内变量数
  - 也可使用 WGCNA 模块特征基因或 GSVA 通路得分作为观测变量，通常更稳健
- 依据中心法则设定层间路径方向，建议顺序：{pathOrder}
  若该顺序不符合实际生物学背景，请在计划中说明并给出更合理的路径设定
- 构建 inner model 邻接矩阵与 outer model 分块定义
- 估计路径系数，并报告 R²、GoF 拟合优度、以及各路径系数的 bootstrap 置信区间
- 绘制路径图，节点按组学层次着色

# 绘图要求
- 使用 plspm、igraph、ggplot2
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）
- 样本量不足（共有个体数明显少于观测变量数）时，PLS-PM 结果不稳定，
  此时应减少观测变量数量或改用模块特征基因，并在结论中明确说明样本量限制
- 重点分析各组学层次之间的因果关系强度与方向"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        If Not _context.IsMultiOmics Then
            Return "1. 说明本次为单组学分析，不具备构建跨组学因果路径模型的前提，本模块已跳过"
        End If

        Return "1. PLS-PM 因果路径分析结果（各组学层次之间的因果路径及其方向）
2. 各组学层次潜变量的构建方式、观测变量选择及路径系数
3. 模型拟合优度（R²、GoF）与路径系数的显著性
4. 哪一条跨组学路径的效应最强，其生物学解读
5. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
6. 与前面模块分析结果的一致性和补充性
7. 共有个体数量对模型稳定性的影响说明"
    End Function

End Class
