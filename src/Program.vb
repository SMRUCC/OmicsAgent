Imports Ollama

' ============================================================================
' 主程序入口 - 命令行参数解析与主流程编排
' ============================================================================

Module Program

    ''' <summary>命令行参数帮助文本</summary>
    Private Const HelpText As String = "
Omics Data Analysis LLM Agent
============================
基于 Ollama 大语言模型的组学数据分析 Agent

用法:
  research.exe [options]

必需参数:
  --research=<path>       研究主题描述文件路径（txt 纯文本）
  --expression=<path>     表达矩阵 CSV 文件路径，或包含多组学矩阵的文件夹路径
  --annotation=<path>     分子注释信息 CSV 文件路径
  --sampleinfo=<path>     样本元数据 CSV 文件路径，或包含多组学元数据的文件夹路径

可选参数:
  --reference=<path>      参考文献文件夹路径（文件夹内为 txt 文件）
  --workspace=<path>      工作区文件夹路径（默认在表达矩阵所在位置创建 analysis 文件夹）
  --config=<path>          INI 配置文件路径（默认为 ./config.ini）
  --skip-literature       跳过文献检索步骤
  --skip-kb               跳过知识库构建步骤
  --module=<n>            仅执行指定模块（1-9），多个模块用逗号分隔
  --help                  显示帮助信息

示例:
  research.exe --research=research.txt --expression=data.csv --annotation=anno.csv --sampleinfo=sample.csv
  research.exe --research=research.txt --expression=omics_folder/ --annotation=anno.csv --sampleinfo=sample_folder/ --reference=refs/
"

    Private _logger As Action(Of String) = AddressOf ConsoleLog
    Private _config As AgentConfig
    Private _context As AnalysisContext

    ''' <summary>程序主入口</summary>
    Function Main(args As String()) As Integer
        Try
            Console.OutputEncoding = Encoding.UTF8
            Console.WriteLine("Omics Data Analysis LLM Agent v1.0")
            Console.WriteLine("=" & New String("="c, 50))
            Console.WriteLine()

            ' 解析命令行参数
            Dim parsed = ParseArgs(args)

            If parsed.ContainsKey("help") Then
                Console.WriteLine(HelpText)
                Return 0
            End If

            ' 验证必需参数
            If Not ValidateRequiredArgs(parsed) Then
                Return 1
            End If

            ' 加载配置
            Dim configPath = parsed.GetValueOrDefault("config", "config.ini")
            _config = AgentConfig.Load(configPath)

            ' 初始化分析上下文
            _context = InitializeContext(parsed)

            ' 异步执行主流程
            MainAsync(parsed).GetAwaiter().GetResult()

            Console.WriteLine()
            Console.WriteLine("Analysis completed successfully!")
            Console.WriteLine($"Results saved to: {_context.WorkspaceDir}")
            Return 0

        Catch ex As Exception
            Console.Error.WriteLine($"FATAL ERROR: {ex.Message}")
            Console.Error.WriteLine(ex.StackTrace)
            Return -1
        End Try
    End Function

    ''' <summary>异步主流程</summary>
    Private Async Function MainAsync(parsed As Dictionary(Of String, String)) As Task
        Dim cts As New CancellationTokenSource()
        Dim cancellationToken = cts.Token

        AddHandler Console.CancelKeyPress, Sub(s, e)
                                               e.Cancel = True
                                               cts.Cancel()
                                               Console.WriteLine("Cancellation requested...")
                                           End Sub


        ' 1. 环境检查
        Dim checker As New EnvironmentChecker(_config, _logger)
        If Not Await checker.CheckAllAsync() Then
            Console.Error.WriteLine("Environment check failed. Please fix the issues above and try again.")
            Return
        End If
        Console.WriteLine()

        ' 2. 验证输入文件
        If Not ValidateInputFiles() Then Return
        Console.WriteLine()

        ' 3. 知识库构建（可选）
        If Not parsed.ContainsKey("skip-kb") Then
            Dim kbBuilder As New KnowledgeBaseBuilder(_config, _context, Function() CreateLLMClient(), _logger)
            Await kbBuilder.BuildAsync(cancellationToken)
            Console.WriteLine()
        End If

        ' 4. 执行分析模块
        Dim modulesToRun = ParseModulesToRun(parsed)
        For Each moduleIdx In modulesToRun
            If cancellationToken.IsCancellationRequested Then Exit For

            Try
                Dim [module] As AnalysisModuleBase = CreateModule(moduleIdx)
                If [module] IsNot Nothing Then
                    Console.WriteLine($"========== Module {moduleIdx}: {[module].ModuleName} ==========")
                    Await [module].RunAsync(cancellationToken)
                    Console.WriteLine()
                End If
            Catch ex As Exception
                _logger($"ERROR in module {moduleIdx}: {ex.Message}")
                Console.Error.WriteLine(ex.StackTrace)
                Console.WriteLine("Continuing to next module...")
            End Try
        Next

        ' 5. 生成最终报告（如果模块 9 未在指定列表中，也强制执行）
        If Not modulesToRun.Contains(9) AndAlso Not modulesToRun.Contains(0) Then
            ' 如果用户指定了具体模块，则不强制执行报告模块
        End If
    End Function

    ''' <summary>创建 LLM 客户端实例</summary>
    Private Function CreateLLMClient() As LLMClient
        Return New LLMClient(LLMUrl.Create(_config.LLMServiceUrl, _config.LLMApiKey), _config.LLMModelName)
    End Function

    ''' <summary>初始化分析上下文</summary>
    Private Function InitializeContext(parsed As Dictionary(Of String, String)) As AnalysisContext
        Dim context As New AnalysisContext()

        ' 研究主题文件
        context.ResearchFile = parsed("research")

        ' 表达矩阵文件/文件夹
        Dim exprPath = parsed("expression")
        If Directory.Exists(exprPath) Then
            ' 多组学：文件夹
            For Each csv In Directory.GetFiles(exprPath, "*.csv")
                Dim ds As New OmicsDataset() With {
                    .ExpressionFile = csv,
                    .OmicsType = InferOmicsType(Path.GetFileName(csv))
                }
                context.Datasets.Add(ds)
            Next
        ElseIf File.Exists(exprPath) Then
            ' 单组学：单个 CSV 文件
            Dim ds As New OmicsDataset() With {
                .ExpressionFile = exprPath,
                .OmicsType = InferOmicsType(Path.GetFileName(exprPath))
            }
            context.Datasets.Add(ds)
        End If

        ' 分子注释表
        context.AnnotationFile = parsed("annotation")

        ' 样本元数据文件/文件夹
        context.SampleInfoInput = parsed("sampleinfo")
        If File.Exists(context.SampleInfoInput) Then
            ' 单个文件：所有组学共用
            For Each ds In context.Datasets
                ds.SampleInfoFile = context.SampleInfoInput
            Next
        ElseIf Directory.Exists(context.SampleInfoInput) Then
            ' 文件夹：按文件名匹配
            For Each ds In context.Datasets
                Dim matchedSampleInfo = Path.Combine(context.SampleInfoInput, ds.MatrixName & ".csv")
                If File.Exists(matchedSampleInfo) Then
                    ds.SampleInfoFile = matchedSampleInfo
                End If
            Next
        End If

        ' 参考文献文件夹
        If parsed.ContainsKey("reference") Then
            context.ReferenceDir = parsed("reference")
        End If

        ' 工作区
        If parsed.ContainsKey("workspace") Then
            context.WorkspaceDir = parsed("workspace")
        Else
            ' 默认在表达矩阵所在位置创建 analysis 文件夹
            Dim firstExpr = context.Datasets.FirstOrDefault()?.ExpressionFile
            If Not String.IsNullOrEmpty(firstExpr) Then
                context.WorkspaceDir = Path.Combine(Path.GetDirectoryName(firstExpr), "analysis")
            Else
                context.WorkspaceDir = Path.Combine(Directory.GetCurrentDirectory(), "analysis")
            End If
        End If

        ' 创建工作区目录结构
        PathUtils.EnsureDirectory(context.WorkspaceDir)
        PathUtils.EnsureDirectory(Path.Combine(context.WorkspaceDir, "research_kb"))
        PathUtils.EnsureDirectory(Path.Combine(context.WorkspaceDir, "tmp"))
        PathUtils.EnsureDirectory(Path.Combine(context.WorkspaceDir, "scripts"))
        PathUtils.EnsureDirectory(Path.Combine(context.WorkspaceDir, "analysis"))

        ' 读取研究主题文本
        context.ResearchTopic = PathUtils.ReadAllText(context.ResearchFile)

        ' 读取分子注释表
        context.AnnotationContent = PathUtils.ReadAllText(context.AnnotationFile)

        ' 读取样本元数据
        For Each ds In context.Datasets
            If File.Exists(ds.SampleInfoFile) Then
                ds.SampleIDs = CsvUtils.ReadSampleIDs(ds.ExpressionFile)
                ds.MoleculeIDs = CsvUtils.ReadFirstColumn(ds.ExpressionFile)
            End If
        Next

        ' 检测是否为时间序列数据
        DetectTimeSeries(context)

        ' 检测是否为多组学数据
        context.IsMultiOmics = context.Datasets.Count > 1

        Return context
    End Function

    ''' <summary>从文件名推断组学类型</summary>
    Private Function InferOmicsType(fileName As String) As String
        Dim name = fileName.ToLower()
        If name.Contains("rna") Or name.Contains("transcript") Or name.Contains("gene") Then Return "rna"
        If name.Contains("protein") Or name.Contains("proteom") Then Return "protein"
        If name.Contains("metabol") Then Return "metabolite"
        If name.Contains("lipid") Then Return "lipid"
        Return "unknown"
    End Function

    ''' <summary>检测时间序列数据</summary>
    Private Sub DetectTimeSeries(context As AnalysisContext)
        For Each ds In context.Datasets
            If File.Exists(ds.SampleInfoFile) Then
                Dim header = CsvUtils.ReadHeader(ds.SampleInfoFile)
                If header.Any(Function(h) h.ToLower().Contains("time")) Then
                    context.IsTimeSeries = True
                    Return
                End If
            End If
        Next
    End Sub

    ''' <summary>验证输入文件</summary>
    Private Function ValidateInputFiles() As Boolean
        _logger("Validating input files...")

        ' 验证表达矩阵格式
        For Each ds In _context.Datasets
            Dim err As String = ""
            If Not CsvUtils.ValidateExpressionMatrix(ds.ExpressionFile, err) Then
                _logger($"  [X] Expression matrix validation failed: {ds.ExpressionFile}")
                _logger($"      {err}")
                Return False
            End If
            _logger($"  [OK] Expression matrix: {ds.ExpressionFile} ({ds.MoleculeIDs.Count} molecules x {ds.SampleIDs.Count} samples)")
        Next

        ' 验证注释表格式
        Dim annoErr As String = ""
        If Not CsvUtils.ValidateAnnotationTable(_context.AnnotationFile, annoErr) Then
            _logger($"  [X] Annotation table validation failed: {_context.AnnotationFile}")
            _logger($"      {annoErr}")
            Return False
        End If
        _logger($"  [OK] Annotation table: {_context.AnnotationFile}")

        ' 验证样本元数据格式
        For Each ds In _context.Datasets
            If File.Exists(ds.SampleInfoFile) Then
                Dim sampleErr As String = ""
                If Not CsvUtils.ValidateSampleInfoTable(ds.SampleInfoFile, sampleErr) Then
                    _logger($"  [X] Sample info validation failed: {ds.SampleInfoFile}")
                    _logger($"      {sampleErr}")
                    Return False
                End If
                _logger($"  [OK] Sample info: {ds.SampleInfoFile}")
            End If
        Next

        Return True
    End Function

    ''' <summary>解析命令行参数</summary>
    Private Function ParseArgs(args As String()) As Dictionary(Of String, String)
        Dim result As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
        For Each arg In args
            If arg.StartsWith("--") Then
                Dim cleanArg = arg.Substring(2)
                Dim eqIdx = cleanArg.IndexOf("="c)
                If eqIdx > 0 Then
                    Dim key = cleanArg.Substring(0, eqIdx)
                    Dim value = cleanArg.Substring(eqIdx + 1).Trim(""""c, "'"c)
                    result(key) = value
                Else
                    result(cleanArg) = "true"
                End If
            End If
        Next
        Return result
    End Function

    ''' <summary>验证必需参数</summary>
    Private Function ValidateRequiredArgs(parsed As Dictionary(Of String, String)) As Boolean
        Dim required = {"research", "expression", "annotation", "sampleinfo"}
        Dim missing = required.Where(Function(k) Not parsed.ContainsKey(k) OrElse String.IsNullOrEmpty(parsed(k))).ToList()
        If missing.Count > 0 Then
            Console.Error.WriteLine("Missing required arguments: " & String.Join(", ", missing.Select(Function(k) "--" & k)))
            Console.Error.WriteLine()
            Console.Error.WriteLine(HelpText)
            Return False
        End If
        Return True
    End Function

    ''' <summary>解析要执行的模块</summary>
    Private Function ParseModulesToRun(parsed As Dictionary(Of String, String)) As List(Of Integer)
        If parsed.ContainsKey("module") Then
            Dim modulesStr = parsed("module")
            Return modulesStr.Split(","c).Select(Function(s) Integer.Parse(s.Trim())).ToList()
        End If
        ' 默认执行所有模块
        Return {1, 2, 3, 4, 5, 6, 7, 8, 9}.ToList()
    End Function

    ''' <summary>根据索引创建分析模块</summary>
    Private Function CreateModule(index As Integer) As AnalysisModuleBase
        Select Case index
            Case 1 : Return New PreprocessingModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case 2 : Return New PCAAnalysisModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case 3 : Return New ComparisonDesignModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case 4 : Return New LimmaDiffModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case 5 : Return New KeggFunctionModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case 6 : Return New WGCNAModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case 7 : Return New AdvancedAnalysisModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case 8 : Return New ResultTablesModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case 9 : Return New ReportModule(_config, _context, Function() CreateLLMClient(), _logger)
            Case Else
                _logger($"Unknown module index: {index}")
                Return Nothing
        End Select
    End Function

    Private Sub ConsoleLog(msg As String)
        Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] {msg}")
    End Sub

End Module
