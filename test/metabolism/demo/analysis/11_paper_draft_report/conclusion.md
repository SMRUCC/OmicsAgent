Module Paper Draft Report failed with error: Failed to compare two elements in the array.

Stack trace:
   at System.Collections.Generic.ArraySortHelper`1.Sort(Span`1 keys, Comparison`1 comparer)
   at System.Linq.Enumerable.EnumerableSorter`2.QuickSort(Int32[] keys, Int32 lo, Int32 hi)
   at System.Linq.Enumerable.OrderedIterator`2.MoveNext()
   at OmicsAgent.ReportModule.BuildHtmlReport(ReportContent content, List`1 figures, List`1 tables) in G:\OmicsWorks\src\Modules\Standard\Module11_Report.vb:line 393
   at OmicsAgent.ReportModule.GenerateAndRunScriptAsync(LLMClient llm, ModulePlan plan, Step step, CancellationToken cancellationToken) in G:\OmicsWorks\src\Modules\Standard\Module11_Report.vb:line 112
   at OmicsAgent.AnalysisModuleBase.GenerateAndRunScriptAsync(LLMClient llm, ModulePlan plan, CancellationToken cancellationToken) in G:\OmicsWorks\src\Modules\Base\AnalysisModuleBase.vb:line 265
   at OmicsAgent.AnalysisModuleBase.RunAgent(CancellationToken cancellationToken) in G:\OmicsWorks\src\Modules\Base\AnalysisModuleBase.vb:line 129
   at OmicsAgent.AnalysisModuleBase.RunAsync(CancellationToken cancellationToken) in G:\OmicsWorks\src\Modules\Base\AnalysisModuleBase.vb:line 95