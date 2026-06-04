function rootDir = reg_setup(seed)
%REG_SETUP Add the parent src/python folder to path and initialize RNG.

    if nargin < 1
        seed = 1;
    end

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(thisDir);
    addpath(rootDir);
    rng(seed);
end
