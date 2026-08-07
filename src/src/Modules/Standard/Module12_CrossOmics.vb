Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 12: 跨组学整合分析（仅多组学场景执行）
' ============================================================================

''' <summary>
''' 跨组学整合分析模块。
''' 
''' 前置模块 1-11 均以「单个组学」为单位开展分析，各组学的结果彼此独立。
''' 本模块专门负责把这些相互独立的结果在统一的生物学个体（subject_id）层面
''' 打通，回答只有多组学联合才能回答的问题。
''' 
''' 分析内容：
''' 1. 跨组学分子间相关性网络（例如基因-代谢物关联）
''' 2. 组学层间整体一致性评估（Procrustes / RV 系数 / CCA）
''' 3. KEGG 通路层面的多组学联合映射
''' 4. 关键跨组学调控轴识别
''' 
''' 该模块仅在多组学场景下被实例化，单组学分析流程完全不受影响。
''' </summary>
Public Class CrossOmicsModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Cross Omics Integration"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 12

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "crossomics_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
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

        Return $"为跨组学整合分析设计计划。本分析的目标是把前面各模块中彼此独立的单组学结果，
在统一的生物学个体层面打通，回答只有多组学联合才能回答的科学问题。

# 参与整合的组学数据集（共 {datasets.Count} 个）
{omicsList}

需要考察的组学两两组合：{String.Join("、", pairs)}

# 数据对齐前提（非常重要）
- 所有组学的表达矩阵均已完成样本对齐：列名已统一替换为生物学个体标识 subject_id，
  且仅保留全部组学共有的个体，共 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个。
- 因此跨组学合并时可直接按列名（subject_id）对齐，**不需要**再做任何样本 ID 转换。
- 各组学样本 ID 与 subject_id 的原始对应关系记录在：{_context.SubjectMapFile}
- 合并矩阵前务必确认各组学矩阵的列顺序一致；若不一致，按 subject_id 重新排列后再合并。

# 上下游衔接说明
- 上游输入：模块 1 预处理后的各组学表达矩阵（tmp/ 目录，每个组学一个文件，见上方清单）
- 上游输入（可选）：模块 4 的差异分析结果、模块 5 的 KEGG/GSVA 结果、模块 6 的 WGCNA 模块特征基因
- 下游输出：跨组学整合结果供模块 13(Spearman+MIC 关联网络)、14(表格) 和模块 15(报告) 引用

# 实现要求

## 1. 跨组学分子间相关性网络
- 对每一组组学两两组合，计算跨组学的分子间相关性（Spearman 或 Pearson）
- 为控制计算量与假阳性：优先只纳入各组学中的差异分子或高变分子（例如各组学 top 500）
- 必须做多重检验校正（BH/FDR），并明确给出显著性阈值
- 输出显著的跨组学分子对及其相关系数、p 值、校正后 q 值
- 绘制跨组学相关性网络图，节点按组学来源着色

## 2. 组学层间整体一致性评估
- 在共有个体层面评估不同组学的整体结构是否一致
- 可选方法：Procrustes 分析、RV 系数、典型相关分析（CCA）、O2PLS
- 说明各组学是否呈现一致的样本分群结构

## 3. KEGG 通路层面的多组学联合映射
- 利用各组学各自的注释表把分子映射到 KEGG 通路
- 识别同时被多个组学富集或覆盖的通路（多组学共同响应通路）
- 绘制通路层面的多组学联合富集对比图

## 4. 关键跨组学调控轴识别
- 综合上述结果，识别贯穿多个组学层次的关键调控轴
- 结合研究主题说明其潜在生物学意义

# 注释表使用说明
- 各组学有各自专属的注释表，跨组学映射时务必使用对应组学自己的注释表
- 工作区中另有一张合并后的全局注释总表：{_context.AnnotationFile}
  该表包含 omics_id 列用于标识每条注释的组学来源，可按需筛选

# 绘图要求
- 使用 ggplot2、igraph、ComplexHeatmap、vegan（Procrustes）等
- 出版级质量主题
- 所有文字标签使用英文
- 图例中必须明确区分不同组学来源
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）
- 不同组学的数据单位与量纲不同（见上方清单），做相关性分析前务必先各自标准化
- 共有个体数量较少时，相关性结果不稳定，需在结论中明确说明样本量限制
- 避免把全部分子两两配对导致组合爆炸，必须先做分子筛选并说明筛选依据"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 跨组学分子间显著相关的分子对及其生物学含义
2. 各组学层次之间的整体一致性评估结果
3. 被多个组学共同覆盖或富集的 KEGG 通路
4. 识别出的关键跨组学调控轴
5. 跨组学整合结果是否支持用户的研究主题，多组学证据之间是否相互印证
6. 与前面各单组学模块分析结果的一致性和补充性"
    End Function

End Class
