Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama

' ============================================================================
' 模块 2: 总体样本 PCA/PLSDA/OPLSDA 分析
' ============================================================================

''' <summary>
''' 总体样本 PCA/PLSDA/OPLSDA 分析模块。
''' 
''' 分析内容：
''' 1. PCA 主成分分析
''' 2. PLSDA 偏最小二乘判别分析
''' 3. OPLSDA 正交偏最小二乘判别分析
''' 4. 表达矩阵总体 F 检验
''' 5. 表达矩阵总体多因素 ANOVA 检验
''' 
''' 基于 PCA 结果计算各样本到组别质心的加权欧氏距离作为组内离散度，
''' 采用置换检验判断组内距离是否显著小于组间距离，评估数据重复性质量。
''' </summary>
Public Class PCAAnalysisModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "PCA/PLSDA/OPLSDA Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 2

    Public Sub New(config As AgentConfig, context As AnalysisContext, llmFactory As Func(Of LLMClient), Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, llmFactory, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Using llm = _llmFactory()
            RegisterTools(llm)

            Dim prompt = $"
You are a bioinformatics analysis expert. Design a PCA/PLSDA/OPLSDA analysis plan for the omics data.

{BuildContextInfo()}

# Your Task
Design a plan for overall sample analysis including:
1. PCA (Principal Component Analysis) - extract PC1, PC2, PC3 scores
2. PLSDA (Partial Least Squares Discriminant Analysis)
3. OPLSDA (Orthogonal PLS-DA)
4. Overall F-test on expression matrix
5. Multi-factor ANOVA test

For each analysis:
- Calculate sample scores on principal components
- Compute weighted Euclidean distance from each sample to its group centroid (weighted by variance explained)
- Use permutation test to assess if intra-group distance is significantly smaller than inter-group distance
- Generate scatter plots with confidence ellipses, colored by sample group, with different shapes for metadata
- Save score tables as CSV
- Generate stage conclusion text

Return your plan as JSON:
{{
  ""module_name"": ""PCA/PLSDA/OPLSDA Analysis"",
  ""goal"": ""<brief description>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
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
        Using llm = _llmFactory()
            RegisterTools(llm)

            Dim prompt = $"
You are a bioinformatics R script expert. Write an R script to perform PCA/PLSDA/OPLSDA analysis.

{BuildContextInfo()}

# Analysis Plan
{plan.ToJson()}

# Your Task
Write a complete R script that:
1. Reads the preprocessed expression matrix from tmp/ (files starting with 'preprocessed_')
2. Reads the sample info table to get group labels
3. Performs PCA using prcomp or FactoMineR
4. Performs PLSDA using mixOmics
5. Performs OPLSDA using ropls
6. Computes weighted Euclidean distance from each sample to group centroid
7. Performs permutation test (n=1000) for intra-group vs inter-group distance
8. Performs overall F-test and multi-factor ANOVA
9. Generates the following plots (PNG + PDF, 300 dpi, English labels):
   - PCA score scatter plot with confidence ellipses (colored by group, shaped by metadata)
   - PLSDA score plot
   - OPLSDA score plot
   - Scree plot of PCA variance explained
   - Permutation test result plot
10. Saves score tables as CSV in tables/ directory
11. Saves a quality assessment text file

# Plot Requirements
- Use ggplot2 with publication-quality theme
- Use distinct colors for groups (e.g., RColorBrewer or viridis)
- Add confidence ellipses (stat_ellipse)
- Add sample labels
- Save both PNG (300 dpi) and PDF versions
- All text labels in English

# Important Notes
- Use source() to load helper scripts from rscript/ folder when applicable
- Handle missing packages gracefully (install if missing)
- Print progress messages
- Use absolute paths

Write the complete R script. Use ```r ... ``` code block.
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim rCode = resp.ExtractCodeBlock("r")

            Dim scriptFile = Path.Combine(_context.ScriptsDir, $"module_{ModuleIndex}_pca_plsda.R")
            rCode.SaveTo(scriptFile)
            plan.RScriptContent = rCode
            plan.RScriptFile = scriptFile

            Dim shell As New ShellTool(_config, _context.WorkspaceDir, _logger)
            Dim result = shell.run_rscript($"scripts/module_{ModuleIndex}_pca_plsda.R", timeout_seconds:=900)
            LogInfo($"R script execution result: {result.Substring(0, Math.Min(300, result.Length))}")
        End Using
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Using llm = _llmFactory()
            Dim prompt = $"
You are a biomedical research expert. Based on the PCA/PLSDA/OPLSDA analysis results, write a stage conclusion in Chinese.

{BuildContextInfo()}

# Analysis Plan
{plan.ToJson()}

# Your Task
Read the analysis output files in the tables/ and figures/ directories of module 2.
Write a conclusion in Chinese that describes:
1. PCA/PLSDA/OPLSDA 分析的整体结果
2. 各组别在主成分上的分离情况
3. 模型解释率（R2X, R2Y, Q2）
4. 置换检验结果，组内离散度与组间离散度的比较
5. 数据重复性质量评估
6. F 检验和 ANOVA 检验的总体结果
7. 与用户研究主题的生物学关联性说明
8. 若数据质量不佳，给出明确的警告信息

The conclusion should be 400-600 words in Chinese. Be specific and rigorous. Do NOT fabricate data.
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Return resp.output
        End Using
    End Function
End Class
