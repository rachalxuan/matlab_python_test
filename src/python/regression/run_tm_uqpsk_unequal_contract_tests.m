function report = run_tm_uqpsk_unequal_contract_tests(userOpts)
%RUN_TM_UQPSK_UNEQUAL_CONTRACT_TESTS Fast no-channel unequal-I/Q tests.
%
%   R = RUN_TM_UQPSK_UNEQUAL_CONTRACT_TESTS() checks the public bit
%   contract and UQPSK convolutional 1/2 generator equivalence for the
%   three randomizer configurations.
%
%   R = RUN_TM_UQPSK_UNEQUAL_CONTRACT_TESTS( ...
%       struct('Profile','full','FailOnFailure',true)) additionally checks
%   every formally supported ordinary-TM coding/rate. It does not create a
%   channel or run synchronization/BER acquisition.

    if nargin < 1 || isempty(userOpts)
        userOpts = struct();
    end
    if ~isstruct(userOpts)
        error('run_tm_uqpsk_unequal_contract_tests:InvalidOptions', ...
            'userOpts must be a struct.');
    end

    thisDir = fileparts(mfilename('fullpath'));
    sourceDir = fileparts(thisDir);
    addpath(thisDir);
    addpath(sourceDir);

    opts = struct( ...
        'Profile','quick', ...
        'FailOnFailure',true, ...
        'Verbose',true);
    names = fieldnames(userOpts);
    for k = 1:numel(names)
        if ~isfield(opts, names{k})
            error('run_tm_uqpsk_unequal_contract_tests:UnknownOption', ...
                'Unknown option "%s".', names{k});
        end
        opts.(names{k}) = userOpts.(names{k});
    end
    profile = lower(string(opts.Profile));
    if ~isscalar(profile) || ~any(profile == ["helpers","quick","full"])
        error('run_tm_uqpsk_unequal_contract_tests:InvalidProfile', ...
            'Profile must be "helpers", "quick", or "full".');
    end

    rows = localEmptyRows();
    rows(end+1,1) = localRunCase( ...
        "uqpsk.unequal.bit.hard_round_trip", "bit_contract", "", "", ...
        false, "", @localHardRoundTrip); %#ok<AGROW>
    rows(end+1,1) = localRunCase( ...
        "uqpsk.unequal.bit.soft_round_trip", "bit_contract", "", "", ...
        false, "", @localSoftRoundTrip); %#ok<AGROW>
    rows(end+1,1) = localRunCase( ...
        "uqpsk.unequal.bit.rate_guard", "bit_contract", "", "", ...
        false, "", @localRateGuard); %#ok<AGROW>
    rows(end+1,1) = localRunCase( ...
        "uqpsk.unequal.bit.tail_policy", "bit_contract", "", "", ...
        false, "", @localTailPolicy); %#ok<AGROW>
    rows(end+1,1) = localRunCase( ...
        "uqpsk.unequal.generator.modulation_guard", ...
        "unsupported_guard", "none", "-", false, "afterEncoding", ...
        @localModulationGuard); %#ok<AGROW>

    if profile ~= "helpers"
        cases = localGeneratorCases(profile);
        for k = 1:numel(cases)
            c = cases(k);
            caseId = "uqpsk.unequal.generator." + ...
                lower(string(c.Coding)) + "." + ...
                localToken(c.Rate) + ".random." + ...
                lower(string(c.RandomizerLabel));
            rows(end+1,1) = localRunCase( ...
                caseId, "generator_equivalence", c.Coding, c.Rate, ...
                c.RandomizerEnabled, c.RandomizerPosition, ...
                @() localGeneratorEquivalence(c)); %#ok<AGROW>
        end
    end

    results = struct2table(rows);
    results.Status = repmat("FAIL", height(results), 1);
    results.Status(results.Pass) = "PASS";
    results = movevars(results, ...
        {'CaseId','Status','Pass','Category','Coding','Rate', ...
         'RandomizerEnabled','RandomizerPosition'}, 'Before', 1);

    capabilities = tm_data_path_capabilities();
    report = struct();
    report.ContractVersion = capabilities.ContractVersion;
    report.DataPathMode = capabilities.UnequalDualIQ.DataPathMode;
    report.RRatio = capabilities.UnequalDualIQ.RRatio;
    report.ARatio = capabilities.UnequalDualIQ.ARatio;
    report.Profile = profile;
    report.Results = results;
    report.Pass = all(results.Pass);

    if opts.Verbose
        fprintf(['\nUQPSK unequal dual-I/Q contract: profile=%s, ', ...
            'PASS=%d/%d\n'], char(profile), nnz(results.Pass), ...
            height(results));
        disp(results(:, {'CaseId','Status','Rate', ...
            'DurationSeconds','Details'}));
    end
    if opts.FailOnFailure && ~report.Pass
        failedIds = strjoin(results.CaseId(~results.Pass), ', ');
        error('run_tm_uqpsk_unequal_contract_tests:Failed', ...
            'UQPSK unequal-I/Q contract failed: %s', char(failedIds));
    end
