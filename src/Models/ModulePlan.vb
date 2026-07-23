
Imports Microsoft.VisualBasic.Serialization.JSON

''' <summary>
''' 表示 LLM 为单个分析模块生成的分析计划。
''' 该计划描述了模块的分析目标、所需输入文件、预期输出文件、
''' 以及 LLM 编写的 R/Python 脚本内容。
''' </summary>
Public Class ModulePlan

    ''' <summary>模块名称</summary>
    Public Property module_name As String = ""

    ''' <summary>分析目标描述</summary>
    Public Property goal As String = ""

    ''' <summary>所需输入文件路径列表</summary>
    Public Property input_files As String()

    ''' <summary>预期输出文件路径列表</summary>
    Public Property output_files As String()

    Public Property execution_steps As [Step]()

    Public Property notes As String

    ''' <summary>阶段性总结文本</summary>
    Public Property conclusion As String = ""

    Public Function ToJson() As String
        Return Me.GetJson
    End Function

End Class

Public Class [Step]

    Public Property action As String
    Public Property goal As String
    Public Property rscript_path As String

End Class
