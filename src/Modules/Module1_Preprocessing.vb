Imports Microsoft.VisualBasic.MIME.application.json
Imports Microsoft.VisualBasic.Serialization.JSON
Imports Ollama
Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 1: 表达矩阵数据预处理
' ============================================================================

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
Public Class PreprocessingModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Expression Matrix Preprocessing"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 1

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(llm As LLMClient, cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Dim prompt = $"
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

Simply generate the specific execution plan here. Do not execute the actual analysis pipeline code. Return your plan as JSON in your response output, at least one execution step for your plan must be generated:
{{
  ""module_name"": ""Expression Matrix Preprocessing"",
  ""goal"": ""<brief description of the preprocessing goal>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""execution_steps"": [{{""action"": ""<description of current step action>"", ""goal"": ""<goal of current step...>""}}, ...],
  ""notes"": ""<any special considerations>""
}}
"
        Return Await GeneratePlanAsync(llm, Await llm.Chat(prompt, cancellationToken), cancellationToken)
    End Function

    Protected Overrides Async Function GenerateAndRunScriptAsync(llm As LLMClient, plan As ModulePlan, [step] As [Step], cancellationToken As CancellationToken) As Task
        Dim prompt = $"
You are a bioinformatics R script expert. Write and execute R script to preprocess the omics expression matrix data according to the following plan.

{BuildContextInfo()}

# Preprocessing Plan
{plan.module_name}

plan goal: {plan.goal}
plan notes: {plan.notes}

# Your Task
Write a complete R script that:

{[step].action}
{[step].goal}

All scripts and the generated CSV files are placed in this designated temporary workspace folder: {Workspace.GetDirectoryFullPath}
All pdf/png figure image files should save to workspace folder: {FiguresDir.GetDirectoryFullPath}

# Important Notes
- Use the source() function to load helper scripts from the rscript/ folder when applicable
- Use ggplot2 for any visualization
- Save all output files using absolute paths
- The script should be self-contained and runnable via Rscript
- Handle both single-omics and multi-omics cases
- Print progress messages to stdout
"
        Await llm.Chat(prompt, cancellationToken)
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(llm As LLMClient, plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Dim prompt = $"
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
    End Function

End Class
