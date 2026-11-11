function app = background_simulation_gui(config,visible)
%BACKGROUND_SIMULATION_GUI Single-condition and batch Doppler/background GUI.
% Inputs: optional background_simulation_config structure; visible='on'/'off'.
% Output: app.figure, controls and callback handles for automated testing.
% Uses existing physics/RMS/mixing/export functions. No new acoustic model.
% Units: positions [m], Source speed [km/h], Receiver speed [m/s], time [s].
% Horizontal constant velocity only; no acceleration/obstacles/diffraction.
if nargin<1, config=background_simulation_config(); end
if nargin<2, visible='on'; end
base=config; cancelled=false;
player=[]; lastResult=[]; lastOutput=''; lastError='';
fig=uifigure('Name','Doppler + 背景音 / WAV生成', ...
    'Position',[60,60,1180,850],'Visible',visible,'CloseRequestFcn',@closeRequested);
setappdata(fig,'Busy',false); setappdata(fig,'Saving',false); setappdata(fig,'HasResult',false);
setappdata(fig,'BatchRunning',false);
root=uigridlayout(fig,[5,1]); root.RowHeight={32,'1x',160,42,68};
uilabel(root,'Text','RMS校正・移動Source/Receiver・地面反射を使用（障害物なし / 加速度なし）','FontWeight','bold');
tabs=uitabgroup(root);
inputTab=uitab(tabs,'Title','1. 音源・保存'); motionTab=uitab(tabs,'Title','2. 位置・速度');
bgTab=uitab(tabs,'Title','3. 背景音の配置'); advancedTab=uitab(tabs,'Title','4. 音圧・詳細');
resultTab=uitab(tabs,'Title','5. 生成結果');
ui=struct(); editable={}; browseButtons=gobjects(0);
g=form(inputTab,7);
field(g,1,1,'救急車 WAV','inputFile','text',[]);
action(g,1,3,'選択',@()chooseAudio('inputFile'));
action(g,1,4,'原音を試聴',@()previewAudio(false));
ui.inputInfo=uilabel(g,'Text',''); place(ui.inputInfo,2,[1,4]);
field(g,3,1,'背景音 WAV','backgroundFile','text',[]);
action(g,3,3,'選択',@()chooseAudio('backgroundFile'));
action(g,3,4,'切出しを試聴',@()previewAudio(true));
ui.backgroundInfo=uilabel(g,'Text',''); place(ui.backgroundInfo,4,[1,4]);
field(g,5,1,'保存先フォルダ','outputRoot','text',[]);
action(g,5,3,'保存先を選択',@chooseOutput); action(g,5,4,'試聴停止',@stopAudio);
note(g,6,'音声長は入力WAV全体＋伝搬遅延。短い背景音の自動ループは行いません。');
g=form(motionTab,9);
field(g,1,1,'Source 初期 x [m]','sourceX','numeric',[-Inf,Inf]);
field(g,2,1,'Source 初期 y [m]','sourceY','numeric',[-Inf,Inf]);
field(g,3,1,'Source 高さ z [m]','sourceZ','numeric',[eps,Inf]);
field(g,4,1,'Source 速度 [km/h]','sourceSpeed','numeric',[0,Inf]);
field(g,5,1,'Source 方向 [deg]','sourceHeading','numeric',[-180,180]);
check(g,6,2,'Source 静止','sourceStationary');
field(g,1,3,'Receiver 初期 x [m]','receiverX','numeric',[-Inf,Inf]);
field(g,2,3,'Receiver 初期 y [m]','receiverY','numeric',[-Inf,Inf]);
field(g,3,3,'Receiver 高さ z [m]','receiverZ','numeric',[eps,Inf]);
field(g,4,3,'Receiver 速度 [m/s]','receiverSpeed','numeric',[0,Inf]);
field(g,5,3,'Receiver 方向 [deg]','receiverHeading','numeric',[-180,180]);
check(g,6,4,'Receiver 静止','receiverStationary');
note(g,7,'方向: 0° = +x、90° = +y。速度一定・水平移動。静止を選ぶと速度を0として計算。');
check(g,8,2,'地面反射を有効にする','reflectionEnabled');
field(g,8,3,'音圧反射係数 [-]','reflectionCoefficient','numeric',[-1,1]);
g=form(bgTab,9);
check(g,1,2,'背景音を合成する','backgroundEnabled');
drop(g,2,'配置基準','timeReference',{'録音開始','幾何学的CPA'},{'start','cpa'});
field(g,3,1,'基準からの開始オフセット [s]','startOffset','numeric',[-Inf,Inf]);
field(g,4,1,'背景WAVの切出し開始 [s]','sourceStart','numeric',[0,Inf]);
field(g,5,1,'背景音の長さ [s]','duration','numeric',[eps,Inf]);
field(g,6,1,'各端のフェード [ms]','fadeMs','numeric',[0,Inf]);
drop(g,7,'背景音レベルの指定方法','backgroundMode',{'固定 RMS SPL','区間 SNR'},{'fixed_rms','snr'});
field(g,3,3,'背景 RMS SPL [dB re 20 µPa]','backgroundSpl','numeric',[-Inf,Inf]);
field(g,4,3,'区間 SNR [dB]','snr','numeric',[-Inf,Inf]);
note(g,8,'固定SPL: 背景音圧を維持 / SNR: 挿入区間のサイレンRMSに合わせて背景音圧を変更');
note(g,9,'背景音は受音点の録音として加算。救急車のドップラー・距離減衰は背景音に適用しません。');
g=form(advancedTab,8);
field(g,1,1,'出力サンプリング周波数 [Hz]','fs','numeric',[1000,192000]);
field(g,2,1,'音速 [m/s]','c','numeric',[eps,Inf]);
field(g,3,1,'Source 基準 RMS SPL [dB]','sourceSpl','numeric',[-Inf,Inf]);
field(g,4,1,'基準距離 [m]','referenceDistance','numeric',[eps,Inf]);
field(g,5,1,'許容最小経路長 [m]','minimumDistance','numeric',[eps,Inf]);
field(g,6,1,'共通 WAV フルスケール [Pa/FS]','wavScale','numeric',[eps,Inf]);
check(g,7,2,'波形・スペクトログラム PNGを保存','makeFigures');
note(g,8,'最大値正規化なし。136 dB・1 mは設定上の仮定校正値で、入力WAVの実測校正値ではありません。');
rg=uigridlayout(resultTab,[3,1]); rg.RowHeight={34,42,'1x'};
ui.resultLabel=uilabel(rg,'Text','まだ生成していません。');
pb=uigridlayout(rg,[1,8]); pb.Padding=[0,0,0,0];
components={'final','siren','background','direct','reflected'};
titles={'合成音','サイレン','背景音','直接音','反射音'};
resultButtons=gobjects(1,7);
for k=1:5
    component=components{k};
    resultButtons(k)=uibutton(pb,'Text',[titles{k} ' 再生'], ...
        'ButtonPushedFcn',@(~,~)guard(@()playResult(component)));
