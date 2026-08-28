function tests = test_ccsds_tm_internal_data_source
%TEST_CCSDS_TM_INTERNAL_DATA_SOURCE Unit tests for modem-style test data.
    tests = functiontests(localfunctions);
end

function testEveryDocumentedInternalType(testCase)
    sourceTypes = {'random','PN7','PN8','PN9','PN10','PN11', ...
        'PN15','PN23','PN31','fixed','incrementing'};
    for k = 1:numel(sourceTypes)
        [bytes, state, info] = ccsdsTMInternalDataSource(37, ...
            sourceTypes{k}, [], struct());
        verifyClass(testCase, bytes, 'uint8');
        verifySize(testCase, bytes, [1 37]);
        verifyTrue(testCase, isstruct(state));
        verifyNotEmpty(testCase, info.CanonicalType);
    end
end

function testPNChunkContinuity(testCase)
    [partA, state] = ccsdsTMInternalDataSource(13, 'PN15', [], struct());
    [partB, state] = ccsdsTMInternalDataSource(17, 'PN15', state, struct()); %#ok<ASGLU>
    whole = ccsdsTMInternalDataSource(30, 'PN15', [], struct());
    verifyEqual(testCase, [partA partB], whole);
end

function testSplitPNInitialStatesAreIndependent(testCase)
    a = ccsdsTMInternalDataSource(32, 'PN23', [], ...
        struct('PNInitialState', hex2dec('7FFFFF')));
    b = ccsdsTMInternalDataSource(32, 'PN23', [], ...
        struct('PNInitialState', 1));
    verifyNotEqual(testCase, a, b);
end

function testFixedPatternContinuity(testCase)
    opt = struct('FixedPattern', uint8([hex2dec('AA') hex2dec('55') hex2dec('F0')]));
    [partA, state] = ccsdsTMInternalDataSource(5, 'fixed', [], opt);
    partB = ccsdsTMInternalDataSource(7, 'fixed', state, opt);
    whole = ccsdsTMInternalDataSource(12, 'fixed', [], opt);
    verifyEqual(testCase, [partA partB], whole);
end

function testIncrementingWrap(testCase)
    [bytes, state] = ccsdsTMInternalDataSource(5, 'incrementing', [], ...
        struct('IncrementStart', 254));
    verifyEqual(testCase, bytes, uint8([254 255 0 1 2]));
    verifyEqual(testCase, state.Counter, 3);
end

function testAllZeroPNStateIsRejected(testCase)
    verifyError(testCase, @() ccsdsTMInternalDataSource(1, 'PN7', [], ...
        struct('PNInitialState', zeros(1,7))), ...
        'ccsdsTMInternalDataSource:InvalidInitialState');
end

function testCustomPolynomialValidation(testCase)
    verifyError(testCase, @() ccsdsTMInternalDataSource(1, 'PN15', [], ...
        struct('PNPolynomialExponents', [15 14])), ...
        'ccsdsTMInternalDataSource:InvalidPolynomial');
end
