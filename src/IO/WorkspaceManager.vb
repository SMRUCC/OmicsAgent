' ============================================================================
' 工作区文件夹结构管理
' ============================================================================
Imports System.IO

Namespace IO

    ''' <summary>
    ''' 管理分析工作区的文件夹结构
    ''' </summary>
    Public Class WorkspaceManager

        Public Property WorkspaceDir As String

        Public Sub New(workspaceDir As String)
            Me.WorkspaceDir = workspaceDir
        End Sub

        Public ReadOnly Property TmpDir As String
            Get
                Return Path.Combine(WorkspaceDir, "tmp")
            End Get
        End Property

        Public ReadOnly Property ScriptsDir As String
            Get
                Return Path.Combine(WorkspaceDir, "scripts")
            End Get
        End Property

        Public ReadOnly Property KbDir As String
            Get
                Return Path.Combine(WorkspaceDir, "research_kb")
            End Get
        End Property

        Public ReadOnly Property ReportPath As String
            Get
                Return Path.Combine(WorkspaceDir, "report.pdf")
            End Get
        End Property

        Public ReadOnly Property HtmlReportPath As String
            Get
                Return Path.Combine(WorkspaceDir, "report.html")
            End Get
        End Property

        Public ReadOnly Property LogPath As String
            Get
                Return Path.Combine(WorkspaceDir, "agent.log")
            End Get
        End Property

        ''' <summary>
        ''' 创建工作区基础目录结构
        ''' </summary>
        Public Sub CreateBaseStructure()
            EnsureDir(WorkspaceDir)
            EnsureDir(TmpDir)
            EnsureDir(ScriptsDir)
            EnsureDir(KbDir)
        End Sub

        ''' <summary>
        ''' 为某个分析模块创建子目录结构
        ''' </summary>
        Public Function CreateModuleDir(moduleName As String) As String
            Dim dir = Path.Combine(WorkspaceDir, moduleName)
            EnsureDir(dir)
            EnsureDir(Path.Combine(dir, "tables"))
            EnsureDir(Path.Combine(dir, "figures"))
            Return dir
        End Function

        Public Shared Sub EnsureDir(path As String)
            If Not String.IsNullOrEmpty(path) AndAlso Not Directory.Exists(path) Then
                Directory.CreateDirectory(path)
            End If
        End Sub

        Public Shared Sub EnsureParentDir(filePath As String)
            Dim parent = Path.GetDirectoryName(filePath)
            EnsureDir(parent)
        End Sub

        ''' <summary>
        ''' 列出工作区中所有模块的 conclusion.txt
        ''' </summary>
        Public Function ListModuleConclusions() As List(Of String)
            Dim list As New List(Of String)()
            If Not Directory.Exists(WorkspaceDir) Then Return list
            For Each dir As String In Directory.GetDirectories(WorkspaceDir)
                Dim name = Path.GetFileName(dir)
                If name.StartsWith("analysis_modules_") Then
                    Dim f = Path.Combine(dir, "conclusion.txt")
                    If File.Exists(f) Then list.Add(f)
                End If
            Next
            Return list.OrderBy(Function(x) x).ToList()
        End Function

    End Class

End Namespace
