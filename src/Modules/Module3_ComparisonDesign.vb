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

    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
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

Return your plan as JSON, at least one execution step for your plan must be generated:
{{
  ""module_name"": ""Comparison Group Design"",
  ""goal"": ""<brief description of comparison design rationale>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""execution_steps"": [{{""action"": ""<description of current step action>"", ""goal"": ""<goal of current step...>""}}, ...],
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
            plan.module_name = ModuleName
        Else
            plan = New ModulePlan() With {.module_name = ModuleName, .goal = resp.output}
        End If

        Return plan
    End Function

    Protected Overrides Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        Dim prompt = $"
You are a bioinformatics R script expert. Write and execute R script to save the comparison design as a structured CSV file according to the following plan.

{BuildContextInfo()}

# Comparison Design Plan
{plan.module_name}

plan goal: {plan.goal}
plan notes: {plan.notes}
current plan execution step: {[step].GetJson}

All scripts and the generated CSV files are placed in this designated temporary workspace folder: {Workspace.GetDirectoryFullPath}
All pdf/png figure image files should save to workspace folder: {FiguresDir.GetDirectoryFullPath}

# Your Task
Write a complete R script that:
1. Creates a data frame containing the comparison design
2. Columns: comparison_name, treatment_group, control_group, biological_rationale, expected_findings
3. Saves the design as CSV to tables/comparison_design.csv
4. Generates a summary visualization showing the comparison structure

# Important Notes
- Use the source() function to load helper scripts from the rscript/ folder when applicable
- Save all output files using absolute paths
- The script should be self-contained and runnable via Rscript
- Print progress messages to stdout
"
        Await llm.Chat(prompt, cancellationToken)
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
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
    End Function

End Class
