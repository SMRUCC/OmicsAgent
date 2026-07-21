' ============================================================================
' 模块 1: 数据预处理
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Models

Namespace Agent.Modules

    ''' <summary>
    ''' 数据预处理模块：缺失值处理、归一化、对数转换、质量控制
    ''' </summary>
    Public Class PreprocessingModule
        Inherits AnalysisModuleBase

        Public Sub New(index As Integer, config As Config.AppConfig, workspace As IO.WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Utils.Logger,
                       llmClientFactory As Func(Of LLMClient))
            MyBase.New("preprocessing", index, config, workspace, input, kbPath, logger, llmClientFactory)
        End Sub

        Protected Overrides Async Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task
            Dim ctx = BuildContext()

            Dim prompt = <string><![CDATA[
You are a bioinformatics analysis agent. This is the DATA PREPROCESSING module of an omics data analysis pipeline.

<%= context %>

Your task in this module:
1. Read the expression matrix CSV file(s) and sample info CSV file(s) to understand the data structure.
2. Write an R script to perform data preprocessing:
   a. Load the expression matrix and sample info
   b. Check data quality: missing values, zero variance features, outliers
   c. Handle missing values (KNN imputation for proteomics/metabolomics; min value for RNA-seq)
   d. Apply appropriate normalization:
      - RNA-seq: use edgeR TMM or DESeq2 size factor normalization, then log2 transform
      - Proteomics/metabolomics: Pareto scaling or auto scaling
   e. Generate QC plots: 
      - Boxplot of expression distribution per sample (before/after normalization)
      - PCA plot of samples colored by group
      - Density plot of expression values
      - Sample correlation heatmap
   f. Save the cleaned/normalized expression matrix to the tmp/ folder as CSV
   g. Save all plots to the figures/ folder as PNG (300 dpi)
3. Execute the R script using run_rscript.
4. If errors occur, read the error message, fix the R script, and re-run.
5. After successful execution, write a conclusion.txt summary describing:
   - Data quality issues found
   - Normalization method applied
   - Number of features/samples before and after filtering
   - Key observations from QC plots

Important guidelines:
- Use the read_file tool to inspect CSV headers before writing R code
- Use write_rscript to save your R script to the scripts/ folder
- Use run_rscript to execute
- All output files must use absolute paths
- For Chinese figure labels, use the showtext R package or English labels
- Save the normalized matrix as: <tmp_dir>/normalized_<dataset_name>.csv

Please proceed step by step.
]]></string>.Value.Replace("<%= context %>", ctx)

            Logger.Info("Sending preprocessing task to LLM...")
            Dim resp = Await llm.Chat(prompt)
            result.ConclusionText = resp.output

            ' 收集生成的脚本和输出文件
            CollectOutputs(result)
        End Function

        Private Sub CollectOutputs(result As ModuleResult)
            If Directory.Exists(TablesDir) Then
                result.Tables.AddRange(Directory.GetFiles(TablesDir, "*.csv").Select(Function(f) Path.GetFileName(f)))
            End If
            If Directory.Exists(FiguresDir) Then
                result.Figures.AddRange(Directory.GetFiles(FiguresDir, "*.png").Select(Function(f) Path.GetFileName(f)))
            End If
            If Directory.Exists(ScriptsDir) Then
                result.Scripts.AddRange(Directory.GetFiles(ScriptsDir, "*preprocessing*.R").Select(Function(f) Path.GetFileName(f)))
            End If
        End Sub

    End Class

End Namespace
