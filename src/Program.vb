' ============================================================================
' OmicsAgent 主入口 - 命令行程序
' ============================================================================
Imports System.IO
Imports System.Threading
Imports OmicsAgent.Agent
Imports OmicsAgent.Config
Imports OmicsAgent.Models
Imports OmicsAgent.IO
Imports OmicsAgent.Utils

Module Program

    Private ReadOnly s_usage As String = <string><![CDATA[
================================================================
  Omics Research Agent v1.0
  LLM-driven omics data analysis agent based on local Ollama
================================================================

Usage:
  research --research <path> --expression <path> --annotation <path>
           --sampleinfo <path> --workspace <path> [--references <dir>]
           [--config <ini_path>]

Required arguments:
  --research <path>       Research topic description text file
  --expression <path>     Expression matrix CSV file (single omics) or
                          directory containing multiple omics CSV files
  --annotation <path>     Molecule annotation CSV file
  --sampleinfo <path>     Sample metadata CSV file (single) or directory
  --workspace <path>      Output workspace directory

Optional arguments:
  --references <dir>      Directory containing reference literature
                          text files (.txt). If not provided, agent will
                          search literature based on INI config.
  --config <ini_path>     Path to INI configuration file.
                          Default: ./research.ini next to the executable.

INI configuration sections:
  [tools]         rscript, wkhtmltopdf, rsharp, python paths
  [llm]           url, model, apikey
  [mysql]         host, port, user, password, database
  [literature]    mode = none | local_mysql | ncbi_online
  [workspace]     kegg_data_dir, rscript_tool_dir, gcmodeller_tool_dir,
                  python_tool_dir
  [analysis]      diff_pvalue_cutoff, diff_vip_cutoff, top_molecules_count,
                  wgcna_top_mad

Example:
  research --research topic.txt --expression expr.csv ^
           --annotation anno.csv --sampleinfo meta.csv ^
           --workspace ./workspace --references ./refs ^
           --config ./research.ini
]]></string>.Value

    Function Main(args As String()) As Integer
        Console.WriteLine(s_usage)

        Try
            Return RunAsync(args).GetAwaiter().GetResult()
        Catch ex As Exception
            Console.Error.WriteLine($"[FATAL] {ex.Message}")
            Console.Error.WriteLine(ex.StackTrace)
            Return 1
        End Try
    End Function

    Private Async Function RunAsync(args As String()) As Task(Of Integer)
        ' 1. 解析命令行参数
        Dim parsed = ParseArgs(args)
        If parsed Is Nothing Then Return 1

        ' 2. 加载配置
        Dim iniPath = parsed("config")
        If String.IsNullOrEmpty(iniPath) Then
            iniPath = Path.Combine(AppContext.BaseDirectory, "research.ini")
        End If
        Console.WriteLine($"[Config] Using INI file: {iniPath}")

        Dim ini As New IniFile(iniPath)
        Dim config = AppConfig.LoadFromIni(ini)

        ' 3. 检查环境
        Dim checker As New EnvironmentChecker(config, iniPath)
        If Not Await checker.CheckAsync() Then
            Return 1
        End If

        ' 4. 验证输入文件
        If Not ValidateInputs(parsed, config) Then Return 1

        ' 5. 创建工作区
        Dim workspaceDir = parsed("workspace")
        Dim workspace As New WorkspaceManager(workspaceDir)
        workspace.InitWorkspace()

        ' 6. 创建日志器
        Dim logger As New Logger(workspace.LogPath)
        logger.Phase("Omics Research Agent - Initialization")
        logger.Info($"Workspace: {workspaceDir}")
        logger.Info($"Research file: {parsed("research")}")
        logger.Info($"Expression: {parsed("expression")}")
        logger.Info($"Annotation: {parsed("annotation")}")
        logger.Info($"Sample info: {parsed("sampleinfo")}")
        logger.Info($"References: {parsed("references")}")

        ' 7. 构建输入数据模型
        Dim input = BuildAnalysisInput(parsed, config, logger)
        If input Is Nothing Then Return 1

        logger.Info($"Datasets: {input.Datasets.Count}")
        For Each d In input.Datasets
            logger.Info($"  - {d}")
        Next

        ' 8. 运行 agent
        Dim referencesDir = parsed("references")
        Dim agent As New OmicsAnalysisAgent(config, workspace, input, referencesDir, logger)
        Await agent.RunAsync()

        logger.Info("Done.")
        Return 0
    End Function

    Private Function ParseArgs(args As String()) As Dictionary(Of String, String)
        Dim result As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase) From {
            {"research", ""},
            {"expression", ""},
            {"annotation", ""},
            {"sampleinfo", ""},
            {"workspace", ""},
            {"references", ""},
            {"config", ""}
        }

        Dim i = 0
        While i < args.Length
            Dim a = args(i)
            If a.StartsWith("--") OrElse a.StartsWith("-") Then
                Dim key = a.TrimStart("-"c).ToLower()
                If i + 1 < args.Length AndAlso Not args(i + 1).StartsWith("-") Then
                    If result.ContainsKey(key) Then
                        result(key) = args(i + 1)
                    End If
                    i += 2
                Else
                    i += 1
                End If
            Else
                i += 1
            End If
        End While

        ' 验证必填参数
        Dim required = {"research", "expression", "annotation", "sampleinfo", "workspace"}
        For Each k In required
            If String.IsNullOrEmpty(result(k)) Then
                Console.Error.WriteLine($"[ERROR] Missing required argument: --{k}")
                Console.Error.WriteLine()
                Console.Error.WriteLine(s_usage)
                Return Nothing
            End If
        Next

        Return result
    End Function

    Private Function ValidateInputs(parsed As Dictionary(Of String, String), config As AppConfig) As Boolean
        If Not File.Exists(parsed("research")) Then
            Console.Error.WriteLine($"[ERROR] Research file not found: {parsed("research")}")
            Return False
        End If
        If Not File.Exists(parsed("annotation")) Then
            Console.Error.WriteLine($"[ERROR] Annotation file not found: {parsed("annotation")}")
            Return False
        End If
        If Not File.Exists(parsed("expression")) AndAlso Not Directory.Exists(parsed("expression")) Then
            Console.Error.WriteLine($"[ERROR] Expression path not found: {parsed("expression")}")
            Return False
        End If
        If Not File.Exists(parsed("sampleinfo")) AndAlso Not Directory.Exists(parsed("sampleinfo")) Then
            Console.Error.WriteLine($"[ERROR] Sample info path not found: {parsed("sampleinfo")}")
            Return False
        End If
        If Not String.IsNullOrEmpty(parsed("references")) AndAlso Not Directory.Exists(parsed("references")) Then
            Console.Error.WriteLine($"[ERROR] References directory not found: {parsed("references")}")
            Return False
        End If
        Return True
    End Function

    Private Function BuildAnalysisInput(parsed As Dictionary(Of String, String), config As AppConfig, logger As Logger) As AnalysisInput
        Dim input As New AnalysisInput()

        ' 1. 读取研究主题
        input.Research = New ResearchDescription With {
            .RawText = File.ReadAllText(parsed("research"))
        }

        ' 2. 读取注释文件
        input.AnnotationCsvPath = parsed("annotation")

        ' 3. 构建数据集列表
        Dim validator As New CsvValidator()
        Dim errMsg = ""

        If File.Exists(parsed("expression")) Then
            ' 单组学
            Dim ds As New OmicsDataset()
            ds.Name = Path.GetFileNameWithoutExtension(parsed("expression"))
            ds.ExpressionCsvPath = parsed("expression")
            ds.SampleInfoCsvPath = parsed("sampleinfo")
            ds.OmicsType = InferOmicsType(parsed("annotation"))

            If Not validator.ValidateExpressionMatrix(ds.ExpressionCsvPath, errMsg) Then
                logger.Error(errMsg)
                Return Nothing
            End If

            ' 读取样本分组
            ds.SampleGroups = validator.ReadSampleGroups(ds.SampleInfoCsvPath)
            ds.SampleCount = CountSamples(ds.ExpressionCsvPath)
            ds.MoleculeCount = CountMolecules(ds.ExpressionCsvPath)
            ds.HasTimeSeries = CheckTimeSeries(ds.SampleInfoCsvPath)
            input.Datasets.Add(ds)
        Else
            ' 多组学：扫描目录
            Dim exprDir = parsed("expression")
            Dim sampleDir = If(Directory.Exists(parsed("sampleinfo")), parsed("sampleinfo"), Nothing)

            For Each csv In Directory.GetFiles(exprDir, "*.csv")
                Dim ds As New OmicsDataset()
                ds.Name = Path.GetFileNameWithoutExtension(csv)
                ds.ExpressionCsvPath = csv
                ds.OmicsType = InferOmicsType(parsed("annotation"))

                ' 查找对应的 sampleinfo
                Dim sampleFile = Path.Combine(sampleDir, Path.GetFileName(csv))
                If File.Exists(sampleFile) Then
                    ds.SampleInfoCsvPath = sampleFile
                ElseIf File.Exists(parsed("sampleinfo")) Then
                    ds.SampleInfoCsvPath = parsed("sampleinfo")
                End If

                If Not validator.ValidateExpressionMatrix(ds.ExpressionCsvPath, errMsg) Then
                    logger.Warn($"Skipping invalid expression matrix: {csv}. {errMsg}")
                    Continue For
                End If

                ds.SampleGroups = validator.ReadSampleGroups(ds.SampleInfoCsvPath)
                ds.SampleCount = CountSamples(ds.ExpressionCsvPath)
                ds.MoleculeCount = CountMolecules(ds.ExpressionCsvPath)
                ds.HasTimeSeries = CheckTimeSeries(ds.SampleInfoCsvPath)
                input.Datasets.Add(ds)
            Next
        End If

        If input.Datasets.Count = 0 Then
            logger.Error("No valid datasets found.")
            Return Nothing
        End If

        input.WorkspaceDir = parsed("workspace")
        Return input
    End Function

    Private Function InferOmicsType(annotationCsv As String) As String
        Try
            Dim firstLine = File.ReadLines(annotationCsv).FirstOrDefault()
            If String.IsNullOrEmpty(firstLine) Then Return "unknown"
            Dim headers = firstLine.Split(","c).Select(Function(h) h.Trim().ToLower()).ToArray()
            Dim typeIdx = Array.IndexOf(headers, "type")
            If typeIdx < 0 Then Return "unknown"

            ' 读取第二行获取类型
            Dim secondLine = File.ReadLines(annotationCsv).Skip(1).FirstOrDefault()
            If String.IsNullOrEmpty(secondLine) Then Return "unknown"
            Dim fields = secondLine.Split(","c)
            If typeIdx < fields.Length Then
                Return fields(typeIdx).Trim().ToLower()
            End If
        Catch
        End Try
        Return "unknown"
    End Function

    Private Function CountSamples(exprCsv As String) As Integer
        Try
            Dim firstLine = File.ReadLines(exprCsv).FirstOrDefault()
            If String.IsNullOrEmpty(firstLine) Then Return 0
            Return firstLine.Split(","c).Length - 1
        Catch
            Return 0
        End Try
    End Function

    Private Function CountMolecules(exprCsv As String) As Integer
        Try
            Return File.ReadLines(exprCsv).Count() - 1
        Catch
            Return 0
        End Try
    End Function

    Private Function CheckTimeSeries(sampleInfoCsv As String) As Boolean
        Try
            Dim firstLine = File.ReadLines(sampleInfoCsv).FirstOrDefault()
            If String.IsNullOrEmpty(firstLine) Then Return False
            Dim headers = firstLine.Split(","c).Select(Function(h) h.Trim().ToLower()).ToArray()
            Return headers.Contains("time") OrElse headers.Contains("timepoint") OrElse headers.Contains("time_point")
        Catch
            Return False
        End Try
    End Function

End Module
