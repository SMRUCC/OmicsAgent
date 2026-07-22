Imports System.IO
Imports System.Text
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Microsoft.VisualBasic.ComponentModel.Settings.Inf
Imports Microsoft.VisualBasic.ComponentModel.DataSourceModel
Imports Microsoft.VisualBasic.ComponentModel.DataSourceModel.SchemaMaps

' ============================================================================
' 配置管理模块
'
' 本模块负责 agent 运行所需的全部配置参数的加载与模板生成。
' 配置的读写基于底层运行时（Microsoft.VisualBasic.Core）提供的 IOProvider
' 模块完成 CLR 对象与 INI 文件之间的自动映射：
'   * 反序列化：IOProvider.LoadProfile(Of AgentConfig)
'   * 序列化：  IOProvider.WriteProfile
'
' 配置按主题划分为五个段（section），与 INI 文件中的 [tools]/[llm]/[mysql]/
' [literature]/[analysis] 一一对应。每个段对应一个嵌套的段子对象，段名由子
' 类上的 <ClassName("...")> 决定，键名由属性上的 <DataFrameColumn("ini键名")>
' 决定，从而保证与历史 CreateTemplate 生成的文件格式完全兼容。
' ============================================================================

''' <summary>
''' 表示整个 agent 运行所需的全部配置信息，从 INI 文件中加载得到。
''' </summary>
Public Class AgentConfig

    ' ------------------------------------------------------------------
    ' 段子对象（各段对应 INI 文件中的一个 section）
    ' ------------------------------------------------------------------
    ''' <summary>外部工具路径</summary>
    <DataFrameColumn("tools")> Public Property Tools As New ToolConfig()

    ''' <summary>大语言模型服务配置</summary>
    <DataFrameColumn("llm")> Public Property LLM As New LLMConfig()

    ''' <summary>MySQL 数据库连接参数（用于 PubMed 本地镜像查询）</summary>
    <DataFrameColumn("mysql")> Public Property MySql As New MySqlConfig()

    ''' <summary>文献检索策略</summary>
    <DataFrameColumn("literature")> Public Property Literature As New LiteratureConfig()

    ''' <summary>分析流程参数</summary>
    <DataFrameColumn("analysis")> Public Property Analysis As New AnalysisConfig()

    ' ------------------------------------------------------------------
    ' 共享 / 计算属性（不参与 INI 序列化，故必须为 Shared 或非属性）
    ' ------------------------------------------------------------------
    ''' <summary>
    ''' agent 程序所在目录的上级目录（即包含 bin/、rscript/、python/、gcmodeller/、data/ 的根目录）。
    ''' 该路径在程序启动时自动推断得到。
    ''' </summary>
    Public Shared ReadOnly Property ApplicationRoot As String = App.HOME.ParentPath

    ''' <summary>R 工具脚本目录路径（rscript/）</summary>
    Public Shared ReadOnly Property RScriptsDir As String
        Get
            Return Path.Combine(ApplicationRoot, "rscript").GetDirectoryFullPath
        End Get
    End Property

    ''' <summary>R# 工具脚本目录路径（gcmodeller/）</summary>
    Public Shared ReadOnly Property RsharpScriptsDir As String
        Get
            Return Path.Combine(ApplicationRoot, "gcmodeller").GetDirectoryFullPath
        End Get
    End Property

    ''' <summary>Python 工具脚本目录路径（python/）</summary>
    ''' <remarks>
    ''' Python 脚本工具目录（用于读取 NCBI 检索等模板脚本）
    ''' </remarks>
    Public Shared ReadOnly Property PythonScriptsDir As String
        Get
            Return Path.Combine(ApplicationRoot, "python").GetDirectoryFullPath
        End Get
    End Property

    ''' <summary>KEGG 背景模型数据目录路径（data/）</summary>
    Public Shared ReadOnly Property KeggDataDir As String
        Get
            Return Path.Combine(ApplicationRoot, "data").GetDirectoryFullPath
        End Get
    End Property

    ''' <summary>INI 配置文件路径</summary>
    Public Shared ReadOnly Property DefaultIniPath As String
        Get
            Dim exeDir As String = AppDomain.CurrentDomain.BaseDirectory
            Return Path.Combine(exeDir, "config.ini")
        End Get
    End Property

    ''' <summary>
    ''' 生成 MySQL 连接字符串。
    ''' 注意：此前的版本将其实现为 ReadOnly 属性，但 ReadOnly 基元属性会参与
    ''' INI 序列化，导致 LoadProfile 在反序列化时无 setter 可写而抛出异常，
    ''' 故此处改为方法暴露，以避免破坏 IOProvider 的自动序列化流程。
    ''' </summary>
    Public Function GetMySqlConnectionString() As String
        Return MySql.GetConnectionString()
    End Function

    ' ------------------------------------------------------------------
    ' 加载与保存
    ' ------------------------------------------------------------------
    ''' <summary>
    ''' 加载 INI 配置文件。若文件不存在则创建模板并返回 Nothing，
    ''' 调用方应当据此终止程序并提示用户填写配置。
    ''' 反序列化工作交由底层运行时 IOProvider.LoadProfile 完成。
    ''' </summary>
    Public Shared Function Load(iniPath As String) As AgentConfig
        If Not File.Exists(iniPath) Then
            Call CreateTemplate(iniPath)
            Return Nothing
        End If

        Try
            Return IOProvider.LoadProfile(Of AgentConfig)(iniPath)
        Catch ex As Exception
            Call App.LogException(ex)
            Return Nothing
        End Try
    End Function

    ''' <summary>
    ''' 将配置对象序列化写回 INI 文件（基于 IOProvider.WriteProfile）。
    ''' 生成的文件结构与此模块读取的格式完全一致。
    ''' </summary>
    Public Shared Sub Save(cfg As AgentConfig, iniPath As String)
        Call IOProvider.WriteProfile(Of AgentConfig)(cfg, iniPath)
    End Sub

    ''' <summary>创建 INI 配置文件模板（手动生成，保留可读注释与现有格式）。</summary>
    Public Shared Sub CreateTemplate(iniPath As String)
        Dim dir As String = Path.GetDirectoryName(iniPath)

        If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
            Call Directory.CreateDirectory(dir)
        End If

        Dim sb As New StringBuilder()
        Call sb.AppendLine("; OmicsAgent 运行环境配置文件")
        Call sb.AppendLine("; 请在使用本程序之前，将下列各项配置项设置为实际环境中的正确取值。")
        Call sb.AppendLine()
        Call sb.AppendLine("[tools]")
        Call sb.AppendLine("; R 语言脚本解释器路径")
        Call sb.AppendLine("rscript = C:\Program Files\R\R-4.4.0\bin\Rscript.exe")
        Call sb.AppendLine("; wkhtmltopdf 工具路径，用于渲染 HTML 报告为 PDF 格式")
        Call sb.AppendLine("wkhtmltopdf = C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe")
        Call sb.AppendLine("; R# 语言解释器（GCModeller 工作环境）路径")
        Call sb.AppendLine("rsharp = C:\GCModeller\GCModeller\R#\R#.exe")
        Call sb.AppendLine("; python 解释器路径")
        Call sb.AppendLine("python = C:\ProgramData\miniforge3\python.exe")
        Call sb.AppendLine()
        Call sb.AppendLine("[llm]")
        Call sb.AppendLine("; 大语言模型服务的 HTTP 接口 URL 地址")
        Call sb.AppendLine("url = http://localhost:11434")
        Call sb.AppendLine("; 默认使用的 LLM 模型名称")
        Call sb.AppendLine("model = qwen2.5:14b")
        Call sb.AppendLine("; 访问 LLM 服务时所使用的 API 密钥（若本地部署无需填写）")
        Call sb.AppendLine("apikey = ")
        Call sb.AppendLine()
        Call sb.AppendLine("[mysql]")
        Call sb.AppendLine("; 用于本地查询 NCBI PubMed 文献数据库的 MySQL 服务器")
        Call sb.AppendLine("host = localhost")
        Call sb.AppendLine("port = 3306")
        Call sb.AppendLine("; PubMed 文献数据库名称")
        Call sb.AppendLine("database = pubmed")
        Call sb.AppendLine("user = root")
        Call sb.AppendLine("password = ")
        Call sb.AppendLine()
        Call sb.AppendLine("[literature]")
        Call sb.AppendLine("; 文献检索策略：none 表示不进行文献检索；mysql 表示从本地 PubMed 镜像检索；ncbi 表示从 NCBI 在线检索")
        Call sb.AppendLine("strategy = none")
        Call sb.AppendLine("; 单次检索所返回的最大文献数量")
        Call sb.AppendLine("max_count = 20")
        Call sb.AppendLine("; 是否启用相关文献的自动检索功能")
        Call sb.AppendLine("auto_search = true")
        Call sb.AppendLine()
        Call sb.AppendLine("[analysis]")
        Call sb.AppendLine("; 差异表达分析的 p-value 显著性阈值")
        Call sb.AppendLine("diff_pvalue = 0.05")
        Call sb.AppendLine("; 代谢组学 VIP 值阈值，用于筛选关键代谢物")
        Call sb.AppendLine("metabolite_vip = 1.0")
        Call sb.AppendLine("; WGCNA 共表达网络分析中，按 MAD 值排序筛选的前 N 个基因")
        Call sb.AppendLine("wgcna_top_mad = 20000")
        Call sb.AppendLine("; 差异分析中所保留的 Top 差异特征数量")
        Call sb.AppendLine("diff_top_count = 200")

        Call File.WriteAllText(iniPath, sb.ToString(), Encoding.UTF8)
    End Sub

    ''' <summary>将配置对象序列化为 JSON 字符串，便于日志输出。</summary>
    Public Function ToJson() As String
        Return Me.GetJson
    End Function

    ' ==================================================================
    ' 段子对象定义
    ' ==================================================================

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

End Class
