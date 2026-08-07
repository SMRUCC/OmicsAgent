Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 13: Spearman + MIC 跨组学关联网络分析
' ============================================================================

''' <summary>
''' 基于 Spearman 秩相关与 MIC（最大信息系数）双重方法的关联网络分析模块。
'''
''' 该模块使用两种互补的关联度量来挖掘分子之间的关系：
''' 1. Spearman 秩相关：捕捉分子对之间的单调关联，输出相关系数 rho 与 p 值
''' 2. MIC 最大信息系数：捕捉线性与非线性关联，输出 MIC 值及 MIC-ρ² 差值
'''    用于判别关联是线性还是非线性关系
'''
''' 两种方法联合筛选：同时满足 Spearman 显著性阈值与 MIC 阈值的分子对
''' 才被判定为显著关联边，从而在控制假阳性的同时保留非线性关联。
'''
''' 分析内容：
''' 1. 显著关联边列表（分子对、来源组学、Spearman rho、p 值、q 值、MIC、MIC-ρ²、方向、类型）
''' 2. 网络节点属性表（度数、中心性指标）与网络拓扑统计（社团划分、跨组学边占比）
''' 3. 关联网络可视化（网络图、关联强度热图、Spearman vs MIC 散点、枢纽节点条形图）
'''
''' 该模块在单组学与多组学场景下均会执行：
''' - 多组学场景：以「跨组学分子对」为核心，按 subject_id 对齐后计算组学两两之间的分子关联
''' - 单组学场景：退化为「组学内部分子-分子关联网络」，流程与产出结构保持一致，模块不会被跳过
''' </summary>
Public Class AssociationNetworkModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Spearman MIC Association Network"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 13

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "assocnet_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    ''' <summary>
    ''' 多组学场景下的跨组学层间关联要求。
    ''' </summary>
    ''' <remarks>
    ''' 多组学场景下以「跨组学分子对」为核心，按 subject_id 对齐后计算组学两两之间的分子关联。
    ''' 单组学时返回空串，交由 SingleOmicsSection() 说明退化的组学内部网络方案。
    ''' </remarks>
    Private Function MultiOmicsSection() As String
        If Not _context.IsMultiOmics Then
            Return ""
        End If

        Dim datasets = _context.Datasets
        Dim omicsList As String = String.Join(vbLf, datasets.Select(
            Function(d) $"  - [{d.Id}] {d.DisplayName}：组学类型 {d.OmicsType}" &
                        If(d.Unit.StringEmpty(, True), "", $"，数据单位 {d.Unit}") &
                        $"，预处理产物 tmp/{d.PreprocessedFileName}"))

        Dim pairs As New List(Of String)

        For i As Integer = 0 To datasets.Count - 2
            For j As Integer = i + 1 To datasets.Count - 1
                pairs.Add($"{datasets(i).Id} x {datasets(j).Id}")
            Next
        Next

        Return $"
# 多组学关联分析要求（重要）
- 本模块在多组学场景下需要完成**两个层次**的关联网络，缺一不可：
  1. **组学内部关联网络**：对每个组学分别独立计算分子之间的关联，输出文件带各自的组学标识
  2. **跨组学关联网络**：对每一组组学两两组合，计算「组学 A 的分子」与「组学 B 的分子」之间的关联，
     输出文件统一命名为 '{CsvFileNamePrefix}cross.csv' 形式
- 参与跨组学关联计算的组学两两组合：{String.Join("、", pairs)}
- 参与计算的各组学矩阵如下：
{omicsList}
- 各矩阵的样本列名已统一为 subject_id（共 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个共有个体），
  跨组学对齐时按列名对齐即可，无需任何样本 ID 转换；合并前务必确认列顺序一致
- 最终网络图中节点按来源组学着色，须明确区分组学内部边与跨组学边，
  并在拓扑统计中汇报跨组学边的占比
- 结论中需比较：跨组学关联边中哪些关联是单组学模块（如模块 4 差异分析、模块 6 WGCNA）已提示过的关系，
  哪些是跨组学层面新发现的关联
