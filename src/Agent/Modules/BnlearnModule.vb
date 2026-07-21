' ============================================================================
' 模块 7: bnlearn 动态贝叶斯网络分析（时间序列）
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Models

Namespace Agent.Modules

    ''' <summary>
    ''' bnlearn 动态贝叶斯网络分析模块（仅用于时间序列数据）
    ''' </summary>
    Public Class BnlearnModule
        Inherits AnalysisModuleBase

        Public Sub New(index As Integer, config As Config.AppConfig, workspace As IO.WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Utils.Logger,
                       llmClientFactory As Func(Of LLMClient))
            MyBase.New("bnlearn", index, config, workspace, input, kbPath, logger, llmClientFactory)
        End Sub

        Protected Overrides Async Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task
            ' 检查是否为时间序列数据
            Dim hasTimeSeries = Input.Datasets.Any(Function(d) d.HasTimeSeries)
            If Not hasTimeSeries AndAlso Not Input.Research.IsTimeSeries Then
                Logger.Info("Data is not time-series, skipping bnlearn dynamic Bayesian network analysis.")
                result.ConclusionText = "Skipped: data is not time-series. bnlearn dynamic Bayesian network analysis requires time-series design."
                result.Success = True
                Return
            End If

            Dim ctx = BuildContext()

            Dim prompt = <string><![CDATA[
You are a bioinformatics analysis agent. This is the BNLEARN DYNAMIC BAYESIAN NETWORK module for time-series causal inference.

<%= context %>

Your task in this module:

## Step 1: Data preparation for dynamic Bayesian network
a. Read the normalized expression matrix from tmp/ folder
b. Identify time points from sample info (use "time" column or sequential groups)
c. Select features for network construction:
   - Use hub genes from WGCNA modules if available
   - Otherwise use top differential features (top 50-100)
   - Limit to ~50-100 features for computational feasibility
d. Discretize expression values if needed (use bnlearn::discretize)
   - Or use continuous data with Gaussian Bayesian network

## Step 2: Dynamic Bayesian network structure learning
a. Use bnlearn package:
   - For continuous data: use hc (hill-climbing) or tabu search with Gaussian network
   - For discrete data: use hc or tabu with multinomial network
b. Apply blacklist/whitelist if prior knowledge available (from kb.json)
c. Perform bootstrap analysis:
   - Use boot.strength with R = 100-200 bootstrap samples
   - Apply averaged network with threshold > 0.5
d. Generate network visualization:
   - Use Rgraphviz or igraph to plot the network
   - Color nodes by module (if WGCNA results available)
   - Edge width by bootstrap strength

## Step 3: Static Bayesian network (for non-time-series or comparison)
a. Also construct a static Bayesian network for comparison
b. Compare with dynamic network structure

## Step 4: Network analysis
a. Identify hub nodes (high in-degree and out-degree)
b. Identify key regulatory edges (high bootstrap strength)
c. Perform conditional probability queries for key nodes
d. Compute node centrality measures (betweenness, closeness)

## Step 5: Pathway-level network (optional)
a. Aggregate features to pathway level (using KEGG annotation)
b. Construct pathway-level Bayesian network
c. Identify key regulatory pathways

## Step 6: Execute and iterate
- Use run_rscript to execute
- Fix errors and re-run

## Step 7: Write conclusion.txt
- Network structure summary (number of nodes, edges)
- Top hub nodes and their roles
- Key regulatory relationships identified
- Bootstrap strength statistics
- Biological interpretation of regulatory network based on knowledge base
- Comparison with known pathways from literature

Guidelines:
- Limit network size to 50-100 nodes for computational feasibility
- All plots saved as PNG 300 dpi to figures/ folder
- All tables saved as CSV to tables/ folder
- Use absolute paths
- For Chinese labels, use showtext package
- If bnlearn structure learning is too slow, reduce feature count

Please proceed step by step.
]]></string>.Value.Replace("<%= context %>", ctx)

            Logger.Info("Sending bnlearn task to LLM...")
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
                result.Scripts.AddRange(Directory.GetFiles(ScriptsDir, "*bnlearn*.R").Select(Function(f) Path.GetFileName(f)))
            End If
        End Sub

    End Class

End Namespace
