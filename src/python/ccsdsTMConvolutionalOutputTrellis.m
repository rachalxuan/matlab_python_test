function [trellis, canonicalMode] = ccsdsTMConvolutionalOutputTrellis(baseTrellis, mode, codeRate)
%CCSDSTMCONVOLUTIONALOUTPUTTRELLIS Apply the modem G1/G2 stream convention.
%   [T, MODE] = ccsdsTMConvolutionalOutputTrellis(BASE, MODE) returns a
%   rate-1/2 mother-code trellis whose two output bits are arranged like
%   the selectable modem convention.  Puncturing can then be applied by
%   comm.ConvolutionalEncoder/comm.ViterbiDecoder without losing the G1/G2
%   phase.
%
%   Supported MODE values (English aliases and the labels printed in the
%   device manual are accepted):
%     G1G2             -> [ G1,  G2]
%     G1G2-inverted    -> [ G1, ~G2]  (CCSDS default)
%     G2G1             -> [ G2,  G1]
%     G2G1-inverted    -> [ G2, ~G1]
%     both-inverted    -> [~G1, ~G2]  (extra compatibility option)

%   "inverted" therefore applies to the second transmitted generator
%   stream, matching the modem labels G1G2反 and G2G1反.

    if nargin < 2 || isempty(mode)
        mode = 'auto-ccsds';
    end
    if nargin < 3 || isempty(codeRate)
        codeRate = '1/2';
    end

    key = upper(strtrim(char(string(mode))));
    key = regexprep(key, '[\s_\-\/\\]', '');
    if any(strcmp(key, {'AUTO','AUTOCCSDS','LEGACY'}))
        % Preserve the historical CCSDS implementation: the rate-1/2
        % stream transmits G1/~G2, while the existing punctured modes use
        % their unmodified G1/G2 mother-code ordering.
        if strcmp(strtrim(char(string(codeRate))), '1/2')
            key = 'G1G2INVERTED';
        else
            key = 'G1G2';
        end
    end
    switch key
        case {'G1G2', 'NORMAL'}
            canonicalMode = 'G1G2';
            order = [1 2];
            invertMask = [false false];
        case {'G1G2反', 'G1G2INV', 'G1G2INVERTED', 'G1G2BAR', 'CCSDS'}
            canonicalMode = 'G1G2-inverted';
            order = [1 2];
            invertMask = [false true];
        case 'G2G1'
            canonicalMode = 'G2G1';
            order = [2 1];
            invertMask = [false false];
        case {'G2G1反', 'G2G1INV', 'G2G1INVERTED', 'G2G1BAR'}
            canonicalMode = 'G2G1-inverted';
            order = [2 1];
            invertMask = [false true];
        case {'G1反G2反', 'G1INVERTEDG2INVERTED', ...
                'G1BARG2BAR', 'BOTHINVERTED'}
            canonicalMode = 'G1-inverted-G2-inverted';
            order = [1 2];
            invertMask = [true true];
        otherwise
            error('ccsdsTMConvolutionalOutputTrellis:InvalidMode', ...
                ['Unsupported ConvolutionalG1G2Mode="%s". Use G1G2, ', ...
                 'G1G2-inverted (G1G2反), G2G1, or ', ...
                 'G2G1-inverted (G2G1反), both-inverted ', ...
                 '(G1反G2反), or auto-ccsds.'], ...
                char(string(mode)));
    end

    if ~isstruct(baseTrellis) || ~isfield(baseTrellis, 'outputs') || ...
            ~isfield(baseTrellis, 'numOutputSymbols') || ...
            double(baseTrellis.numOutputSymbols) ~= 4
        error('ccsdsTMConvolutionalOutputTrellis:InvalidTrellis', ...
            'The G1/G2 selector requires a two-output-bit mother trellis.');
    end

    % trellis.outputs stores each two-bit branch label as an octal number.
    % With two bits the octal and decimal numeric values are identical, but
    % reshape explicitly so the state/input-symbol matrix shape is retained.
    raw = baseTrellis.outputs;
    pairBits = de2bi(raw(:), 2, 'left-msb');
    pairBits = pairBits(:, order);
    for iBit = 1:2
        if invertMask(iBit)
            pairBits(:, iBit) = 1 - pairBits(:, iBit);
        end
    end

    trellis = baseTrellis;
    trellis.outputs = reshape(bi2de(pairBits, 'left-msb'), size(raw));
    if ~istrellis(trellis)
        error('ccsdsTMConvolutionalOutputTrellis:InvalidResult', ...
            'The selected G1/G2 mode produced an invalid trellis.');
    end
end
