Imports OmicsAgent.AppRuntime

' ============================================================================
' JSON 驱动的自定义分析模块
' ============================================================================

''' <summary>
''' 由 JSON 配置文件驱动的自定义分析模块。
''' 
''' 通过 <see cref="CustomModuleDefinition"/> 提供模块特定的 prompt 提示词，
''' 完全复用 <see cref="AnalysisModuleBase"/> 的标准执行流程
''' （生成计划 → 编写脚本 → 执行脚本 → 生成总结）。
''' 
''' 用户只需在 JSON 文件中定义模块名称、CSV 前缀、计划 prompt 和总结条目，
''' 即可将自定义分析步骤插入到标准分析流程中。
''' </summary>
Public Class JsonDefinedModule : Inherits AnalysisModuleBase

    Private ReadOnly _definition As CustomModuleDefinition
    Private ReadOnly _customIndex As Integer

    ''' <summary>
    ''' 创建 JSON 驱动的自定义分析模块。
    ''' </summary>
    ''' <param name="config">Agent 配置</param>
    ''' <param name="context">分析上下文</param>
    ''' <param name="logger">日志输出委托</param>
    ''' <param name="definition">从 JSON 文件加载的模块定义</param>
    ''' <param name="moduleIndex">模块序号（从 12 开始，避免与标准模块 1-11 冲突）</param>
    Public Sub New(config As AgentConfig,
                   context As AnalysisContext,
                   logger As Action(Of String),
                   definition As CustomModuleDefinition,
                   moduleIndex As Integer)
        MyBase.New(config, context, logger)
        _definition = definition
        _customIndex = moduleIndex
    End Sub

    Public Overrides ReadOnly Property ModuleName As String
        Get
            Return _definition.module_name
        End Get
    End Property

    Public Overrides ReadOnly Property ModuleIndex As Integer
        Get
            Return _customIndex
        End Get
    End Property

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return _definition.csv_file_name_prefix
        End Get
    End Property

    Protected Overrides Function GeneratePlanPromptText() As String
        Return _definition.generate_plan_prompt
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return _definition.conclusion_items
    End Function

End Class
