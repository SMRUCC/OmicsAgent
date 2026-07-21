' ============================================================================
' 配置管理模块 - INI 文件读写与运行环境配置
' ============================================================================

Imports Microsoft.VisualBasic.Serialization.JSON

''' <summary>
''' 表示整个 agent 运行所需的全部配置信息，从 INI 文件中加载得到。
''' 该配置包括外部工具路径、大语言模型服务参数、MySQL 数据库连接参数、
''' 以及文献检索策略等。
''' </summary>
Public Class AgentConfig

    ' ------------------------------------------------------------------
    ' 外部工具路径
    ' ------------------------------------------------------------------
    ''' <summary>Rscript 解释器路径</summary>
    Public Property RscriptPath As String = ""
    ''' <summary>wkhtmltopdf 程序路径，用于将 HTML 报告转换为 PDF</summary>
    Public Property WkHtmlToPdfPath As String = ""
    ''' <summary>R# 解释器路径</summary>
    Public Property RsharpPath As String = ""
    ''' <summary>Python 解释器路径</summary>
    Public Property PythonPath As String = ""

    ' ------------------------------------------------------------------
    ' 大语言模型服务配置
    ' ------------------------------------------------------------------
    ''' <summary>Ollama 服务 URL，例如 http://localhost:11434</summary>
    Public Property LLMServiceUrl As String = "http://localhost:11434"
    ''' <summary>所使用的大语言模型名称，例如 qwen2.5:14b</summary>
    Public Property LLMModelName As String = ""
    ''' <summary>访问 LLM 服务的 API Key（若服务需要鉴权）</summary>
    Public Property LLMApiKey As String = ""

    ' ------------------------------------------------------------------
    ' MySQL 数据库连接参数（用于 PubMed 本地镜像查询）
    ' ------------------------------------------------------------------
    Public Property MySqlHost As String = "localhost"
    Public Property MySqlPort As Integer = 3306
    Public Property MySqlDatabase As String = "pubmed"
    Public Property MySqlUser As String = "root"
    Public Property MySqlPassword As String = ""

    ''' <summary>
    ''' 生成 MySQL 连接字符串
    ''' </summary>
    Public ReadOnly Property MySqlConnectionString As String
        Get
            Return $"server={MySqlHost};port={MySqlPort};database={MySqlDatabase};uid={MySqlUser};pwd={MySqlPassword};Charset=utf8mb4;SslMode=None;AllowPublicKeyRetrieval=True;"
        End Get
    End Property

    ' ------------------------------------------------------------------
    ' 文献检索策略
    ' ------------------------------------------------------------------
    ''' <summary>
    ''' 文献检索策略：
    '''   - mysql : 从本地 MySQL PubMed 镜像检索
    '''   - ncbi  : 通过 Python 脚本从 NCBI 在线检索
    '''   - none  : 不自动检索文献
    ''' </summary>
    Public Property LiteratureSearchStrategy As String = "none"

    ''' <summary>自动检索文献的最大数量</summary>
    Public Property MaxLiteratureCount As Integer = 20

    ''' <summary>是否在缺少参考文献时自动检索文献</summary>
    Public Property AutoSearchLiterature As Boolean = True

    ' ------------------------------------------------------------------
    ' 分析流程参数
    ' ------------------------------------------------------------------
    ''' <summary>差异分析 pvalue 阈值</summary>
    Public Property DiffPvalueCutoff As Double = 0.05
    ''' <summary>代谢组 VIP 阈值</summary>
    Public Property MetaboliteVipCutoff As Double = 1.0
    ''' <summary>WGCNA 中按 MAD 排序取 top 多少分子</summary>
    Public Property WgcnaTopMAD As Integer = 20000
    ''' <summary>差异分析结果取 top 多少分子（按 |logFC| 降序）</summary>
    Public Property DiffTopCount As Integer = 200

    ' ------------------------------------------------------------------
    ' 工作目录
    ' ------------------------------------------------------------------
    ''' <summary>
    ''' agent 程序所在目录的上级目录（即包含 bin/、rscript/、python/、gcmodeller/、data/ 的根目录）。
    ''' 该路径在程序启动时自动推断得到。
    ''' </summary>
    Public Property ApplicationRoot As String = ""

    ''' <summary>R 工具脚本目录路径（rscript/）</summary>
    Public ReadOnly Property RScriptsDir As String
        Get
            Return Path.Combine(ApplicationRoot, "rscript")
        End Get
    End Property

    ''' <summary>R# 工具脚本目录路径（gcmodeller/）</summary>
    Public ReadOnly Property RsharpScriptsDir As String
        Get
            Return Path.Combine(ApplicationRoot, "gcmodeller")
        End Get
    End Property

    ''' <summary>Python 工具脚本目录路径（python/）</summary>
    Public ReadOnly Property PythonScriptsDir As String
        Get
            Return Path.Combine(ApplicationRoot, "python")
        End Get
    End Property

    ''' <summary>KEGG 背景模型数据目录路径（data/）</summary>
    Public ReadOnly Property KeggDataDir As String
        Get
            Return Path.Combine(ApplicationRoot, "data")
        End Get
    End Property

    ''' <summary>INI 配置文件路径</summary>
    Public Shared ReadOnly Property DefaultIniPath As String
        Get
            Dim exeDir = AppDomain.CurrentDomain.BaseDirectory
            Return Path.Combine(exeDir, "config.ini")
        End Get
    End Property

    ''' <summary>
    ''' 加载 INI 配置文件。若文件不存在则创建模板并返回 Nothing，
    ''' 调用方应当据此终止程序并提示用户填写配置。
    ''' </summary>
    Public Shared Function Load(iniPath As String) As AgentConfig
        If Not File.Exists(iniPath) Then
            CreateTemplate(iniPath)
            Return Nothing
        End If

        Dim cfg As New AgentConfig()
        Dim currentSection As String = ""

        For Each rawLine In File.ReadAllLines(iniPath, Encoding.UTF8)
            Dim line = rawLine.Trim()
            If line = "" OrElse line.StartsWith(";", StringComparison.Ordinal) OrElse line.StartsWith("#", StringComparison.Ordinal) Then
                Continue For
            End If

            If line.StartsWith("[") AndAlso line.EndsWith("]") Then
                currentSection = line.Substring(1, line.Length - 2).Trim().ToLower()
                Continue For
            End If

            Dim eqIdx = line.IndexOf("="c)
            If eqIdx <= 0 Then Continue For

            Dim key = line.Substring(0, eqIdx).Trim()
            Dim value = line.Substring(eqIdx + 1).Trim()
            ApplyValue(cfg, currentSection, key, value)
        Next

        cfg.ApplicationRoot = InferApplicationRoot()
        Return cfg
    End Function

    ''' <summary>根据 section/key 将值赋给配置对象的对应字段</summary>
    Private Shared Sub ApplyValue(cfg As AgentConfig, section As String, key As String, value As String)
        Select Case section
            Case "tools"
                Select Case key.ToLower()
                    Case "rscript" : cfg.RscriptPath = value
                    Case "wkhtmltopdf" : cfg.WkHtmlToPdfPath = value
                    Case "rsharp" : cfg.RsharpPath = value
                    Case "python" : cfg.PythonPath = value
                End Select
            Case "llm"
                Select Case key.ToLower()
                    Case "url" : cfg.LLMServiceUrl = value
                    Case "model" : cfg.LLMModelName = value
                    Case "apikey" : cfg.LLMApiKey = value
                End Select
            Case "mysql"
                Select Case key.ToLower()
                    Case "host" : cfg.MySqlHost = value
                    Case "port" : Integer.TryParse(value, cfg.MySqlPort)
                    Case "database" : cfg.MySqlDatabase = value
                    Case "user" : cfg.MySqlUser = value
                    Case "password" : cfg.MySqlPassword = value
                End Select
            Case "literature"
                Select Case key.ToLower()
                    Case "strategy" : cfg.LiteratureSearchStrategy = value.ToLower()
                    Case "max_count" : Integer.TryParse(value, cfg.MaxLiteratureCount)
                    Case "auto_search"
                        cfg.AutoSearchLiterature = (value.ToLower() = "true" OrElse value = "1" OrElse value.ToLower() = "yes")
                End Select
            Case "analysis"
                Select Case key.ToLower()
                    Case "diff_pvalue" : Double.TryParse(value, cfg.DiffPvalueCutoff)
                    Case "metabolite_vip" : Double.TryParse(value, cfg.MetaboliteVipCutoff)
                    Case "wgcna_top_mad" : Integer.TryParse(value, cfg.WgcnaTopMAD)
                    Case "diff_top_count" : Integer.TryParse(value, cfg.DiffTopCount)
                End Select
        End Select
    End Sub

    ''' <summary>推断 agent 程序根目录（bin/ 的上一级目录）</summary>
    Private Shared Function InferApplicationRoot() As String
        Dim exeDir = AppDomain.CurrentDomain.BaseDirectory
        ' bin/Release/net10.0/ 或 bin/Debug/net10.0/ -> 上溯到 bin/ 的父目录
        Dim parent = Directory.GetParent(exeDir)
        If parent?.Name.Equals("bin", StringComparison.OrdinalIgnoreCase) Then
            Return parent.Parent.FullName
        ElseIf parent?.Parent?.Name.Equals("bin", StringComparison.OrdinalIgnoreCase) Then
            Return parent.Parent.Parent.FullName
        Else
            ' 开发模式下直接使用 exe 目录
            Return exeDir
        End If
    End Function

    ''' <summary>创建 INI 配置文件模板</summary>
    Public Shared Sub CreateTemplate(iniPath As String)
        Dim sb As New StringBuilder()
        sb.AppendLine("; ============================================================================")
        sb.AppendLine("; OmicsAgent 配置文件 - 请根据本机实际路径填写以下配置项")
        sb.AppendLine("; 字段值中等号两侧不要加引号；以 ; 或 # 开头的行视为注释")
        sb.AppendLine("; ============================================================================")
        sb.AppendLine()
        sb.AppendLine("[tools]")
        sb.AppendLine("; R 语言脚本解释器路径")
        sb.AppendLine("rscript = C:\Program Files\R\R-4.4.0\bin\Rscript.exe")
        sb.AppendLine("; wkhtmltopdf 程序路径，用于将 HTML 报告转换为 PDF")
        sb.AppendLine("wkhtmltopdf = C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe")
        sb.AppendLine("; R# 语言解释器路径")
        sb.AppendLine("rsharp = C:\GCModeller\Rsharp.exe")
        sb.AppendLine("; Python 解释器路径")
        sb.AppendLine("python = C:\Python312\python.exe")
        sb.AppendLine()
        sb.AppendLine("[llm]")
        sb.AppendLine("; Ollama 服务 URL")
        sb.AppendLine("url = http://localhost:11434")
        sb.AppendLine("; 大语言模型名称")
        sb.AppendLine("model = qwen2.5:14b")
        sb.AppendLine("; API Key（若服务无需鉴权可留空）")
        sb.AppendLine("apikey =")
        sb.AppendLine()
        sb.AppendLine("[mysql]")
        sb.AppendLine("; PubMed 本地镜像 MySQL 数据库连接参数")
        sb.AppendLine("host = localhost")
        sb.AppendLine("port = 3306")
        sb.AppendLine("database = pubmed")
        sb.AppendLine("user = root")
        sb.AppendLine("password =")
        sb.AppendLine()
        sb.AppendLine("[literature]")
        sb.AppendLine("; 文献检索策略：mysql / ncbi / none")
        sb.AppendLine("strategy = mysql")
        sb.AppendLine("; 自动检索文献的最大数量")
        sb.AppendLine("max_count = 20")
        sb.AppendLine("; 当用户未提供参考文献时是否自动检索")
        sb.AppendLine("auto_search = true")
        sb.AppendLine()
        sb.AppendLine("[analysis]")
        sb.AppendLine("; 差异分析 pvalue 阈值")
        sb.AppendLine("diff_pvalue = 0.05")
        sb.AppendLine("; 代谢组 VIP 阈值")
        sb.AppendLine("metabolite_vip = 1.0")
        sb.AppendLine("; WGCNA 按 MAD 排序取 top 分子数量")
        sb.AppendLine("wgcna_top_mad = 20000")
        sb.AppendLine("; 差异分析结果按 |logFC| 降序取 top 分子数量")
        sb.AppendLine("diff_top_count = 200")

        Dim dir = Path.GetDirectoryName(iniPath)
        If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
            Directory.CreateDirectory(dir)
        End If
        File.WriteAllText(iniPath, sb.ToString(), Encoding.UTF8)
    End Sub

    ''' <summary>将配置对象序列化为 JSON 字符串，便于日志输出</summary>
    Public Function ToJson() As String
        Return Me.GetJson
    End Function

End Class
