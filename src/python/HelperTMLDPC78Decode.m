function [message, diagnostic, model] = HelperTMLDPC78Decode(llr, maxIterations)
%HELPERTMLDPC78DECODE Isolated CCSDS (8160,7136) experiment; NOT the default RX.
%   Input: 8160-by-N aligned, derandomized codeword LLRs, positive = bit 0.
%   No ASM, TX reference, phase search, reliability rescaling or frame gating.
%   [~,~,MODEL] = HelperTMLDPC78Decode() returns the graph and index contract.
%   The original 1022-by-8176 graph has rank 1020. DecoderConfig's N-M is
%   NOT an information-bit index contract: use the explicit indices below.
%
%   CCSDS 131.0-B-3, sections 7.3.2--7.3.5, Table 7-1:
%   https://ccsds.org/Pubs/131x0b3s.pdf
%   TX = [message(7136); parity(1022); zero-fill(2)]. The 18 leading
%   virtual zero bits are shortened, NOT punctured. Eliminate their columns
%   exactly (known zero RHS), rather than adding zero LLRs or a tuned prior.
%   The two transmitted fill bits are outside the LDPC graph. Their received
%   hard decisions are reported, not used as parity observations.
%
%   Graph parity alone does not prove membership of the encoder's (8176,7154)
%   subcode, or correct information. The regression separately re-encodes the
%   decoded message and compares all code bits, without using TX truth to decode.

persistent cachedModel cachedConfig
if isempty(cachedModel)
    cachedModel = localModel();
    cachedConfig = ldpcDecoderConfig(cachedModel.H, 'bp');
end
model = cachedModel;
message = int8([]);
diagnostic = struct();
if nargin == 0, return; end
if nargin < 2, maxIterations = 20; end
validateattributes(llr, {'double','single'}, ...
    {'real','finite','2d','nonempty','nrows',8160}, mfilename, 'llr');
validateattributes(maxIterations, {'numeric'}, ...
    {'real','finite','scalar','integer','positive'}, mfilename, 'maxIterations');

% No gain/clipping change: only the standard-defined wire-to-graph projection.
graphLLR = double(llr(model.GraphToWireIndices,:));
t = tic;
[decoded, iterations, checks] = ldpcDecode(graphLLR, cachedConfig, ...
    maxIterations, 'OutputFormat','whole', 'Termination','early', ...
    'Multithreaded',true);
elapsed = toc(t);
message = int8(decoded(model.InformationIndices,:));
diagnostic = struct( ...
    'Algorithm','bp', 'MatrixMode',model.MatrixMode, ...
    'ActualIterations',double(iterations), ...
    'ParityCheckWeight',sum(checks ~= 0,1), ...
    'GraphParityPassed',all(checks == 0,1), ...
    'ReceivedFillHardErrors',sum(llr(model.FillWireIndices,:) < 0,1), ...
    'DecodeSeconds',elapsed, ...
    'DecodedCoreBits',int8(decoded));
end

function model = localModel()
% First-row positions, zero-based. Subsequent rows shift RIGHT, not left.
p1 = [0 176;12 239;0 352;24 431;0 392;151 409;0 351;9 359; ...
    0 307;53 329;0 207;18 281;0 399;202 457;0 247;36 261];
p2 = [99 471;130 473;198 435;260 478;215 420;282 481;48 396;193 445; ...
    273 430;302 451;96 379;191 386;244 467;364 470;51 382;192 414];
positions = cat(3,p1,p2);
rows = zeros(32704,1); cols = rows;
offset = 0;
for blockRow = 1:2
    for blockCol = 1:16
        for edge = 1:2
            indices = offset+(1:511);
            rows(indices) = (blockRow-1)*511+(1:511);
            cols(indices) = (blockCol-1)*511+ ...
                mod((0:510)+positions(blockCol,edge,blockRow),511)+1;
            offset = offset+511;
        end
    end
end
Hfull = sparse(rows,cols,true,1022,8176);
assert(nnz(Hfull)==32704 && all(full(sum(Hfull,2))==32) && ...
    all(full(sum(Hfull,1))==4), 'Invalid CCSDS 7/8 base graph.');
H = Hfull(:,19:8176); % exact shortening: the deleted variables are zero
model = struct('Version',1, 'MatrixMode','ccsds-7/8-table7-1-exact-shortening', ...
    'H',H, 'MotherH',Hfull, 'InformationLength',7136, ...
    'TransmittedLength',8160, 'MotherLength',8176, ...
    'ShortenedMotherIndices',(1:18).', ...
    'GraphToMotherIndices',(19:8176).', ...
    'GraphToWireIndices',(1:8158).', ...
    'InformationIndices',(1:7136).', ...
    'InformationMotherIndices',(19:7154).', ...
    'FillWireIndices',(8159:8160).', ...
    'PuncturedIndices',zeros(0,1), ...
    'ShorteningMethod','eliminate-known-zero-columns', ...
    'Algorithm','bp');
end
