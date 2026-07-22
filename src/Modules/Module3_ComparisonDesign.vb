Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 3: 设计差异分析的比对组别
' ============================================================================

''' <summary>
''' 差异分析比对组别设计模块。
''' 
''' 根据用户的研究主题设计差异分析的比对组别，这些组别应该深入契合
''' 用户当前研究主题已知相关的生物学机制。会参考 kb.json 中的生物学知识
''' 生成阶段性研究总结文件，阐述差异比对设计的生物学依据、分析目的、
''' 与用户研究主题的生物学机制相关性等。
''' </summary>
Public Class ComparisonDesignModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Comparison Group Design"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 3

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Using llm As LLMClient = _config.CreateLLMClient(_context.TmpDir)
            RegisterTools(llm)

            Dim prompt = $"
You are a biomedical research expert. Design differential analysis comparison groups based on the user's research topic.

{BuildContextInfo()}

# Your Task
Based on the user's research topic and the available sample groups (from sample_info column in sample metadata):
1. Identify all available sample groups
2. Design biologically meaningful comparison pairs that align with the research topic
3. For time-series data, design comparisons across time points within each group
4. Consider both pairwise comparisons and multi-group comparisons
5. For multi-omics data, design consistent comparisons across omics layers

The comparison design should be deeply aligned with the known biological mechanisms related to the user's research topic.
Reference the kb.json knowledge base for biological insights.

Return your plan as JSON:
{{
  ""module_name"": ""Comparison Group Design"",
  ""goal"": ""<brief description of comparison design rationale>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""comparisons"": [
    {{
      ""name"": ""<comparison name, e.g., 'disease_vs_control'>"",
      ""treatment"": ""<treatment group name>"",
      ""control"": ""<control group name>"",
      ""biological_rationale"": ""<why this comparison is biologically meaningful>"",
      ""expected_findings"": ""<what biological insights are expected>""
    }}
  ],
  ""notes"": ""<special considerations>""
}}
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = resp.ExtractJsonFromResponse
            Dim plan As ModulePlan
            If Not String.IsNullOrEmpty(json) Then
                plan = json.LoadJSON(Of ModulePlan)
            Else
                plan = New ModulePlan() With {.ModuleName = ModuleName, .Goal = resp.output}
            End If
            plan.ModuleName = ModuleName
            Return plan
        End Using
    End Function

    Protected Overrides Async Function GenerateAndRunScriptAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task
        Using llm As LLMClient = _config.CreateLLMClient(_context.TmpDir)
            RegisterTools(llm)

            Dim prompt = $"
You are a bioinformatics R script expert. Write an R script to save the comparison design as a structured CSV file.

{BuildContextInfo()}

# Comparison Design Plan
{plan.ToJson()}

# Your Task
Write an R script that:
1. Creates a data frame containing the comparison design
2. Columns: comparison_name, treatment_group, control_group, biological_rationale, expected_findings
3. Saves the design as CSV to tables/comparison_design.csv
4. Generates a summary visualization showing the comparison structure

Write the complete R script. Use ```r ... ``` code block.
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim rCode = resp.ExtractCodeBlock("r")

            Dim scriptFile = Path.Combine(_context.ScriptsDir, $"module_{ModuleIndex}_comparison_design.R")
            rCode.SaveTo(scriptFile)
            plan.RScriptContent = rCode
            plan.RScriptFile = scriptFile

            Dim shell As New ShellTool(_config, _context.WorkspaceDir, _logger)
            Dim result = shell.run_rscript($"scripts/module_{ModuleIndex}_comparison_design.R", timeout_seconds:=300)
            LogInfo($"R script execution result: {result.Substring(0, Math.Min(300, result.Length))}")
        End Using
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Using llm As LLMClient = _config.CreateLLMClient(_context.TmpDir)
            Dim prompt = $"
You are a biomedical research expert. Based on the comparison group design, write a stage conclusion in Chinese.

{BuildContextInfo()}

# Comparison Design Plan
{plan.ToJson()}

# Your Task
Write a conclusion in Chinese that describes:
1. 差异比对设计的整体思路
2. 每个比对组别的生物学依据
3. 比对设计与用户研究主题的生物学机制相关性
4. 预期能够获得的生物学发现
5. 比对设计的合理性论证（参考 kb.json 中的生物学知识）

The conclusion should be 400-600 words in Chinese. Be specific and rigorous. Do NOT fabricate biological knowledge.
Reference the kb.json knowledge base when explaining biological mechanisms.
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Return resp.output
        End Using
    End Function

End Class
