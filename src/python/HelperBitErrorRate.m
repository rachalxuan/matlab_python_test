function berinfo = HelperBitErrorRate(txBits,rxBits,berinfo)
%HelperBitErrorRate Calculate it error rate
%
%   Note: This is a helper and its API and/or functionality may change
%   in subsequent releases.
%
%   BERINFO = HelperBitErrorRate(TXBITS,RXBITS,BERINFO) compares TXBITS and
%   RXBITS and provides bit error rate (BER) information in BERINFO. The input
%   BERINFO contains information of BER till previous bits. Output BERINFO
%   uses the input BERINFO and the bit comparisons done in current input to
%   update the BER. TXBITS and RXBITS are vectors or matrices of same
%   number of rows. When matrices, best match of TXBITS with RXBITS are
%   chosen to calculate BER. Number of columns in TXBITS must be greater
%   than or equal to the number of columns in RXBITS. BERINFO is a
%   structure with fields:
%
%   NumBitsInError - Number of bits in error
%   TotalNumBits   - Total number of bits that are processed
%   BitErrorRate   - Bit error rate

%   Copyright 2021 The MathWorks, Inc.

nTx = size(txBits,2);
nRx = size(rxBits,2);

numErr = zeros(nTx-nRx+1,1);
for iSliding = 1:nTx-nRx+1
    txCompBits = txBits(:,iSliding+(0:nRx-1));
    numErr(iSliding) = nnz(xor(txCompBits,rxBits));
end
berinfo.NumBitsInError = berinfo.NumBitsInError + min(numErr);
berinfo.TotalNumBits = berinfo.TotalNumBits + numel(rxBits);
berinfo.BitErrorRate = berinfo.NumBitsInError/berinfo.TotalNumBits;
end

% LocalWords:  TXBITS RXBITS BERINFO
