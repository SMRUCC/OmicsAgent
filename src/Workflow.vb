Imports Microsoft.VisualBasic.Data.Framework.IO.CSVFile
Imports Ollama
Imports OmicsAgent.AppRuntime

Module Workflow

    Private _logger As Action(Of String) = AddressOf ConsoleLog
    Private _config As AgentConfig
    Private _context As AnalysisContext

    Public Async Function Run(parsed As Opts) As Task(Of Integer)
        Console.OutputEncoding = Encoding.UTF8
        Console.WriteLine("Omics Data Analysis LLM Agent v1.0")
        Console.WriteLine("=" & New String("="c, 50))
        Console.WriteLine()

        ' 加载配置
        _config = AgentConfig.Load(If(parsed.config, "config.ini"))

        ' 配置文件缺失或无法解析时，AgentConfig.Load 会生成模板并返回 Nothing。
        ' 此时应提示用户按模板填写后重新运行并终止，避免后续空引用崩溃。
        If _config Is Nothing Then
            Console.Error.WriteLine("配置文件缺失或无法解析。已生成配置模板，请按提示填写 config.ini 后重新运行程序。")
            Return 1
        Else
            ' 初始化分析上下文
            _context = InitializeContext(parsed)
        End If

        ' 异步执行主流程
        Await MainAsync(parsed)

        Console.WriteLine()
        Console.WriteLine("Analysis completed successfully!")
        Console.WriteLine($"Results saved to: {_context.WorkspaceDir}")

        Return 0
    End Function

    Private Function GetCancelToken() As CancellationToken
        Dim cts As New CancellationTokenSource()

        AddHandler Console.CancelKeyPress,
            Sub(s, e)
                e.Cancel = True
                cts.Cancel()
                Console.WriteLine("Cancellation requested...")
            End Sub

        Return cts.Token
    End Function

    ''' <summary>异步主流程</summary>
    Private Async Function MainAsync(parsed As Opts) As Task
        Dim cancellationToken = GetCancelToken()
        ' 1. 环境检查
        Dim checker As New EnvironmentChecker(_config, _logger)

        If Not Await checker.CheckAllAsync() Then
            Console.Error.WriteLine("Environment check failed. Please fix the issues above and try again.")
            Return
        Else
            Console.WriteLine()
        End If

        ' 2. 验证输入文件
        If Not ValidateInputFiles() Then
            Return
        Else
            Console.WriteLine()
        End If

        ' 3. 知识库构建（可选）
        If Not parsed.skip_kb Then
            Dim kbBuilder As New KnowledgeBaseBuilder(_config, _context, _logger)
            Await kbBuilder.BuildAsync(cancellationToken)
            Console.WriteLine()
        End If

        ' 4. 执行分析模块
        Dim modulesToRun = parsed.ParseModulesToRun
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

    ''' <summary>初始化分析上下文</summary>
    Private Function InitializeContext(parsed As Opts) As AnalysisContext
        Dim context As New AnalysisContext()

        ' 研究主题文件
        context.ResearchFile = parsed.research

        ' 表达矩阵文件/文件夹
        Dim exprPath = parsed.expression
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
        context.AnnotationFile = parsed.annotation.GetFullPath

        ' 样本元数据文件/文件夹
        context.SampleInfoInput = parsed.sampleinfo
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
        If Not parsed.reference.StringEmpty(, True) Then
            context.ReferenceDir = parsed.reference
        End If

        ' 工作区
        If Not parsed.workspace.StringEmpty(, True) Then
            context.WorkspaceDir = parsed.workspace.GetDirectoryFullPath
        Else
            ' 默认在表达矩阵所在位置创建 analysis 文件夹
            Dim firstExpr = context.Datasets.FirstOrDefault()?.ExpressionFile
            If Not String.IsNullOrEmpty(firstExpr) Then
                context.WorkspaceDir = Path.Combine(Path.GetDirectoryName(firstExpr), "analysis").GetDirectoryFullPath
            Else
                context.WorkspaceDir = Path.Combine(Directory.GetCurrentDirectory(), "analysis").GetDirectoryFullPath
            End If
        End If

        ' 创建工作区目录结构
        Call context.WorkspaceDir.MakeDir
        Call Path.Combine(context.WorkspaceDir, "research_kb").MakeDir
        Call Path.Combine(context.WorkspaceDir, "tmp").MakeDir
        Call Path.Combine(context.WorkspaceDir, "scripts").MakeDir
        Call Path.Combine(context.WorkspaceDir, "analysis").MakeDir

        ' 读取研究主题文本
        context.ResearchTopic = context.ResearchFile.ReadAllText
        ' 读取分子注释表
        context.AnnotationContent = Molecule.ReadCsv(context.AnnotationFile).ToArray

        ' 读取样本元数据
        For Each ds In context.Datasets
            If File.Exists(ds.SampleInfoFile) Then
                ds.SampleIDs = CsvUtils.ReadSampleIDs(ds.ExpressionFile)
                ds.MoleculeIDs = CsvUtils.ReadFirstColumn(ds.ExpressionFile)
            End If
        Next

        ' 检测是否为时间序列数据
        DetectTimeSeries(context)

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
                Dim header = Tokenizer.CharsParser(ds.SampleInfoFile.ReadFirstLine)
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
        If Not CsvUtils.ValidateAnnotation(_context.AnnotationFile, annoErr) Then
            _logger($"  [X] Annotation table validation failed: {_context.AnnotationFile}")
            _logger($"      {annoErr}")
            Return False
        End If
        _logger($"  [OK] Annotation table: {_context.AnnotationFile}")

        ' 验证样本元数据格式
        For Each ds In _context.Datasets
            If File.Exists(ds.SampleInfoFile) Then
                Dim sampleErr As String = ""
                If Not CsvUtils.ValidateSampleInfo(ds.SampleInfoFile, sampleErr) Then
                    _logger($"  [X] Sample info validation failed: {ds.SampleInfoFile}")
                    _logger($"      {sampleErr}")
                    Return False
                End If
                _logger($"  [OK] Sample info: {ds.SampleInfoFile}")
            End If
        Next

        Return True
    End Function

    ''' <summary>根据索引创建分析模块</summary>
    Private Function CreateModule(index As Integer) As AnalysisModuleBase
        Select Case index
            Case 1 : Return New PreprocessingModule(_config, _context, _logger)
            Case 2 : Return New PCAAnalysisModule(_config, _context, _logger)
            Case 3 : Return New ComparisonDesignModule(_config, _context, _logger)
            Case 4 : Return New LimmaDiffModule(_config, _context, _logger)
            Case 5 : Return New KeggFunctionModule(_config, _context, _logger)
            Case 6 : Return New WGCNAModule(_config, _context, _logger)
            Case 7 : Return New AdvancedAnalysisModule(_config, _context, _logger)
            Case 8 : Return New ResultTablesModule(_config, _context, _logger)
            Case 9 : Return New ReportModule(_config, _context, _logger)
            Case Else
                _logger($"Unknown module index: {index}")
                Return Nothing
        End Select
    End Function

    Private Sub ConsoleLog(msg As String)
        Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] {msg}")
    End Sub
End Module
