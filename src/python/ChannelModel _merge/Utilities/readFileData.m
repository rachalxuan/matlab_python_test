
function Data = readFileData(P_scope_P_filenames,p,rows,cols)
    % Use a switch statement to map p to the corresponding file index
    switch p
        case 1
            filename = P_scope_P_filenames{1};
        case 2
            filename = P_scope_P_filenames{2};
        case 3
            filename = P_scope_P_filenames{3};
        case 4
            filename = P_scope_P_filenames{4};
        case 5
            filename = P_scope_P_filenames{5};
        case 6
            filename = P_scope_P_filenames{6};
        case 7
            filename = P_scope_P_filenames{7};
        case 8
            filename = P_scope_P_filenames{8};
        case 9
            filename = P_scope_P_filenames{9};
        case 10
            filename = P_scope_P_filenames{10};
        case 11
            filename = P_scope_P_filenames{11};
        case 12
            filename = P_scope_P_filenames{12};
        case 13
            filename = P_scope_P_filenames{13};
        case 14
            filename = P_scope_P_filenames{14};
        case 15
            filename = P_scope_P_filenames{15};
        case 16
            filename = P_scope_P_filenames{16};
        case 17
            filename = P_scope_P_filenames{17};
        case 18
            filename = P_scope_P_filenames{18};
        case 19
            filename = P_scope_P_filenames{19};
        case 20
            filename = P_scope_P_filenames{20};
        case 21
            filename = P_scope_P_filenames{21};
        case 22
            filename = P_scope_P_filenames{22};
        otherwise
            error('Unknown exceedance probability: %f', p);
    end     
    fileID = fopen(filename, 'r');      % Open the file
    if fileID == -1
        error('Unable to open file: %s', filename);
    end
    % Assume the file contains floating-point numbers, read the data into a matrix
    Data = fscanf(fileID, '%f', [cols,rows])'; 
    fclose(fileID);                     % Close the file
end

