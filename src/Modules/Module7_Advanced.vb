Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 7: 进阶分析（CMeans 模糊聚类 + bnlearn 动态贝叶斯网络 + PLS-PM 因果路径）
' ============================================================================

''' <summary>
''' 进阶分析模块。
''' 
''' 分析内容：
''' 1. CMeans 模糊聚类对分子表达矩阵数据做聚类分析
''' 2. 对聚类簇中的分子做 KEGG 富集分析
''' 3. 将聚类簇的结果与 WGCNA 的共表达模块做关联分析
''' 4. 时间序列数据：进行 bnlearn 动态贝叶斯网络的构建以及后续分析
''' 5. 多组学数据且样本量足够：按不同的组学层次构建潜变量，进行 PLS-PM 因果路径分析
''' </summary>
Public Class AdvancedAnalysisModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Advanced Analysis (CMeans + Bayesian + PLS-PM)"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 7

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Dim prompt = $"
You are a bioinformatics analysis expert. Design an advanced analysis plan.

{BuildContextInfo()}

# Your Task
Design a plan for advanced analysis including:
1. CMeans fuzzy clustering on the expression matrix
   - Determine optimal cluster number
   - Cluster molecules into fuzzy groups
   - KEGG enrichment for each cluster
   - Compare clusters with WGCNA modules (from module 6)
2. For time-series data with sufficient samples:
   - Build dynamic Bayesian network using bnlearn
   - Identify regulatory relationships between molecules/modules
3. For multi-omics data with sufficient samples:
   - Construct latent variables for each omics layer
   - Perform PLS-PM (Partial Least Squares Path Modeling) causal path analysis

Return your plan as JSON, at least one execution step for your plan must be generated:
{{
  ""module_name"": ""Advanced Analysis"",
  ""goal"": ""<brief description>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""execution_steps"": [{{""action"": ""<description of current step action>"", ""goal"": ""<goal of current step...>""}}, ...],
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
You are a bioinformatics R script expert. Write and execute R script to perform advanced analysis according to the following plan.

{BuildContextInfo()}

# Analysis Plan
{plan.module_name}

plan goal: {plan.goal}
plan notes: {plan.notes}
current plan execution step: {[step].GetJson}

All scripts and the generated CSV files are placed in this designated temporary workspace folder: {Workspace.GetDirectoryFullPath}
All pdf/png figure image files should save to workspace folder: {FiguresDir.GetDirectoryFullPath}

# Your Task
Write a complete R script that:
1. CMeans Fuzzy Clustering:
   - Read preprocessed expression matrix
   - Determine optimal cluster number (e.g., using validation indices)
   - Perform fuzzy c-means clustering using e1071 or Mfuzz
   - KEGG enrichment for each cluster
   - Compare clusters with WGCNA modules (contingency table, Fisher's exact test)
2. Dynamic Bayesian Network (if time-series data):
   - Read expression matrix and time information
   - Build dynamic Bayesian network using bnlearn
   - Identify regulatory edges
   - Plot network graph
3. PLS-PM (if multi-omics with sufficient samples):
   - Construct latent variables for each omics layer
   - Build path model
   - Estimate path coefficients
   - Plot path diagram

# Plot Requirements
- Use Mfuzz/e1071, bnlearn, plspm, igraph, ggplot2
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Use the source() function to load helper scripts from the rscript/ folder when applicable
- Handle missing packages gracefully
- Save all output files using absolute paths
- The script should be self-contained and runnable via Rscript
- Print progress messages to stdout
- Skip analyses that don't apply (e.g., skip bnlearn if not time-series)
"
        Await llm.Chat(prompt, cancellationToken)
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Dim prompt = $"
You are a biomedical research expert. Based on the advanced analysis results, write a stage conclusion in Chinese.

{BuildContextInfo()}

# Analysis Plan
{plan.ToJson()}

# Your Task
Read the advanced analysis output files in the tables/ and figures/ directories of module 7.
Write a conclusion in Chinese that describes:
1. CMeans 模糊聚类的整体结果（聚类数量、各簇的分子数量、关键簇的生物学功能）
2. 聚类簇与 WGCNA 模块的关联分析结果
3. 动态贝叶斯网络分析结果（若适用，关键调控关系）
4. PLS-PM 因果路径分析结果（若适用，组学层次间的因果路径）
5. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
6. 与前面模块分析结果的一致性和补充性

The conclusion should be 500-800 words in Chinese. Be specific and rigorous. Do NOT fabricate biological knowledge.
Reference the kb.json knowledge base when explaining biological mechanisms.
"
        Dim resp = Await llm.Chat(prompt, cancellationToken)
        Return resp.output
    End Function
End Class
