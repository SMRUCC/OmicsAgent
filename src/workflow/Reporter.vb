Imports Microsoft.VisualBasic.ApplicationServices.Terminal.Utility
Imports OmicsAgent.AppRuntime

' ============================================================================
' /report 模式工作流 - 用户数据报告生成
' ============================================================================

Module Reporter

    Private _logger As Action(Of String) = AddressOf ConsoleLog
    Private _config As AgentConfig
    Private _context As AnalysisContext

    ''' <summary>
    ''' /report 模式主入口。
    ''' 扫描用户通过 --dirs 参数指定的数据文件夹，
    ''' 整理 CSV 表格并生成论文初稿报告。
    ''' </summary>
    Public Async Function Run(parsed As Opts) As Task(Of Integer)
        Console.OutputEncoding = Encoding.UTF8
        Console.WriteLine("Omics Data Report Generator v1.0")
        Console.WriteLine("=" & New String("="c, 50))
        Console.WriteLine()

        ' 1. 加载配置
        _config = parsed.LoadConfig

        ' 配置文件缺失或无法解析时终止
        If _config Is Nothing Then
            Console.Error.WriteLine("配置文件缺失或无法解析。已生成配置模板，请按提示填写 config.ini 后重新运行程序。")
            Return 1
        End If

        ' 2. 验证 /report 模式必需参数
        If Not ValidateReportArgs(parsed) Then
            Return 1
        End If

        ' 3. 初始化分析上下文（精简版，无需数据集解析）
        _context = InitializeReportContext(parsed)

        ' 4. 异步执行报告生成流程
        Await RunReportAsync(parsed)

        Console.WriteLine()
        Console.WriteLine("Report generation completed successfully!")
        Console.WriteLine($"Results saved to: {_context.WorkspaceDir}")

        Return 0
    End Function

    ''' <summary>验证 /report 模式必需的参数</summary>
    Private Function ValidateReportArgs(parsed As Opts) As Boolean
        Dim missing As New List(Of String)

        If parsed.research.StringEmpty(, True) Then
            missing.Add("--research")
        ElseIf Not parsed.research.FileExists Then
            Console.Error.WriteLine($"Research file not found: {parsed.research}")
            Return False
        End If

        If parsed.dirs.StringEmpty(, True) Then
            missing.Add("--dirs")
        ElseIf Not parsed.dirs.FileExists Then
            Console.Error.WriteLine($"User data dirs file not found: {parsed.dirs}")
            Return False
        End If

        If missing.Count > 0 Then
            Console.Error.WriteLine("Missing required arguments: " & String.Join(", ", missing))
            Console.Error.WriteLine()
            Console.Error.WriteLine("用法: research /report --research=research.txt --dirs=dirs.txt [options]")
            Return False
        End If

        Return True
    End Function

    ''' <summary>初始化 /report 模式的轻量级分析上下文</summary>
    ''' <remarks>
    ''' /report 模式不需要解析组学数据集（--dataset / -e/-a/-s），
    ''' 不需要样本对齐等 /agent 专属逻辑，仅需设置研究主题、
    ''' 工作区和用户数据文件夹列表即可。
    ''' </remarks>
    Private Function InitializeReportContext(parsed As Opts) As AnalysisContext
        Dim context As New AnalysisContext()

        ' 研究主题文件
        context.ResearchFile = parsed.research
        context.ResearchTopic = parsed.research.ReadAllText

        ' 用户数据文件夹列表文件
        context.UserDataDirsFile = parsed.dirs

        ' 参考文献文件夹（可选）
        If Not parsed.reference.StringEmpty(, True) Then
            context.ReferenceDir = parsed.reference
        End If

        ' 工作区
        If Not parsed.workspace.StringEmpty(, True) Then
            context.WorkspaceDir = parsed.workspace.GetDirectoryFullPath
        Else
            context.WorkspaceDir = Path.Combine(Directory.GetCurrentDirectory(), "report_output").GetDirectoryFullPath
        End If

        ' 创建工作区目录结构
        Call context.WorkspaceDir.MakeDir
        Call Path.Combine(context.WorkspaceDir, "research_kb").MakeDir
        Call Path.Combine(context.WorkspaceDir, "tmp").MakeDir
        Call Path.Combine(context.WorkspaceDir, "scripts").MakeDir
        Call Path.Combine(context.WorkspaceDir, "analysis").MakeDir

        Return context
    End Function

    ''' <summary>异步执行报告生成流程</summary>
    Private Async Function RunReportAsync(opts As Opts) As Task
        Dim cancellationToken = UserTaskCancelAction.GetConsoleCancellationToken(prompt:="Cancellation requested...")

        ' 1. 环境检查
        Dim checker As New EnvironmentChecker(_config, _logger)

        If Not Await checker.CheckAllAsync() Then
            Console.Error.WriteLine("Environment check failed. Please fix the issues above and try again.")
            Return
        Else
            Console.WriteLine()
        End If

        ' 2. 知识库构建（可选）
        If Not opts.skip_kb Then
            Dim kbBuilder As New KnowledgeBaseBuilder(_config, _context, _logger)
            Await kbBuilder.BuildAsync(cancellationToken)
            Console.WriteLine()
        End If

        ' 3. 用户数据表格整理模块
        Console.WriteLine("========== Phase 1: User Data Tables Compilation ==========")
        Console.WriteLine()

        Dim userDataModule As New UserDataTablesModule(_config, _context, _logger)

        Try
            Await userDataModule.RunAsync(cancellationToken)
            Console.WriteLine()
        Catch ex As Exception
            _logger($"ERROR in user data tables compilation: {ex.Message}")
            Console.Error.WriteLine(ex.StackTrace)
            Console.WriteLine("Proceeding to report generation with available data...")
        End Try

        ' 4. 论文报告撰写模块
        Console.WriteLine("========== Phase 2: Paper Draft Report Generation ==========")
        Console.WriteLine()

        Dim reportModule As New ReportModule(_config, _context, _logger)

        Try
            Await reportModule.RunAsync(cancellationToken)
            Console.WriteLine()
        Catch ex As Exception
            _logger($"ERROR in report generation: {ex.Message}")
            Console.Error.WriteLine(ex.StackTrace)
        End Try
    End Function

    Private Sub ConsoleLog(msg As String)
        Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] {msg}")
    End Sub

End Module
