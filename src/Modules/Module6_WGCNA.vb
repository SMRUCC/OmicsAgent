Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 6: 生物学性状关联分析（WGCNA）
' ============================================================================

''' <summary>
''' 生物学性状关联分析模块（WGCNA）。
''' 
''' 分析内容：
''' 1. 默认按 MAD 值降序排序取 top 20000 个分子做 WGCNA 分析
''' 2. 根据用户研究主题和样本分组信息、元数据信息构建 WGCNA 的生物表型关联性状数据
''' 3. 多组学数据：可将下游组学数据的 GSVA 分析结果作为表型数据，
'''    与上游组学数据的分子表达数据做关联分析
''' 4. 共表达模块与生物学性状值的线性回归分析
''' 5. 共表达模块分子的 KEGG 功能富集分析
''' </summary>
Public Class WGCNAModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "WGCNA Trait Association Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 6

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Dim prompt = $"
You are a bioinformatics analysis expert. Design a WGCNA trait association analysis plan.

{BuildContextInfo()}

# Your Task
Design a plan for WGCNA analysis including:
1. Select top 20000 molecules by MAD (Median Absolute Deviation) descending
2. Construct WGCNA co-expression network
   - Determine soft threshold power
   - Build network and identify modules
   - Calculate module eigengenes
3. Build biological trait data:
   - Use sample metadata (group, line, time, etc.) as traits
   - For multi-omics: use downstream omics GSVA scores as traits for upstream omics
4. Correlate modules with biological traits
5. Linear regression analysis of modules vs trait values
6. KEGG enrichment analysis of module molecules

Return your plan as JSON:
{{
  ""module_name"": ""WGCNA Trait Association Analysis"",
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
You are a bioinformatics R script expert. Write and execute R script to perform WGCNA analysis according to the following plan.

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
1. Reads preprocessed expression matrix from tmp/
2. Selects top 20000 molecules by MAD descending (or all if fewer)
3. Determines soft threshold power using pickSoftThreshold
4. Builds WGCNA network:
   - Block-wise network construction
   - Module identification
   - Module eigengene calculation
5. Builds trait data from sample metadata:
   - Numeric encoding of group, line, time columns
   - For multi-omics: load GSVA scores from module 5 as traits
6. Correlates module eigengenes with traits (Pearson correlation + pvalue)
7. Performs linear regression of modules vs significant traits
8. Performs KEGG enrichment for each module's molecules
9. Generates the following plots (PNG + PDF, 300 dpi, English labels):
   - Soft threshold power selection plot
   - Module dendrogram (cluster tree)
   - Module-trait correlation heatmap
   - Module eigengene bar plot
   - Hub gene network visualization (for top modules)
   - KEGG enrichment dot plot for each significant module
10. Saves module results, module-trait correlations, KEGG enrichment as CSV

# Plot Requirements
- Use WGCNA, ggplot2, ComplexHeatmap, clusterProfiler
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Use the source() function to load helper scripts from the rscript/ folder when applicable
- Handle missing packages gracefully
- Save all output files using absolute paths
- The script should be self-contained and runnable via Rscript
- Print progress messages to stdout
- WGCNA can be memory-intensive, use blocks if needed
"
        Await llm.Chat(prompt, cancellationToken)
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Dim prompt = $"
You are a biomedical research expert. Based on the WGCNA analysis results, write a stage conclusion in Chinese.

{BuildContextInfo()}

# Analysis Plan
{plan.ToJson()}

# Your Task
Read the WGCNA analysis output files in the tables/ and figures/ directories of module 6.
Write a conclusion in Chinese that describes:
1. WGCNA 网络构建的整体情况（soft threshold power、模块数量、模块大小分布）
2. 模块与生物学性状的关联分析结果（哪些模块与哪些性状显著相关）
3. 关键模块的生物学功能（KEGG 富集结果，参考 kb.json 知识库）
4. Hub 基因/分子的识别
5. 多组学关联分析结果（若适用）
6. 共表达模块与生物学性状的线性回归分析结果
7. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关

The conclusion should be 500-800 words in Chinese. Be specific and rigorous. Do NOT fabricate biological knowledge.
Reference the kb.json knowledge base when explaining biological mechanisms.
"
        Dim resp = Await llm.Chat(prompt, cancellationToken)
        Return resp.output
    End Function
End Class