"
    End Function

    ''' <summary>
    ''' 单组学场景下的退化方案：组学内部分子-分子关联网络。
    ''' </summary>
    ''' <remarks>
    ''' 单组学时不存在跨组学分子对，本模块退化为「组学内部分子-分子关联网络」，
    ''' 流程（两阶段筛选、FDR 校正、边列表、节点属性、网络可视化）与多组学保持一致。
    ''' 多组学时返回空串，交由 MultiOmicsSection() 说明跨组学层间关联方案。
    ''' </remarks>
    Private Function SingleOmicsSection() As String
        If _context.IsMultiOmics Then
            Return ""
        End If

        Dim single_ = _context.Datasets.FirstOrDefault

        If single_ Is Nothing Then
            Return ""
        End If

        Return $"
# 单组学关联分析说明
- 本次为**单组学**分析，只有一个组学数据集：[{single_.Id}] {single_.DisplayName}
  （组学类型 {single_.OmicsType}{If(single_.Unit.StringEmpty(, True), "", $"，数据单位 {single_.Unit}")}），
  不存在跨组学分子对，本模块**退化为组学内部分子-分子关联网络**。
- 读取该组学预处理后的表达矩阵：tmp/{single_.PreprocessedFileName}
- 虽然只有一个组学，但分子数量仍然很大，必须同样执行下方的「两阶段筛选 + FDR 校正」流程，
  并产出与多组学一致的边列表、节点属性表、网络拓扑统计与所有可视化图形。
- 网络图中节点的「来源组学」均标记为 [{single_.Id}]，因此本场景下不存在跨组学边，
  拓扑统计中跨组学边占比记为 0，并据此说明这是单组学内部关联网络。
"
    End Function

    Protected Overrides Function GeneratePlanPromptText() As String
        Return $"为 Spearman + MIC 关联网络分析设计计划。本分析的目标是基于
Spearman 秩相关与 MIC（最大信息系数）两种互补方法，挖掘分子之间的显著关联关系，
导出显著关联网络（边列表 + 节点属性）并生成网络可视化结果。
{SingleOmicsSection()}
{MultiOmicsSection()}
# 上下游衔接说明
- 上游输入：{PreprocessedInputHint()}
- 上游输入（可选）：模块 4(LIMMA 差异分析) 的差异分子列表，作为分子初筛的优先来源
- 上游输入（可选）：模块 6(WGCNA) 的模块特征基因、模块 10(随机森林) 的重要特征，可纳入关联分析
- 下游输出：显著关联网络与拓扑统计供模块 14(表格) 和模块 15(报告) 引用

# 实现要求

## 1. 分子初筛（控制组合爆炸，必须最先执行）
- 分子对数量为 O(N×M)，全量配对在组学数据规模下不可行，必须先做分子筛选
- 筛选优先级：差异分子（模块 4 结果，如有） > 高变分子（按 MAD 或方差排序 top N）
- 每组学建议纳入 ≤ 500 个分子，并在结果中明确记录筛选依据与最终纳入的分子数
- 本模块的后续所有关联计算只在筛选后的分子子集上进行

## 2. 两阶段关联度量（核心方法）
- 在计算前，对每组学分别做标准化（z-score），消除量纲与单位差异
- **阶段一（Spearman 粗筛）**：对所有筛选后的分子对计算 Spearman 秩相关系数 rho 与 p 值，
  得到全量 p 值矩阵，先做 FDR/BH 多重检验校正得到 q 值
- **阶段二（MIC 精筛）**：仅对阶段一中通过初筛（如 q < 0.05）的分子对计算 MIC（最大信息系数），
  将 MIC 计算量从 O(N×M) 降到显著边规模，避免性能灾难
- 额外计算 **MIC-ρ² 差值** = MIC - rho²，用于判别关联类型：
  该差值越大，越倾向非线性关联；差值接近 0，则关联近似线性
- MIC 的具体 R 实现由你自行选择（例如可通过合适的 R 包计算），
  若所需 R 包缺失则自动安装；不得因缺少特定包而中断整个模块

## 3. 显著关联边的联合筛选
- 采用「Spearman + MIC 双重筛选」判定显著关联边：
  一个分子对必须**同时满足** Spearman 显著性阈值（如 q < 0.05）与 MIC 阈值（如 MIC > 0.3）
  才被判定为显著关联边，从而在控制假阳性的同时保留非线性关联
