' ============================================================================
' 数据模型 - 分析上下文、模块计划、组学数据描述等
' ============================================================================

''' <summary>
''' 表示整个分析流程的上下文，包含用户研究主题、所有组学数据集、
''' 工作区路径、知识库路径、阶段性总结文本路径等。
''' 该对象在分析过程中持续累积状态，供各分析模块共享使用。
''' </summary>
Public Class AnalysisContext

    ' ------------------------------------------------------------------
    ' 用户输入
    ' ------------------------------------------------------------------
    ''' <summary>研究主题描述文本（来自 research 文件）</summary>
    Public Property ResearchTopic As String = ""

    ''' <summary>研究主题文件路径</summary>
    Public Property ResearchFile As String = ""

    ''' <summary>参考文献文件夹路径（可选）</summary>
    Public Property ReferenceDir As String = ""

    Public Property AnnotationFile As String
    Public Property AnnotationContent As String
    Public Property SampleInfoInput As String

    ' ------------------------------------------------------------------
    ' 数据集
    ' ------------------------------------------------------------------
    ''' <summary>所有组学数据集列表</summary>
    Public Property Datasets As List(Of OmicsDataset) = New List(Of OmicsDataset)()

    ''' <summary>是否为多组学分析</summary>
    Public ReadOnly Property IsMultiOmics As Boolean
        Get
            Return Datasets.Count > 1
        End Get
    End Property

    ''' <summary>是否为时间序列数据（根据样本元数据 time 列判断）</summary>
    Public Property IsTimeSeries As Boolean = False

    ' ------------------------------------------------------------------
    ' 工作区
    ' ------------------------------------------------------------------
    ''' <summary>分析工作区根目录路径</summary>
    Public Property WorkspaceDir As String = ""

    Public ReadOnly Property AnalysisDir As String
        Get
            Return Path.Combine(WorkspaceDir, "analysis")
        End Get
    End Property

    ''' <summary>临时文件目录路径</summary>
    Public ReadOnly Property TmpDir As String
        Get
            Return Path.Combine(WorkspaceDir, "tmp")
        End Get
    End Property

    ''' <summary>agent 生成的脚本目录路径</summary>
    Public ReadOnly Property ScriptsDir As String
        Get
            Return Path.Combine(WorkspaceDir, "scripts")
        End Get
    End Property

    ''' <summary>知识库目录路径</summary>
    Public ReadOnly Property KnowledgeDir As String
        Get
            Return Path.Combine(WorkspaceDir, "research_kb")
        End Get
    End Property

    ''' <summary>知识库 JSON 文件路径</summary>
    Public ReadOnly Property KnowledgeBaseFile As String
        Get
            Return Path.Combine(KnowledgeDir, "kb.json")
        End Get
    End Property

    ''' <summary>最终报告 PDF 文件路径</summary>
    Public ReadOnly Property ReportPdf As String
        Get
            Return Path.Combine(WorkspaceDir, "report.pdf")
        End Get
    End Property

    ''' <summary>最终报告 HTML 文件路径</summary>
    Public ReadOnly Property ReportHtml As String
        Get
            Return Path.Combine(WorkspaceDir, "report.html")
        End Get
    End Property

    ' ------------------------------------------------------------------
    ' 分析结果
    ' ------------------------------------------------------------------
    ''' <summary>所有差异比较组别设计</summary>
    Public Property Comparisons As List(Of ComparisonGroup) = New List(Of ComparisonGroup)()

    ''' <summary>各分析模块的阶段性总结文本文件路径列表（用于最终报告生成）</summary>
    Public Property ModuleConclusions As List(Of String) = New List(Of String)()

    ''' <summary>各分析模块的章节标题（与 ModuleConclusions 一一对应）</summary>
    Public Property ModuleTitles As List(Of String) = New List(Of String)()

    ''' <summary>各分析模块生成的图片文件路径列表（用于最终报告插图）</summary>
    Public Property ModuleFigures As List(Of String) = New List(Of String)()

    ''' <summary>各分析模块生成的表格文件路径列表（用于最终报告表格）</summary>
    Public Property ModuleTables As List(Of String) = New List(Of String)()

    ''' <summary>各分析模块的图片注解文本（中文）</summary>
    Public Property FigureCaptions As Dictionary(Of String, String) = New Dictionary(Of String, String)()

    ''' <summary>各分析模块的图片注解文本（英文）</summary>
    Public Property FigureCaptionsEn As Dictionary(Of String, String) = New Dictionary(Of String, String)()

    ' ------------------------------------------------------------------
    ' 配置
    ' ------------------------------------------------------------------
    Public Property Config As AgentConfig
    Public Property ModuleResults As New List(Of ModuleResult)

    ' ------------------------------------------------------------------
    ' 工作区初始化
    ' ------------------------------------------------------------------
    ''' <summary>创建工作区目录结构</summary>
    Public Sub InitializeWorkspace()
        If String.IsNullOrEmpty(WorkspaceDir) Then Return
        If Not Directory.Exists(WorkspaceDir) Then Directory.CreateDirectory(WorkspaceDir)
        If Not Directory.Exists(TmpDir) Then Directory.CreateDirectory(TmpDir)
        If Not Directory.Exists(ScriptsDir) Then Directory.CreateDirectory(ScriptsDir)
        If Not Directory.Exists(KnowledgeDir) Then Directory.CreateDirectory(KnowledgeDir)
    End Sub

    ''' <summary>为指定分析模块创建结果目录</summary>
    Public Function CreateModuleDir(moduleName As String) As String
        Dim dir = Path.Combine(WorkspaceDir, moduleName)
        Dim tablesDir = Path.Combine(dir, "tables")
        Dim figuresDir = Path.Combine(dir, "figures")
        If Not Directory.Exists(dir) Then Directory.CreateDirectory(dir)
        If Not Directory.Exists(tablesDir) Then Directory.CreateDirectory(tablesDir)
        If Not Directory.Exists(figuresDir) Then Directory.CreateDirectory(figuresDir)
        Return dir
    End Function

    ''' <summary>记录一个分析模块的阶段性总结文本</summary>
    Public Sub AddConclusion(title As String, conclusionFile As String)
        ModuleTitles.Add(title)
        ModuleConclusions.Add(conclusionFile)
    End Sub

    ''' <summary>记录一个分析模块生成的图片</summary>
    Public Sub AddFigure(figPath As String, captionCn As String, captionEn As String)
        ModuleFigures.Add(figPath)
        FigureCaptions(figPath) = captionCn
        FigureCaptionsEn(figPath) = captionEn
    End Sub

    ''' <summary>记录一个分析模块生成的表格</summary>
    Public Sub AddTable(tablePath As String)
        ModuleTables.Add(tablePath)
    End Sub

End Class