end
uibutton(pb,'Text','停止','ButtonPushedFcn',@(~,~)stopAudio());
resultButtons(6)=uibutton(pb,'Text','保存先を開く','ButtonPushedFcn',@(~,~)guard(@openOutput));
resultButtons(7)=uibutton(pb,'Text','図を拡大','ButtonPushedFcn',@(~,~)guard(@openFigure));
views=uitabgroup(rg); wt=uitab(views,'Title','波形'); st=uitab(views,'Title','スペクトログラム');
wg=uigridlayout(wt,[1,1]); ui.waveImage=uiimage(wg,'ScaleMethod','fit');
sg=uigridlayout(st,[1,1]); ui.specImage=uiimage(sg,'ScaleMethod','fit');
ui.timeline=uiaxes(root); title(ui.timeline,'「入力チェック・配置確認」でタイムラインを更新');
xlabel(ui.timeline,'受音時間 [s]'); ui.timeline.YLim=[0,3]; ui.timeline.YTick=[1,2];
ui.timeline.YTickLabel={'背景音','受音区間'};
actions=uigridlayout(root,[1,6]); actions.Padding=[0,0,0,0];
ui.checkButton=uibutton(actions,'Text','入力チェック・配置確認','ButtonPushedFcn',@(~,~)guard(@checkInputs));
ui.generateButton=uibutton(actions,'Text','WAV生成','FontWeight','bold','ButtonPushedFcn',@(~,~)guard(@generate));
ui.cancelButton=uibutton(actions,'Text','キャンセル','Enable','off','ButtonPushedFcn',@(~,~)requestCancel());
ui.saveButton=uibutton(actions,'Text','設定を保存','ButtonPushedFcn',@(~,~)guard(@saveDialog));
ui.loadButton=uibutton(actions,'Text','設定を読込','ButtonPushedFcn',@(~,~)guard(@loadDialog));
ui.resetButton=uibutton(actions,'Text','初期設定へ戻す','ButtonPushedFcn',@(~,~)guard(@resetDefaults));
ui.status=uitextarea(root,'Editable','off','Value',{'準備完了。'});
try
    setConfig(config);
