function [locations, info] = HelperTMASMLocator(rxSymbols, asmTemplates, periodSymbols, options)
%HELPERTMASMLOCATOR Locate periodic ASM symbols by normalized correlation.
%
% The correlation magnitude is invariant to one unknown complex scalar, so
% the locator can run before an ASM-trained equalizer.  asmTemplates is an
% L-by-N matrix; each column is one allowed template.

if nargin < 4 || isempty(options)
    options = struct();
end
rxSymbols = complex(rxSymbols(:));
asmTemplates = complex(asmTemplates);
locations = zeros(0,1);
info = localEmptyInfo();

if isempty(rxSymbols) || isempty(asmTemplates)
    info.Reason = 'empty received stream or ASM template';
    return;
end
if isvector(asmTemplates)
    asmTemplates = asmTemplates(:);
end
if size(asmTemplates,1) > numel(rxSymbols)
    info.Reason = 'received stream is shorter than the ASM template';
    return;
end
if ~isscalar(periodSymbols) || ~isfinite(periodSymbols) || periodSymbols <= 0
    info.Reason = 'periodSymbols must be finite and positive';
    return;
end
periodSymbols = round(periodSymbols);

templateLength = size(asmTemplates,1);
validStarts = numel(rxSymbols)-templateLength+1;
scoreByTemplate = zeros(validStarts,size(asmTemplates,2));
gainByTemplate = complex(zeros(validStarts,size(asmTemplates,2)));
windowPower = conv(abs(rxSymbols).^2,ones(templateLength,1),'valid');
for kTemplate = 1:size(asmTemplates,2)
    template = asmTemplates(:,kTemplate);
    templatePower = sum(abs(template).^2);
    numerator = conv(rxSymbols,conj(flipud(template)),'valid');
    denominator = sqrt(max(windowPower*templatePower,eps));
    scoreByTemplate(:,kTemplate) = abs(numerator)./denominator;
    gainByTemplate(:,kTemplate) = numerator/max(templatePower,eps);
end
[bestScore,bestTemplate] = max(scoreByTemplate,[],2);

minimumScore = localNumber(options,'asmLocatorMinScore',0.45);
minimumScore = min(max(minimumScore,0),1);
searchRadius = max(1,round(localNumber(options, ...
    'asmLocatorSearchRadiusSymbols',max(4,0.02*periodSymbols))));
maximumOccurrences = max(1,round(localNumber(options, ...
    'asmLocatorMaxOccurrences',floor(numel(rxSymbols)/periodSymbols)+2)));

% Anchor in the first two frame periods.  This avoids choosing a later
% isolated false peak while still tolerating front-end filter transients.
anchorLimit = min(validStarts,max(periodSymbols+searchRadius,2*periodSymbols));
[anchorScore,anchor] = max(bestScore(1:anchorLimit));
if isempty(anchor) || ~isfinite(anchorScore) || anchorScore < minimumScore
    info.Reason = sprintf('no ASM correlation above %.3f',minimumScore);
    info.MaximumScore = max(bestScore);
    return;
end

% Walk backwards first so the output starts with the earliest reliable ASM.
positionList = anchor;
predicted = anchor-periodSymbols;
while predicted >= 1
    [candidate,score] = localRefine(bestScore,predicted,searchRadius);
    if score < minimumScore
        break;
    end
    positionList = [candidate;positionList]; %#ok<AGROW>
    predicted = candidate-periodSymbols;
end

predicted = positionList(end)+periodSymbols;
while predicted <= validStarts && numel(positionList) < maximumOccurrences
    [candidate,score] = localRefine(bestScore,predicted,searchRadius);
    if score < minimumScore
        % Preserve frame numbering across one bad fade by trying the next
        % predicted period.  No location is emitted for the missing ASM.
        predicted = predicted+periodSymbols;
        continue;
    end
    if candidate <= positionList(end)
        predicted = predicted+periodSymbols;
        continue;
    end
    positionList(end+1,1) = candidate; %#ok<AGROW>
    predicted = candidate+periodSymbols;
end

locations = unique(positionList(:),'stable');
indices = sub2ind(size(gainByTemplate),locations,bestTemplate(locations));
info.Applied = true;
info.Reason = 'periodic normalized complex ASM correlation';
info.TemplateLength = templateLength;
info.PeriodSymbols = periodSymbols;
info.SearchRadiusSymbols = searchRadius;
info.MinimumScore = minimumScore;
info.MaximumScore = max(bestScore);
info.Positions = locations;
info.Scores = bestScore(locations);
info.TemplateIndices = bestTemplate(locations);
info.ComplexGains = gainByTemplate(indices);
info.MedianScore = median(info.Scores);
end

function [position,score] = localRefine(scores,predicted,radius)
    first = max(1,round(predicted)-radius);
    last = min(numel(scores),round(predicted)+radius);
    [score,localIndex] = max(scores(first:last));
    position = first+localIndex-1;
end

function value = localNumber(s,name,fallback)
    value = fallback;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
        candidate = double(s.(name));
        if isscalar(candidate) && isfinite(candidate)
            value = candidate;
        end
    end
end

function info = localEmptyInfo()
    info = struct('Applied',false,'Reason','disabled', ...
        'TemplateLength',0,'PeriodSymbols',NaN, ...
        'SearchRadiusSymbols',NaN,'MinimumScore',NaN, ...
        'MaximumScore',NaN,'MedianScore',NaN, ...
        'Positions',zeros(0,1),'Scores',zeros(0,1), ...
        'TemplateIndices',zeros(0,1), ...
        'ComplexGains',complex(zeros(0,1)));
end
