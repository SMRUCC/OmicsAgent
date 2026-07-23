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
        Return "Design a preprocessing plan for the expression matrix data. The standard preprocessing workflow is:
1. Fill missing values with half of the minimum positive value per molecule (row)
2. Normalize by column sum to convert to relative expression
3. Apply log transformation if necessary (when max value > 100, indicating non-log scale)
4. Median scaling per row (molecule)

# Important Notes
- Check the research topic for any user-specified preprocessing exceptions
- For multi-omics data, each omics dataset should be preprocessed separately
- The preprocessed matrix should be saved as CSV in the tmp/ directory"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 数据预处理的整体情况（每个组学数据集的样本数、分子数）
2. 缺失值填充、归一化、log转换、中位数缩放的具体参数和结果
3. 预处理前后数据分布的变化
4. 数据质量评估
5. 与用户研究主题的关联性说明"
    End Function

End Class
