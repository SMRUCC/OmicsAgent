Imports Microsoft.VisualBasic.ApplicationServices.Terminal.Utility
Imports Microsoft.VisualBasic.Data.Framework.IO.CSVFile
Imports Microsoft.VisualBasic.Serialization.JSON
Imports OmicsAgent.AppRuntime

Module Workflow

    Private _logger As Action(Of String) = AddressOf ConsoleLog
    Private _config As AgentConfig
    Private _context As AnalysisContext
    Private _customModules As New List(Of CustomModuleDefinition)

    Public Async Function Run(parsed As Opts) As Task(Of Integer)
        Console.OutputEncoding = Encoding.UTF8
        Console.WriteLine("Omics Data Analysis LLM Agent v1.0")
        Console.WriteLine("=" & New String("="c, 50))
        Console.WriteLine()

        ' 加载配置
        _config = parsed.LoadConfig

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

    ''' <summary>异步主流程</summary>
    Private Async Function MainAsync(opts As Opts) As Task
        Dim cancellationToken = UserTaskCancelAction.GetConsoleCancellationToken(prompt:="Cancellation requested...")
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
        If Not opts.skip_kb Then
            Dim kbBuilder As New KnowledgeBaseBuilder(_config, _context, _logger)
            Await kbBuilder.BuildAsync(cancellationToken)
            Console.WriteLine()
        End If

        ' 4. 执行分析模块
        Dim modulesToRun = opts.ParseModulesToRun

        ' 加载自定义分析模块（从 JSON 配置文件）
        Dim customModuleDir = GetCustomModulesDir(opts)
        _customModules = LoadCustomModules(customModuleDir)

        ' 若执行列表包含结果汇总(11)或报告(12)模块，则在其之前插入自定义模块索引，
        ' 确保自定义模块在 ResultTablesModule 和 ReportModule 之前执行，
        ' 这样自定义模块的结论才能被结果表与最终报告收录。
        If _customModules.Count > 0 Then
            Dim firstReportIdx = -1
            For i = 0 To modulesToRun.Count - 1
                If modulesToRun(i) = 11 OrElse modulesToRun(i) = 12 Then
                    firstReportIdx = i
                    Exit For
                End If
            Next

            If firstReportIdx >= 0 Then
                Dim customIndices = Enumerable.Range(0, _customModules.Count).Select(Function(i) 13 + i).ToList()
                modulesToRun.InsertRange(firstReportIdx, customIndices)
            End If
        End If

        For Each moduleIdx As Integer In modulesToRun
            If cancellationToken.IsCancellationRequested Then
                Exit For
            End If

            Dim [module] As AnalysisModuleBase = CreateModule(moduleIdx)

            ' CreateModule 返回 Nothing 表示该模块在当前数据场景下不适用
            ' （例如单组学时的跨组学整合模块），直接跳过
            If [module] Is Nothing Then
                Continue For
            End If

            If opts.make_report Then
                If TypeOf [module] Is ReportModule Then
                    DirectCast([module], ReportModule).debugCache = opts.debug_cache
                    Await [module].RunAsync(cancellationToken)
                Else
                    _context.ModuleConclusions.Add($"{[module].ConclusionFile}")
                    _context.ModuleResults.Add($"{[module].Workspace}/result.json".ReadAllText.LoadJSON(Of ModuleResult))
                End If
            Else
                Try
                    If [module] IsNot Nothing Then
                        Dim checkCache = $"{[module].ConclusionFile}".FileExists AndAlso $"{[module].Workspace}/result.json".FileExists

                        If checkCache AndAlso opts.debug_cache Then
                            ' skip
                            _context.ModuleConclusions.Add($"{[module].ConclusionFile}")
                            _context.ModuleResults.Add($"{[module].Workspace}/result.json".ReadAllText.LoadJSON(Of ModuleResult))
                        Else
                            Console.WriteLine($"========== Module {moduleIdx}: {[module].ModuleName} ==========")
                            Await [module].RunAsync(cancellationToken)
                            Console.WriteLine()
                        End If
                    End If
                Catch ex As Exception
                    _logger($"ERROR in module {moduleIdx}: {ex.Message}")
                    Console.Error.WriteLine(ex.StackTrace)
                    Console.WriteLine("Continuing to next module...")
                End Try
            End If
        Next

    End Function

    ''' <summary>初始化分析上下文</summary>
    Private Function InitializeContext(parsed As Opts) As AnalysisContext
        Dim context As New AnalysisContext()

        ' 研究主题文件
        context.ResearchFile = parsed.research

        ' 解析组学数据输入。--dataset 定义文件模式与 -e/-a/-s 传统参数模式
        ' 在此归一为结构一致的数据集集合，下游流程无需感知输入来源。
        Dim resolver As New OmicsInputResolver(_logger)

        Call resolver.Resolve(parsed)

        context.Datasets.AddRange(resolver.Datasets)
        context.AnnotationFile = resolver.GlobalAnnotationFile
        context.SampleInfoInput = resolver.SampleInfoInput

        If resolver.Manifest IsNot Nothing Then
            context.DatasetManifestFile = resolver.Manifest.ManifestFile
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
        Call Path.Combine(context.WorkspaceDir, "aligned").MakeDir

        ' 读取研究主题文本
        context.ResearchTopic = context.ResearchFile.ReadAllText

        ' 多组学：先把各组学样本对齐到统一的生物学个体，并生成对齐后的新矩阵。
        ' 该步骤必须在读取样本 ID / 分子 ID 之前完成，因为它会重定向表达矩阵路径。
        If context.IsMultiOmics Then
            Dim aligner As New SampleAligner(context, _logger)

            Call aligner.Align(resolver.Manifest?.sample_alignment)
        End If

        ' 整理分子注释表：单组学直接沿用原表，多组学合并为带来源标识的全局总表
        Dim merger As New AnnotationMerger(context, _logger)

        Call merger.Merge()

        ' 读取各组学的样本 ID 与分子 ID。
        ' 注意：此处不能依赖样本元数据是否存在——缺失样本元数据时同样需要这些 ID
        ' 用于输入校验与提示词上下文构建。
        For Each ds In context.Datasets
            ds.SampleIDs = CsvUtils.ReadSampleIDs(ds.ExpressionFile)
            ds.MoleculeIDs = CsvUtils.ReadFirstColumn(ds.ExpressionFile).ToArray
        Next

        ' 检测是否为时间序列数据
        DetectTimeSeries(context)

        Return context
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

        ' 验证注释表格式：每个组学都有各自的注释表，需逐一校验
        Dim validatedAnnotation As New HashSet(Of String)(StringComparer.OrdinalIgnoreCase)

        For Each ds In _context.Datasets
            If ds.AnnotationFile.StringEmpty(, True) Then
                _logger($"  [!] Dataset [{ds.Id}] has no annotation table, related analysis will be limited.")
                Continue For
            End If

            ' 传统参数模式下各组学共用同一张注释表，避免重复校验与重复日志
            If Not validatedAnnotation.Add(ds.AnnotationFile) Then
                Continue For
            End If

            Dim annoErr As String = ""

            If Not CsvUtils.ValidateAnnotation(ds.AnnotationFile, annoErr) Then
                _logger($"  [X] Annotation table validation failed for dataset [{ds.Id}]: {ds.AnnotationFile}")
                _logger($"      {annoErr}")
                Return False
            End If

            _logger($"  [OK] Annotation table [{ds.Id}]: {ds.AnnotationFile}")
        Next

        ' 多组学场景下另有一张合并生成的全局注释总表
        If _context.IsMultiOmics AndAlso _context.AnnotationFile.FileExists Then
            _logger($"  [OK] Merged annotation table: {_context.AnnotationFile}")
        End If

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
            Case 7 : Return New CMeansAnalysisModule(_config, _context, _logger)
            Case 8 : Return New BayesianNetworkModule(_config, _context, _logger)
            Case 9 : Return New PLSPMAnalysisModule(_config, _context, _logger)
            Case 10
                ' 跨组学整合分析：仅在多组学场景下有意义，单组学时静默跳过
                If Not _context.IsMultiOmics Then
                    Return Nothing
                End If

                Return New CrossOmicsModule(_config, _context, _logger)
            Case 11 : Return New ResultTablesModule(_config, _context, _logger)
            Case 12 : Return New ReportModule(_config, _context, _logger)
            Case Is >= 13
                ' 自定义模块：索引从 13 开始，映射到 _customModules 列表
                Dim customIdx = index - 13
                If customIdx < _customModules.Count Then
                    Dim def = _customModules(customIdx)
                    Return New JsonDefinedModule(_config, _context, _logger, def, index)
                End If
                _logger($"Unknown custom module index: {index}")
                Return Nothing
            Case Else
                _logger($"Unknown module index: {index}")
                Return Nothing
        End Select
    End Function

    ''' <summary>获取自定义模块文件夹路径</summary>
    Private Function GetCustomModulesDir(parsed As Opts) As String
        ' 优先使用命令行参数指定的路径
        If Not parsed.custom_modules.StringEmpty(, True) Then
            Return parsed.custom_modules.GetDirectoryFullPath
        End If

        ' 默认使用应用程序根目录下的 custom_modules/ 文件夹
        Return Path.Combine(AgentConfig.ApplicationRoot, "custom_modules").GetDirectoryFullPath
    End Function

    ''' <summary>扫描文件夹加载自定义模块 JSON 定义</summary>
    Private Function LoadCustomModules(dir As String) As List(Of CustomModuleDefinition)
        Dim result As New List(Of CustomModuleDefinition)()

        If dir.StringEmpty(, True) Then Return result

        If Not Directory.Exists(dir) Then
            _logger($"Custom modules directory not found: {dir} (skipping)")
            Return result
        End If

        _logger($"Scanning custom modules in: {dir}")

        For Each jsonFile In Directory.GetFiles(dir, "*.json")
            Try
                Dim def = CustomModuleDefinition.LoadFromFile(jsonFile)
                If def IsNot Nothing Then
                    result.Add(def)
                    _logger($"  [OK] Loaded custom module: {def.module_name} from {Path.GetFileName(jsonFile)}")
                Else
                    _logger($"  [SKIP] Failed to load custom module from: {jsonFile}")
                End If
            Catch ex As Exception
                _logger($"  [ERROR] Failed to load {jsonFile}: {ex.Message}")
            End Try
        Next

        _logger($"Loaded {result.Count} custom module(s)")
        Return result
    End Function

    Private Sub ConsoleLog(msg As String)
        Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] {msg}")
    End Sub
End Module
