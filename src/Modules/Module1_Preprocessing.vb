' ============================================================================
' 模块 1: 表达矩阵数据预处理
' ============================================================================
Imports System.IO
Imports System.Text
Imports System.Threading
Imports System.Threading.Tasks

''' <summary>
''' 表达矩阵数据预处理模块。
''' 
''' 预处理流程：
''' 1. 按行做分子表达数据最小阳性值的一半做缺失值填充
''' 2. 按列总和归一化转化为相对表达量
''' 3. 如有必要，针对归一化后的值做 log 转换
''' 4. 按行做中位数缩放
''' 
''' 除非用户在 research 文件中明确标注某个表达矩阵不需要预处理，否则默认执行。
''' </summary>
Public Class PreprocessingModule
    Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Expression Matrix Preprocessing"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 1

    Public Sub New(config As AgentConfig, context As AnalysisContext, llmFactory As Func(Of LLMClient), Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, llmFactory, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Using llm = _llmFactory()
            RegisterTools(llm)

            Dim prompt = $@"
You are a bioinformatics analysis expert. Your task is to design a preprocessing plan for omics expression matrix data.

{BuildContextInfo()}

# Your Task
Design a preprocessing plan for the expression matrix data. The standard preprocessing workflow is:
1. Fill missing values with half of the minimum positive value per molecule (row)
2. Normalize by column sum to convert to relative expression
3. Apply log transformation if necessary (when max value > 100, indicating non-log scale)
4. Median scaling per row (molecule)

# Important Notes
- Check the research topic for any user-specified preprocessing exceptions
- For multi-omics data, each omics dataset should be preprocessed separately
- The preprocessed matrix should be saved as CSV in the tmp/ directory
- Use the R scripts in the rscript/ folder as reference; source them when applicable

Return your plan as JSON:
{{
  ""module_name"": ""Expression Matrix Preprocessing"",
  ""goal"": ""<brief description of the preprocessing goal>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""notes"": ""<any special considerations>""
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
You are a bioinformatics R script expert. Write an R script to preprocess the omics expression matrix data according to the following plan.

{BuildContextInfo()}

# Preprocessing Plan
{plan.ToJson()}

# Your Task
Write a complete R script that:
1. Reads each expression matrix CSV file (rows = molecules, columns = samples, first column = molecule ID, first row = sample IDs)
2. For each matrix:
   a. Replace NA/0 values with half of the minimum positive value in each row
   b. Normalize by column sum (divide each value by column sum, multiply by 1e6 for readability)
   c. Apply log2 transformation if max value > 100
   d. Median scale per row (subtract row median)
3. Save preprocessed matrices to the tmp/ directory with prefix 'preprocessed_'
4. Generate a summary statistics table (before/after: number of molecules, samples, NA count, value range)

# Important Notes
- Use the source() function to load helper scripts from the rscript/ folder when applicable
- Use ggplot2 for any visualization
- Save all output files using absolute paths
- The script should be self-contained and runnable via Rscript
- Handle both single-omics and multi-omics cases
- Print progress messages to stdout

Write the complete R script. Use ```r ... ``` code block.
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim rCode = ExtractCodeBlock(resp.output, "r")

            ' 保存脚本
            Dim scriptFile = Path.Combine(_context.ScriptsDir, $"module_{ModuleIndex}_preprocessing.R")
            PathUtils.WriteAllText(scriptFile, rCode)
            plan.RScriptContent = rCode
            plan.RScriptFile = scriptFile

            ' 执行脚本
            Dim shell As New ShellTool(_config, _context.WorkspaceDir, _logger)
            Dim result = shell.run_rscript($"scripts/module_{ModuleIndex}_preprocessing.R", timeout_seconds:=600)
            LogInfo($"R script execution result: {result.Substring(0, Math.Min(300, result.Length))}")
        End Using
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Using llm = _llmFactory()
            Dim prompt = $@"
You are a biomedical research expert. Based on the preprocessing analysis results, write a stage conclusion in Chinese.

{BuildContextInfo()}

# Preprocessing Plan
{plan.ToJson()}

# Your Task
Read the preprocessing output files in the tmp/ directory (files starting with 'preprocessed_') and the tables/ directory of module 1.
Write a conclusion in Chinese that describes:
1. 数据预处理的整体情况（每个组学数据集的样本数、分子数）
2. 缺失值填充、归一化、log转换、中位数缩放的具体参数和结果
3. 预处理前后数据分布的变化
4. 数据质量评估
5. 与用户研究主题的关联性说明

The conclusion should be 300-500 words in Chinese. Be specific and rigorous. Do NOT fabricate data.
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
