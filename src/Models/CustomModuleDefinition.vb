Imports Microsoft.VisualBasic.Serialization.JSON

' ============================================================================
' 自定义分析模块 JSON 配置数据模型
' ============================================================================

''' <summary>
''' 自定义分析模块的 JSON 配置数据模型。
''' 用户在 JSON 文件中定义模块元数据和 prompt 提示词，
''' 程序通过扫描文件夹加载这些定义来创建自定义分析模块。
''' 
''' JSON 示例：
''' {
'''   "module_name": "Custom Network Analysis",
'''   "csv_file_name_prefix": "custom_network_",
'''   "generate_plan_prompt": "Design a plan for network analysis...",
'''   "conclusion_items": "1. 网络分析整体结果\n2. 关键节点识别\n3. ..."
''' }
''' </summary>
Public Class CustomModuleDefinition

    ''' <summary>模块名称，用于创建输出目录和日志显示</summary>
    Public Property module_name As String

    ''' <summary>CSV 文件名前缀，用于模块输出文件的命名</summary>
    Public Property csv_file_name_prefix As String

    ''' <summary>
    ''' 分析计划 prompt 提示词，对应 AnalysisModuleBase.GeneratePlanPromptText() 的返回值。
    ''' 描述该模块的分析目标、实现要求和注意事项。
    ''' </summary>
    Public Property generate_plan_prompt As String

    ''' <summary>
    ''' 总结条目文本，对应 AnalysisModuleBase.GetConclusionItems() 的返回值。
    ''' 指导 LLM 生成阶段性总结时应涵盖的内容要点。
    ''' </summary>
    Public Property conclusion_items As String

    ''' <summary>
    ''' 从 JSON 文件加载自定义模块定义。
    ''' 解析失败时返回 Nothing。
    ''' </summary>
    Public Shared Function LoadFromFile(jsonPath As String) As CustomModuleDefinition
        Try
            Dim json = File.ReadAllText(jsonPath, Encoding.UTF8)
            Dim def = json.LoadJSON(Of CustomModuleDefinition)()

            If def Is Nothing Then Return Nothing
            If def.module_name.StringEmpty(, True) Then Return Nothing
            If def.generate_plan_prompt.StringEmpty(, True) Then Return Nothing

            ' 为可选字段提供默认值
            If def.csv_file_name_prefix.StringEmpty(, True) Then
                def.csv_file_name_prefix = $"custom_{def.module_name.NormalizePathString(alphabetOnly:=True).Replace(" ", "_").ToLower}_"
            End If
            If def.conclusion_items.StringEmpty(, True) Then
                def.conclusion_items = "1. 分析结果的整体描述
2. 关键发现总结
3. 与用户研究主题的关联性说明"
            End If

            Return def
        Catch ex As Exception
            Call App.LogException(ex)
            Return Nothing
        End Try
    End Function

End Class
