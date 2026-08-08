Imports OmicsAgent.AppRuntime

''' <summary>
''' 仅用于构建知识库的流程
''' </summary>
Module KnowledgeLibrary

    Dim _config As AgentConfig
    Dim _context As AnalysisContext

    Public Async Function Run(parsed As Opts) As Task(Of Integer)
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

        _context = New AnalysisContext()

        ' 研究主题文件
        _context.ResearchFile = parsed.research
        _context.ResearchTopic = parsed.research.ReadAllText

        ' 用户数据文件夹列表文件
        _context.UserDataDirsFile = parsed.dirs

        ' 参考文献文件夹（可选）
        If Not parsed.reference.StringEmpty(, True) Then
            _context.ReferenceDir = parsed.reference
        End If

        ' 工作区
        If Not parsed.workspace.StringEmpty(, True) Then
            _context.WorkspaceDir = parsed.workspace.GetDirectoryFullPath
        Else
            _context.WorkspaceDir = Path.Combine(Directory.GetCurrentDirectory(), "report_output").GetDirectoryFullPath
        End If

        ' 创建工作区目录结构
        Call _context.WorkspaceDir.MakeDir
        Call Path.Combine(_context.WorkspaceDir, "research_kb").MakeDir
        Call Path.Combine(_context.WorkspaceDir, "tmp").MakeDir
        Call Path.Combine(_context.WorkspaceDir, "scripts").MakeDir
        Call Path.Combine(_context.WorkspaceDir, "analysis").MakeDir

        Return Await Build()
    End Function

    Private Async Function Build() As Task(Of Integer)
        Dim agent As New KnowledgeBaseBuilder(_config, _context)

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

        If parsed.reference.StringEmpty(, True) Then
            missing.Add("--reference")
        ElseIf Not parsed.reference.DirectoryExists Then
            Console.Error.WriteLine($"User knowledge library data dir not found: {parsed.reference}")
            Return False
        End If

        If missing.Count > 0 Then
            Console.Error.WriteLine("Missing required arguments: " & String.Join(", ", missing))
            Console.Error.WriteLine()
            Console.Error.WriteLine("用法: research /kb --research=research.txt --reference=/path/to/kb_library [options]")
            Return False
        End If

        Return True
    End Function
End Module
