Namespace AppRuntime

    ''' <summary>
    ''' 收尾模块的索引常量定义。
    ''' 
    ''' 结果表格整理与论文报告撰写这两个模块并非「可选的分析方法」，
    ''' 而是对前序所有分析产出的汇总与呈现，因此不参与 --module 参数的调度，
    ''' 而是在分析模块循环结束之后必定执行。
    ''' </summary>
    Public NotInheritable Class FinalizeModules

        Private Sub New()
        End Sub

        ''' <summary>结果表格整理模块索引</summary>
        Public Const ResultTablesIndex As Integer = 13
        ''' <summary>论文报告撰写模块索引</summary>
        Public Const ReportIndex As Integer = 14
        ''' <summary>自定义 JSON 模块的起始索引，须大于全部标准模块索引</summary>
        Public Const CustomModuleStartIndex As Integer = 15

        ''' <summary>
        ''' 收尾模块的执行顺序。顺序不可调换：
        ''' 报告模块需要引用结果表格模块整理出的表格产出。
        ''' </summary>
        Public Shared ReadOnly Property Indices As Integer() = {ResultTablesIndex, ReportIndex}

        ''' <summary>判断给定索引是否属于收尾模块</summary>
        Public Shared Function IsFinalizeModule(index As Integer) As Boolean
            Return index = ResultTablesIndex OrElse index = ReportIndex
        End Function
    End Class
End Namespace