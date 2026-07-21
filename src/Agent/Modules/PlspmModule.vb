' ============================================================================
' 模块 8: PLS-PM 因果路径分析
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Models

Namespace Agent.Modules

    ''' <summary>
    ''' PLS-PM (Partial Least Squares Path Modeling) 因果路径分析模块
    ''' </summary>
    Public Class PlspmModule
        Inherits AnalysisModuleBase

        Public Sub New(index As Integer, config As Config.AppConfig, workspace As IO.WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Utils.Logger,
                       llmClientFactory As Func(Of LLMClient))
            MyBase.New("plspm", index, config, workspace, input, kbPath, logger, llmClientFactory)
        End Sub

        Protected Overrides Async Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task
            Dim ctx = BuildContext()

            Dim prompt = <string><![CDATA[
You are a bioinformatics analysis agent. This is the PLS-PM (Partial Least Squares Path Modeling) CAUSAL PATH ANALYSIS module.

<%= context %>

Your task in this module:

## Step 1: Define latent variables (constructs)
Based on the research topic and knowledge base, define latent variables for path modeling:
a. Group biological features into latent variables based on:
   - KEGG pathway membership (from annotation file)
   - WGCNA module membership (if available)
   - Biological function (from knowledge base)
b. Typical latent variables for omics research:
   - Metabolism pathways (e.g., glycolysis, TCA cycle, lipid metabolism)
   - Signaling pathways (e.g., MAPK, PI3K-Akt)
   - Immune response
   - Disease phenotype (use sample group as indicator)
   - Clinical traits (if available in sample info)
c. Document the rationale for each latent variable definition

## Step 2: Define path model (inner design)
a. Specify hypothesized causal relationships between latent variables
b. Based on biological knowledge from kb.json:
   - Upstream pathways → downstream pathways
   - Pathways → phenotype/disease
   - Cross-omics relationships (e.g., gene → protein → metabolite)
c. Create path matrix (square matrix, lower triangular)
d. Document the biological rationale for each path

## Step 3: Define measurement model (outer design)
a. For each latent variable, specify its indicator features:
   - Reflective mode (mode = "A"): indicators reflect the latent variable
   - Formative mode (mode = "B"): indicators form the latent variable
b. Use 3-10 indicators per latent variable
c. Select indicators based on:
   - High loading in previous analyses
   - Hub genes from WGCNA
   - Differential features from LIMMA

## Step 4: Run PLS-PM analysis
a. Use plspm::plspm function
b. Parameters:
   - scale = "std" (standardized)
   - scheme = "centroid" or "factorial"
   - validation = "bootstrap" with 100 resamples
c. Extract results:
   - Path coefficients (inner model)
   - Loadings and weights (outer model)
   - R-squared for endogenous latent variables
   - Total effects (direct + indirect)
   - Bootstrap confidence intervals

## Step 5: Visualization
a. Generate path diagram:
   - Use plspm::plot.plspm or DiagrammeR
   - Show path coefficients on arrows
   - Show R-squared in latent variable boxes
   - Color by significance
b. Generate:
   - Loading bar plot per latent variable
   - Path coefficient heatmap
   - Bootstrap validation plot
   - Inner model summary plot

## Step 6: Execute and iterate
- Use run_rscript to execute
- Fix errors and re-run

## Step 7: Write conclusion.txt
- Latent variables defined and their biological meaning
- Significant path coefficients (with bootstrap CI)
- R-squared values for endogenous constructs
- Total effects analysis
- Key causal pathways identified
- Biological interpretation based on knowledge base
- Comparison with known biological mechanisms from literature

Guidelines:
- Limit to 5-10 latent variables for model stability
- Use bootstrap validation for robustness
- All plots saved as PNG 300 dpi to figures/ folder
- All tables saved as CSV to tables/ folder
- Use absolute paths
- For Chinese labels, use showtext package

Please proceed step by step.
]]></string>.Value.Replace("<%= context %>", ctx)

            Logger.Info("Sending PLS-PM task to LLM...")
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
                result.Scripts.AddRange(Directory.GetFiles(ScriptsDir, "*plspm*.R").Select(Function(f) Path.GetFileName(f)))
            End If
        End Sub

    End Class

End Namespace
