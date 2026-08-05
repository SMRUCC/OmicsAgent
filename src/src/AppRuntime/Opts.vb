Imports Microsoft.VisualBasic.CommandLine.Reflection
Imports OmicsAgent.AppRuntime.Ini

Namespace AppRuntime

    ''' <summary>
    ''' The commandline argument options
    ''' </summary>
    Public Class Opts

        <Opt("--research", "-r")> Public Property research As String
        <Opt("--expression", "-e")> Public Property expression As String
        <Opt("--annotation", "-a")> Public Property annotation As String
        <Opt("--sampleinfo", "-s")> Public Property sampleinfo As String

        ''' <summary>
        ''' 多组学数据集定义 JSON 文件路径。该参数与 --expression/--annotation/--sampleinfo 互斥：
        ''' 提供 --dataset 时，全部组学数据（表达矩阵、各自的注释表、样本元数据）以及跨组学的
        ''' 样本对齐关系均由该 JSON 文件描述。
        ''' </summary>
        <Opt("--dataset", "-d")> Public Property dataset As String

        <Opt("--reference", "-k")> Public Property reference As String
        <Opt("--workspace", "-w")> Public Property workspace As String
        <Opt("--config", "-c")> Public Property config As String
        <Opt("--skip-literature")> Public Property skip_literature As Boolean = False
        <Opt("--skip-kb")> Public Property skip_kb As Boolean = False
        <Opt("--module")> Public Property modules As String

        <Opt("--custom-modules")> Public Property custom_modules As String

        <Opt("--debug-cache")> Public Property debug_cache As Boolean
        <Opt("--make-report")> Public Property make_report As Boolean

        ''' <summary>
        ''' 报告输出格式，取值 pdf / docx / both。
        ''' 该命令行参数的优先级高于 config.ini 中的 [report] format 配置项。
        ''' </summary>
        <Opt("--report-format")> Public Property report_format As String

        ''' <summary>
        ''' /report 模式专用。一个纯文本文件，每行指定一个用户数据文件夹路径，
        ''' 文件夹内存放用户自行分析产生的 CSV 结果表格文件。
        ''' </summary>
        <Opt("--dirs")> Public Property dirs As String

        <Opt("--help", "-h")> Public Property help As Boolean = False

        ''' <summary>
        ''' 是否使用 --dataset 指定的多组学数据集定义文件作为数据输入来源。
        ''' </summary>
        Public ReadOnly Property UseDatasetManifest As Boolean
            Get
                Return Not dataset.StringEmpty(, True)
            End Get
        End Property

        ''' <summary>验证必需参数</summary>
        ''' <remarks>
        ''' 数据输入存在两种互斥的模式：
        ''' 1. 数据集定义模式：--dataset 指定 JSON 文件，适用于多组学（也兼容单组学）；
        ''' 2. 传统参数模式：--expression/--annotation/--sampleinfo 直接给出文件路径。
        ''' 两种模式不可混用，且必须二选一。
        ''' </remarks>
        Public Function ValidateRequiredArgs() As Boolean
            Dim legacyArgs As New Dictionary(Of String, String) From {
                {"expression", expression},
                {"annotation", annotation},
                {"sampleinfo", sampleinfo}
            }
            Dim legacyUsed = legacyArgs.Where(Function(a) Not a.Value.StringEmpty(, True)).Select(Function(a) a.Key).ToList()

            ' 互斥检查：--dataset 不能与 -e/-a/-s 同时出现
            If UseDatasetManifest AndAlso legacyUsed.Count > 0 Then
                Console.Error.WriteLine("Conflicting arguments: --dataset cannot be used together with " &
                    String.Join(", ", legacyUsed.Select(Function(k) "--" & k)) & ".")
                Console.Error.WriteLine("Please provide either --dataset (dataset manifest) or --expression/--annotation/--sampleinfo, but not both.")
                Console.Error.WriteLine()
                Console.Error.WriteLine(Program.HelpText)
                Return False
            End If

            ' 二选一检查：两种模式都未提供
            If Not UseDatasetManifest AndAlso legacyUsed.Count = 0 Then
                Console.Error.WriteLine("Missing data input: please specify either --dataset=<manifest.json> " &
                    "or the --expression/--annotation/--sampleinfo argument group.")
                Console.Error.WriteLine()
                Console.Error.WriteLine(Program.HelpText)
                Return False
            End If

            Dim missing As New List(Of String)

            If research.StringEmpty(, True) Then
                missing.Add("--research")
            End If

            If UseDatasetManifest Then
                If Not dataset.FileExists Then
                    Console.Error.WriteLine($"Dataset manifest file not found: {dataset}")
                    Return False
                End If
            Else
                ' 传统参数模式下三个参数缺一不可
                For Each arg In legacyArgs
                    If arg.Value.StringEmpty(, True) Then
                        missing.Add("--" & arg.Key)
                    End If
                Next
            End If

            If missing.Count > 0 Then
                Console.Error.WriteLine("Missing required arguments: " & String.Join(", ", missing))
                Console.Error.WriteLine()
                Console.Error.WriteLine(Program.HelpText)
                Return False
            End If

            Return True
        End Function

        Public Function LoadConfig() As AgentConfig
            Dim cfg As AgentConfig = AgentConfig.Load(If(config, "config.ini"))

            If cfg Is Nothing Then
                Return Nothing
            End If

            ' 命令行 --report-format 覆盖 INI 中的取值，非法取值回退到默认的 pdf
            If Not report_format.StringEmpty(, True) Then
                If ReportOutputFormats.IsValid(report_format) Then
                    cfg.Report.OutputFormat = LCase(Trim(report_format))
                Else
                    Call VBDebugger.EchoLine($"[warning] invalid --report-format value '{report_format}', fallback to '{ReportOutputFormats.Pdf}'.")
                    cfg.Report.OutputFormat = ReportOutputFormats.Pdf
                End If
            ElseIf Not ReportOutputFormats.IsValid(cfg.Report.OutputFormat) Then
                Call VBDebugger.EchoLine($"[warning] invalid [report] format value '{cfg.Report.OutputFormat}' in config file, fallback to '{ReportOutputFormats.Pdf}'.")
                cfg.Report.OutputFormat = ReportOutputFormats.Pdf
            End If

            Return cfg
        End Function

        ''' <summary>
        ''' 解析要执行的分析模块列表。
        ''' </summary>
        ''' <returns>
        ''' 仅包含主循环内执行的分析模块索引。结果表格(13)与报告(14)属于收尾模块，
        ''' 由主循环结束后强制执行，故一律不会出现在返回结果中。
        ''' </returns>
        Public Function ParseModulesToRun() As List(Of Integer)
            If Not modules.StringEmpty(, True) Then
                ' 收尾模块必定在主循环之后执行，若用户在 --module 中误传 13/14，
                ' 此处必须过滤掉，否则这两个模块会被重复执行两次
                Return modules.Split(","c) _
                    .Select(Function(s) Integer.Parse(s.Trim())) _
                    .Where(Function(i) Not FinalizeModules.IsFinalizeModule(i)) _
                    .ToList()
            End If

            ' 默认执行全部标准分析模块
            ' （12 = 跨组学整合，仅在多组学场景下实际执行）
            Return {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}.ToList()
        End Function
    End Class
End Namespace