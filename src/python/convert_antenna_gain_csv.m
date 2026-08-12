%% Convert complex antenna-pattern CSV files to three-column real-gain CSV files

inputDir = 'E:\matlab_project\antenna_gain\antenna_gain';
outputDir = 'E:\matlab_project\antenna_gain\antenna_gain_real';

% true  : output dB(RealizedGainTotal), matching AntennaPattern-example.csv
% false : output the linear real magnitude after the square-root operation
 outputAsDb = true;

assert(isfolder(inputDir), 'Input folder does not exist: %s', inputDir);

if ~isfolder(outputDir)
    mkdir(outputDir);
end

files = dir(fullfile(inputDir, '*.csv'));
assert(~isempty(files), 'No CSV files found in: %s', inputDir);

fprintf('Input : %s\n', inputDir);
fprintf('Output: %s\n', outputDir);
fprintf('Files : %d\n\n', numel(files));

for fileIndex = 1:numel(files)
    inputFile = fullfile(files(fileIndex).folder, files(fileIndex).name);
    outputFile = fullfile(outputDir, files(fileIndex).name);

    raw = readmatrix(inputFile, 'NumHeaderLines', 1, 'OutputType', 'double');

    % Original layout:
    %   1:7   = Freq, Phi, Theta, Re(E_theta), Im(E_theta), Re(E_phi), Im(E_phi)
    %   8     = empty separator
    %   9:15  = the same fields for the second Phi cut
    if size(raw, 2) < 15
        error('Unexpected column count in %s: got %d, expected at least 15.', ...
            inputFile, size(raw, 2));
    end

    phi = [raw(:,2); raw(:,10)];
    theta = [raw(:,3); raw(:,11)];

    reETheta = [raw(:,4); raw(:,12)];
    imETheta = [raw(:,5); raw(:,13)];
    reEPhi = [raw(:,6); raw(:,14)];
    imEPhi = [raw(:,7); raw(:,15)];

    % Magnitudes of the two complex polarization components:
    %   |E_theta| = sqrt(Re(E_theta)^2 + Im(E_theta)^2)
    %   |E_phi|   = sqrt(Re(E_phi)^2   + Im(E_phi)^2)
    eThetaMagnitude = hypot(reETheta, imETheta);
    ePhiMagnitude = hypot(reEPhi, imEPhi);

    % Total real field magnitude:
    %   |E_total| = sqrt(|E_theta|^2 + |E_phi|^2)
    totalMagnitude = hypot(eThetaMagnitude, ePhiMagnitude);

    valid = isfinite(phi) & isfinite(theta) & isfinite(totalMagnitude);
    phi = phi(valid);
    theta = theta(valid);
    totalMagnitude = totalMagnitude(valid);

     if outputAsDb
         gainValue = 20*log10(max(totalMagnitude, realmin('double')));
         gainColumnName = 'dB(RealizedGainTotal)';
    else
        gainValue = totalMagnitude;
        gainColumnName = 'RealizedGainTotalMagnitude';
     end

    % Match the example ordering: Theta first, then Phi.
    outputData = sortrows([phi, theta, gainValue], [2 1]);

    outputTable = array2table(outputData);
    outputTable.Properties.VariableNames = { ...
        'Phi[deg]', 'Theta[deg]', gainColumnName};

    writetable(outputTable, outputFile);

    fprintf('[%02d/%02d] %s -> %d rows\n', ...
        fileIndex, numel(files), files(fileIndex).name, height(outputTable));
end

fprintf('\nConversion complete. Output folder:\n%s\n', outputDir);
