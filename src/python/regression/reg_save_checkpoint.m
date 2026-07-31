function reg_save_checkpoint(checkpointPath, state)
%REG_SAVE_CHECKPOINT Save checkpoint only after a complete temporary file exists.

    outputDir = fileparts(checkpointPath);
    if ~isfolder(outputDir)
        mkdir(outputDir);
    end

    temporaryPath = [tempname(outputDir), '.mat'];
    cleanup = onCleanup(@() localDeleteIfPresent(temporaryPath));
    % Metrics-only checkpoints remain well below the v7 2 GB limit. The
    % classic MAT format is substantially faster for nested struct arrays
    % than HDF5/v7.3, which otherwise dominates short regression cases.
    save(temporaryPath, 'state', '-v7');
    [ok, message] = movefile(temporaryPath, checkpointPath, 'f');
    if ~ok
        error('reg_save_checkpoint:MoveFailed', ...
            'Could not replace checkpoint "%s": %s', checkpointPath, message);
    end
    clear cleanup;
end

function localDeleteIfPresent(pathValue)
    if exist(pathValue, 'file') == 2
        delete(pathValue);
    end
end