catch exception
    delete(fig); rethrow(exception);
end
set(resultButtons,'Enable','off');
host=struct('getConfig',@getConfig,'getHeading',@()ui.sourceHeading.Value, ...
    'setHeading',@(value)set(ui.sourceHeading,'Value',value),'isBusy',@isBusy, ...
    'begin',@beginBatch,'finish',@()finishWork(fig,ui,editable,browseButtons,resultButtons), ...
    'status',@(value)set(ui.status,'Value',value),'progress',@batchProgress);
batchUI=add_background_batch_tab(tabs,host);
setappdata(fig,'BatchSetEnabled',batchUI.setEnabled); setappdata(fig,'BatchInvalidate',batchUI.invalidate);
app=struct('figure',fig,'tabs',tabs,'controls',ui,'getConfig',@getConfig,'setConfig',@setConfig, ...
    'check',@checkInputs,'generate',@generate,'cancel',@requestCancel, ...
    'saveConfig',@saveConfig,'loadConfig',@loadConfig,'getState',@getState,'batch',batchUI);

    function layout = form(parent,n)
        % Return a scrollable four-column labelled form (no numerical work).
        layout=uigridlayout(parent,[n,4]); layout.ColumnWidth={240,'1x',240,'1x'};
        layout.RowHeight=repmat({34},1,n); layout.Scrollable='on';
    end
    function place(h,row,col)
        % Position a UI component in its parent grid.
        h.Layout.Row=row; h.Layout.Column=col;
    end
    function field(layout,row,col,label,key,type,limits)
        % Create a labelled text/numeric input; limits use displayed units.
        h=uilabel(layout,'Text',label); place(h,row,col);
        if strcmp(type,'numeric')
            ui.(key)=uieditfield(layout,type,'Limits',limits,'Value',max(0,limits(1)),'ValueChangedFcn',@changed);
        else
            ui.(key)=uieditfield(layout,type,'ValueChangedFcn',@changed);
        end
        place(ui.(key),row,col+1); editable{end+1}=key;
    end
    function check(layout,row,col,label,key)
        % Create an editable logical setting.
        ui.(key)=uicheckbox(layout,'Text',label,'ValueChangedFcn',@changed);
        place(ui.(key),row,col); editable{end+1}=key;
    end
    function drop(layout,row,label,key,items,data)
        % Create a dropdown mapping Japanese labels to existing config values.
        h=uilabel(layout,'Text',label); place(h,row,1);
        ui.(key)=uidropdown(layout,'Items',items,'ItemsData',data,'ValueChangedFcn',@changed);
        place(ui.(key),row,2); editable{end+1}=key;
    end
    function note(layout,row,label)
        % Add a full-width explanatory label.
        h=uilabel(layout,'Text',label); place(h,row,[1,4]);
    end
    function action(layout,row,col,label,callback)
        % Add a guarded auxiliary button; disabled during generation.
        h=uibutton(layout,'Text',label,'ButtonPushedFcn',@(~,~)guard(callback));
        place(h,row,col); browseButtons(end+1)=h;
    end
    function changed(~,~)
        % Mark plots as stale without discarding the last completed audio.
        syncEnabled(); title(ui.timeline,'設定変更あり：入力チェックで再確認してください');
        ui.status.Value={'設定を変更しました。生成済み音声・図がある場合、それらは変更前の結果です。'};
        if isappdata(fig,'BatchInvalidate'), callback=getappdata(fig,'BatchInvalidate'); callback(); end
    end
    function syncEnabled()
        % Busy/state-dependent enablement; preserves inactive field values.
        setControlStates(fig,ui,editable,browseButtons);
    end
    function value = isBusy()
        % Read lock from the figure handle so onCleanup does not mutate shared variables.
        value=isvalid(fig) && getappdata(fig,'Busy');
    end
    function c = getConfig()
        % Convert displayed units to the existing configuration schema.
        c=base; c.inputFile=ui.inputFile.Value; c.outputRoot=ui.outputRoot.Value;
        c.source.positionM=[ui.sourceX.Value,ui.sourceY.Value,ui.sourceZ.Value];
        c.receiver.positionM=[ui.receiverX.Value,ui.receiverY.Value,ui.receiverZ.Value];
        c.source.velocityMps=velocity(ui.sourceSpeed.Value/3.6,ui.sourceHeading.Value,ui.sourceStationary.Value);
        c.receiver.velocityMps=velocity(ui.receiverSpeed.Value,ui.receiverHeading.Value,ui.receiverStationary.Value);
        c.reflection.enabled=ui.reflectionEnabled.Value; c.reflection.coefficient=ui.reflectionCoefficient.Value;
        c.fs=ui.fs.Value; c.c=ui.c.Value; c.sourceSplDb=ui.sourceSpl.Value;
        c.referenceDistanceM=ui.referenceDistance.Value; c.minimumDistanceM=ui.minimumDistance.Value;
        c.wavFullScalePa=ui.wavScale.Value; c.makeFigures=ui.makeFigures.Value; c.figureVisible='off';
        c.background=struct('enabled',ui.backgroundEnabled.Value,'file',ui.backgroundFile.Value, ...
            'timeReference',ui.timeReference.Value,'startOffsetSec',ui.startOffset.Value, ...
            'sourceStartSec',ui.sourceStart.Value,'durationSec',ui.duration.Value,'fadeSec',ui.fadeMs.Value/1000, ...
            'mode',ui.backgroundMode.Value,'splDb',ui.backgroundSpl.Value,'snrDb',ui.snr.Value);
        if c.fs~=round(c.fs), error('backgroundGUI:Fs','サンプリング周波数は整数にしてください。'); end
        if isempty(strtrim(c.outputRoot)) || isfile(c.outputRoot)
            error('backgroundGUI:Output','有効な保存先フォルダを指定してください。');
        end
    end
    function v = velocity(speed,heading,stationary)
        % Speed [m/s], heading [deg] -> horizontal Cartesian velocity [m/s].
        v=speed*[cosd(heading),sind(heading),0]; if stationary, v=[0,0,0]; end
    end
    function setConfig(c)
        % Validate all settings before changing controls; invalid loads are atomic.
        if isBusy(), error('backgroundGUI:Busy','処理中は設定を変更できません。'); end
        validateattributes(c,{'struct'},{'scalar'});
        for entity={'source','receiver'}
            e=c.(entity{1}); validateattributes(e.positionM,{'numeric'},{'vector','numel',3,'real','finite'});
            validateattributes(e.velocityMps,{'numeric'},{'vector','numel',3,'real','finite'});
            if e.velocityMps(3)~=0, error('backgroundGUI:Vertical','水平移動のみ対応しています。'); end
        end
        v=struct('inputFile',c.inputFile,'backgroundFile',c.background.file,'outputRoot',c.outputRoot, ...
            'sourceX',c.source.positionM(1),'sourceY',c.source.positionM(2),'sourceZ',c.source.positionM(3), ...
            'sourceSpeed',norm(c.source.velocityMps)*3.6,'sourceHeading',atan2d(c.source.velocityMps(2),c.source.velocityMps(1)), ...
            'sourceStationary',norm(c.source.velocityMps)==0, ...
            'receiverX',c.receiver.positionM(1),'receiverY',c.receiver.positionM(2),'receiverZ',c.receiver.positionM(3), ...
            'receiverSpeed',norm(c.receiver.velocityMps),'receiverHeading',atan2d(c.receiver.velocityMps(2),c.receiver.velocityMps(1)), ...
            'receiverStationary',norm(c.receiver.velocityMps)==0,'reflectionEnabled',c.reflection.enabled, ...
            'reflectionCoefficient',c.reflection.coefficient,'backgroundEnabled',c.background.enabled, ...
            'timeReference',c.background.timeReference,'startOffset',c.background.startOffsetSec, ...
            'sourceStart',c.background.sourceStartSec,'duration',c.background.durationSec,'fadeMs',c.background.fadeSec*1000, ...
            'backgroundMode',c.background.mode,'backgroundSpl',c.background.splDb,'snr',c.background.snrDb, ...
            'fs',c.fs,'c',c.c,'sourceSpl',c.sourceSplDb,'referenceDistance',c.referenceDistanceM, ...
            'minimumDistance',c.minimumDistanceM,'wavScale',c.wavFullScalePa,'makeFigures',c.makeFigures);
        for j=1:numel(editable)
            key=editable{j}; value=v.(key); h=ui.(key);
            if isa(h,'matlab.ui.control.NumericEditField')
                validateattributes(value,{'numeric'},{'scalar','real','finite','>=',h.Limits(1),'<=',h.Limits(2)});
            elseif isa(h,'matlab.ui.control.CheckBox')
                validateattributes(value,{'numeric','logical'},{'scalar','binary'}); v.(key)=logical(value);
            else
                if ~(ischar(value) && (isrow(value) || isempty(value)) || isstring(value) && isscalar(value))
                    error('backgroundGUI:Config','文字列設定が不正です: %s',key);
                end
                v.(key)=char(value);
                if isa(h,'matlab.ui.control.DropDown') && ~ismember(v.(key),h.ItemsData)
                    error('backgroundGUI:Config','選択肢が不正です: %s',key);
                end
            end
        end
        if c.fs~=round(c.fs), error('backgroundGUI:Fs','サンプリング周波数は整数にしてください。'); end
        base=c;
        for j=1:numel(editable), ui.(editable{j}).Value=v.(editable{j}); end
        changed([],[]); refreshInfo();
    end
    function refreshInfo()
        % Inspect selected WAV headers; missing files are reported, not generated.
        ui.inputInfo.Text=fileInfo(ui.inputFile.Value); ui.backgroundInfo.Text=fileInfo(ui.backgroundFile.Value);
    end
    function value = fileInfo(path)
        % File path -> duration [s], fs [Hz], channels; no audio normalization.
        try
            a=audioinfo(path); value=sprintf('%.6f s / %d Hz / %d ch  |  %s',a.Duration,a.SampleRate,a.NumChannels,path);
        catch
            value=['未選択または読込不可: ' char(path)];
        end
    end
    function chooseAudio(key)
        % File dialog updates only the selected input path.
        if isBusy(), return; end
        [name,folder]=uigetfile({'*.wav','WAV files'},'音源を選択',ui.(key).Value);
        if isequal(name,0), return; end
        ui.(key).Value=fullfile(folder,name); changed([],[]); refreshInfo();
    end
    function chooseOutput()
        % Choose a parent folder; each generation gets a new unique subfolder.
        if isBusy(), return; end
        folder=uigetdir(ui.outputRoot.Value,'保存先'); if isequal(folder,0), return; end
        ui.outputRoot.Value=folder; changed([],[]);
    end
    function r = checkInputs()
        % Full dry run through existing physics/mixer; no files are written.
        beginWork(); cleanup=onCleanup(@()finishWork(fig,ui,editable,browseButtons,resultButtons));
        c=getConfig();
        if ~progress('simulation',0), error('background:Cancelled','Cancelled.'); end
        r=simulate_moving_receiver_rms(c);
        if ~progress('mixing',.55), error('background:Cancelled','Cancelled.'); end
        r=mix_background_audio(r,c.background);
        drawnow;
        if cancelled, error('background:Cancelled','Cancelled.'); end
        signals=[r.direct_signal,r.reflected_signal,r.siren_signal,r.background_signal,r.final_signal];
        peak=max(abs(signals),[],'all')/c.wavFullScalePa;
        if ~isfinite(peak) || peak>=1, error('background:Clipping','共通スケールでクリッピングします。比較条件全体のPa/FSを見直してください。'); end
        drawTimeline(r); refreshInfo();
        ui.status.Value={sprintf('入力チェック PASS / 受音 %.6f s / 全成分最大 %.6f FS',numel(r.timeSec)/r.fs,peak), ...
            '保存は未実施。WAV生成を押すと現在の設定で再計算して保存します。'};
    end
    function [r,folder] = generate()
        % Render and export with the original runner, then display its outputs.
        beginWork(); cleanup=onCleanup(@()finishWork(fig,ui,editable,browseButtons,resultButtons));
        c=getConfig(); [r,folder]=run_background_simulation(c,@progress);
        lastResult=r; lastOutput=folder; setappdata(fig,'HasResult',true); drawTimeline(r);
        ui.waveImage.ImageSource=''; ui.specImage.ImageSource='';
        if c.makeFigures
            ui.waveImage.ImageSource=fullfile(folder,'background_waveforms.png');
            ui.specImage.ImageSource=fullfile(folder,'background_spectrograms.png');
        end
        ui.resultLabel.Text=['生成済み（設定変更後もこの結果を再生）: ' char(r.simulationId)];
        set(resultButtons,'Enable','on'); tabs.SelectedTab=resultTab;
        ui.status.Value={['保存完了: ' folder],sprintf('合成音最大 %.6f FS / 正規化なし / 共通 %.6f Pa/FS',max(abs(r.final_signal))/c.wavFullScalePa,c.wavFullScalePa)};
    end
    function beginWork()
        % Acquire single-run lock and stop playback before numerical work.
        if isBusy(), error('backgroundGUI:Busy','既に処理中です。'); end
        setappdata(fig,'Busy',true); setappdata(fig,'Saving',false); cancelled=false; lastError=''; stopAudio();
        syncEnabled(); set(resultButtons,'Enable','off'); ui.cancelButton.Enable='on';
    end
    function keepGoing = progress(stage,fraction)
        % Process queued UI events at safe boundaries; fraction is a phase estimate.
        ui.status.Value={sprintf('処理中: %s (%d%%) / キャンセルは次の処理区切りで反映',stage,round(100*fraction))};
        drawnow; keepGoing=~cancelled;
        if strcmp(stage,'saving') && keepGoing
            setappdata(fig,'Saving',true); ui.cancelButton.Enable='off';
            ui.status.Value={'WAV・CSV・MAT・図を保存中。保存開始後は中断せず完了を待ちます。'}; drawnow;
        end
    end
    function beginBatch()
        % Share the single-run lock with batch actions; never overlap renderers.
        beginWork(); setappdata(fig,'BatchRunning',true);
    end
    function keepGoing = batchProgress(stage,index,total)
        % Cancel may be queued during saving, but the current save completes.
        setappdata(fig,'Saving',strcmp(stage,'saving'));
        ui.cancelButton.Enable='on';
        ui.status.Value={sprintf('一括処理 %d / %d: %s',index,total,stage), ...
            'キャンセルは計算の区切りで反映。保存中の場合は現在の条件の保存完了後に停止。'};
        drawnow; keepGoing=~cancelled;
    end
    function requestCancel()
        % Request cancellation before saving, never truncate an active export.
        if isBusy() && (~getappdata(fig,'Saving') || getappdata(fig,'BatchRunning'))
            cancelled=true; ui.status.Value={'キャンセル受付済み。現在の計算区間が終わるまでお待ちください。'};
        end
    end
    function drawTimeline(r)
        % Plot actual sample-quantized placement and simultaneous geometric CPA.
        ax=ui.timeline; cla(ax); hold(ax,'on');
        plot(ax,[0,numel(r.timeSec)/r.fs],[2,2],'LineWidth',8); info=r.backgroundInfo;
        if info.Enabled, plot(ax,[info.ActualStartSec,info.ActualEndExclusiveSec],[1,1],'LineWidth',8); end
        if isfinite(info.GeometricCpaTimeSec) && info.GeometricCpaTimeSec>=0 && info.GeometricCpaTimeSec<=r.timeSec(end)
            xline(ax,info.GeometricCpaTimeSec,'--','幾何学的CPA');
        end
        hold(ax,'off'); ax.XLim=[0,numel(r.timeSec)/r.fs]; ax.YLim=[0,3];
        title(ax,'検証済み配置（背景音区間はAI正解ラベルではありません）'); grid(ax,'on');
    end
    function previewAudio(isBackground)
        % Audition original PCM/crop only: no calibration/fade/loudness boost.
        if isBusy(), return; end
        c=getConfig(); stopAudio();
        if isBackground
            a=audioinfo(c.background.file); first=round(c.background.sourceStartSec*a.SampleRate)+1;
            count=round(c.background.durationSec*a.SampleRate);
            if count<2 || first+count-1>a.TotalSamples, error('backgroundGUI:Crop','背景音の切出しがファイル範囲外です。'); end
            [y,fs]=audioread(c.background.file,[first,first+count-1]);
        else
            [y,fs]=audioread(c.inputFile);
        end
        player=audioplayer(mean(y,2),fs); play(player);
        ui.status.Value={'原音PCMを試聴中（校正・合成前）。生成後の試聴とは音量が異なります。'};
    end
    function playResult(component)
        % Audition a completed component using its saved common Pa/FS scale.
        if isBusy() || isempty(lastResult), return; end
        stopAudio(); y=lastResult.([component '_signal'])/lastResult.config.wavFullScalePa;
        player=audioplayer(y,lastResult.fs); play(player);
        ui.status.Value={['生成済み ' component ' を共通WAVスケールで再生中（自動音量調整なし）']};
    end
    function stopAudio()
        % Stop and release the current audio player, if any.
        if ~isempty(player), stop(player); player=[]; end
    end
    function openOutput()
        % Open the last successful output folder in Windows Explorer.
        if ~isBusy() && isfolder(lastOutput), winopen(lastOutput); end
    end
    function openFigure()
        % Open the selected saved PNG at full size in the system image viewer.
        if isBusy() || isempty(lastResult), return; end
        filename='background_waveforms.png';
        if views.SelectedTab==st, filename='background_spectrograms.png'; end
        path=fullfile(lastOutput,filename);
        if ~isfile(path), error('backgroundGUI:NoFigure','図を保存していません。PNG保存を有効にして再生成してください。'); end
        winopen(path);
    end
    function saveConfig(path)
        % Save configuration and schema version only; no executable GUI state.
        if isBusy(), error('backgroundGUI:Busy','処理中です。'); end
        payload=struct('config',getConfig(),'schemaVersion',1,'batch',batchUI.getSettings()); save(path,'-struct','payload');
    end
    function loadConfig(path)
        % Load an explicitly selected GUI settings MAT, validate, then apply.
        if isBusy(), error('backgroundGUI:Busy','処理中です。'); end
        loaded=load(path);
        if ~isfield(loaded,'schemaVersion') || ~isequal(loaded.schemaVersion,1) || ~isfield(loaded,'config')
            error('backgroundGUI:Schema','このGUIで保存した設定MATファイルを指定してください。');
        end
        if isfield(loaded,'batch'), batchUI.validateSettings(loaded.batch); end
        setConfig(loaded.config);
        if isfield(loaded,'batch'), batchUI.setSettings(loaded.batch); end
    end
    function saveDialog()
        % Prompt for a settings file; cancellation leaves settings unchanged.
        [name,folder]=uiputfile('*.mat','設定保存','background_gui_config.mat');
        if ~isequal(name,0), saveConfig(fullfile(folder,name)); ui.status.Value={'設定を保存しました。'}; end
    end
    function resetDefaults()
        % Reset both single-condition and sweep settings, never saved results.
        setConfig(background_simulation_config()); batchUI.setSettings(background_batch_config());
    end
    function loadDialog()
        % Prompt for a settings file; cancellation leaves settings unchanged.
        [name,folder]=uigetfile('*.mat','設定読込');
        if ~isequal(name,0), loadConfig(fullfile(folder,name)); end
    end
    function state = getState()
        % Return minimal runtime state for noninteractive smoke/regression tests.
        state=struct('busy',isBusy(),'cancelled',cancelled,'saving',getappdata(fig,'Saving'),'outputDir',lastOutput,'lastError',lastError);
    end
    function guard(callback)
        % Display callback errors in the status area, leaving controls usable.
        try
            callback();
        catch exception
            lastError=exception.identifier;
            ui.status.Value={['処理を完了できませんでした: ' exception.message],exception.identifier};
        end
    end
    function closeRequested(~,~)
        % Stop playback on close; busy closing requests cancellation instead.
        if isBusy()
            requestCancel(); ui.status.Value={'処理中は閉じられません。計算のキャンセル／保存の完了後にもう一度閉じてください。'}; return;
        end
        stopAudio(); delete(fig);
    end
