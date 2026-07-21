
Imports Microsoft.VisualBasic.Serialization.JSON

''' <summary>
''' 表示 LLM 为单个分析模块生成的分析计划。
''' 该计划描述了模块的分析目标、所需输入文件、预期输出文件、
''' 以及 LLM 编写的 R/Python 脚本内容。
''' </summary>
Public Class ModulePlan

    ''' <summary>模块名称</summary>
    Public Property ModuleName As String = ""

    ''' <summary>分析目标描述</summary>
    Public Property Goal As String = ""

    ''' <summary>所需输入文件路径列表</summary>
    Public Property InputFiles As List(Of String) = New List(Of String)()

    ''' <summary>预期输出文件路径列表</summary>
    Public Property OutputFiles As List(Of String) = New List(Of String)()

    ''' <summary>LLM 生成的 R 脚本内容</summary>
    Public Property RScriptContent As String = ""

    ''' <summary>LLM 生成的 R 脚本文件路径</summary>
    Public Property RScriptFile As String = ""

    ''' <summary>LLM 生成的 Python 脚本内容（可选）</summary>
    Public Property PythonScriptContent As String = ""

    ''' <summary>LLM 生成的 Python 脚本文件路径（可选）</summary>
    Public Property PythonScriptFile As String = ""

    ''' <summary>阶段性总结文本</summary>
    Public Property Conclusion As String = ""

    Public Function ToJson() As String
        Return Me.GetJson
    End Function

End Class
