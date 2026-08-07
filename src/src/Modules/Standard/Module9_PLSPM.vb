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
            Return SingleOmicsPrompt()
        Else
            Return MultipleOmicsPrompt()
        End If
    End Function

    Private Function SingleOmicsPrompt() As String
        Return $"你是一个顶级的生物信息学数据分析专家和R语言程序员。你的当前任务是：基于用户提供的单组学表达矩阵、WGCNA分析结果以及KEGG通路注释结果，构建 Partial Least Squares Path Modeling (PLS-PM) 因果网络模型。
你需要通过编写R脚本，构建模块与通路之间的调控关系路径，执行分析，生成可视化图表，并从结果中提炼生物学机制。

## 数据输入规范
在执行任务前，确认以下数据对象已在R环境中可用：

+ expr_data: 标准化后的表达矩阵（行为分子/基因，列为样本）。
+ wgcna_modules: WGCNA模块归属数据框（至少包含两列：molecule 和 module_color 或 module_name）。
+ kegg_annotation: KEGG通路注释数据框（至少包含两列：molecule 和 pathway_id 或 pathway_name）。
+ me_matrix (可选): WGCNA计算出的模块特征基因矩阵，样本为行，模块为列。若无，需在脚本中计算。

## 核心执行步骤与规则
步骤 1：构建 PLS-PM 数据模型（潜变量与显变量定义）
请LLM根据输入数据，遵循以下规则构建PLS-PM所需的blocks（显变量列表）和path_matrix（路径矩阵）：

潜变量定义：将WGCNA模块（如""MEblue"", ""MEbrown""）和KEGG通路（如""hsa04910"", ""hsa04210""）均定义为潜变量。
显变量选择：
为避免显变量重叠导致的多重共线性问题，严禁将同一个分子同时分配给模块和通路。
对于模块潜变量：选取该模块内连通性或模块隶属度最高的Top 5-10个分子作为显变量；或者直接使用模块特征基因作为单一显变量（推荐，以提高模型稳定性）。
对于通路潜变量：选取该通路内表达方差最大或差异最显著的Top 5-10个分子作为显变量。确保这些分子不属于上述任何模块的显变量集。
路径矩阵设定：
基于先验生物学知识设定路径方向。通常设定为：KEGG通路 -> WGCNA模块（即通路调控模块共表达），或 WGCNA模块 -> KEGG通路。
路径矩阵必须为下三角矩阵，符合plspm包的输入要求。不得存在循环路径。

# 绘图要求
- 使用 plspm、igraph、ggplot2
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式
"
    End Function

    Private Function MultipleOmicsPrompt() As String
        Dim datasets = _context.Datasets
        Dim blocks As String = datasets _
            .Select(Function(d) $"  - [{d.Id}] {d.DisplayName}（{d.OmicsType}）：tmp/{d.PreprocessedFileName}") _
            .JoinBy(vbLf)

        Dim pathOrder As String = datasets.Select(Function(d) $"[{d.Id}]").JoinBy(" -> ")

        Return $"你是一个顶级的生物信息学数据分析专家和R语言程序员。你的当前任务是为 PLS-PM（偏最小二乘路径建模）因果路径分析设计计划。
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
  - 直接使用KEGG数据库注释结果构建潜变量
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
            Return "1. PLS-PM 因果路径分析结果
2. 各WGCNA模块，KEGG通路层次潜变量的构建情况及路径系数
3. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
4. 与前面模块分析结果的一致性和补充性"
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
