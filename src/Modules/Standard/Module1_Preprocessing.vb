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
        Return "为表达矩阵数据设计预处理计划。标准预处理流程如下：
1. 按行（分子）用该分子最小阳性值的一半填充缺失值
2. 按列总和归一化，转化为相对表达量
3. 如有必要进行 log 转换（当最大值 > 100 时，表明数据未经过 log 转换）
4. 按行（分子）做中位数缩放

# 上下游衔接说明
- 本模块是整个分析流程的第一个模块，处理原始表达矩阵
- 预处理后的表达矩阵（CSV 文件，前缀 'preprocessed_'）将作为下游模块 2(PCA)、4(LIMMA)、6(WGCNA)、7(CMeans) 的输入

# 重要注意事项
- 检查研究主题中是否有用户指定的预处理例外情况
- 对于多组学数据，每个组学数据集应独立预处理
- 预处理后的矩阵须保存为 CSV 文件到 tmp/ 目录，文件名以 'preprocessed_' 为前缀"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 数据预处理的整体情况（每个组学数据集的样本数、分子数）
2. 缺失值填充、归一化、log转换、中位数缩放的具体参数和结果
3. 预处理前后数据分布的变化
4. 数据质量评估
5. 与用户研究主题的关联性说明"
    End Function

End Class
