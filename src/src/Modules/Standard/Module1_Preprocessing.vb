Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 1: 表达矩阵数据预处理
' ============================================================================

''' <summary>
''' 表达矩阵数据预处理模块。
''' 
''' 预处理流程：
''' 1. 按行做分子表达数据最小阳性值的一半做缺失值填充
''' 2. 按列总和归一化转化为相对表达量
''' 3. 如有必要，针对归一化后的值做 log 转换
''' 4. 按行做中位数缩放
''' 
''' 除非用户在 research 文件中明确标注某个表达矩阵不需要预处理，否则默认执行。
''' </summary>
Public Class PreprocessingModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Expression Matrix Preprocessing"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 1

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "preprocess_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Dim datasets = _context.Datasets
        Dim outputs As String = datasets _
            .Select(Function(d) $"  - [{d.Id}] {d.DisplayName}" &
                                If(d.Unit.StringEmpty(, True), "", $"（原始单位 {d.Unit}）") &
                                $" -> tmp/{d.PreprocessedFileName}") _
            .JoinBy(vbLf)

        Dim multiOmicsNotes As String = ""

        If _context.IsMultiOmics Then
            multiOmicsNotes = "
# 多组学预处理要求
- 每个组学必须**独立**完成上述预处理流程，各组学之间不得混合计算归一化因子或缩放系数
- 不同组学的数据单位与量纲差异很大（见上方清单），必须分别判断是否需要 log 转换，
  不要用同一个阈值一刀切地套用到所有组学
- 各组学的样本列名已统一为 subject_id 且顺序一致，预处理过程中务必保持列名与列顺序不变，
  这是后续跨组学整合分析能够按列名直接合并的前提
- 预处理完成后，请分别报告每个组学的样本数、分子数以及所采用的具体处理参数"
        End If

        Return $"为表达矩阵数据设计预处理计划。标准预处理流程如下：
1. 按行（分子）用该分子最小阳性值的一半填充缺失值
2. 按列总和归一化，转化为相对表达量
3. 如有必要进行 log 转换（当最大值 > 100 时，表明数据未经过 log 转换）
4. 按行（分子）做中位数缩放

# 上下游衔接说明
- 本模块是整个分析流程的第一个模块，处理原始表达矩阵
- 预处理后的表达矩阵将作为下游模块 2(PCA)、4(LIMMA)、6(WGCNA)、7(CMeans){If(_context.IsMultiOmics, "、10(跨组学整合)", "")} 的输入
{multiOmicsNotes}

# 预处理产物命名（严格遵守）
预处理后的矩阵须保存为 CSV 文件到 tmp/ 目录，且必须按下列对应关系逐一命名：
{outputs}

文件名中的组学标识必须与上方数据集清单中方括号内的 id 完全一致，不得自行改写或合并输出。

# 重要注意事项
- 检查研究主题中是否有用户指定的预处理例外情况
- 预处理只改变数值，不得增删分子行或样本列"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 数据预处理的整体情况（每个组学数据集的样本数、分子数）
2. 缺失值填充、归一化、log转换、中位数缩放的具体参数和结果
3. 预处理前后数据分布的变化
4. 数据质量评估
5. 与用户研究主题的关联性说明"
    End Function

End Class
