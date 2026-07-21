' ============================================================================
' 模块 3: 差异比较设计 + LIMMA 差异分析
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Models

Namespace Agent.Modules

    ''' <summary>
    ''' 差异分析模块：基于 LIMMA 进行差异分子分析
    ''' </summary>
    Public Class DifferentialModule
        Inherits AnalysisModuleBase

        Public Sub New(index As Integer, config As Config.AppConfig, workspace As IO.WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Utils.Logger,
                       llmClientFactory As Func(Of LLMClient))
            MyBase.New("differential", index, config, workspace, input, kbPath, logger, llmClientFactory)
        End Sub

        Protected Overrides Async Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task
            Dim ctx = BuildContext()

            Dim prompt = <string><![CDATA[
You are a bioinformatics analysis agent. This is the DIFFERENTIAL ANALYSIS module (LIMMA-based).

<%= context %>

Your task in this module:

## Step 1: Design comparison groups
Based on the research topic and sample_info column, design biologically meaningful comparison groups:
- Identify the main control vs treatment comparisons
- For time-series data, design pairwise comparisons between time points
- For multi-group data, design all relevant pairwise comparisons
- Document the biological rationale for each comparison

## Step 2: Write R script for LIMMA differential analysis
For each comparison:
a. Load the normalized expression matrix and sample info
b. Construct the design matrix using model.matrix
c. For RNA-seq data: use limma::voom + lmFit + eBayes (or edgeR/DESeq2 if appropriate)
   For proteomics/metabolomics: use limma::lmFit + eBayes directly
d. Define contrasts using makeContrasts
e. Extract differential results with topTable
f. Apply thresholds:
   - p-value < 0.05 (adjusted)
   - |log2FC| > 1 for RNA-seq, |log2FC| > 0.585 for proteomics/metabolomics
   - VIP > 1.0 (if available from previous module)
g. Generate plots:
   - Volcano plot (log2FC vs -log10 p-value), with up/down/non-significant colored differently
   - MA plot
   - Heatmap of top differential features (top 50 by p-value)
   - Venn diagram of overlapping differential features across comparisons
h. Save results:
   - Full differential table as CSV in tables/ folder
   - Filtered significant features as CSV in tables/ folder
   - All plots as PNG 300 dpi in figures/ folder

## Step 3: Execute and iterate
- Use run_rscript to execute
- If errors occur, read error, fix script, re-run

## Step 4: Write conclusion.txt
- Number of up/down regulated features per comparison
- Top 20 most significant features per comparison
- Overlap between comparisons
- Biological interpretation based on knowledge base (refer to kb.json)
- Potential biomarkers identified

Guidelines:
- Use absolute paths for all file outputs
- For Chinese labels in figures, use showtext package
- Save R script to scripts/ folder with name like "differential_analysis.R"
- For multi-omics data, perform analysis per omics type

Please proceed step by step.
]]></string>.Value.Replace("<%= context %>", ctx)

            Logger.Info("Sending differential analysis task to LLM...")
            Dim resp = Await llm.Chat(prompt)
            result.ConclusionText = resp.output
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
                result.Scripts.AddRange(Directory.GetFiles(ScriptsDir, "*differential*.R").Select(Function(f) Path.GetFileName(f)))
            End If
        End Sub

    End Class

End Namespace
