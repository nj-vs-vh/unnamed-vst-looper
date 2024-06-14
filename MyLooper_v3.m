classdef MyLooper_v3 < audioPlugin
    
    properties
        inVol = 0; %dB
        loopVol = 0; %dB
        dryloopVol = -30; %dB
        
        RecB = false; % start/stop recording/odub
        CutloopB = false; % place end-of-loop mark at current playback position
        DoubleB = false; % double loop if possible
        ClearB = false; % stop and reset looping engine
        JumpB = false; % jump to start of loop
        StopB = false; % start/stop playing
        RevB = false; % reverse loop
        GlitchB = false; % enable glitch mod
        
        PitchS = 0;
        pitchSnap = PitchSnapType.Maj;
        portToct = 0.02; % sec / octave
        
        glitchT = 1;
        randPos = true;
        randDir = true;
        randPitch = true;
        glitchTimeSnap = TimeSnapType.Q;
        glitchRange = 12;
        
        compVol = -60; %dB, threshold
        compInvert = false;
        compAtkT = 0.01; %sec
        compDecT = 0.01; %sec
        
        Tempo = 120;
        BeatN = 32;
    end
    
    properties(Access = private)
        SampleRate;
        
        inVolstate = 0; % input and loop volumes on previous frame for smooth transition
        loopVolstate = 0;
        dryloopVolstate = -30;
        
        inAmp = 1;
        loopAmp = 1;
        dryloopAmp = 0;
        
        buf; % buffer
        i = 1; % loop pointer (w/ effects)
        dryi = 1; % dry loop pointer
        dir; % buffer read direction
        bufSize; % read buffer size
        
        % flags
        Running = false;
        Recing = false;
        loopReady = false;
        
        firstFrameRec = true; % delicate write flags
        lastFrameRec = false;
        endRecNow = false;
        jumpNow = false;
        newi = 0;
        newdir = 1;
        cutLoopHere = false;
        
        frameSize = 0; % frame size for read/write operations
        ioframeSize = 0; % frame size for IO
        
        bufMaxLen = 300; % sec
        Nch = 2;
        
        speed = 1; targetSpeed = 1; portCounter = 0; % pitch changing param with portamento
        
        Pitch = 0;
        pitchchanged = false;
        glitching = false;
        glitchCounter = 0;
        
        compVolstate = -60;
        compAmp = 0;
        compCounter = 0; % samples
        aboveThr = false;
        
        preBuf; % pre-recording buf
        preBufT = 0.05; % sec
        preBufSize;
        
        fade; % "technical" fade in/out
        fadeT = 0.01; % sec
        fadeSize;
        
        % fader-button states
        RecBstate = false;
        CutloopBstate = false;
        DoubleBstate = false;
        ClearBstate = false;
        JumpBstate = false;
        StopBstate = false;
        RevBstate = false;
        GlitchBstate = false;
        
        Pitchstate = 0;
        
        Tempostate = 0; % for memory reallocation
        BeatNstate = 0;
    end
    
    properties (Constant)
        %minVol = -30; % min possible volume in DB (lower only complete silence = -inf)
        PluginInterface = audioPluginInterface(...
            ... % ==============================  volumes
            audioPluginParameter('inVol',...
            'DisplayName','Pre vol',...
            'Label', 'dB', ...
            'Mapping',{'lin', -30, 0}),...
            audioPluginParameter('loopVol',...
            'DisplayName','Loop vol',...
            'Label', 'dB', ...
            'Mapping',{'lin', -30, 0}),...
            audioPluginParameter('dryloopVol',...
            'DisplayName','Dry loop vol',...
            'Label', 'dB', ...
            'Mapping',{'lin', -30, 0}),...
            ... % ============================== pitch settings
            audioPluginParameter('PitchS',...
            'DisplayName','Pitch',...
            'Label', 'h.s.', ...
            'Mapping',{'int', -48, 48}),...
            audioPluginParameter('pitchSnap',...
            'DisplayName','Pitch snap',...
            'Mapping',{'enum', 'Oct', 'Maj', 'Pent', 'no'}),...
            audioPluginParameter('portToct',...
            'DisplayName','Portamento',...
            'Label', 'sec/oct', ...
            'Mapping',{'lin', 0.001, 3}),...
            ... % ============================== glitch settings
            audioPluginParameter('glitchT',...
            'DisplayName','Glitch time',...
            'Label', 'QN', ...
            'Mapping',{'lin', 0.01, 4}), ...
            audioPluginParameter('glitchTimeSnap',...
            'DisplayName','Glitch time snap',...
            'Mapping',{'enum', 'no', '32nd', '16th', '8th', '4th', '4 dot', 'half', 'whole'}),...
            audioPluginParameter('randDir',...
            'DisplayName','Direction glitch',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('randPos',...
            'DisplayName','Position glitch',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('randPitch',...
            'DisplayName','Pitch glitch',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('glitchRange',...
            'DisplayName','Pitch glitch width',...
            'Label', 'h.s.', ...
            'Mapping',{'lin', 0, 36}),...
            ... % ============================== "compressor" settings            
            audioPluginParameter('compVol',...
            'DisplayName','Compress thr',...
            'Label', 'dB', ...
            'Mapping',{'lin', -60, 0}),...
            audioPluginParameter('compInvert',...
            'DisplayName','Invert',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('compAtkT',...
            'DisplayName','Attack',...
            'Label', 'sec', ...
            'Mapping',{'lin', 0.001, 0.5}), ...
            audioPluginParameter('compDecT',...
            'DisplayName','Decay',...
            'Label', 'sec', ...
            'Mapping',{'lin', 0.001, 0.5}), ...
            ... % ============================== loop length tempo sync
            audioPluginParameter('Tempo',...
            'DisplayName','Tempo',...
            'Label','bpm',...
            'Mapping',{'int', 30, 210}),...
            audioPluginParameter('BeatN',...
            'DisplayName','Beats',...
            'Mapping',{'int', 1, 128}), ...
            ... % ==============================  buttons
            audioPluginParameter('RecB',...
            'DisplayName','Rec',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('CutloopB',...
            'DisplayName','Cut loop',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('DoubleB',...
            'DisplayName','Double loop',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('JumpB',...
            'DisplayName','Jump',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('ClearB',...
            'DisplayName','Clear',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('StopB',...
            'DisplayName','Stop/Play',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('RevB',...
            'DisplayName','Reverse',...
            'Mapping',{'enum', '0', '1'}),...
            audioPluginParameter('GlitchB',...
            'DisplayName','Glitch',...
            'Mapping',{'enum', '0', '1'}), ...
            ...
            'PluginName','MyLooper v3',...
            'VendorName','Me',...
            'VendorVersion','3.0.0',...
            'UniqueId','MLp4',...
            'InputChannels', 2,...
            'OutputChannels', 2 ...
            );
    end
    
    methods
        
        %% constructor
        function p = MyLooper_v3
            p.initializeBuffers;
            p.initializeButtons;
        end
        
        %% main processing func
        function out = process(p,in)
            
            p.ioframeSize = size(in,1);
            
            %% controls
            
            p.RecButtonPress;
            p.CutLoopButtonPress;
            p.DoubleButtonPress;
            p.ClearButtonPress;
            p.JumpButtonPress;
            p.StopButtonPress;
            p.ReverseButtonPress;
            p.GlitchButtonPress;
            
            %% pre-processing
            
            % applying input volume and adding dry signal to the output buffer
            if p.inVolstate~=p.inVol
                p.inAmp = 2^(p.inVol/6.0206);
            end
            in = p.applyVolChange(in, p.inVolstate, p.inVol, p.inAmp);
            p.inVolstate = p.inVol;
            out = in;
            
            %% glitch processing
            
            if p.glitching
                if p.glitchCounter>0
                    % ticking glitch counter in 4th notes
                    p.glitchCounter = p.glitchCounter - (p.ioframeSize*p.Tempo)/(60*p.SampleRate);
                else
                    % counter reset, in 4th notes
                    p.glitchCounter = -p.glitchT * log(1-rand(1));
                    if p.glitchTimeSnap~=0
                        timesnapQN = double(p.glitchTimeSnap) / 8;
                        p.glitchCounter = max(round(p.glitchCounter/timesnapQN),1) * timesnapQN;
                    end

                	% performing glitch
                    if p.randPitch
                        p.pitchchanged = true;
                        p.Pitch = sign(rand(1)-0.5) * floor( rand(1)*(p.glitchRange+1) );
                    end
                    if p.randPos
                        p.newi = ceil(rand(1)*(p.bufSize));
                        p.newdir = p.dir;
                        p.jumpNow = true;
                    end
                    if (p.randDir) && (rand(1)>0.5)
                        p.newi = p.i;
                        p.newdir = -1 * p.dir;
                        p.jumpNow = true;
                    end
                    
                end
            end
            
            %% compressor
            
            if p.compVolstate~=p.compVol
                if p.compVol>-60, p.compAmp = 2^(p.compVol/6.0206);
                else, p.compAmp = 0; end
                p.compVolstate = p.compVol;
            end
            
            if p.Running && p.loopReady && p.compCounter<=0
                if ~p.jumpNow, anlsi = p.i;
                else, anlsi = p.newi; end
                atkSize = round(p.compAtkT * p.SampleRate);
                if ~p.compInvert
                    compsign = 1;
                    compval = p.compAmp;
                else
                    compsign = -1;
                    compval = 1 - p.compAmp;
                end
                RMSamp = rms( sum( p.circularRead(atkSize, anlsi, -p.dir), 2) );
                if compsign*RMSamp >= compsign*compval
                    p.aboveThr = true;
                else
                    if p.aboveThr
                        % waiting for decay
                        p.aboveThr = false;
                        p.compCounter = round(p.compDecT*p.SampleRate);
                    else
                        findCount = 0;
                        findCountMax = ceil(p.bufSize / atkSize);
                        findi = anlsi;
                        % looking for where to jump (loud enough part)
                        while 1
                            findCount = findCount+1;
                            findi = p.movePointer(findi, atkSize, p.dir);
                            RMSamp = rms( sum( p.circularRead(atkSize, findi, -p.dir), 2) );
                            % if a buffer is searched through -- start again (TODO think through)
                            if findCount>findCountMax, findi = anlsi; break; end
                            if compsign*RMSamp >= compsign*compval
                                p.aboveThr = true;
                                p.compCounter = atkSize;
                                break;
                            end
                        end
                        
                        if p.dir==1, findi = max(findi-atkSize, anlsi);
                        else, findi = min(findi+atkSize, anlsi); end
                        
                        p.jumpNow = true;
                        p.newi = findi;
                        p.newdir = p.dir;
                    end
                end
            end
            
            if p.compCounter>0
                p.compCounter = p.compCounter - p.frameSize;
            elseif p.compCounter<0
                p.compCounter = 0;
            end
            
            %% pitch-shifting
            
            % manual or from glitcher
            if p.PitchS~=p.Pitchstate
                p.pitchchanged = true;
                p.Pitch = p.PitchS;
                p.Pitchstate = p.PitchS;
            end
            
            if (p.pitchchanged) && (p.loopReady)
                p.pitchchanged = false;
                
                step = mod(p.Pitch, 12);
                if p.pitchSnap == PitchSnapType.Oct, step = 0;
                elseif p.pitchSnap == PitchSnapType.Pent
                    if step == 1, step = 0;
                    elseif step == 3, step = 4;
                    elseif step == 5, step = 4;
                    elseif step == 6, step = 7;
                    elseif step == 8, step = 9;
                    elseif step == 10, step = 9;
                    elseif step == 11, step = 0;
                    end
                elseif p.pitchSnap == PitchSnapType.Maj
                    if step == 1, step = 0;
                    elseif step == 3, step = 4;
                    elseif step == 6, step = 7;
                    elseif step == 8, step = 9;
                    elseif step == 10, step = 11;
                    end
                end
                
                p.targetSpeed = 2^( floor(p.Pitch/12) + step/12 );
                if p.targetSpeed < 1/8, p.targetSpeed = 1/8; end
                if p.targetSpeed > 16, p.targetSpeed = 16; end
                
                % rounding speed to align with frame boundaries
                p.targetSpeed = p.ioframeSize / round(p.ioframeSize / p.targetSpeed);
                
                % portamento time
                p.portCounter = p.portToct * log(p.targetSpeed / p.speed) / log(2);
                
                % stretching technical values
                p.fadeSize = ceil(p.fadeT * (p.SampleRate * p.targetSpeed));
                if p.fadeSize < 1, p.fadeSize=1; end
                if p.fadeSize > p.frameSize, p.fadeSize = p.frameSize; end
                p.fade = ones(p.fadeSize, p.Nch);
                p.fade(1:p.fadeSize-1,:) = repmat(sqrt( (0:1:p.fadeSize-2)'/(p.fadeSize) ), 1, p.Nch);
                
                newpreBufSize = ceil(p.preBufT * (p.SampleRate * p.targetSpeed));
                p.preBuf = timeStretch(p, p.preBuf, p.preBufSize, newpreBufSize);
                p.preBufSize = newpreBufSize;
            end
            
            % portamento step
            if p.speed~=p.targetSpeed && p.portCounter~=0
                p.speed = p.speed * 2^( (p.ioframeSize/p.SampleRate) / p.portCounter );
                if ((p.portCounter>0) && (p.speed > p.targetSpeed)) || ... % portamento end check
                   ((p.portCounter<0) && (p.speed < p.targetSpeed))
                    p.speed = p.targetSpeed;
                end
                % aligning step with frame size
                p.speed = round(p.ioframeSize * p.speed) / p.ioframeSize;
            elseif p.portCounter==0 % if it's off
                p.speed = p.targetSpeed;
            end
            
            % calculating internal frame size from speed
            if (p.speed~=1)
                p.frameSize = ceil(p.ioframeSize * p.speed);
            else
                p.frameSize = p.ioframeSize;
            end
            
            % protection from extra small p.frameSize
            if p.fadeSize > p.frameSize
                p.fadeSize = p.frameSize;
                p.fade = ones(p.fadeSize, p.Nch);
                p.fade(1:p.fadeSize-1, :) = repmat(sqrt( (0:1:p.fadeSize-2)'/(p.fadeSize) ), 1, p.Nch);
            end
            if p.bufSize < p.frameSize, p.bufSize = p.frameSize+1; end
            
            % time stretchin input frame to rw frame size
            in = timeStretch(p, in, p.ioframeSize, p.frameSize);
            
            %% reading playback from memory (no effects)
            
            playbackDry = zeros(p.ioframeSize, p.Nch);
            
            if p.Running && p.loopReady
                playbackDry = p.circularRead(p.ioframeSize, p.dryi, 1);
                p.dryi = p.movePointer(p.dryi, p.ioframeSize, 1);
            end
                
            
            %% reading playback with effects
            
            playback = zeros(p.frameSize, p.Nch);
            
            if p.Running
                
                if p.loopReady
                    playback = p.circularRead(p.frameSize, p.i, p.dir);
                end
                
                % moving the index (unless it's moved again later)
                if ~p.Recing
                    p.i = p.movePointer(p.i, p.frameSize, p.dir);
                end
                
                %% recording
                if p.Recing
                    if p.firstFrameRec % recording start, adding pre-rec buffer with technical fade in
                        p.preBuf(1:p.fadeSize,:) = ... % fade in
                        p.preBuf(1:p.fadeSize,:) .* p.fade;
                        p.circularWrite(p.preBuf, p.i-p.dir*p.preBufSize, p.dir);
                        p.firstFrameRec = false;
                    end
                    
                    if p.lastFrameRec || p.jumpNow % recording end, adding technical fade out
                        in(p.frameSize-p.fadeSize+1:p.frameSize,:) = ... % fade out
                        in(p.frameSize-p.fadeSize+1:p.frameSize,:) .* p.fade(end:-1:1,:);
                        p.lastFrameRec = false;
                        if p.endRecNow
                            p.Recing = false;
                            p.endRecNow = false;
                        end
                    end
                    
                    % writing input frame
                    p.circularWrite(in, p.i, p.dir);
                    p.i = p.movePointer(p.i, p.frameSize, p.dir);
                    
                    % checking max loop length reached
                    if ~p.loopReady && p.i+p.frameSize > p.bufSize
                        p.cutLoopHere = true;
                    end
                end
                
                
                %% another pass in case of jump (sudden position change)

                if p.jumpNow
                    p.i = p.newi;
                    p.dir = p.newdir;
                    
                    playback2 = zeros(p.frameSize, p.Nch);
                    
                    if p.loopReady
                        playback2 = p.circularRead(p.frameSize, p.i, p.dir);
                    end
                    p.i = p.movePointer(p.i, p.frameSize, p.dir);
                    
                    % x - fade
                    fadeFrame = repmat(sqrt( (0:1:p.frameSize-1)'/(p.frameSize) ), 1, p.Nch);
                    playback = playback.*fadeFrame(end:-1:1, :) + playback2.*fadeFrame;
                    
                    p.firstFrameRec = true; % starting writing anew
                    p.jumpNow = false;
                end
                
                %% cutting loop if needed -- resetting params
                
                if p.cutLoopHere
                    p.bufSize = p.i - 1;
                    p.i = 1;
                    p.dryi = 1;
                    p.loopReady = true;
                    p.cutLoopHere = false;
                end
                
            end
            
            %% writing output buffer
            
            p.preboofWrite(in); % saving a part of the input buffer for prerec
            
            playback = timeStretch(p, playback, p.frameSize, p.ioframeSize);
            
            if p.loopVolstate~=p.loopVol
                p.loopAmp = 2^(p.loopVol/6.0206);
            end
            playback = p.applyVolChange(playback, p.loopVolstate, p.loopVol, p.loopAmp);
            p.loopVolstate = p.loopVol;
            
            if p.dryloopVolstate~=p.dryloopVol
                p.dryloopAmp = 2^(p.dryloopVol/6.0206);
            end
            playbackDry = p.applyVolChange(playbackDry, p.dryloopVolstate, p.dryloopVol, p.dryloopAmp);
            p.dryloopVolstate = p.dryloopVol;
            
            out = out + playback + playbackDry;
            
        end
        
        function reset(p)
            p.SampleRate = getSampleRate(p);
            p.initializeBuffers;
            p.initializeButtons;
        end
    end
    
    methods (Access = private)
        
        %% button press handlers
        
        function RecButtonPress(p)
            if p.RecB~=p.RecBstate
                % first rec press, start
                if ~p.loopReady && ~p.Running
                    p.Running = true;
                end
                
                if ~p.Recing % start recording (overdub)
                    p.Recing = true;
                    p.firstFrameRec = true;
                else % stop recording
                    p.lastFrameRec = true;
                    p.endRecNow = true;
                    if ~p.loopReady % first loop rec, cutting is required
                        p.cutLoopHere = true;
                    end
                end
            end
            p.RecBstate = p.RecB;
        end

        function CutLoopButtonPress(p)
            if p.CutloopBstate~=p.CutloopB
                if p.Running, p.cutLoopHere = true; end
                p.CutloopBstate = p.CutloopB;
            end
        end
        
        function DoubleButtonPress(p)
            if p.DoubleBstate~=p.DoubleB
                if p.loopReady && (2*p.bufSize+1 < p.bufMaxLen*p.SampleRate)
                    p.buf(p.bufSize+1:2*p.bufSize, :) = p.buf(1:p.bufSize, :);
                    p.bufSize = 2*p.bufSize;
                end
                p.DoubleBstate = p.DoubleB;
            end
        end
        
        function ClearButtonPress(p)
            if p.ClearBstate~=p.ClearB
                p.resetBuf;
                p.ClearBstate = p.ClearB;
            end
        end
        
        function JumpButtonPress(p)
            if p.JumpBstate~=p.JumpB
                p.newi = 1;
                p.dryi = 1;
                p.newdir = 1;
                p.jumpNow = true;
                
                p.glitching = false;
                p.glitchCounter = 0;
                
                p.pitchchanged = true;
                p.Pitch = 0;
            
                p.compAmp = 0;
                p.compCounter = 0;
                
                p.JumpBstate = p.JumpB;
            end
        end
        
        function StopButtonPress(p)
            if p.StopBstate~=p.StopB
                p.i = 1;
                p.dryi = 1;
                if p.loopReady && p.Running, p.Running=false; % stop
                elseif p.loopReady && ~p.Running, p.Running=true; end % continuing
                if ~p.loopReady && p.Running % erasing unfinished loop
                    p.resetBuf;
                end
                p.StopBstate = p.StopB;
            end
        end
        
        function ReverseButtonPress(p)
            if p.RevBstate~=p.RevB
                p.newi = p.i;
                p.newdir = -1*p.dir;
                p.jumpNow = true;
                p.RevBstate = p.RevB;
            end
        end
        
        function GlitchButtonPress(p)
            if p.GlitchBstate~=p.GlitchB
                if ~p.glitching, p.glitching=true;
                else, p.glitching=false; end
                p.GlitchBstate = p.GlitchB;
            end
        end
        
        %% functions for working with buffer
        
        function newi = movePointer(p, i, frameSize, dir)
            newi = i + dir*frameSize;
            if newi<1, newi = p.bufSize + 1 - mod((1-newi), p.bufSize); end
            if newi>p.bufSize, newi = mod(newi, p.bufSize); end
        end
        
        % buffer write wrapping over edges
        function circularWrite(p, in, i, dir)
            
            inframeSize = size(in,1);
            
            if dir==-1
                in = flip(in);
                i = i-inframeSize+1;
            end
            
            if size(in,2)~=p.Nch, return; end
            if inframeSize > p.bufSize, return; end

            if i<1, i = p.bufSize + 1 - mod((1-i), p.bufSize); end
            if i>p.bufSize, i = mod(i, p.bufSize); end
            
            if i+inframeSize-1 > p.bufSize
                p.buf(i : p.bufSize, 1:p.Nch) = ...
                p.buf(i : p.bufSize, 1:p.Nch) + ...
                    in(1 : p.bufSize-i+1, 1:p.Nch);
                in2 = in(p.bufSize-i+2 : inframeSize, 1:p.Nch);
                inframeSize = inframeSize - (p.bufSize-i+1);
                i=1;
                p.buf(i:i+inframeSize-1, 1:p.Nch) = ...
                    p.buf(i:i+inframeSize-1, 1:p.Nch) + ...
                        in2;
            else
                p.buf(i:i+inframeSize-1, 1:p.Nch) = ...
                    p.buf(i:i+inframeSize-1, 1:p.Nch) + ...
                        in;
            end
            
        end
        
        % sliding write to pre-rec buffer
        function preboofWrite(p, in)

            if p.frameSize >= p.preBufSize
                p.preBuf = in(p.frameSize-p.preBufSize+1 : p.frameSize, :);
            else
                p.preBuf(1:p.preBufSize-p.frameSize, :) = p.preBuf(p.frameSize+1:p.preBufSize, :);
                p.preBuf(p.preBufSize-p.frameSize+1:p.preBufSize, :) = in(:, :);
            end
            
        end
        
        % time stretching from one sampling freq to another with pchip resampling
        function out = timeStretch(~, in, fin, fout)
            if fin==fout, out = in; return; end
            if fin<4 || fout<4, out = zeros(fout, size(in,2)); return; end
            out = zeros(fout, size(in,2));
            for ch=1:size(in,2)
                if fout>fin
                    out(:,ch) = interp1((1:fin)' / fin, ...
                                        in(:,ch), ...
                                        (1:fout)' / fout, 'pchip');
                else
                    out(:,ch) = interp1((1:fin)' / fin, ...
                                        in(:,ch), ...
                                        (1:fout)' / fout, 'linear');
                end
            end
        end
        

        function out = circularRead(p, frameSize, i, dir)

            if dir==-1
                i = i-frameSize+1;
            end
            
            if i<1, i = p.bufSize + 1 - mod((1-i), p.bufSize); end
            if i>p.bufSize, i = mod(i, p.bufSize); end
            
            if frameSize>p.bufSize
                out = zeros(frameSize, p.Nch);
                return;
            end
            
            if i+frameSize-1 < p.bufSize
                out = p.buf(i:i+frameSize-1, :);
            else
                out = [ p.buf(i:p.bufSize, :); ...
                        p.buf(1:(i + frameSize - 1 - p.bufSize), :) ];
            end

            if dir==-1
                out = flip(out);
            end
            
        end
        
        % gradual volume change
        function out = applyVolChange(~, in, volStart, volEnd, constAmp)
            if (volStart <= -30) && (volEnd <= -30)
                out = zeros(size(in));
            elseif (volStart == volEnd)
                out = in * constAmp;
            else
                out = in .* ...
                    repmat( ...
                        transpose( ...
                            linspace( 2^(volStart/6.0206)*gt(volStart,-30), ...
                                      2^(volEnd/6.0206)*gt(volEnd,-30), ...
                                      size(in,1) ...
                            ) ...
                        ), ...
                        1, size(in,2) ...
                    );
            end
        end
        
        function resetBuf(p)
            
            p.bufSize = 1+ceil(p.BeatN * (60 / p.Tempo) * p.SampleRate);
            
            p.buf = zeros(p.bufMaxLen*p.SampleRate, p.Nch);
            p.i = p.preBufSize+1;
            p.dryi = p.i;
            p.dir = 1;
            
            p.Running = false;
            p.Recing = false;
            p.loopReady = false;
            
            p.frameSize = p.ioframeSize;
            p.speed = 1;
            p.targetSpeed = 1;
            p.portCounter = 0;
            
            p.firstFrameRec = true;
            p.lastFrameRec = false;
            p.endRecNow = false;
            p.jumpNow = false;
            p.newi = 1;
            p.newdir = 1;
            p.cutLoopHere = false;

            p.pitchchanged = false; p.Pitch = 0;
            p.glitching = false; p.glitchCounter = 0;
            
            p.compAmp = 0;
            p.compCounter = 0;
        end
        
        %% initializer functions
        
        % called on every sample rate change
        function initializeBuffers(p)
            p.SampleRate = getSampleRate(p);
            
            p.bufSize = ceil(p.BeatN * (60 / p.Tempo) * p.SampleRate);
            p.Nch = 2;
            
            p.preBufSize = ceil(p.preBufT * p.SampleRate);
            p.preBuf = zeros(p.preBufSize, p.Nch);
            
            p.resetBuf;

            p.fadeSize = ceil(p.fadeT * p.SampleRate);
            if p.fadeSize < 1, p.fadeSize = 1; end
            if p.fadeSize > p.frameSize, p.fadeSize = p.frameSize; end
            p.fade = ones(p.fadeSize, p.Nch);
            p.fade(1:p.fadeSize-1,:) = repmat(sqrt( (0:1:p.fadeSize-2)'/(p.fadeSize) ), 1, p.Nch);
            
        end
        
        function initializeButtons(p)
            p.RecBstate = p.RecB;
            p.JumpBstate = p.JumpB;
            p.CutloopBstate = p.CutloopB;
            p.DoubleBstate = p.DoubleB;
            p.ClearBstate = p.ClearB;
            p.StopBstate = p.StopB;
            p.RevBstate = p.RevB;
            p.GlitchBstate = p.GlitchB;
            
            p.Pitchstate = p.PitchS;
            p.compVolstate = p.compVol;
            
            p.Tempostate = p.Tempo;
            p.BeatNstate = p.BeatN;
        end
    
    end
end