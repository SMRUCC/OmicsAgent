Imports Microsoft.VisualBasic.ComponentModel.DataSourceModel.SchemaMaps
Imports Microsoft.VisualBasic.ComponentModel.Settings.Inf
Imports OmicsAgent.AppRuntime.Ini

Namespace Settings

    Public Class AppConfig

        ' ------------------------------------------------------------------
        ' 段子对象（各段对应 INI 文件中的一个 section）
        ' ------------------------------------------------------------------
        ''' <summary>外部工具路径</summary>
        <DataFrameColumn("tools")> Public Property Tools As New ToolConfig()

        ''' <summary>大语言模型服务配置</summary>
        <DataFrameColumn("llm")> Public Property LLM As New LLMConfig()

        ''' <summary>MySQL 数据库连接参数（用于 PubMed 本地镜像查询）</summary>
        <DataFrameColumn("mysql")> Public Property MySql As New MySqlConfig()

        ''' <summary>文献检索策略</summary>
        <DataFrameColumn("literature")> Public Property Literature As New LiteratureConfig()

        ''' <summary>分析流程参数</summary>
        <DataFrameColumn("analysis")> Public Property Analysis As New AnalysisConfig()

        ''' <summary>最终报告输出格式配置</summary>
        <DataFrameColumn("report")> Public Property Report As New ReportConfig()

        Shared ReadOnly Property defaultFile As String = App.ProductProgramData & "/omics-works-config.ini"

        Public Shared Function Load() As AppConfig
            Dim config As AppConfig = IOProvider.LoadProfile(Of AppConfig)(defaultFile)

            If config Is Nothing Then
                config = New AppConfig With {.LLM = New LLMConfig}
                config.WriteProfile(defaultFile)
            End If

            If config.LLM Is Nothing Then config.LLM = New LLMConfig

            Return config
        End Function

        Public Function Save() As Boolean
            Return Me.WriteProfile(defaultFile)
        End Function
    End Class
End Namespace