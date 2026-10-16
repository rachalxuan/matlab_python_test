function evidence = HelperTMLDPC78CapturePhase(asmWindows, asmBits, angles, maxError, minGap)
% Diagnostic-only phase selection from signed ASM observations, NEVER TX bits.
% Each cell contains ASM-length x N hard bits at an already acquired periodic
% boundary. Complement scores are diagnostic: they must NOT count as matches
% when selecting the actual phase used by the soft demapper.
if nargin<4, maxError=6; end
if nargin<5, minGap=4; end
n=numel(asmWindows); normal=inf(n,1); inverse=inf(n,1); counts=zeros(n,1);
asmBits=logical(asmBits(:));
assert(numel(angles)==n && ~isempty(asmBits));
for k=1:n
    w=asmWindows{k};
    if isempty(w), continue; end
    assert(size(w,1)==numel(asmBits));
    counts(k)=size(w,2);
    normal(k)=mean(sum(logical(w)~=asmBits,1));
    inverse(k)=mean(sum(logical(w)==asmBits,1));
end
eligible=normal; eligible(counts<3)=inf;
[sorted,order]=sort(eligible);
gap=NaN; chosen=NaN;
if n>=2 && isfinite(sorted(1)), gap=sorted(2)-sorted(1); end
accepted=n>=2 && isfinite(sorted(1)) && sorted(1)<=maxError && gap>=minGap;
if accepted, chosen=order(1); end
evidence=struct('Accepted',accepted,'SelectedIndex',chosen, ...
    'Rotation_deg',double(angles(:)), 'NormalMeanErrors',normal, ...
    'InverseMeanErrors',inverse,'PeriodicFrames',counts,'Gap',gap, ...
    'MaxMeanErrors',maxError,'MinGap',minGap,'ASMWindows',{asmWindows}, ...
    'Reason','insufficient or ambiguous signed ASM evidence');
if accepted, evidence.Reason='unique signed periodic ASM candidate'; end
end
