' ============================================================================
' 模块 2: PCA / PLSDA / OPLSDA 多元统计分析
' ============================================================================
Imports System.IO
Imports System.Text
Imports OmicsAgent.Models

Namespace Agent.Modules

    ''' <summary>
    ''' 多元统计分析模块：PCA、PLSDA、OPLSDA
    ''' </summary>
    Public Class MultivariateModule
        Inherits AnalysisModuleBase

        Public Sub New(index As Integer, config As Config.AppConfig, workspace As IO.WorkspaceManager,
                       input As AnalysisInput, kbPath As String, logger As Utils.Logger,
                       llmClientFactory As Func(Of LLMClient))
            MyBase.New("multivariate", index, config, workspace, input, kbPath, logger, llmClientFactory)
        End Sub

        Protected Overrides Async Function ExecuteAsync(llm As LLMClient, result As ModuleResult) As Task
            Dim ctx = BuildContext()

            Dim prompt = <string><![CDATA[
You are a bioinformatics analysis agent. This is the MULTIVARIATE STATISTICAL ANALYSIS module (PCA / PLSDA / OPLSDA).

<%= context %>

Your task in this module:
1. Read the normalized expression matrix from the tmp/ folder (produced by the preprocessing module).
   If not found, read the original expression matrix and apply log2 + scaling in your R script.
2. Write an R script to perform:
   a. PCA (Principal Component Analysis):
      - Use prcomp or FactoMineR::PCA
      - Generate PCA score plot (PC1 vs PC2, colored by sample group)
      - Generate PCA loading plot (top contributing features)
      - Report explained variance for each PC
      - Save scores and loadings as CSV in tables/ folder
   b. PLS-DA (Partial Least Squares Discriminant Analysis):
      - Use mixOmics::plsda
      - Generate PLS-DA score plot
      - Calculate VIP scores for all features
      - Save VIP scores as CSV in tables/ folder
      - Generate VIP score bar plot (top 30 features)
   c. OPLS-DA (Orthogonal PLS-DA) - if mixOmics is available:
      - Use ropls::opls or MetaboAnalystR
      - Generate OPLS-DA score plot
      - Calculate VIP scores (VIP > 1.0 considered significant)
      - Save OPLS-DA VIP scores as CSV
   d. Cross-validation:
      - Perform leave-one-out or 5-fold cross-validation for PLS-DA
      - Report Q2 and R2 values
      - Generate permutation test plot (n=100 permutations)
3. Execute the R script using run_rscript.
4. If errors occur, fix and re-run.
5. Write conclusion.txt describing:
   - Sample clustering patterns observed in PCA
   - Group separation quality in PLS-DA / OPLS-DA
   - Q2/R2 values and model validity
   - Top discriminating features (VIP > 1.0)
   - Biological interpretation based on knowledge base

Guidelines:
- All plots saved as PNG 300 dpi to figures/ folder
- All tables saved as CSV to tables/ folder
- Use absolute paths
- For VIP score cutoff, use VIP > 1.0
- For Chinese labels in figures, use showtext package

Please proceed step by step.
]]></string>.Value.Replace("<%= context %>", ctx)

            Logger.Info("Sending multivariate analysis task to LLM...")
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
                result.Scripts.AddRange(Directory.GetFiles(ScriptsDir, "*multivariate*.R").Select(Function(f) Path.GetFileName(f)))
            End If
        End Sub

    End Class

End Namespace
