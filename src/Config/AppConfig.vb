' ============================================================================
' 应用配置数据模型
' ============================================================================
Imports System.IO

Namespace Config

    ''' <summary>
    ''' 应用程序全局配置，从 INI 文件加载
    ''' </summary>
    Public Class AppConfig

        ' ===== 工具路径 =====
        Public Property RscriptPath As String = ""
        Public Property WkHtmlToPdfPath As String = ""
        Public Property RsharpPath As String = ""
        Public Property PythonPath As String = ""

        ' ===== LLM 配置 =====
        Public Property LlmUrl As String = "http://localhost:11434"
        Public Property LlmModel As String = "llama3.1"
        Public Property LlmApiKey As String = ""

        ' ===== MySQL 配置 =====
        Public Property MysqlHost As String = "localhost"
        Public Property MysqlPort As Integer = 3306
        Public Property MysqlUser As String = "root"
        Public Property MysqlPassword As String = ""
        Public Property MysqlDatabase As String = "pubmed"

        ' ===== 文献检索策略 =====
        ''' <summary>none / local_mysql / ncbi_online</summary>
        Public Property LiteratureSearchMode As String = "none"

        ' ===== 工作区配置 =====
        Public Property KeggDataDir As String = ""
        Public Property RscriptToolDir As String = ""
        Public Property GcmodellerToolDir As String = ""
        Public Property PythonToolDir As String = ""

        ' ===== 分析参数 =====
        Public Property DiffPvalueCutoff As Double = 0.05
        Public Property DiffVipCutoff As Double = 1.0
        Public Property TopMoleculesCount As Integer = 200
        Public Property WgcnaTopMAD As Integer = 20000

        Public ReadOnly Property MysqlConnectionString As String
            Get
                Return $"server={MysqlHost};port={MysqlPort};user id={MysqlUser};password={MysqlPassword};database={MysqlDatabase};Charset=utf8;SslMode=None;AllowPublicKeyRetrieval=True;"
            End Get
        End Property

        ''' <summary>
        ''' 从 INI 文件加载配置
        ''' </summary>
        Public Shared Function LoadFromIni(ini As IO.IniFile) As AppConfig
            Dim cfg As New AppConfig With {
                .RscriptPath = ini.Get("tools", "rscript", ""),
                .WkHtmlToPdfPath = ini.Get("tools", "wkhtmltopdf", ""),
                .RsharpPath = ini.Get("tools", "rsharp", ""),
                .PythonPath = ini.Get("tools", "python", ""),
                .LlmUrl = ini.Get("llm", "url", "http://localhost:11434"),
                .LlmModel = ini.Get("llm", "model", "llama3.1"),
                .LlmApiKey = ini.Get("llm", "apikey", ""),
                .MysqlHost = ini.Get("mysql", "host", "localhost"),
                .MysqlPort = Integer.Parse(ini.Get("mysql", "port", "3306")),
                .MysqlUser = ini.Get("mysql", "user", "root"),
                .MysqlPassword = ini.Get("mysql", "password", ""),
                .MysqlDatabase = ini.Get("mysql", "database", "pubmed"),
                .LiteratureSearchMode = ini.Get("literature", "mode", "none").ToLower(),
                .KeggDataDir = ini.Get("workspace", "kegg_data_dir", ""),
                .RscriptToolDir = ini.Get("workspace", "rscript_tool_dir", ""),
                .GcmodellerToolDir = ini.Get("workspace", "gcmodeller_tool_dir", ""),
                .PythonToolDir = ini.Get("workspace", "python_tool_dir", ""),
                .DiffPvalueCutoff = Double.Parse(ini.Get("analysis", "diff_pvalue_cutoff", "0.05")),
                .DiffVipCutoff = Double.Parse(ini.Get("analysis", "diff_vip_cutoff", "1.0")),
                .TopMoleculesCount = Integer.Parse(ini.Get("analysis", "top_molecules_count", "200")),
                .WgcnaTopMAD = Integer.Parse(ini.Get("analysis", "wgcna_top_mad", "20000"))
            }
            Return cfg
        End Function

        ''' <summary>
        ''' 生成默认 INI 配置文件模板
        ''' </summary>
        Public Shared Sub WriteDefaultTemplate(ini As IO.IniFile)
            ini.Set("tools", "rscript", "C:/Program Files/R/R-4.4.0/bin/Rscript.exe")
            ini.Set("tools", "wkhtmltopdf", "C:/Program Files/wkhtmltopdf/bin/wkhtmltopdf.exe")
            ini.Set("tools", "rsharp", "C:/GCModeller/Rsharp.exe")
            ini.Set("tools", "python", "python")

            ini.Set("llm", "url", "http://localhost:11434")
            ini.Set("llm", "model", "llama3.1")
            ini.Set("llm", "apikey", "")

            ini.Set("mysql", "host", "localhost")
            ini.Set("mysql", "port", "3306")
            ini.Set("mysql", "user", "root")
            ini.Set("mysql", "password", "")
            ini.Set("mysql", "database", "pubmed")

            ini.Set("literature", "mode", "none")

            ini.Set("workspace", "kegg_data_dir", "../data")
            ini.Set("workspace", "rscript_tool_dir", "../rscript")
            ini.Set("workspace", "gcmodeller_tool_dir", "../gcmodeller")
            ini.Set("workspace", "python_tool_dir", "../python")

            ini.Set("analysis", "diff_pvalue_cutoff", "0.05")
            ini.Set("analysis", "diff_vip_cutoff", "1.0")
            ini.Set("analysis", "top_molecules_count", "200")
            ini.Set("analysis", "wgcna_top_mad", "20000")

            ini.Save()
        End Sub

    End Class

End Namespace
