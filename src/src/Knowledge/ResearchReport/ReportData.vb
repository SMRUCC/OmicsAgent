Imports Microsoft.VisualBasic.MIME.text.markdown

Namespace ReportData

    ''' <summary>
    ''' 报告内容数据模型。
    ''' 
    ''' 正文部分（引言/材料与方法/结果章节正文/讨论/结论）统一采用
    ''' <see cref="JSONSchema.Block"/> 结构化内容块数组承载，由 LLM 直接生成，
    ''' 避免 markdown 纯文本的语法错误导致排版混乱。
    ''' 标题、摘要、关键词等单行元信息保持字符串形态。
    ''' </summary>
    Public Class ReportContent

        ''' <summary>报告标题，单行元信息</summary>
        Public Property title As String = ""
        ''' <summary>中文摘要，单段连续文本</summary>
        Public Property abstract As String = ""
        ''' <summary>关键词列表</summary>
        Public Property keywords As String()

        ''' <summary>引言正文，结构化内容块数组</summary>
        Public Property introduction As JSONSchema.Block()
        ''' <summary>材料与方法正文，结构化内容块数组</summary>
        Public Property materials_methods As JSONSchema.Block()
        ''' <summary>结果章节列表，每个章节携带正文块与图表引用</summary>
        Public Property results_sections As ResultSection()
        ''' <summary>讨论正文，结构化内容块数组</summary>
        Public Property discussion As JSONSchema.Block()
        ''' <summary>结论正文，结构化内容块数组</summary>
        Public Property conclusion As JSONSchema.Block()

    End Class

    ''' <summary>结果章节：正文块 + 该章节引用的图与表</summary>
    Public Class ResultSection

        ''' <summary>该章节对应的分析模块编号</summary>
        Public Property module_index As Integer
        ''' <summary>章节标题，单行元信息</summary>
        Public Property title As String = ""
        ''' <summary>章节正文，结构化内容块数组</summary>
        Public Property content As JSONSchema.Block()
        ''' <summary>该章节引用的插图</summary>
        Public Property figures As TableFigureCaption()
        ''' <summary>该章节引用的数据表</summary>
        Public Property tables As TableFigureCaption()

    End Class

    Public Class TableFigureCaption

        Public Property file As String = ""
        Public Property type As String
        ''' <summary>
        ''' field names to display on html report.
        ''' empty means * for display all fields
        ''' </summary>
        ''' <returns></returns>
        Public Property fields As String()
        Public Property caption_cn As String = ""
        Public Property caption_en As String = ""

        Public Overrides Function ToString() As String
            Return $"[{type}] {caption_cn}"
        End Function
    End Class

End Namespace
