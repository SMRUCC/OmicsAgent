' ============================================================================
' 模块 4: LIMMA 差异比较分析
' ============================================================================
Imports System.IO
Imports System.Text
Imports System.Threading
Imports System.Threading.Tasks

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
''' 默认按 pvalue < 0.05 判断显著差异，代谢组数据增加 VIP > 1 条件。
''' 默认不考虑 logFC 阈值过滤，按 pvalue 和 VIP 筛选后，对剩余分子按 |logFC| 降序排序，
''' 取一定数量的 top 分子做差异分析结果。
''' </summary>
Public Class LimmaDiffModule
    Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "LIMMA Differential Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 4

    Public Sub New(config As AgentConfig, context As AnalysisContext, llmFactory As Func(Of LLMClient), Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, llmFactory, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Using llm = _llmFactory()
            RegisterTools(llm)

            Dim prompt = $@"
You are a bioinformatics analysis expert. Design a LIMMA differential analysis plan.

{BuildContextInfo()}

# Your Task
Design a plan for LIMMA differential analysis including:
1. Multi-factor ANOVA test on expression matrix
2. Overall F-test using limma
3. Pairwise comparisons using limma (based on comparison design from module 3)
4. For time-series data: include time as covariate, perform differential analysis with time effect removed
5. For metabolomics data: include VIP value calculation (VIP > 1 threshold)
6. Default thresholds: pvalue < 0.05, no logFC cutoff, take top N molecules by |logFC| descending

Return your plan as JSON:
{{
  ""module_name"": ""LIMMA Differential Analysis"",
  ""goal"": ""<brief description>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""notes"": ""<special considerations>""
}}
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = ExtractJsonFromResponse(resp.output)
            Dim plan As ModulePlan
            If Not String.IsNullOrEmpty(json) Then
                plan = Newtonsoft.Json.JsonConvert.DeserializeObject(Of ModulePlan)(json)
            Else
                plan = New ModulePlan() With {.ModuleName = ModuleName, .Goal = resp.output}
            End If
            plan.ModuleName = ModuleName
            Return plan
        End Using
    End Function

    Protected Overrides Async Function GenerateAndRunScriptAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task
        Using llm = _llmFactory()
            RegisterTools(llm)

            Dim prompt = $@"
You are a bioinformatics R script expert. Write an R script to perform LIMMA differential analysis.

{BuildContextInfo()}

# Analysis Plan
{plan.ToJson()}

# Your Task
Write a complete R script that:
1. Reads preprocessed expression matrix from tmp/ (files starting with 'preprocessed_')
2. Reads sample info table and comparison design from tables/comparison_design.csv
3. Performs multi-factor ANOVA test
4. Performs overall F-test using limma
5. Performs pairwise limma comparisons for each comparison in the design
6. For time-series data: include time as covariate in the design matrix
7. For metabolomics data: calculate VIP values using mixOmics
8. Applies thresholds: pvalue < 0.05, VIP > 1 (for metabolomics), no logFC cutoff
9. Takes top N molecules by |logFC| descending after pvalue/VIP filtering
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
- Use source() to load helper scripts from rscript/ folder when applicable
- Handle missing packages gracefully
- Print progress messages
- Use absolute paths

Write the complete R script. Use ```r ... ``` code block.
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim rCode = ExtractCodeBlock(resp.output, "r")

            Dim scriptFile = Path.Combine(_context.ScriptsDir, $"module_{ModuleIndex}_limma.R")
            PathUtils.WriteAllText(scriptFile, rCode)
            plan.RScriptContent = rCode
            plan.RScriptFile = scriptFile

            Dim shell As New ShellTool(_config, _context.WorkspaceDir, _logger)
            Dim result = shell.run_rscript($"scripts/module_{ModuleIndex}_limma.R", timeout_seconds:=1200)
            LogInfo($"R script execution result: {result.Substring(0, Math.Min(300, result.Length))}")
        End Using
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Using llm = _llmFactory()
            Dim prompt = $@"
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
        End Using
    End Function

    Private Function ExtractJsonFromResponse(text As String) As String
        If String.IsNullOrEmpty(text) Then Return ""
        Dim match = System.Text.RegularExpressions.Regex.Match(text, "```(?:json)?\s*([\s\S]*?)```")
        If match.Success Then Return match.Groups(1).Value.Trim()
        Dim startIdx = text.IndexOf("{"c)
        Dim endIdx = text.LastIndexOf("}"c)
        If startIdx >= 0 AndAlso endIdx > startIdx Then Return text.Substring(startIdx, endIdx - startIdx + 1)
        Return ""
    End Function

End Class
