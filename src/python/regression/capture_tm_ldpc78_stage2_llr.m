function [T, reportFile, batchFiles] = capture_tm_ldpc78_stage2_llr(opt)
%CAPTURE_TM_LDPC78_STAGE2_LLR Capture fixed Stage2 LLRs and compare BP graphs.
%   This is a receiver diagnostic, not another link sweep. It reuses the
%   complete saved Stage2 inputs for exactly three cases:
%       CDL_A_2 - normal baseline
%       CDL_B_1 - residual decoded errors
%       CDL_A_4 - severe decoded failure
%   The complete channel interval is processed. The production dense BP is
%   bypassed while LLRs are captured at the aligned/derandomized decoder
%   boundary. Only small, labelled codeword windows are written to disk.
%
%   Example:
%     o=struct('SourceFile',fullfile(pwd,'artifacts','ccsds','system-eq', ...
%       'TM_EQ_files_20261014_101855_691.mat'));
%     [T,F,B]=capture_tm_ldpc78_stage2_llr(o);
%
%   Options: SourceFile, OutputDir, CaseIndices (default [2 5 4]),
%   CaseLabels, MaxCodewordsPerCase (12), WindowRadius (1),
%   MaxIterations (20), RunComparison (true).

if nargin < 1, opt=struct(); end
assert(isstruct(opt) && isscalar(opt),'Options must be a scalar struct.');
allowed={'SourceFile','OutputDir','CaseIndices','CaseLabels', ...
    'MaxCodewordsPerCase','WindowRadius','MaxIterations','RunComparison'};
assert(all(ismember(fieldnames(opt),allowed)),'Unknown option.');

root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
sourceDir=fullfile(root,'src','python');
oldPath=path; pathCleanup=onCleanup(@()path(oldPath)); %#ok<NASGU>
oldRng=rng; rngCleanup=onCleanup(@()rng(oldRng)); %#ok<NASGU>
addpath(sourceDir);
addpath(fullfile(sourceDir,'regression'));

sourceFile=option(opt,'SourceFile',fullfile(root,'artifacts','ccsds', ...
    'system-eq','TM_EQ_files_20261014_101855_691.mat'));
assert(isfile(sourceFile),'Stage2 source MAT not found: %s',sourceFile);
stored=load(sourceFile);
assert(isfield(stored,'inputs') && iscell(stored.inputs), ...
    'Stage2 source must contain the saved inputs cell array.');

caseIndices=double(option(opt,'CaseIndices',[2 5 4]));
caseLabels=string(option(opt,'CaseLabels', ...
    ["CDL_A_2-normal","CDL_B_1-residual","CDL_A_4-severe"]));
assert(isvector(caseIndices) && numel(caseIndices)==numel(caseLabels) && ...
    all(caseIndices>=1) && all(caseIndices<=numel(stored.inputs)) && ...
    all(mod(caseIndices,1)==0),'Case indices/labels are invalid.');
