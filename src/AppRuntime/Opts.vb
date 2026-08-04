Imports Microsoft.VisualBasic.CommandLine.Reflection

Namespace AppRuntime

    ''' <summary>
    ''' The commandline argument options
    ''' </summary>
    Public Class Opts

        <Opt("--research", "-r")> Public Property research As String
        <Opt("--expression", "-e")> Public Property expression As String
        <Opt("--annotation", "-a")> Public Property annotation As String
        <Opt("--sampleinfo", "-s")> Public Property sampleinfo As String

        <Opt("--reference", "-k")> Public Property reference As String
        <Opt("--workspace", "-w")> Public Property workspace As String
        <Opt("--config", "-c")> Public Property config As String
        <Opt("--skip-literature")> Public Property skip_literature As Boolean = False
        <Opt("--skip-kb")> Public Property skip_kb As Boolean = False
        <Opt("--module")> Public Property modules As String

        <Opt("--custom-modules")> Public Property custom_modules As String

        <Opt("--debug-cache")> Public Property debug_cache As Boolean

        ''' <summary>
        ''' make check for run Rscript
        ''' </summary>
        ''' <returns></returns>
        <Opt("--check-r")> Public Property check_interop As Boolean

        <Opt("--make-report")> Public Property make_report As Boolean

        ''' <summary>
        ''' 报告输出格式，取值 pdf / docx / both。
        ''' 该命令行参数的优先级高于 config.ini 中的 [report] format 配置项。
        ''' </summary>
        <Opt("--report-format")> Public Property report_format As String

        <Opt("--help", "-h")> Public Property help As Boolean = False

        ''' <summary>验证必需参数</summary>
        Public Function ValidateRequiredArgs() As Boolean
            Dim required = {"research", "expression", "annotation", "sampleinfo"}
            Dim parsed As New Dictionary(Of String, String) From {
                {"research", research},
                {"expression", expression},
                {"annotation", annotation},
                {"sampleinfo", sampleinfo}
            }
            Dim missing = required.Where(Function(k) Not parsed.ContainsKey(k) OrElse String.IsNullOrEmpty(parsed(k))).ToList()

            If missing.Count > 0 Then
                Console.Error.WriteLine("Missing required arguments: " & String.Join(", ", missing.Select(Function(k) "--" & k)))
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

        ''' <summary>解析要执行的模块</summary>
        Public Function ParseModulesToRun() As List(Of Integer)
            If Not modules.StringEmpty(, True) Then
                Return modules.Split(","c).Select(Function(s) Integer.Parse(s.Trim())).ToList()
            End If
            ' 默认执行所有模块
            Return {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}.ToList()
        End Function
    End Class
End Namespace