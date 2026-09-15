function capture = HelperTMFSEDiagnosticCapture(x, options)
% Read-only, bounded capture. Never returns a corrected receiver signal.
capture = struct('SymbolIndex',zeros(0,1),'Samples',complex(zeros(0,1)), ...
    'TotalSymbols',numel(x));
if ~isfield(options,'FSEDiagnostics') || ~isstruct(options.FSEDiagnostics)
    return;
end
cfg = options.FSEDiagnostics;
if ~isfield(cfg,'SymbolRange') || numel(cfg.SymbolRange) ~= 2
    error('FSEDiagnostics:Range','FSEDiagnostics.SymbolRange must have two indices.');
end
ranges = round(double(cfg.SymbolRange(:).'));
if isfield(cfg,'AnchorRange')
    anchor = round(double(cfg.AnchorRange(:).'));
else
    anchor = [50000 54095];
end
assert(numel(anchor)==2 && all(isfinite([ranges anchor])) && ...
    ranges(2)>=ranges(1) && anchor(2)>=anchor(1), ...
    'FSEDiagnostics:Range','Invalid diagnostic ranges.');
extra = zeros(1,0);
if isfield(cfg,'SwitchRange')
    switchRange = round(double(cfg.SwitchRange(:).'));
    assert(numel(switchRange)==2 && all(isfinite(switchRange)) && ...
        switchRange(2)>=switchRange(1), 'FSEDiagnostics:Range','Invalid switch range.');
    extra = max(1,switchRange(1)):min(numel(x),switchRange(2));
end
assert(diff(ranges)+1+diff(anchor)+1+numel(extra) <= 65536, ...
    'FSEDiagnostics:CaptureLimit','Capture is limited to 65536 symbols per stage.');
idx = unique([max(1,ranges(1)):min(numel(x),ranges(2)), ...
    max(1,anchor(1)):min(numel(x),anchor(2)),extra]).';
capture.SymbolIndex = idx;
capture.Samples = x(idx);
end