maxWords=double(option(opt,'MaxCodewordsPerCase',12));
radius=double(option(opt,'WindowRadius',1));
maxIterations=double(option(opt,'MaxIterations',20));
runComparison=logical(option(opt,'RunComparison',true));
validateattributes(maxWords,{'numeric'},{'scalar','integer','positive'});
validateattributes(radius,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(maxIterations,{'numeric'},{'scalar','integer','positive'});
validateattributes(runComparison,{'logical'},{'scalar'});

outDir=option(opt,'OutputDir',fullfile(root,'artifacts','ccsds','ldpc78','stage2'));
if ~isfolder(outDir), mkdir(outDir); end
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
reportFile=fullfile(outDir,['LDPC78_Stage2_AB_' stamp '.mat']);
batchFiles=strings(numel(caseIndices),1);
T=table();
meta=struct('SourceFile',sourceFile,'CaseIndices',caseIndices, ...
    'CaseLabels',caseLabels,'FullChannelIntervalPreserved',true, ...
    'CaptureDecoderMode','capture-only','PhaseSelection', ...
    'receiver-signed-periodic-ASM','TXTruthUsedForCapture',false, ...
    'TXTruthUse','window labelling and decoder error evaluation only', ...
    'MaxCodewordsPerCase',maxWords,'WindowRadius',radius, ...
    'MaxIterations',maxIterations,'CompletedCases',0, ...
    'FailedCaseLabels',strings(0,1),'DiagnosticFiles',strings(0,1));

for c=1:numel(caseIndices)
    caseIndex=caseIndices(c);
    label=caseLabels(c);
    if isfield(stored,'T') && istable(stored.T) && ...
            ismember('Channel',stored.T.Properties.VariableNames)
        actualLabel=string(stored.T.Channel(caseIndex));
        expectedLabel=extractBefore(label,"-");
        assert(contains(actualLabel,expectedLabel,'IgnoreCase',true), ...
            'Source index %d is %s, expected %s.',caseIndex, ...
            char(actualLabel),char(expectedLabel));
    end
    p=stored.inputs{caseIndex};
    assert(isstruct(p) && isscalar(p),'inputs{%d} is not a scalar options struct.',caseIndex);
    p.captureLDPC78LLR=true;
    p.LDPCDecoderMode='capture-only';
    p.phaseResolveMode='asm';
    p.phaseResolveFallback=false;
    p.debugLDPC=false;
    p.debugCodedBoundary=false;
    p.enableReceiverTimeline=false;
    p.enableRuntimeLockTelemetry=false;
    fprintf('\n[Stage2 capture %d/%d] %s (source index %d), full interval\n', ...
        c,numel(caseIndices),label,caseIndex);
    % Match run_tm_equalizer_system_checks: run_ccsds_tm_evaluation does not
    % itself seed the RNG merely because randomSeed is present in options.
    seed=localNumericField(p,'randomSeed',NaN);
    validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative','finite'});
    rng(seed,'twister');
    fprintf('[capture replay] restored Stage2 RNG seed=%d (twister)\n',seed);
    timer=tic;
    result=run_ccsds_tm_evaluation(p);
    captureSeconds=toc(timer);
    capture=option(result,'LDPCDiagnosticCapture',struct('Available',false));
    failure='';
    if ~option(result,'success',false)
        failure=char(string(option(result,'errorMsg','evaluation failed')));
    elseif ~option(capture,'Available',false)
        failure=char(string(option(capture,'Reason','no decoder-boundary capture')));
    elseif ~isfield(capture,'ReferenceAvailable') || ~any(capture.ReferenceAvailable)
        failure=char(string(option(capture,'ReferenceAssociationReason','no offline reference mapping')));
    end
    if ~isempty(failure)
        % Keep bounded evidence even when there is no trusted TX association.
        % Never manufacture references or use BER to pick another phase.
        diagnostic=capture;
        if isfield(capture,'LLR')
            n=size(capture.LLR,2);
            keep=unique(round(linspace(1,n,min(n,maxWords))));
            diagnostic.LLR=capture.LLR(:,keep);
            diagnostic.SavedReceiverCodewordIndex=keep;
            diagnostic.TotalCapturedCodewords=n;
            for field={'Message','TxFrameIndex','ReferenceAvailable','InputStartBit'}
                key=field{1};
                if ~isfield(capture,key), continue; end
                if strcmp(key,'Message')
                    diagnostic.(key)=capture.(key)(:,keep);
                elseif numel(capture.(key))==n
                    diagnostic.(key)=capture.(key)(keep);
                end
            end
        end
        diagnostic.FailureReason=failure;
        diagnostic.Stage2Case=label;
        diagnostic.SourceIndex=caseIndex;
        diagnostic.Options=p;
        diagnostic.CaptureSeconds=captureSeconds;
        safeLabel=regexprep(char(label),'[^A-Za-z0-9_-]','_');
        diagnosticFile=fullfile(outDir,sprintf('LDPC78_CAPTURE_FAILED_%s_%s.mat',safeLabel,stamp));
        save(diagnosticFile,'diagnostic','-v7');
        meta.FailedCaseLabels(end+1,1)=label;
        meta.DiagnosticFiles(end+1,1)=string(diagnosticFile);
        save(reportFile,'T','meta','batchFiles','-v7');
        warning('capture_tm_ldpc78_stage2_llr:UnmappedCapture', ...
            '%s: %s. No BP comparison performed. Diagnostic: %s',label,failure,diagnosticFile);
        continue;
    end
    assert(size(capture.LLR,1)==8160 && ...
        capture.InformationLength==7136 && ...
        strcmp(capture.LLRPolarity,'positive-zero') && ...
        capture.ASMRemoved && capture.Derandomized, ...
        'Capture contract mismatch for %s.',label);

    badTargets=localBaselineBadTargets(stored,caseIndex);
    selected=localSelectCodewords(capture,badTargets,maxWords,radius);
    assert(~isempty(selected),'No reference-mapped codewords available for %s.',label);
    Batch=struct( ...
        'LLR',capture.LLR(:,selected), ...
        'Message',capture.Message(:,selected), ...
        'Labels',repmat(label,1,numel(selected)), ...
        'FrameIndex',double(capture.TxFrameIndex(selected)).', ...
        'ReceiverCodewordIndex',double(selected(:)).', ...
        'InputStartBit',double(capture.InputStartBit(selected)).', ...
        'Provenance',sprintf(['actual Stage2 receiver LLR; source=%s; ', ...
            'case=%s index=%d; complete channel interval processed; ', ...
            'selected windows only'],sourceFile,label,caseIndex), ...
        'Seed',localNumericField(p,'randomSeed',localNumericField(p,'seed',NaN)), ...
        'LLRPolarity','positive-zero', ...
        'ASMRemoved',true, ...
        'Derandomized',true, ...
        'CandidateRotation_deg',capture.CandidateRotation_deg, ...
        'PhaseSelectionSource',capture.PhaseSelectionSource, ...
        'PhaseEvidence',capture.PhaseEvidence, ...
        'ReferenceUse',capture.ReferenceUse);
    safeLabel=regexprep(char(label),'[^A-Za-z0-9_-]','_');
    batchFile=fullfile(outDir,sprintf('LDPC78_LLR_%s_%s.mat',safeLabel,stamp));
    save(batchFile,'Batch','-v7');
    batchFiles(c)=string(batchFile);
    fprintf(['[capture] codewords=%d, reference-mapped=%d, saved=%d, ', ...
        'rotation=%+.1f deg, elapsed=%.1fs\n'], ...
        size(capture.LLR,2),nnz(capture.ReferenceAvailable),numel(selected), ...
        capture.CandidateRotation_deg,captureSeconds);

    if runComparison
        compareOpt=struct('Batch',Batch,'MaxIterations',maxIterations, ...
            'SaveResults',false);
        caseTable=test_tm_ldpc78_decoder('replay',compareOpt);
        caseTable.Stage2Case=repmat(label,height(caseTable),1);
        caseTable.Stage2SourceIndex=repmat(caseIndex,height(caseTable),1);
        caseTable.CaptureSeconds=repmat(captureSeconds,height(caseTable),1);
        if isempty(T), T=caseTable; else, T=[T;caseTable]; end %#ok<AGROW>
    end
    meta.CompletedCases=meta.CompletedCases+1;
    meta.BatchFiles=batchFiles;
    save(reportFile,'T','meta','batchFiles','-v7');
end

if ~isempty(T)
    summary=groupsummary(T,{'Stage2Case','Decoder'}, ...
        {'sum','mean','max'},{'DecodedInfoErrors','Iterations','Seconds'});
    disp(summary);
else
    summary=table();
end
save(reportFile,'T','summary','meta','batchFiles','-v7');
fprintf('\n[Stage2 LDPC A/B done] completed=%d/%d failed=%d report=%s\n', ...
    meta.CompletedCases,numel(caseIndices),numel(meta.FailedCaseLabels),reportFile);
end

function selected=localSelectCodewords(capture,badTargets,maxWords,radius)
mapped=find(capture.ReferenceAvailable(:) & isfinite(capture.TxFrameIndex(:)));
assert(~isempty(mapped),'Capture contains no offline reference mapping.');
tx=double(capture.TxFrameIndex(:));
targets=[];
badTargets=unique(double(badTargets(isfinite(badTargets))),'stable');
if ~isempty(badTargets)
    anchors=badTargets(unique(round(linspace(1,numel(badTargets), ...
        min(3,numel(badTargets))))));
    for a=reshape(anchors,1,[])
        targets=[targets (a-radius):(a+radius)]; %#ok<AGROW>
    end
end
% Always retain beginning/middle/end controls from the full mapped interval.
control=mapped(unique(round(linspace(1,numel(mapped),min(3,numel(mapped))))));
targets=unique([targets tx(control).'],'stable');
selected=zeros(0,1);
for target=targets
    hit=mapped(tx(mapped)==target);
    if ~isempty(hit), selected(end+1,1)=hit(1); end %#ok<AGROW>
end
% If source bad-frame rows were absent or not mapped, add the largest raw
% systematic hard-error words. This uses TX truth only after the waveform,
% boundary, phase, and LLR capture have all been frozen.
hard=reshape(capture.LLR(1:7136,mapped)<0,7136,[]);
reference=capture.Message(:,mapped);
rawErrors=sum(hard~=reference,1);
[~,order]=sort(rawErrors,'descend');
selected=unique([selected;mapped(order(1:min(numel(order),maxWords)))],'stable');
selected=selected(1:min(numel(selected),maxWords));
end

function targets=localBaselineBadTargets(stored,index)
targets=[];
if ~isfield(stored,'badFrames') || numel(stored.badFrames)<index
    return;
end
bad=stored.badFrames{index};
if istable(bad) && ismember('TxFrameIndex',bad.Properties.VariableNames)
    targets=double(bad.TxFrameIndex(:));
elseif isstruct(bad) && isfield(bad,'TxFrameIndex')
    targets=double([bad.TxFrameIndex].');
end
end

function v=localNumericField(s,name,fallback)
if isfield(s,name) && isnumeric(s.(name)) && isscalar(s.(name))
    v=double(s.(name));
else
    v=fallback;
end
end

function v=option(s,name,fallback)
if isfield(s,name), v=s.(name); else, v=fallback; end
end