end

function rows = localEmptyRows()
    rows = struct( ...
        'CaseId',{}, ...
        'Category',{}, ...
        'Coding',{}, ...
        'Rate',{}, ...
        'RandomizerEnabled',{}, ...
        'RandomizerPosition',{}, ...
        'Pass',{}, ...
        'DurationSeconds',{}, ...
        'Details',{});
end

function row = localRunCase(caseId, category, coding, rate, ...
        randomizerEnabled, randomizerPosition, testFunction)
    started = tic;
    passed = false;
    try
        details = string(testFunction());
        passed = true;
    catch exception
        details = string(exception.identifier) + ": " + ...
            string(exception.message);
    end
    row = struct( ...
        'CaseId',string(caseId), ...
        'Category',string(category), ...
        'Coding',string(coding), ...
        'Rate',string(rate), ...
        'RandomizerEnabled',logical(randomizerEnabled), ...
        'RandomizerPosition',string(randomizerPosition), ...
        'Pass',passed, ...
        'DurationSeconds',toc(started), ...
        'Details',details);
end

function details = localHardRoundTrip()
    bitsI = int8([0;1;1;0;1;0;0;1]);
    bitsQ = int8([1;0;1;1]);
    expected = int8([0;1;1;1;0;0;1;0;1;0;1;1]);
    grouped = tm_uqpsk_unequal_bit_mux(bitsI, bitsQ, 2);
    localRequire(isequal(grouped, expected), ...
        'Hard-bit order is not I1,I2,Q1,...');
    [actualI, actualQ, dropped] = ...
        tm_uqpsk_unequal_bit_demux(grouped, 2);
    localRequire(dropped == 0 && isequal(actualI, bitsI) && ...
        isequal(actualQ, bitsQ), ...
        'Hard-bit unequal-I/Q round trip changed a rail.');
    details = "exact int8 [I1,I2,Q1,...] round trip";
end

function details = localSoftRoundTrip()
    softI = [-3.5;0.25;7.0;-0.125;1.25;-8.0];
    softQ = [4.0;-1.5;0.75];
    grouped = tm_uqpsk_unequal_bit_mux(softI, softQ);
    [actualI, actualQ] = tm_uqpsk_unequal_bit_demux(grouped);
    localRequire(isequal(actualI, softI) && isequal(actualQ, softQ), ...
        'Soft-value unequal-I/Q round trip changed a rail.');
    details = "exact double-valued round trip";
end

function details = localRateGuard()
    localAssertThrows( ...
        @() tm_uqpsk_unequal_bit_mux(int8([0;1;0]), int8([1;0])), ...
        'tm_uqpsk_unequal_bit_mux:RateMismatch');
    details = "rejects any input that is not I:Q=2:1";
end

function details = localTailPolicy()
    x = int8([0;1;1;1]);
    localAssertThrows( ...
        @() tm_uqpsk_unequal_bit_demux(x), ...
        'tm_uqpsk_unequal_bit_demux:IncompleteGroup');
    [bitsI, bitsQ, dropped] = ...
        tm_uqpsk_unequal_bit_demux(x, 2, 'drop');
    localRequire(dropped == 1 && ...
        isequal(bitsI, int8([0;1])) && isequal(bitsQ, int8(1)), ...
        'Drop mode did not remove exactly one incomplete tail value.');
    details = "strict rejects tail; RX tolerance drops one value";
