function Data = readData(filename,rows,cols)
    fileID = fopen(filename, 'r');      % Open the file
    if fileID == -1
        error('Unable to open file: %s', filename);
    end
    % Assume the file contains floating-point numbers, read the data into a matrix
    Data = fscanf(fileID, '%f', [cols,rows])'; 
    fclose(fileID);                     % Close the file
end



