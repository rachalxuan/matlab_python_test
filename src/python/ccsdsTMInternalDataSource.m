function [bytes, nextState, info] = ccsdsTMInternalDataSource(numBytes, sourceType, state, opt)
%CCSDSTMINTERNALDATASOURCE Generate receiver-test data for a TM data field.
%
%   [BYTES,NEXTSTATE,INFO] = ccsdsTMInternalDataSource(NUMBYTES,TYPE,...)
%   implements the internal-source choices exposed by the reference modem:
%   random, PN7/8/9/10/11/15/23/31, fixed code, and incrementing code.
%
%   The PN defaults use common maximal-length Fibonacci recurrences.  The
%   equipment manual lists the PN orders but does not specify polynomial,
%   initial state, shift direction, or output polarity, so all convention-
%   dependent values can be overridden through OPT:
%       PNPolynomialExponents  e.g. [15 14 0]
%       PNInitialState         all-ones by default; bit vector/scalar/hex
%       PNInvertOutput         false by default
%       FixedPattern           uint8 pattern, default hex 55
%       IncrementStart         first counter byte, default 0
%
%   STATE is the NEXTSTATE returned by an earlier call.  Passing STATE
%   continuously across TM frames preserves PN/counter continuity while the
%   caller inserts ASM and TM headers independently.

    if nargin < 3
        state = [];
    end
    if nargin < 4 || isempty(opt)
        opt = struct();
    end
    validateattributes(numBytes, {'numeric'}, ...
        {'scalar','real','finite','integer','nonnegative'}, ...
        mfilename, 'numBytes', 1);

    [canonicalType, degree] = localCanonicalType(sourceType);
    numBytes = double(numBytes);

    switch canonicalType
        case 'random'
            bytes = uint8(randi([0 255], 1, numBytes));
            nextState = struct('Mode', canonicalType);
            info = localBaseInfo(canonicalType, numBytes);
            info.Description = 'independent uniformly distributed octets';

        case {'PN7','PN8','PN9','PN10','PN11','PN15','PN23','PN31'}
            exponents = localPNExponents(degree, opt);
            invertOutput = localLogicalOption(opt, 'PNInvertOutput', false);
            reg = localPNRegister(state, canonicalType, degree, opt);

            bits = zeros(1, 8*numBytes, 'uint8');
            feedbackExponents = exponents(exponents > 0 & exponents < degree);
            for k = 1:numel(bits)
                bits(k) = reg(1);
                feedback = logical(reg(1));
                for iTap = 1:numel(feedbackExponents)
                    feedback = xor(feedback, ...
                        logical(reg(feedbackExponents(iTap) + 1)));
                end
                reg = [reg(2:end), uint8(feedback)]; %#ok<AGROW>
            end
            if invertOutput
                bits = uint8(~logical(bits));
            end
            bytes = localBitsToBytesMSB(bits);
            nextState = struct( ...
                'Mode', canonicalType, ...
                'Register', uint8(reg), ...
                'PolynomialExponents', double(exponents), ...
                'InvertOutput', logical(invertOutput));
            info = localBaseInfo(canonicalType, numBytes);
            info.Degree = degree;
            info.PolynomialExponents = double(exponents);
            info.Polynomial = localPolynomialText(exponents);
            info.SequencePeriodBits = 2^degree - 1;
            info.FinalRegisterHex = localBitsToHex(reg);
            info.OutputInverted = logical(invertOutput);
            info.BitPacking = 'MSB-first within each octet';

        case 'fixed'
            pattern = localFixedPattern(opt);
            offset = 0;
            if isstruct(state) && isfield(state, 'Mode') && ...
                    strcmpi(string(state.Mode), canonicalType) && ...
                    isfield(state, 'PatternOffset')
                offset = mod(round(double(state.PatternOffset)), numel(pattern));
            end
            indices = mod(offset + (0:numBytes-1), numel(pattern)) + 1;
            bytes = uint8(pattern(indices));
            nextState = struct('Mode', canonicalType, ...
                'PatternOffset', mod(offset + numBytes, numel(pattern)));
            info = localBaseInfo(canonicalType, numBytes);
            info.FixedPatternHex = upper(reshape(dec2hex(pattern,2).',1,[]));

        case 'incrementing'
            counter = localIncrementStart(opt);
            if isstruct(state) && isfield(state, 'Mode') && ...
                    strcmpi(string(state.Mode), canonicalType) && ...
                    isfield(state, 'Counter')
                counter = mod(round(double(state.Counter)), 256);
            end
            bytes = uint8(mod(counter + (0:numBytes-1), 256));
            nextState = struct('Mode', canonicalType, ...
                'Counter', mod(counter + numBytes, 256));
            info = localBaseInfo(canonicalType, numBytes);
            info.StartByte = counter;
            info.NextByte = nextState.Counter;

        otherwise
            error('ccsdsTMInternalDataSource:InternalMode', ...
                'Unhandled internal data source "%s".', canonicalType);
    end

    if localLogicalOption(opt, 'Debug', false)
        previewCount = min(16, numel(bytes));
        preview = '';
        if previewCount > 0
            preview = upper(strjoin(cellstr(dec2hex(bytes(1:previewCount),2)), ' '));
        end
        if startsWith(canonicalType, 'PN')
            fprintf('[TM internal source] type=%s bytes=%d poly=%s invert=%d first=%s\n', ...
                canonicalType, numBytes, info.Polynomial, ...
                info.OutputInverted, preview);
        else
            fprintf('[TM internal source] type=%s bytes=%d first=%s\n', ...
                canonicalType, numBytes, preview);
        end
    end
end

function info = localBaseInfo(canonicalType, numBytes)
    info = struct();
    info.CanonicalType = canonicalType;
    info.NumBytesGenerated = double(numBytes);
end

function [canonicalType, degree] = localCanonicalType(value)
    key = regexprep(upper(strtrim(char(string(value)))), '[^A-Z0-9]', '');
    degree = NaN;
    switch key
        case {'','RANDOM','RANDOMFRAME','RANDOMFRAMEDATA','RAND'}
            canonicalType = 'random';
        case {'PN7','PRBS7'}
            canonicalType = 'PN7'; degree = 7;
        case {'PN8','PRBS8'}
            canonicalType = 'PN8'; degree = 8;
        case {'PN9','PRBS9'}
            canonicalType = 'PN9'; degree = 9;
        case {'PN10','PRBS10'}
            canonicalType = 'PN10'; degree = 10;
        case {'PN11','PRBS11'}
            canonicalType = 'PN11'; degree = 11;
        case {'PN15','PRBS15'}
            canonicalType = 'PN15'; degree = 15;
        case {'PN23','PRBS23'}
            canonicalType = 'PN23'; degree = 23;
        case {'PN31','PRBS31'}
            canonicalType = 'PN31'; degree = 31;
        case {'FIXED','FIXEDCODE','CONSTANT','CONST'}
            canonicalType = 'fixed';
        case {'INCREMENT','INCREMENTING','INCREMENTINGCODE','COUNTER'}
            canonicalType = 'incrementing';
        otherwise
            error('ccsdsTMInternalDataSource:InvalidSourceType', ...
                ['Unsupported sourceType="%s". Use random, PN7, PN8, ', ...
                 'PN9, PN10, PN11, PN15, PN23, PN31, fixed, or ', ...
                 'incrementing.'], char(string(value)));
    end
end

function exponents = localPNExponents(degree, opt)
    defaults = struct( ...
        'n7',  [7 6 0], ...
        'n8',  [8 6 5 4 0], ...
        'n9',  [9 5 0], ...
        'n10', [10 7 0], ...
        'n11', [11 9 0], ...
        'n15', [15 14 0], ...
        'n23', [23 18 0], ...
        'n31', [31 28 0]);
    fieldName = sprintf('n%d', degree);
    exponents = defaults.(fieldName);
    if isfield(opt, 'PNPolynomialExponents') && ...
            ~isempty(opt.PNPolynomialExponents)
        exponents = double(opt.PNPolynomialExponents(:).');
    end
    if any(~isfinite(exponents)) || any(exponents ~= floor(exponents)) || ...
            ~ismember(degree, exponents) || ~ismember(0, exponents) || ...
            any(exponents < 0 | exponents > degree) || ...
            numel(unique(exponents)) ~= numel(exponents)
        error('ccsdsTMInternalDataSource:InvalidPolynomial', ...
            ['PNPolynomialExponents must contain unique integer ', ...
             'exponents in [0,%d], including %d and 0.'], degree, degree);
    end
    exponents = sort(exponents, 'descend');
end

function reg = localPNRegister(state, canonicalType, degree, opt)
    if isstruct(state) && isfield(state, 'Mode') && ...
            strcmpi(string(state.Mode), canonicalType) && ...
            isfield(state, 'Register')
        reg = uint8(state.Register(:).' ~= 0);
    else
        initial = [];
        if isfield(opt, 'PNInitialState') && ~isempty(opt.PNInitialState)
            initial = opt.PNInitialState;
        end
        reg = localInitialBits(initial, degree);
    end
    if numel(reg) ~= degree || ~any(reg)
        error('ccsdsTMInternalDataSource:InvalidInitialState', ...
            'PN initial state must contain %d bits and cannot be all zero.', degree);
    end
end

function bits = localInitialBits(value, degree)
    if isempty(value)
        bits = ones(1, degree, 'uint8');
        return;
    end
    if ischar(value) || isstring(value)
        textValue = upper(strtrim(char(string(value))));
        if startsWith(textValue, '0X')
            textValue = textValue(3:end);
        end
        if ~isempty(regexp(textValue, '^[01]+$', 'once')) && ...
                numel(textValue) == degree
            bits = uint8(textValue - '0');
            return;
        end
        scalarValue = hex2dec(textValue);
    elseif isnumeric(value) || islogical(value)
        if isscalar(value)
            scalarValue = double(value);
        else
            bits = uint8(value(:).' ~= 0);
            if numel(bits) ~= degree
                error('ccsdsTMInternalDataSource:InitialStateLength', ...
                    'PNInitialState vector must contain %d bits.', degree);
            end
            return;
        end
    else
        error('ccsdsTMInternalDataSource:InvalidInitialStateType', ...
            'PNInitialState must be a bit vector, scalar integer, or hex text.');
    end
    if ~isscalar(scalarValue) || ~isfinite(scalarValue) || ...
            scalarValue < 0 || scalarValue ~= floor(scalarValue) || ...
            scalarValue >= 2^degree
        error('ccsdsTMInternalDataSource:InvalidInitialStateScalar', ...
            'PNInitialState scalar must be an integer in [1,2^%d-1].', degree);
    end
    bits = zeros(1, degree, 'uint8');
    scalarValue = uint64(scalarValue);
    for k = 1:degree
        bits(k) = uint8(bitget(scalarValue, degree-k+1));
    end
end

function pattern = localFixedPattern(opt)
    value = uint8(hex2dec('55'));
    if isfield(opt, 'FixedPattern') && ~isempty(opt.FixedPattern)
        value = opt.FixedPattern;
    end
    if ischar(value) || isstring(value)
        textValue = upper(regexprep(strtrim(char(string(value))), ...
            '[^0-9A-F]', ''));
        if isempty(textValue) || mod(numel(textValue), 2) ~= 0
            error('ccsdsTMInternalDataSource:InvalidFixedPattern', ...
                'FixedPattern hex text must contain complete octets.');
        end
        pattern = uint8(sscanf(textValue, '%2x').');
    else
        validateattributes(value, {'numeric','logical'}, ...
            {'vector','integer','nonnegative','<=',255}, ...
            mfilename, 'FixedPattern');
        pattern = uint8(value(:).');
    end
    if isempty(pattern)
        error('ccsdsTMInternalDataSource:EmptyFixedPattern', ...
            'FixedPattern cannot be empty.');
    end
end

function counter = localIncrementStart(opt)
    counter = 0;
    if isfield(opt, 'IncrementStart') && ~isempty(opt.IncrementStart)
        counter = double(opt.IncrementStart);
    end
    if ~isscalar(counter) || ~isfinite(counter) || counter ~= floor(counter) || ...
            counter < 0 || counter > 255
        error('ccsdsTMInternalDataSource:InvalidIncrementStart', ...
            'IncrementStart must be an integer in [0,255].');
    end
end

function value = localLogicalOption(opt, name, defaultValue)
    value = logical(defaultValue);
    if isfield(opt, name) && ~isempty(opt.(name))
        raw = opt.(name);
        if islogical(raw) || isnumeric(raw)
            value = logical(raw);
        else
            key = lower(strtrim(char(string(raw))));
            if any(strcmp(key, {'1','true','on','yes'}))
                value = true;
            elseif any(strcmp(key, {'0','false','off','no'}))
                value = false;
            else
                error('ccsdsTMInternalDataSource:InvalidLogicalOption', ...
                    '%s must be logical on/off.', name);
            end
        end
    end
end

function bytes = localBitsToBytesMSB(bits)
    bits = uint8(bits(:).' ~= 0);
    if mod(numel(bits),8) ~= 0
        error('ccsdsTMInternalDataSource:InternalAlignment', ...
            'Generated PN bit count is not octet aligned.');
    end
    bytes = zeros(1, numel(bits)/8, 'uint8');
    for iByte = 1:numel(bytes)
        byteBits = bits((iByte-1)*8 + (1:8));
        value = uint8(0);
        for iBit = 1:8
            value = bitor(value, bitshift(byteBits(iBit), 8-iBit));
        end
        bytes(iByte) = value;
    end
end

function textValue = localPolynomialText(exponents)
    terms = cell(1, numel(exponents));
    for k = 1:numel(exponents)
        if exponents(k) == 0
            terms{k} = '1';
        elseif exponents(k) == 1
            terms{k} = 'x';
        else
            terms{k} = sprintf('x^%d', exponents(k));
        end
    end
    textValue = strjoin(terms, '+');
end

function hexText = localBitsToHex(bits)
    bits = uint8(bits(:).' ~= 0);
    padded = [zeros(1, mod(4-mod(numel(bits),4),4), 'uint8'), bits];
    values = zeros(1, numel(padded)/4, 'uint8');
    for k = 1:numel(values)
        nibble = padded((k-1)*4 + (1:4));
        values(k) = uint8(8*nibble(1) + 4*nibble(2) + ...
            2*nibble(3) + nibble(4));
    end
    hexText = upper(reshape(dec2hex(values,1).',1,[]));
end
