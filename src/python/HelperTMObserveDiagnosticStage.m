function HelperTMObserveDiagnosticStage(options,name,data)
% Optional local, read-only diagnostic sink. No signal or state is returned.
% The observer owns bounded capture; production and JSON callers omit it.
if isfield(options,'DiagnosticStageObserver')
    observer=options.DiagnosticStageObserver;
    assert(isa(observer,'function_handle'),'TM:DiagnosticObserver','Observer must be a local function handle.');
    observer(name,data);
end
end
