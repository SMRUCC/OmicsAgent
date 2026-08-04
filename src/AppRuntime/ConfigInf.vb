
' ==================================================================
' 段子对象定义
' ==================================================================

Imports Microsoft.VisualBasic.ComponentModel.DataSourceModel.SchemaMaps
Imports Microsoft.VisualBasic.ComponentModel.Settings.Inf

Namespace AppRuntime

    ''' <summary>外部工具路径配置段 [tools]</summary>
    <ClassName("tools")>
    Public Class ToolConfig
        <DataFrameColumn("rscript")> Public Property RscriptPath As String = ""
        <DataFrameColumn("wkhtmltopdf")> Public Property WkHtmlToPdfPath As String = ""
        <DataFrameColumn("rsharp")> Public Property RsharpPath As String = ""
        <DataFrameColumn("python")> Public Property PythonPath As String = ""
    End Class

    ''' <summary>大语言模型服务配置段 [llm]</summary>
    <ClassName("llm")>
    Public Class LLMConfig
        <DataFrameColumn("url")> Public Property LLMServiceUrl As String = "http://localhost:11434"
        <DataFrameColumn("model")> Public Property LLMModelName As String = ""
        <DataFrameColumn("apikey")> Public Property LLMApiKey As String = ""
        <DataFrameColumn("max_rounds")> Public Property LLMMaxRounds As Integer = 100
    End Class

    ''' <summary>MySQL 数据库连接参数段 [mysql]</summary>
    <ClassName("mysql")>
    Public Class MySqlConfig
        <DataFrameColumn("host")> Public Property MySqlHost As String = "localhost"
        <DataFrameColumn("port")> Public Property MySqlPort As Integer = 3306
        <DataFrameColumn("database")> Public Property MySqlDatabase As String = "pubmed"
        <DataFrameColumn("user")> Public Property MySqlUser As String = "root"
        <DataFrameColumn("password")> Public Property MySqlPassword As String = ""

        ''' <summary>生成 MySQL 连接字符串。</summary>
        Public Function GetConnectionString() As String
            Return $"server={MySqlHost};port={MySqlPort};database={MySqlDatabase};uid={MySqlUser};pwd={MySqlPassword};Charset=utf8mb4;SslMode=None;AllowPublicKeyRetrieval=True;"
        End Function
    End Class

    ''' <summary>文献检索策略段 [literature]</summary>
    <ClassName("literature")>
    Public Class LiteratureConfig
        <DataFrameColumn("strategy")> Public Property LiteratureSearchStrategy As String = "none"
        <DataFrameColumn("max_count")> Public Property MaxLiteratureCount As Integer = 20
        <DataFrameColumn("auto_search")> Public Property AutoSearchLiterature As Boolean = True
    End Class

    ''' <summary>分析流程参数段 [analysis]</summary>
    <ClassName("analysis")>
    Public Class AnalysisConfig
        <DataFrameColumn("diff_pvalue")> Public Property DiffPvalueCutoff As Double = 0.05
        <DataFrameColumn("metabolite_vip")> Public Property MetaboliteVipCutoff As Double = 1.0
        <DataFrameColumn("wgcna_top_mad")> Public Property WgcnaTopMAD As Integer = 20000
        <DataFrameColumn("diff_top_count")> Public Property DiffTopCount As Integer = 200
    End Class

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