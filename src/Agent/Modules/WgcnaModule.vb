' ============================================================================
' 模块 5: WGCNA 共表达网络分析
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Models

Namespace Agent.Modules

    ''' <summary>
    ''' WGCNA 加权基因共表达网络分析模块
    ''' </summary>
    Public Class WgcnaModule
        Inherits AnalysisModuleBase

        Public Sub New(index As Integer, config As Config.AppConfig, workspace As IO.WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Utils.Logger,
                       llmClientFactory As Func(Of LLMClient))
            MyBase.New("wgcna", index, config, workspace, input, kbPath, logger, llmClientFactory)
        End Sub

        Protected Overrides Async Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task
            Dim ctx = BuildContext()

            Dim prompt = <string><![CDATA[
You are a bioinformatics analysis agent. This is the WGCNA (Weighted Gene Co-expression Network Analysis) module.

<%= context %>

Your task in this module:

## Step 1: Data preparation
a. Read the normalized expression matrix from tmp/ folder
b. Filter to top variable features (by MAD, top 5000-20000 features based on data size)
c. Check sample quality (use goodSamplesGenes function)
d. Detect and remove outlier samples (optional, based on sample dendrogram)

## Step 2: Network construction
a. Choose soft-thresholding power:
   - Use pickSoftThreshold to find optimal power
   - Target scale-free topology fit R^2 > 0.8
   - Generate soft threshold plot
b. Construct network using blockwiseModules:
   - Use the selected soft threshold
   - Set appropriate minModuleSize (e.g. 30 for genes, 10 for metabolites)
   - Set mergeCutHeight = 0.25
c. Identify modules:
   - Generate module dendrogram and color assignment plot
   - Generate module eigengene (ME) heatmap

## Step 3: Module-trait correlation
a. Use sample metadata as traits (sample_info group, plus any line/time columns)
b. Calculate module-trait correlations:
   - cor(ME, trait) and corresponding p-values
   - Generate module-trait relationship heatmap
c. Identify modules significantly correlated with traits (|cor| > 0.5, p < 0.05)

## Step 4: Hub gene identification
a. For each significant module:
   - Calculate module membership (MM) and gene significance (GS)
   - Identify hub genes (high MM and high GS)
   - Generate MM vs GS scatter plot
b. Save hub gene lists as CSV

## Step 5: Module enrichment analysis
a. For each significant module, perform KEGG enrichment on its member features
b. Use the annotation file for KEGG ID mapping
c. Generate enrichment dot plot per module
d. Save enrichment results as CSV

## Step 6: Network visualization
a. Export network to Cytoscape format (optional)
b. Generate module eigengene network plot
c. Generate gene-gene interaction network for top hub genes

## Step 7: Execute and iterate
- Use run_rscript to execute
- Fix errors and re-run

## Step 8: Write conclusion.txt
- Number of modules identified
- Modules significantly correlated with traits
- Top hub genes per significant module
- Biological functions of significant modules (based on enrichment and knowledge base)
- Relationship to research topic/disease

Guidelines:
- WGCNA can be memory-intensive; for large datasets use blockwise approach
- All plots saved as PNG 300 dpi to figures/ folder
- All tables saved as CSV to tables/ folder
- Use absolute paths
- For Chinese labels, use showtext package

Please proceed step by step.
]]></string>.Value.Replace("<%= context %>", ctx)

            Logger.Info("Sending WGCNA task to LLM...")
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
                result.Scripts.AddRange(Directory.GetFiles(ScriptsDir, "*wgcna*.R").Select(Function(f) Path.GetFileName(f)))
            End If
        End Sub

    End Class

End Namespace
