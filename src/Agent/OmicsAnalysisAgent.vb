' ============================================================================
' 主 Agent 编排器
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Config
Imports OmicsAgent.Models
Imports OmicsAgent.Utils
Imports OmicsAgent.IO
Imports OmicsAgent.Knowledge
Imports OmicsAgent.Agent.Modules

Namespace Agent

    ''' <summary>
    ''' 组学数据分析 Agent 主编排器
    ''' </summary>
    Public Class OmicsAnalysisAgent

        Private ReadOnly _config As AppConfig
        Private ReadOnly _workspace As WorkspaceManager
        Private ReadOnly _input As AnalysisInput
        Private ReadOnly _logger As Logger
        Private ReadOnly _referencesDir As String

        Public Sub New(config As AppConfig, workspace As WorkspaceManager, input As AnalysisInput,
                       referencesDir As String, logger As Logger)
            _config = config
            _workspace = workspace
            _input = input
            _logger = logger
            _referencesDir = referencesDir
        End Sub

        ''' <summary>
        ''' LLM 客户端工厂方法 - 每次调用创建新实例
        ''' </summary>
        Public Function CreateLlmClient() As LLMClient
            Return New LLMClient(_config.LlmUrl, _config.LlmModel, _config.LlmApiKey)
        End Function

        ''' <summary>
        ''' 运行完整的分析流程
        ''' </summary>
        Public Async Function RunAsync() As Task
            _logger.Phase("Omics Analysis Agent - Starting")

            ' 1. 构建知识库
            Dim kbPath = Await BuildKnowledgeBaseAsync()

            ' 2. 依次执行分析模块
            Dim modules = BuildModuleList(kbPath)
            Dim results As New List(Of ModuleResult)()

            For Each m In modules
                _logger.Info($"Starting module: {m.ModuleName}")
                Dim r = Await m.RunAsync()
                results.Add(r)
                _logger.Info($"Module {m.ModuleName} finished. Success={r.Success}")
                If Not r.Success Then
                    _logger.Warn($"Module {m.ModuleName} failed but continuing to next module.")
                End If
            Next

            ' 3. 生成最终报告
            _logger.Phase("Final Report Generation")
            Await GenerateReportAsync(results, kbPath)

            _logger.Phase("Omics Analysis Agent - Completed")
            _logger.Info($"Final report: {_workspace.ReportPath}")
        End Function

        Private Async Function BuildKnowledgeBaseAsync() As Task(Of String)
            Dim builder As New KnowledgeBaseBuilder(_config, _workspace.KbDir, _referencesDir)
            Return Await builder.BuildAsync(_input.Research.RawText, AddressOf CreateLlmClient, _logger)
        End Function

        Private Function BuildModuleList(kbPath As String) As List(Of AnalysisModuleBase)
            Dim list As New List(Of AnalysisModuleBase)()
            Dim factory As Func(Of LLMClient) = AddressOf CreateLlmClient

            ' 模块 1: 数据预处理
            list.Add(New PreprocessingModule(1, _config, _workspace, _input, kbPath, _logger, factory))
            ' 模块 2: 多元统计分析 (PCA/PLSDA/OPLSDA)
            list.Add(New MultivariateModule(2, _config, _workspace, _input, kbPath, _logger, factory))
            ' 模块 3: 差异分析 (LIMMA)
            list.Add(New DifferentialModule(3, _config, _workspace, _input, kbPath, _logger, factory))
            ' 模块 4: KEGG 富集 + GSVA
            list.Add(New KeggEnrichmentModule(4, _config, _workspace, _input, kbPath, _logger, factory))
            ' 模块 5: WGCNA
            list.Add(New WgcnaModule(5, _config, _workspace, _input, kbPath, _logger, factory))
            ' 模块 6: CMeans 软聚类
            list.Add(New CMeansModule(6, _config, _workspace, _input, kbPath, _logger, factory))
            ' 模块 7: bnlearn 动态贝叶斯网络 (仅时间序列)
            list.Add(New BnlearnModule(7, _config, _workspace, _input, kbPath, _logger, factory))
            ' 模块 8: PLS-PM 因果路径分析
            list.Add(New PlspmModule(8, _config, _workspace, _input, kbPath, _logger, factory))

            Return list
        End Function

        Private Async Function GenerateReportAsync(results As List(Of ModuleResult), kbPath As String) As Task
            _logger.Info("Generating final research report...")
            Dim reportGen As New ReportGenerator(_config, _workspace, _input, _logger, AddressOf CreateLlmClient)
            Await reportGen.GenerateAsync(results, kbPath)
        End Function

    End Class

End Namespace
