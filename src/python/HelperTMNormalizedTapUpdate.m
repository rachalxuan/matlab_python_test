function [next,accepted,constrained,candidateNorm] = ...
    HelperTMNormalizedTapUpdate(w,u,error,step,inputPower,maxNorm,project)
% Shared complex normalized-gradient update, y = w'*u.
% The caller supplies the modulation-specific error and the SAME regressor
% that produced y. inputPower already includes the caller's regularizer.
% project=false preserves the ordinary DD receiver's reject/hold policy.
% project=true performs projected-gradient adaptation on ||w|| <= maxNorm;
% exceeding the bound is not a numerical failure or proof of false lock.
% No decisions, TX reference, frame selection or convergence claims here.
if nargin<7, project=false; end
next=w;
candidate=w+(step/inputPower)*u*conj(error);
candidateNorm=norm(candidate);
accepted=all(isfinite(candidate)) && isfinite(candidateNorm);
constrained=accepted && candidateNorm>maxNorm;
if ~accepted, return; end
if constrained
    if ~project
        accepted=false;
        return;
    end
    candidate=candidate*(maxNorm/candidateNorm);
end
next=candidate;
end
