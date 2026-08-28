function result = test_tpc_decoded_frame_aligner()
%TEST_TPC_DECODED_FRAME_ALIGNER Reproduce the repeated-zero false lock.

    bitsPerFrame = 16200;
    numFrames = 37;
    bits = int8(randi([0 1], bitsPerFrame*numFrames, 1));
    ids = [100; 73; (2:36).'];
    for iFrame = 1:numFrames
        bits((iFrame-1)*bitsPerFrame + (25:32)) = ...
            int8(de2bi(ids(iFrame), 8, 'left-msb')).';
    end

    % At shift 100, force the sampled VCFC field to all zero.  The legacy
    % score counted 36 occurrences of ID 0 and preferred this false phase
    % over the correct 35-frame sequence 2,3,...,36.
    falseShift = 100;
    for iFrame = 1:numFrames-1
        idx = falseShift + (iFrame-1)*bitsPerFrame + (25:32);
        bits(idx) = 0;
    end

    [aligned, info] = HelperTMTPCDecodedFrameAligner( ...
        bits, bitsPerFrame, 0:36, 'Debug', true);

    assert(~info.Applied, ...
        'A confirmed decoder boundary was incorrectly replaced.');
    assert(info.BaselineMaxRun == 35, ...
        'Expected the valid VCFC sequence 2..36 at shift zero.');
    assert(isequal(aligned, bits), ...
        'The confirmed baseline stream must remain bit-identical.');

    % Also verify that a genuinely shifted stream is corrected when shift
    % zero has no confirmed run.
    prefix = int8([1; 0; 1; 1; 0; 0; 1]);
    shifted = [prefix; bits];
    [realigned, shiftedInfo] = HelperTMTPCDecodedFrameAligner( ...
        shifted, bitsPerFrame, 0:36, 'Debug', true);
    assert(shiftedInfo.Applied && shiftedInfo.SelectedShift == numel(prefix), ...
        'A real TPC decoded-bit offset was not recovered.');
    assert(isequal(realigned, bits), ...
        'Recovered TPC stream does not match the expected frame boundary.');

    result = table( ...
        [info.Applied; shiftedInfo.Applied], ...
        [info.SelectedShift; shiftedInfo.SelectedShift], ...
        [info.BaselineMaxRun; shiftedInfo.BaselineMaxRun], ...
        [info.CandidateMaxRun; shiftedInfo.CandidateMaxRun], ...
        string([info.Reason; shiftedInfo.Reason]), ...
        'VariableNames', {'Applied','SelectedShift','BaselineRun', ...
        'CandidateRun','Reason'});
    disp(result);
end
