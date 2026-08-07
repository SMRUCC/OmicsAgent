Imports Microsoft.VisualBasic.ComponentModel.DataSourceModel.SchemaMaps
Imports Microsoft.VisualBasic.ComponentModel.Settings.Inf

Namespace AppRuntime.Ini

    ''' <summary>最终报告输出配置段 [report]</summary>
    <ClassName("report")>
    Public Class ReportConfig

        ''' <summary>
        ''' 报告输出格式，取值：
        ''' <list type="bullet">
        ''' <item><description><c>pdf</c>：仅生成 HTML 并由 wkhtmltopdf 转换为 PDF（默认，与旧版本行为一致）</description></item>
        ''' <item><description><c>docx</c>：仅生成 Word 文档</description></item>
        ''' <item><description><c>both</c>：PDF 与 Word 文档均生成</description></item>
        ''' </list>
        ''' </summary>
        <DataFrameColumn("format")> Public Property OutputFormat As String = ReportOutputFormats.Pdf

    End Class

    ''' <summary>报告输出格式取值常量与判定helper</summary>
    Public Module ReportOutputFormats

        Public Const Pdf As String = "pdf"
        Public Const Docx As String = "docx"
        Public Const Both As String = "both"

        ''' <summary>判定给定的格式字符串是否为受支持的取值</summary>
        Public Function IsValid(format As String) As Boolean
            Select Case LCase(Trim(If(format, "")))
                Case Pdf, Docx, Both : Return True
                Case Else : Return False
            End Select
        End Function

        ''' <summary>是否需要输出 HTML/PDF</summary>
        Public Function RequirePdf(format As String) As Boolean
            Dim normalized As String = LCase(Trim(If(format, "")))
            Return normalized = Pdf OrElse normalized = Both OrElse Not IsValid(normalized)
        End Function

        ''' <summary>是否需要输出 Word docx</summary>
        Public Function RequireDocx(format As String) As Boolean
            Dim normalized As String = LCase(Trim(If(format, "")))
            Return normalized = Docx OrElse normalized = Both
        End Function

    End Module
End Namespace