end

function details = localModulationGuard()
    args = localGeneratorArgs("none", struct( ...
        'NumBytesInTransferFrame',26), false, "afterEncoding");
    args = localReplaceNameValue(args, 'Modulation', 'QPSK');
    generator = ccsdsTMWaveformGenerator(args{:});
    input = zeros(generator.NumInputBits, 1, 'int8');
    localAssertThrows(@() generator(input), ...
        'ccsdsTMWaveformGenerator:UnequalSplitRequiresUQPSK');
    details = "unequalDualIQ cannot silently use equal-rate modulation";
end

function cases = localGeneratorCases(profile)
    profiles = localCodingProfiles();
    if profile == "quick"
        keep = strcmpi(string({profiles.Coding}), "convolutional") & ...
            string({profiles.Rate}) == "1/2";
        profiles = profiles(keep);
    end

    randomizers = struct( ...
        'Label',{"off","after","before"}, ...
        'Enabled',{false,true,true}, ...
        'Position',{"afterEncoding","afterEncoding","beforeEncoding"});
    cases = struct( ...
        'Coding',{},'Rate',{},'Extra',{}, ...
        'RandomizerLabel',{},'RandomizerEnabled',{}, ...
        'RandomizerPosition',{});
    for iProfile = 1:numel(profiles)
        for iRandomizer = 1:numel(randomizers)
            cases(end+1,1) = struct( ... %#ok<AGROW>
                'Coding',profiles(iProfile).Coding, ...
                'Rate',profiles(iProfile).Rate, ...
                'Extra',profiles(iProfile).Extra, ...
                'RandomizerLabel',randomizers(iRandomizer).Label, ...
                'RandomizerEnabled',randomizers(iRandomizer).Enabled, ...
                'RandomizerPosition',randomizers(iRandomizer).Position);
        end
    end
end

function profiles = localCodingProfiles()
    capabilities = tm_data_path_capabilities();
    profiles = struct('Coding',{},'Rate',{},'Extra',{});
    profiles(end+1,1) = localProfile( ... %#ok<AGROW>
        "none", "-", struct('NumBytesInTransferFrame',26));

    for rs = capabilities.SupportedRSProfiles
        extra = struct( ...
            'RSMessageLength', double(rs.RSMessageLength), ...
            'RSInterleavingDepth', double(rs.RSInterleavingDepth), ...
            'IsRSMessageShortened', logical(rs.IsRSMessageShortened));
        if rs.IsRSMessageShortened
            extra.RSShortenedMessageLength = ...
                double(rs.RSShortenedMessageLength);
        end
        profiles(end+1,1) = localProfile("RS", rs.Rate, extra); %#ok<AGROW>
    end
    for rate = capabilities.SupportedConvolutionalRates
        profiles(end+1,1) = localProfile( ... %#ok<AGROW>
            "convolutional", rate, struct( ...
                'NumBytesInTransferFrame', localConvolutionalFrameBytes(rate), ...
                'ConvolutionalCodeRate', char(rate)));
    end
    for rate = capabilities.SupportedLDPCRates
        profiles(end+1,1) = localProfile("LDPC", rate, struct( ... %#ok<AGROW>
            'CodeRate',char(rate), ...
            'NumBitsInInformationBlock',1024, ...
            'IsLDPCOnSMTF',false));
    end
    for rate = capabilities.SupportedTurboRates
        profiles(end+1,1) = localProfile("turbo", rate, struct( ... %#ok<AGROW>
            'CodeRate',char(rate), ...
            'NumBitsInInformationBlock',1784));
    end
end

function profile = localProfile(coding, rate, extra)
    profile = struct( ...
        'Coding',char(coding), ...
        'Rate',string(rate), ...
        'Extra',extra);
end

