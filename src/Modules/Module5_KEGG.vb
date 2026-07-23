Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 5: KEGG 生物学功能分析（富集 + GSVA）
' ============================================================================

''' <summary>
''' KEGG 生物学功能分析模块。
''' 
''' 分析内容：
''' 1. 基于差异分析结果，使用 kegg id 进行富集分析
''' 2. GSVA 分析，并按相同组别设计进行差异分析
''' 3. 富集结果条形图（按 KEGG 大分类分组）
''' 4. GSVA 总体热图（列=样本按分组排序，行=KEGG 通路按大分类分组+层次聚类+聚类树）
''' 5. GSVA 差异分析火山图、得分图
''' </summary>
Public Class KeggFunctionModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "KEGG Functional Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 5

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Dim prompt = $"
You are a bioinformatics analysis expert. Design a KEGG functional analysis plan.

{BuildContextInfo()}

# Your Task
Design a plan for KEGG functional analysis including:
1. KEGG pathway enrichment analysis using differential molecules (from module 4)
   - Use KEGG background XML/JSON files in the data/ directory
   - Use clusterProfiler or similar packages
2. GSVA (Gene Set Variation Analysis) on the expression matrix
   - Use KEGG pathways as gene sets
   - Apply the same comparison design as differential analysis
3. Visualization:
   - Enrichment bar plot grouped by KEGG category
   - GSVA heatmap (columns = samples sorted by group, rows = KEGG pathways grouped by category with hierarchical clustering and dendrogram)
   - GSVA differential analysis volcano plot and score plot

Return your plan as JSON:
{{
  ""module_name"": ""KEGG Functional Analysis"",
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
You are a bioinformatics R script expert. Write and execute R script to perform KEGG functional analysis according to the following plan.

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
1. Reads differential analysis results from module 4 (tables/ directory)
2. Reads KEGG background data from data/ directory (XML or JSON files)
3. Performs KEGG pathway enrichment analysis using clusterProfiler
4. Performs GSVA analysis using GSVA package
5. Performs differential analysis on GSVA scores using limma (same comparison design)
6. Generates the following plots (PNG + PDF, 300 dpi, English labels):
   - Enrichment bar plot:
     * Bar plot of enriched pathways
     * Grouped by KEGG large category (Metabolism, Genetic Information Processing, etc.)
     * Color by category, size by gene count
   - GSVA heatmap:
     * Columns = samples, sorted by sample group
     * Rows = KEGG pathways
     * Group rows by KEGG large category
     * Hierarchical clustering within each category
     * Draw dendrogram on the left side for each category
   - GSVA differential volcano plot
   - GSVA score plot for top differential pathways
7. Saves enrichment and GSVA result tables as CSV

# Plot Requirements
- Use ggplot2, ComplexHeatmap, clusterProfiler, GSVA
- Publication-quality theme
- All text labels in English
- Save both PNG (300 dpi) and PDF versions

# Important Notes
- Use the source() function to load helper scripts from the rscript/ folder when applicable
- Handle missing packages gracefully
- Save all output files using absolute paths
- The script should be self-contained and runnable via Rscript
- Print progress messages to stdout
"
        Await llm.Chat(prompt, cancellationToken)
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Dim prompt = $"
You are a biomedical research expert. Based on the KEGG functional analysis results, write a stage conclusion in Chinese.

{BuildContextInfo()}

# Analysis Plan
{plan.ToJson()}

# Your Task
Read the KEGG analysis output files in the tables/ and figures/ directories of module 5.
Write a conclusion in Chinese that describes:
1. KEGG 富集分析的整体结果（显著富集的通路数量、分类分布）
2. 关键富集通路的生物学意义（参考 kb.json 知识库）
3. GSVA 分析结果（通路得分在不同组别间的差异）
4. GSVA 差异分析结果（差异显著的通路）
5. 通路得分热图所展示的样本聚类模式
6. 生物学通路分析结果如何支持用户的研究主题
7. 与差异分析结果的关联性

The conclusion should be 500-800 words in Chinese. Be specific and rigorous. Do NOT fabricate biological knowledge.
Reference the kb.json knowledge base when explaining biological mechanisms.
"
        Dim resp = Await llm.Chat(prompt, cancellationToken)
        Return resp.output
    End Function

End Class
