Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 4: LIMMA 差异比较分析
' ============================================================================

''' <summary>
''' LIMMA 差异比较分析模块。
''' 
''' 分析内容：
''' 1. 多因素 ANOVA 检验
''' 2. limma 总体 F 检验
''' 3. limma 两两比较差异分析
''' 4. 时间序列数据：将时间因素作为协变量，消除时间因素做差异分析
''' 5. 火山图（显示 top5 差异分子名称）
''' 6. 文氏图（不同比较间的差异内容）
''' 7. 差异分子热图（列按样本分组排序，行做层次聚类，颜色块标记分子分类）
''' 
''' 默认按 pvalue &lt; 0.05 判断显著差异，代谢组数据增加 VIP > 1 条件。
''' 默认不考虑 logFC 阈值过滤，按 pvalue 和 VIP 筛选后，对剩余分子按 |logFC| 降序排序，
''' 取一定数量的 top 分子做差异分析结果。
''' </summary>
Public Class LimmaDiffModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "LIMMA Differential Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 4

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Dim prompt = $"
You are a bioinformatics analysis expert. Design a LIMMA differential analysis plan.

{BuildContextInfo()}

# Your Task
Design a plan for LIMMA differential analysis including:
1. Multi-factor ANOVA test on expression matrix
2. Overall F-test using limma
3. Pairwise comparisons using limma (based on comparison design from module 3)
4. For time-series data: include time as covariate, perform differential analysis with time effect removed
5. For metabolomics data: include VIP value calculation (VIP > {_config.Analysis.MetaboliteVipCutoff} threshold)
6. Default thresholds: pvalue < 0.05, no logFC cutoff, take top {_config.Analysis.DiffTopCount} molecules by |logFC| descending

Return your plan as JSON, at least one execution step for your plan must be generated:
{{
  ""module_name"": ""LIMMA Differential Analysis"",
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
You are a bioinformatics R script expert. Write and execute R script to perform LIMMA differential analysis according to the following plan.

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
1. Reads preprocessed expression matrix from tmp/ (files starting with 'preprocessed_')
2. Reads sample info table and comparison design from tables/comparison_design.csv
3. Performs multi-factor ANOVA test
4. Performs overall F-test using limma
5. Performs pairwise limma comparisons for each comparison in the design
6. For time-series data: include time as covariate in the design matrix
7. For metabolomics data: calculate VIP values using mixOmics (must apply VIP > {_config.Analysis.MetaboliteVipCutoff} filter)
8. Applies thresholds: pvalue < 0.05, VIP > {_config.Analysis.MetaboliteVipCutoff} (for metabolomics), no logFC cutoff
9. Takes top {_config.Analysis.DiffTopCount} molecules by |logFC| descending after pvalue/VIP filtering
10. Generates the following plots (PNG + PDF, 300 dpi, English labels):
    - Volcano plots for each comparison (show top 5 differential molecule names)
    - Venn diagrams showing overlap of differential molecules across comparisons
    - Heatmaps of differential molecules:
      * Columns = samples, sorted by sample group
      * Rows = molecules, hierarchical clustering
      * Color blocks annotating molecule categories (from annotation table 'class' or 'category' column)
      * Display molecule names and sample names
11. Saves differential result tables as CSV in tables/ directory

# Plot Requirements
- Use ggplot2, ggvenn, pheatmap/ComplexHeatmap
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
You are a biomedical research expert. Based on the LIMMA differential analysis results, write a stage conclusion in Chinese.

{BuildContextInfo()}

# Analysis Plan
{plan.ToJson()}

# Your Task
Read the differential analysis output files in the tables/ and figures/ directories of module 4.
Write a conclusion in Chinese that describes:
1. 差异分析的整体结果（每个比较组的差异分子数量：上调、下调、总数）
2. 不同比较组之间差异分子的重叠情况（文氏图结果）
3. 关键差异分子的生物学功能（参考 kb.json 知识库和分子注释表）
4. 差异分子热图所展示的样本聚类模式
5. 差异分析结果与用户研究主题的生物学机制关联性
6. 不同比较组之间的规律性发现
7. 时间序列数据中时间效应的影响

The conclusion should be 500-800 words in Chinese. Be specific and rigorous. Do NOT fabricate biological knowledge.
Reference the kb.json knowledge base when explaining biological mechanisms.
"
        Dim resp = Await llm.Chat(prompt, cancellationToken)
        Return resp.output
    End Function
End Class
