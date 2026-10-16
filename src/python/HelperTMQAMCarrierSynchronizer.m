function [y,phase,info] = HelperTMQAMCarrierSynchronizer(x,ref,bandwidth,symbolRate)
% Full-constellation QAM detector feeding the shared PI/NCO implementation.
% The sign/quadrant detector has data self-noise for unequal I/Q levels,
% even when carrier phase is exactly correct. Use the actual QAM slicer.
% No pilots, transmitted symbols, decoded bits, or BER enter this loop.
x=complex(x(:)); ref=complex(ref(:));
validateattributes(x,{'double','single'},{'vector','finite','nonempty'},mfilename,'x');
validateattributes(ref,{'double','single'},{'vector','finite','nonempty'},mfilename,'ref');
assert(numel(x)>=4 && numel(unique(ref))>=2, ...
    'QAMCarrier:ShortInput','At least four samples and two distinct reference points are required.');
assert(mean(abs(ref).^2)>0,'QAMCarrier:InvalidReference','Reference power must be positive.');
scale=sqrt(mean(abs(x).^2)/mean(abs(ref).^2)+eps);
z=x/scale;
distance=abs(ref-ref.'); distance(distance==0)=Inf; dmin=min(distance(:));

% Keep official wide-angle acquisition, but only on a bounded prefix. Fit
% its settled phase to initialize the reference at sample 1, then replay the
% SAME complete record through one constellation-aware loop. No short crop
% is reset at an error event. Remaining quadrant ambiguity belongs to ASM.
bootstrap=comm.CarrierSynchronizer('Modulation','QAM','SamplesPerSymbol',1, ...
    'DampingFactor',1/sqrt(2),'NormalizedLoopBandwidth',bandwidth);
count=min(numel(z),4096);
[~,p]=bootstrap(z(1:count));
ix=(max(1,floor(count/2)):count)';
fit=polyfit(ix-1,unwrap(p(ix)),1);
opt=struct('SymbolRateHz',symbolRate, ...
    'AcquireLoopBandwidth',bandwidth,'TrackLoopBandwidth',bandwidth, ...
    'InitialPhaseRad',fit(2),'InitialFrequencyHz',fit(1)*symbolRate/(2*pi), ...
    'MaxFrequencyHz',0.05*symbolRate,'MaxPhaseErrorRad',pi/4, ...
    'RecoverGoodSymbols',1,'CollectTrace',false);
[corrected,~,info]=HelperTMSecondOrderCarrierLoop(z,@detector,opt);
y=corrected*scale;
phase=unwrap(angle(z.*conj(corrected)));
info.Detector='nearest-QAM-point with distance/margin gate';
info.Applied=true;
info.AcquisitionSymbols=count;
% Only compact scalar diagnostics leave this adapter.
info=rmfield(info,{'AcceptedMask','ReliableMask','HoldMask','FadeMask', ...
    'PhaseErrorRad','DetectorMetric','FrequencyTraceHz','PhaseTraceRad'});

    function [err,reliable,metric]=detector(v,~)
        ds=abs(v-ref).^2; [first,index]=min(ds); ds(index)=Inf;
        second=min(ds); metric=first/dmin^2;
        reliable=first<=(0.5*dmin)^2 && ...
            (second-first)/max(second,eps)>=0.1;
        err=angle(v*conj(ref(index)));
    end
end