end

function finishWork(fig,ui,editable,browseButtons,resultButtons)
% Release lock and restore controls after success/error/cancel. Inputs are
% captured handle values, NOT mutable parent-workspace variables in onCleanup.
if ~isvalid(fig), return; end
setappdata(fig,'Busy',false); setappdata(fig,'Saving',false);
setappdata(fig,'BatchRunning',false);
set(ui.cancelButton,'Enable','off'); setControlStates(fig,ui,editable,browseButtons);
set(resultButtons,'Enable',enableValue(getappdata(fig,'HasResult')));
end

function setControlStates(fig,ui,editable,browseButtons)
% Set control availability from current widget values and runtime Busy state.
busy=getappdata(fig,'Busy');
for j=1:numel(editable), ui.(editable{j}).Enable=enableValue(~busy); end
ui.sourceSpeed.Enable=enableValue(~busy && ~ui.sourceStationary.Value); ui.sourceHeading.Enable=ui.sourceSpeed.Enable;
ui.receiverSpeed.Enable=enableValue(~busy && ~ui.receiverStationary.Value); ui.receiverHeading.Enable=ui.receiverSpeed.Enable;
ui.reflectionCoefficient.Enable=enableValue(~busy && ui.reflectionEnabled.Value);
bgKeys={'backgroundFile','timeReference','startOffset','sourceStart','duration','fadeMs','backgroundMode'};
for j=1:numel(bgKeys), ui.(bgKeys{j}).Enable=enableValue(~busy && ui.backgroundEnabled.Value); end
ui.backgroundSpl.Enable=enableValue(~busy && ui.backgroundEnabled.Value && strcmp(ui.backgroundMode.Value,'fixed_rms'));
ui.snr.Enable=enableValue(~busy && ui.backgroundEnabled.Value && strcmp(ui.backgroundMode.Value,'snr'));
set([ui.checkButton,ui.generateButton,ui.saveButton,ui.loadButton,ui.resetButton,reshape(browseButtons,1,[])],'Enable',enableValue(~busy));
if isappdata(fig,'BatchSetEnabled'), callback=getappdata(fig,'BatchSetEnabled'); callback(~busy); end
end

function value = enableValue(condition)
% Logical input -> MATLAB UI Enable string.
if condition, value='on'; else, value='off'; end
end
