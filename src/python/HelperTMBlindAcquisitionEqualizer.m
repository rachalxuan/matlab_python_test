function [y,info] = HelperTMBlindAcquisitionEqualizer(x,ref,options)
% Rotation-invariant blind FIR for acquisition, before phase decisions exist.
% Learn on a bounded prefix, freeze taps DURING held-out CFO validation,
% then continue the same rotation-invariant update for time-varying ISI.
% The centered offline FIR preserves sample count/time indices. This is not
% a claim of streaming; subsequent carrier/DD keep their existing roles.
% Only the known constellation radii enter adaptation. No H or TX truth.
x=complex(x(:)); ref=complex(ref(:));
validateattributes(x,{'double','single'},{'vector','finite','nonempty'},mfilename,'x');
validateattributes(ref,{'double','single'},{'vector','finite','nonempty'},mfilename,'ref');
validateattributes(options.AcquisitionSymbols,{'numeric'}, ...
    {'scalar','finite','integer','positive'},mfilename,'AcquisitionSymbols');
assert(mean(abs(ref).^2)>0,'AcquisitionEQ:InvalidReference','Reference power must be positive.');
taps=17; half=(taps-1)/2;
train=min(options.AcquisitionSymbols,numel(x)-taps);
assert(train>2*taps,'AcquisitionEQ:ShortInput','Insufficient acquisition symbols.');
scale=sqrt(mean(abs(x(1:train)).^2)/mean(abs(ref).^2)+eps);
xn=x/scale; radii=unique(round(abs(ref)*1e12)/1e12);
w=complex(zeros(taps,1)); w(half+1)=1;
% Fixed iteration budget, not a BER/seed-dependent parameter search.
for pass=1:3
    for n=taps+1:train-half
        u=xn(n+half:-1:n-half); z=w'*u;
        [~,ring]=min(abs(abs(z)-radii));
        e=z*(radii(ring)^2-abs(z)^2);
        w=HelperTMNormalizedTapUpdate(w,u,e,0.05,real(u'*u)+1e-8,4,true);
    end
end
acquisitionWeights=w;
v=filter(conj(w),1,[xn;complex(zeros(half,1))]);
y=v(half+1:half+numel(x));
% Do not let later channel evolution invalidate a good acquisition FIR.
% The candidate+validation interval is kept frozen, so the CFO holdout is
% not reused to train these taps. Never restart adaptation at TM boundaries.
frozenSymbols=min(numel(x),2*train+half);
for n=frozenSymbols+1:numel(x)-half
    u=xn(n+half:-1:n-half); z=w'*u;
    y(n)=z;
    [~,ring]=min(abs(abs(z)-radii));
    e=z*(radii(ring)^2-abs(z)^2);
    w=HelperTMNormalizedTapUpdate(w,u,e,0.05,real(u'*u)+1e-8,4,true);
end
% Continue the final taps into the zero-extended finite-record tail too.
xp=[xn;complex(zeros(half,1))];
for n=max(frozenSymbols+1,numel(x)-half+1):numel(x)
    y(n)=w'*xp(n+half:-1:n-half);
end
y=y*scale;
info=struct('Applied',true,'Mode','blind-rde-acquisition', ...
    'Position','pre-carrier','Structure','fir', ...
    'NumTaps',taps,'TrainingSymbols',train,'Passes',3, ...
    'InputSymbols',numel(x),'OutputSymbols',numel(y), ...
    'LookaheadSymbols',half,'TapNorm',norm(w), ...
    'AcquisitionWeights',acquisitionWeights,'FinalWeights',w, ...
    'InputPower',mean(abs(x).^2),'OutputPower',mean(abs(y).^2), ...
    'TrainingUpdates',3*max(0,train-half-taps), ...
    'TrackingUpdates',max(0,numel(x)-half-frozenSymbols), ...
    'FrozenValidationEndSymbol',frozenSymbols, ...
    'Reason','rotation-invariant RDE; frozen CFO holdout, continuous tracking afterwards');
end
