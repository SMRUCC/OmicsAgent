' ============================================================================
' 模块 4: KEGG 通路富集分析与 GSVA
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Models

Namespace Agent.Modules

    ''' <summary>
    ''' KEGG 通路富集分析与 GSVA 模块
    ''' </summary>
    Public Class KeggEnrichmentModule
        Inherits AnalysisModuleBase

        Public Sub New(index As Integer, config As Config.AppConfig, workspace As IO.WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Utils.Logger,
                       llmClientFactory As Func(Of LLMClient))
            MyBase.New("kegg_enrichment", index, config, workspace, input, kbPath, logger, llmClientFactory)
        End Sub

        Protected Overrides Async Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task
            Dim ctx = BuildContext()

            Dim prompt = <string><![CDATA[
You are a bioinformatics analysis agent. This is the KEGG PATHWAY ENRICHMENT AND GSVA module.

<%= context %>

Your task in this module:

## Step 1: Read annotation file
Read the annotation CSV file to get molecule-to-KEGG ID mappings. The annotation file has columns:
- id: molecule ID (matching expression matrix first column)
- type: molecule type (rna/protein/metabolite/lipid)
- name: molecule name
- class or category: molecule classification
- kegg: KEGG ID

## Step 2: KEGG Over-Representation Analysis (ORA)
For each comparison's significant differential features:
a. Use clusterProfiler::enrichKEGG (for genes/proteins) or MetaboAnalystR (for metabolites)
b. Parameters:
   - organism: based on research topic species
   - pvalueCutoff = 0.05
   - qvalueCutoff = 0.1
c. Generate plots:
   - Dot plot of enriched pathways (top 20)
   - Bar plot of enriched pathways
   - Ridge plot showing fold enrichment
d. Save enrichment results as CSV in tables/ folder

## Step 3: Gene Set Enrichment Analysis (GSEA)
a. Use clusterProfiler::GSEA with ranked list (by log2FC * -log10(pvalue))
b. Generate:
   - GSEA dot plot
   - Running score plot for top 5 pathways
   - GSEA results table as CSV

## Step 4: GSVA (Gene Set Variation Analysis)
a. Use GSVA::gsva to compute pathway activity scores per sample
b. Use the annotation file to define gene sets (group by class/category or use KEGG pathways)
c. Generate:
   - Heatmap of pathway activity scores (samples x pathways)
   - Boxplot comparing pathway scores between groups
   - Limma analysis on GSVA scores to find differential pathways
   - Save GSVA score matrix as CSV

## Step 5: Pathway network visualization
a. Use enrichplot::cnetplot or emapplot to show pathway-gene networks
b. Save as PNG in figures/ folder

## Step 6: Execute and iterate
- Use run_rscript to execute
- Fix errors and re-run as needed

## Step 7: Write conclusion.txt
- Top enriched pathways per comparison
- Pathways consistently enriched across comparisons
- Differential pathways from GSVA analysis
- Biological interpretation based on knowledge base
- Key pathways related to the research topic/disease

Guidelines:
- For metabolomics, use MetaboAnalystR or manual hypergeometric test
- All plots saved as PNG 300 dpi
- All tables saved as CSV
- Use absolute paths
- For Chinese labels, use showtext package

Please proceed step by step.
]]></string>.Value.Replace("<%= context %>", ctx)

            Logger.Info("Sending KEGG enrichment task to LLM...")
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
                result.Scripts.AddRange(Directory.GetFiles(ScriptsDir, "*kegg*.R").Select(Function(f) Path.GetFileName(f)))
            End If
        End Sub

    End Class

End Namespace