- 导出显著关联边列表（边表），列至少包括：
  分子 A ID、分子 A 名称、分子 B ID、分子 B 名称、
  分子 A 来源组学、分子 B 来源组学（来源组学标识须与上方数据集清单的方括号 id 一致）、
  Spearman rho、Spearman p 值、Spearman q 值（FDR 校正）、MIC 值、MIC-ρ² 差值、
  关联方向（正/负，由 rho 符号决定）、关联类型（线性/非线性，由 MIC-ρ² 差值判定）
- 边表是本模块的核心产出，文件名请使用 '{CsvFileNamePrefix}edges.csv' 形式

## 4. 网络节点属性与拓扑统计
- 基于显著关联边构建关联网络（无向图，节点=分子，边=显著关联），并计算每个节点的：
  度数（degree）、加权度数、接近中心性（closeness）、中介中心性（betweenness）
- 导出节点属性表（节点表），列至少包括：
  节点 ID、节点名称、来源组学、度数、加权度数、接近中心性、中介中心性、是否为枢纽节点（hub，按度数 Top 排序判定）
- 节点表文件名请使用 '{CsvFileNamePrefix}nodes.csv' 形式
- 进行网络社团划分（如 Louvain / fast greedy 模块度优化），导出社团归属表
- 汇总网络拓扑统计，至少包括：
  节点总数、显著边总数、正/负相关边占比、跨组学边占比（多组学时）、模块数量与最大社团规模

# 绘图要求
- 使用 ggplot2、igraph、ggnetwork / ggraph、ComplexHeatmap 等
- 必须绘制以下图形，全部保存为 {FiguresDir.GetDirectoryFullPath} 下的文件：
  - 关联网络图：节点按来源组学着色，边按正/负相关着色、按关联强度（|rho| 或 MIC）设置粗细，
    hub 节点以更大的尺寸突出；跨组学边以特殊线型区分
  - 关联强度热图：并排绘制 Spearman 矩阵与 MIC 矩阵双对照热图
  - Spearman vs MIC 散点图：横轴 Spearman rho、纵轴 MIC，标识出 MIC-ρ² 差值大的非线性关联候选点
  - 枢纽节点（hub）度数排序条形图：Top 若干节点的度数排序
- 出版级质量主题
- 所有文字标签使用英文
- 每张图同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装），MIC 计算相关的依赖缺失时不可中断整个模块
- 不同组学的数据单位与量纲不同（见上方清单），做关联分析前务必先各自标准化
- 共有个体数量较少时，关联结果不稳定，须在结论中明确说明样本量限制
- 避免把全部分子两两配对导致组合爆炸，必须先做分子筛选并说明筛选依据；
  MIC 计算必须放在 Spearman 粗筛之后，只对通过初筛的分子对计算
- 网络中不允许出现孤立边以外的无效节点；导出边表、节点表、社团表时须保证 ID 一致可追溯"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Dim items As String = "1. 分子初筛的依据与最终纳入关联分析分子数（差异分子优先还是高变分子 top N）
2. 两阶段关联度量的方法说明：Spearman 粗筛阈值、MIC 精筛阈值、FDR 校正方式
3. 显著关联对总体情况：显著边总数、正/负相关边占比，以及若干最具生物学意义的强关联分子对
4. 线性与非线性关联的判别：基于 MIC-ρ² 差值识别出的非线性关联候选，及其可能的生物学含义
5. 网络拓扑特征：节点总数、模块（社团）数量、最大社团规模，以及枢纽节点（hub）及其度数
6. 显著关联网络是否与研究主题一致，关键关联是否能在生物网络/通路层面得到解释
7. 与上游模块结果的一致性：显著关联涉及的关键分子是否与模块 4 差异分子、模块 6 WGCNA 模块、
   模块 10 随机森林重要特征相印证"

        If _context.IsMultiOmics Then
            items &= "
8. 跨组学关联边的情况：各跨组学组合（如 A×B）的显著边数量、占比，以及跨组学边整体的占比
9. 哪些跨组学关联是模块 12 跨组学整合已提示的关系，哪些是本模块新发现的跨组学关联"
        Else
            items &= "
8. 单组学场景说明：本模块退化为组学内部分子-分子关联网络，跨组学边占比为 0"
        End If

        Return items
    End Function

End Class
