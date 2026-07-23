Imports Microsoft.VisualBasic.CommandLine.Reflection

Namespace AppRuntime

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

        ''' <summary>
        ''' make check for run Rscript
        ''' </summary>
        ''' <returns></returns>
        <Opt("--check_r")> Public Property check_interop As Boolean

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
            Return AgentConfig.Load(If(config, "config.ini"))
        End Function

        ''' <summary>解析要执行的模块</summary>
        Public Function ParseModulesToRun() As List(Of Integer)
            If Not modules.StringEmpty(, True) Then
                Return modules.Split(","c).Select(Function(s) Integer.Parse(s.Trim())).ToList()
            End If
            ' 默认执行所有模块
            Return {1, 2, 3, 4, 5, 6, 7, 8, 9}.ToList()
        End Function
    End Class
End Namespace