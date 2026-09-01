
function [lowerIndex,upperIndex] = dataQueries(target,dataScope)

% Function: Calculate the range of the target value within the array and return the indices within the data range
% Input values:
% target: The target value to be searched,
% dataScope: The array where the target value is located
% Return values:
% lowerIndex: The lower index of the target value
% upperIndex: The upper index of the target value

       if (target <min(dataScope) || target > max(dataScope))
           error('Unsupported data.');
       end
        idx = find(dataScope >= target, 1);  % If the target value is exactly in the array, find its index
        if dataScope(idx) == target          % If the target value is in the array, return its index directly
            lowerIndex = idx;
            upperIndex = idx;
        else
            % If the target value is not in the array, find the position where it should be inserted
            % idx is the position where the target value should be inserted, idx-1 is the index to the left of the target value
            % Check if the target value is within the range of the array
            if idx == 1
                % The target value is less than the minimum value in the array
                lowerIndex = 1;
                upperIndex = 1;
            elseif idx == length(dataScope) + 1
                % The target value is greater than the maximum value in the array
                lowerIndex = length(dataScope);
                upperIndex = length(dataScope);
            else
                % The target value is within the range of the array, find the closest values
                lowerIndex = idx - 1;
                upperIndex = idx;
            end
        end
end

