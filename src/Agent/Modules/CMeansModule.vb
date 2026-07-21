' ============================================================================
' 模块 6: CMeans 软聚类分析
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Models

Namespace Agent.Modules

    ''' <summary>
    ''' CMeans 模糊聚类分析模块（用于时间序列表达模式分析）
    ''' </summary>
    Public Class CMeansModule
        Inherits AnalysisModuleBase

        Public Sub New(index As Integer, config As Config.AppConfig, workspace As IO.WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Utils.Logger,
                       llmClientFactory As Func(Of LLMClient))
            MyBase.New("cmeans", index, config, workspace, input, kbPath, logger, llmClientFactory)
        End Sub

        Protected Overrides Async Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task
            Dim ctx = BuildContext()

            Dim prompt = <string><![CDATA[
You are a bioinformatics analysis agent. This is the CMEANS (Fuzzy C-Means Clustering) module for time-series expression pattern analysis.

<%= context %>

Your task in this module:

## Step 1: Check time-series design
Read the sample info CSV to identify:
- Whether the data has time-series design (look for "time" column or sequential groups)
- If not time-series, this module can still cluster features by expression pattern across groups
- Define the time/group ordering for clustering

## Step 2: Data preparation
a. Read the normalized expression matrix from tmp/ folder
b. Select features for clustering:
   - Use differential features from previous modules if available
   - Otherwise use top variable features (top 2000-5000 by MAD)
c. Standardize each feature (z-score across time points/groups)
d. Compute mean expression per time point/group per feature

## Step 3: CMeans clustering
a. Use Mfuzz::cmeans or e1071::cmeans
b. Determine optimal cluster number:
   - Try k = 4 to 12 clusters
   - Use within-cluster sum of squares or silhouette to choose optimal k
   - Generate elbow/silhouette plot
c. Perform clustering with optimal k
d. Set fuzzifier (m) parameter:
   - m = 1.25 typically for Mfuzz
   - Or compute based on number of features

## Step 4: Cluster visualization
a. Generate membership-weighted expression profile plots for each cluster
b. Use Mfuzz::mfuzz.plot2 for nice visualization
c. Color features by membership value
d. Save each cluster plot as separate PNG

## Step 5: Cluster characterization
a. For each cluster:
   - List all features with membership > 0.5 (core members)
   - Perform KEGG enrichment on cluster members
   - Identify the temporal pattern (early up, late up, transient, etc.)
b. Save cluster membership table as CSV
c. Save cluster enrichment results as CSV

## Step 6: Cross-omics integration (if multi-omics)
a. If multiple omics datasets, identify correlated clusters across omics
b. Generate cross-omics cluster correlation heatmap

## Step 7: Execute and iterate
- Use run_rscript to execute
- Fix errors and re-run

## Step 8: Write conclusion.txt
- Number of clusters identified and their temporal patterns
- Top features in each cluster
- Enriched pathways per cluster
- Biological interpretation of temporal patterns based on knowledge base
- Relationship to research topic

Guidelines:
- All plots saved as PNG 300 dpi to figures/ folder
- All tables saved as CSV to tables/ folder
- Use absolute paths
- For Chinese labels, use showtext package
- If data is not time-series, adapt the analysis to cluster by group patterns

Please proceed step by step.
]]></string>.Value.Replace("<%= context %>", ctx)

            Logger.Info("Sending CMeans task to LLM...")
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
                result.Scripts.AddRange(Directory.GetFiles(ScriptsDir, "*cmeans*.R").Select(Function(f) Path.GetFileName(f)))
            End If
        End Sub

    End Class

End Namespace
