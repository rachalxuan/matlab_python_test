classdef HelperCCSDSFACMFLL < matlab.System
    % HelperCCSDSFACMFLL Frequency locked loop
    %
    %   Note: This is a helper and its API and/or functionality may change
    %   in subsequent releases.
    %
    %   FLL = HelperCCSDSFACMFLL creates a frequency offset tracking
    %   System object, FLL. FLL is used to detect and track the frequency
    %   shift in the baseband signal. FLL can track the doppler rate too.
    %
    %   Step method syntax:
    %
    %   [Y,FQYDETECTED,FQYERR] = step(FLL,X) detects the frequency offset
    %   that is frequency offset in the input signal, X and tracks the
    %   change in frequency offset. Tracking happens for the complex
    %   baseband signal which is from [1]. It is assumed that frame
    %   synchronization is complete by the time FLL operation starts. FLL
    %   is of type 2.
    %
    %   HelperCCSDSFACMFLL properties:
    %
    %   K1         - Coefficient of first tracking loop
    %   K2         - Coefficient of second tracking loop
    %   SampleRate - Sampling rate of the input signal
    %
    %   References:
    %   [1] Flexible Advanced Coding and Modulation Scheme for High Rate
    %       Telemetry Applications. Recommendation for Space Data System
    %       Standards, CCSDS 131.2-B-1. Blue Book. Issue 1. Washington,
    %       D.C.: CCSDS, March 2012.

    %   Copyright 2021 The MathWorks, Inc.

    % Public, non-tunable properties
    properties(Nontunable)
        K1 = 0.32
        K2 = 0.16
        SampleRate = 100e6
    end

    % Pre-computed constants
    properties(Access = private)
        pfqyComp
        pVCOFqy
        RefFrameMarker
        pX1reg
        pX2reg
        pY1reg
        pY2reg
    end

    methods
        % Constructor
        function obj = HelperCCSDSFACMFLL(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end
    end

    methods(Access = protected)
        %% Common functions
        function setupImpl(obj)
            % Perform one-time calculations, such as computing constants
            obj.pVCOFqy = 0;
        end

        function [y,y1,ef] = stepImpl(obj,u)
            % Implement algorithm. Calculate y as a function of input u and
            % discrete states.
            D = 2; % This value is given in page 5-17 of CCSDS 130.11-G-1

            % Calculate the error. This algorithm is based on Figure 5-27
            % in [2]
            ef = frequencyErrorDetector(obj, u(1:256));
            % Update 2nd registers
            x2 = obj.K1*obj.K2*ef;
            y2 = obj.pX2reg + obj.pY2reg;
            obj.pX2reg = x2;
            obj.pY2reg = y2;

            % Update 1st registers
            x1 = y2 + obj.K1*ef;
            y1 = obj.pX1reg(D) + obj.pY1reg;
            obj.pX1reg(2:end) = obj.pX1reg(1:end-1);
            obj.pX1reg(1) = x1;
            obj.pY1reg = y1;

            % Calculate the final frequency values and the frequency error
            obj.pVCOFqy = y1;

            % Compensate for the frequency offset on the input signal
            obj.pfqyComp.FrequencyOffset = -y1;
            y = obj.pfqyComp(u);
        end

        function resetImpl(obj)
            % Initialize / reset discrete-state properties
            obj.pX1reg = [0;0];
            obj.pVCOFqy = 0;
            obj.pX2reg = 0;
            obj.pY1reg = 0;
            obj.pY2reg = 0;
            obj.pfqyComp = comm.PhaseFrequencyOffset("FrequencyOffset",0,"SampleRate",obj.SampleRate);
            obj.RefFrameMarker =  HelperCCSDSFACMFrameMarker();
        end

        function releaseImpl(obj)
            % Release resources, such as file handles
            release(obj.pfqyComp);
        end

        %% Backup/restore functions
        function s = saveObjectImpl(obj)
            % Set properties in structure s to values in object obj

            % Set public properties and states
            s = saveObjectImpl@matlab.System(obj);

            % Set private and protected properties
            %s.myproperty = obj.myproperty;
        end

        function loadObjectImpl(obj,s,wasLocked)
            % Set properties in object obj to values in structure s

            % Set private and protected properties
            % obj.myproperty = s.myproperty;

            % Set public properties and states
            loadObjectImpl@matlab.System(obj,s,wasLocked);
        end

        %% Advanced functions
        function flag = isInputSizeMutableImpl(~,~)
            % Return false if input size cannot change
            % between calls to the System object
            flag = true;
        end

        function flag = isInactivePropertyImpl(~,~)
            % Return false if property is visible based on object
            % configuration, for the command line and System block dialog
            flag = false;
        end

        function ef = frequencyErrorDetector(obj,r)

            x = obj.RefFrameMarker;
            fs = obj.SampleRate;
            % Find FFT
            fftNpoints = 1024;
            halflen = fftNpoints/2;
            R = fft(r.*conj(x), 1024);
            [~,idx] = max(abs(fftshift(R)));
            fracVal = 1e-6;
            v = interp1(1:1024,fftshift(R),idx-1:fracVal:idx+1,'spline');
            [~,fracIdx] = max(abs(v));
            finalIdx = idx-1+fracVal*fracIdx - halflen-1;
            ef = finalIdx*fs/fftNpoints - obj.pVCOFqy;
        end
    end
end

% LocalWords:  FQYDETECTED FQYERR nd myproperty