function frameBytes = localConvolutionalFrameBytes(rate)
    switch char(rate)
        case {'1/2','2/3'}
            frameBytes = 26;
        case '3/4'
            frameBytes = 41;
        case '5/6'
            frameBytes = 46;
        case '7/8'
            frameBytes = 101;
        otherwise
            error('run_tm_uqpsk_unequal_contract_tests:UnknownRate', ...
                'No aligned contract frame length for rate "%s".', rate);
    end
end

function details = localGeneratorEquivalence(testCase)
    unequalArgs = localGeneratorArgs( ...
        testCase.Coding, testCase.Extra, ...
        testCase.RandomizerEnabled, testCase.RandomizerPosition);
    singleArgs = localReplaceNameValue( ...
        unequalArgs, 'DataPathMode', 'single');

    unequalGenerator = ccsdsTMWaveformGenerator(unequalArgs{:});
    singleGeneratorI = ccsdsTMWaveformGenerator(singleArgs{:});
    singleGeneratorQ = ccsdsTMWaveformGenerator(singleArgs{:});
    frameBits = singleGeneratorI.NumInputBits;
    localRequire(unequalGenerator.NumInputBits == 3*frameBits, ...
        'unequalDualIQ NumInputBits is not three single TM frames.');

    indexI = (0:2*frameBits-1).';
    indexQ = (0:frameBits-1).';
    messageI = int8(mod(indexI + floor(indexI/7), 2));
    messageQ = int8(mod(floor(indexQ/3) + floor(indexQ/11) + 1, 2));

    [~, unequalEncoded] = unequalGenerator([messageI;messageQ]);
    [~, encodedI] = singleGeneratorI(messageI);
    [~, encodedQ] = singleGeneratorQ(messageQ);
    expected = tm_uqpsk_unequal_bit_mux( ...
        int8(encodedI), int8(encodedQ), 2);
    localRequire(isequal(int8(unequalEncoded), expected), ...
        ['unequalDualIQ differs from independent I/Q encoders followed ', ...
         'by [I1,I2,Q1,...] grouping.']);

    [actualI, actualQ] = ...
        tm_uqpsk_unequal_bit_demux(int8(unequalEncoded), 2);
    localRequire(isequal(actualI, int8(encodedI)) && ...
        isequal(actualQ, int8(encodedQ)), ...
        'Encoded rail values did not survive unequal demux.');
    details = sprintf('%d I + %d Q input bits -> %d grouped coded bits', ...
        numel(messageI), numel(messageQ), numel(unequalEncoded));
end

function args = localGeneratorArgs(coding, extra, enabled, position)
    args = { ...
        'WaveformSource','synchronization and channel coding', ...
        'ChannelCoding',char(coding), ...
        'Modulation','UQPSK', ...
        'DataPathMode','unequalDualIQ', ...
        'RandomizerEnabled',logical(enabled), ...
        'RandomizerFECPosition',char(position), ...
        'HasASM',true, ...
        'SamplesPerSymbol',2};
    names = fieldnames(extra);
    for k = 1:numel(names)
        args = [args, {names{k}, extra.(names{k})}]; %#ok<AGROW>
    end
end

function args = localReplaceNameValue(args, name, value)
    index = find(strcmpi(args(1:2:end), name), 1, 'first');
    if isempty(index)
        args = [args, {name,value}];
    else
        args{2*index} = value;
    end
end

function token = localToken(value)
    token = lower(string(value));
    token = regexprep(token, '[^a-zA-Z0-9]+', '_');
    token = regexprep(token, '^_+|_+$', '');
    if strlength(token) == 0
        token = "none";
    end
end

function localAssertThrows(functionHandle, expectedIdentifier)
    try
        functionHandle();
    catch exception
        localRequire(strcmp(exception.identifier, expectedIdentifier), ...
            sprintf('Expected "%s", got "%s": %s', ...
                expectedIdentifier, exception.identifier, ...
                exception.message));
        return;
    end
    error('run_tm_uqpsk_unequal_contract_tests:ExpectedErrorNotThrown', ...
        'Expected error "%s" was not thrown.', expectedIdentifier);
end

function localRequire(condition, message)
    if ~condition
        error('run_tm_uqpsk_unequal_contract_tests:ContractViolation', ...
            '%s', message);
    end
end
