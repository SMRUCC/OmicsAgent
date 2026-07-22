
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
End Namespace