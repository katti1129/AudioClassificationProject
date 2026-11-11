function controller = add_background_batch_tab(tabs,host)
%ADD_BACKGROUND_BATCH_TAB Attach sweep UI without duplicating acoustic models.
% Inputs: existing uitabgroup, host callbacks for shared config/lock/cancel/status.
% Output: controller methods and controls for settings, plan, check and generate.
% Distances are horizontal CPA [m], Source speed [km/h], common CPA time [s].
tab=uitab(tabs,'Title','6. 一括生成');
g=uigridlayout(tab,[5,1]); g.RowHeight={80,48,38,'1x',38};
top=uigridlayout(g,[2,4]); top.ColumnWidth={210,'1x',210,'1x'};
uilabel(top,'Text','水平最近接距離の一覧 [m]'); distance=uieditfield(top,'text','Value','5, 10, 20, 40','ValueChangedFcn',@stale);
uilabel(top,'Text','Source速度の一覧 [km/h]'); speed=uieditfield(top,'text','Value','20, 40, 60','ValueChangedFcn',@stale);
uilabel(top,'Text','共通の幾何学的CPA時刻 [s]'); cpa=uieditfield(top,'numeric','Limits',[0,Inf],'Value',4,'ValueChangedFcn',@stale);
uilabel(top,'Text','数値をカンマ・空白で区切る'); uilabel(top,'Text','最大1000条件 / 同じ値の重複不可');
note=uitextarea(g,'Editable','off','Value',{'Source初期x/y・速度・静止指定は一括条件で上書き。方向・高さ・Receiver・背景音・Pa/FSは他タブと共通。', ...
    '固定RMS SPLを基本とします。SNRを選んだ場合は条件ごとに背景音圧が変わります。'});
note.Tooltip='最近接時刻は同時刻の幾何配置です。到達遅延後の音圧ピーク時刻ではありません。';
bar=uigridlayout(g,[1,5]); bar.Padding=[0,0,0,0];
planButton=uibutton(bar,'Text','条件一覧を作成','ButtonPushedFcn',@(~,~)guard(@plan));
checkButton=uibutton(bar,'Text','全条件をチェック','ButtonPushedFcn',@(~,~)guard(@()run('check')));
generateButton=uibutton(bar,'Text','一括生成','FontWeight','bold','ButtonPushedFcn',@(~,~)guard(@()run('generate')));
folderButton=uibutton(bar,'Text','一括結果フォルダ','ButtonPushedFcn',@(~,~)guard(@openBatch));
rowButton=uibutton(bar,'Text','選択条件の出力','ButtonPushedFcn',@(~,~)guard(@openRow));
grid=uitable(g,'Data',table(),'CellSelectionCallback',@selectRow,'ColumnEditable',false);
label=uilabel(g,'Text','一覧未作成。設定を変更したら再作成／再チェックしてください。');
report=table(); outputDir=''; selectedRow=[]; lastError='';
controller=struct('tab',tab,'plan',@plan,'check',@()run('check'),'generate',@()run('generate'), ...
    'getSettings',@getSettings,'setSettings',@setSettings,'validateSettings',@validateSettings,'getState',@getState, ...
    'setEnabled',@setEnabled,'invalidate',@stale, ...
    'controls',struct('distance',distance,'speed',speed,'cpa',cpa,'table',grid,'label',label, ...
    'planButton',planButton,'checkButton',checkButton,'generateButton',generateButton));

    function batch = getSettings()
        % Read literal lists and shared Source heading; never eval user text.
        batch=background_batch_config();
        batch.distancesM=parse_background_batch_values(distance.Value);
        batch.sourceSpeedsKmh=parse_background_batch_values(speed.Value);
        batch.cpaTimeSec=cpa.Value; batch.sourceHeadingDeg=host.getHeading();
    end
    function setSettings(batch)
        % Validate all sweep fields before modifying UI; retain shared heading.
        if host.isBusy(), error('backgroundGUI:Busy','処理中です。'); end
        [d,v]=validateSettings(batch);
        distance.Value=char(d); speed.Value=char(v); cpa.Value=batch.cpaTimeSec;
        host.setHeading(batch.sourceHeadingDeg); stale();
    end
    function [d,v] = validateSettings(batch)
        % Validate settings without mutating UI, including before loading files.
        validateattributes(batch.distancesM,{'numeric'},{'nonempty','vector','real','finite','nonnegative'});
        validateattributes(batch.sourceSpeedsKmh,{'numeric'},{'nonempty','vector','real','finite','nonnegative'});
        validateattributes(batch.cpaTimeSec,{'numeric'},{'scalar','real','finite','nonnegative'});
        validateattributes(batch.sourceHeadingDeg,{'numeric'},{'scalar','real','finite','>=',-180,'<=',180});
        d=strjoin(compose('%.17g',batch.distancesM),', '); v=strjoin(compose('%.17g',batch.sourceSpeedsKmh),', ');
        parse_background_batch_values(d); parse_background_batch_values(v);
        if numel(batch.distancesM)*numel(batch.sourceSpeedsKmh)>1000, error('backgroundBatch:TooMany','Maximum 1000 conditions.'); end
    end
    function value = plan()
        % Cheap geometry/header check only; no expensive audio or output writes.
        if host.isBusy(), error('backgroundGUI:Busy','処理中です。'); end
        value=background_batch_plan(host.getConfig(),getSettings()); report=value;
        selectedRow=[]; updateTable();
        label.Text=sprintf('%d条件 / 幾何設定OK %d / INVALID %d。音声処理の検査は「全条件をチェック」。',height(report),sum(report.Status=="READY"),sum(report.Status=="INVALID"));
    end
    function [value,folder] = run(mode)
        % Snapshot shared/sweep settings, take host lock, process sequentially.
        if host.isBusy(), error('backgroundGUI:Busy','処理中です。'); end
        c=host.getConfig(); b=getSettings();
        host.begin(); cleanup=onCleanup(@()finishHost(host));
        lastError='';
        [value,folder]=run_background_batch(c,b,mode,@progress);
        report=value; outputDir=folder; updateTable();
        label.Text=sprintf('SUCCESS %d / PASS %d / FAIL %d / CANCELLED %d / NOT_RUN %d', ...
            sum(report.Status=="SUCCESS"),sum(report.Status=="PASS"),sum(report.Status=="FAIL"),sum(report.Status=="CANCELLED"),sum(report.Status=="NOT_RUN"));
        host.status({label.Text,['一覧CSV: ' char(fullfile(folder,'conditions.csv'))]});
    end
    function keepGoing = progress(stage,index,total,snapshot)
        % Update table and service host cancellation, including between conditions.
        report=snapshot; updateTable();
        label.Text=sprintf('%d / %d 条件: %s',index,total,stage);
        keepGoing=host.progress(stage,index,total);
    end
    function updateTable()
        % Show compact columns; full audit fields remain in report/CSV.
        if isempty(report), grid.Data=table(); return; end
        columns={'ConditionID','HorizontalCpaRequestedM','SourceSpeedKmh','GeometricCpaTimeSec','Cpa3DM','Status','ActualSnrDb','Message'};
        grid.Data=report(:,columns);
        grid.ColumnName={'条件ID','水平CPA [m]','Source [km/h]','CPA [s]','3D CPA [m]','状態','SNR [dB]','詳細'};
        grid.ColumnWidth={180,95,110,95,100,105,90,300};
    end
    function stale(varargin)
        % Preserve old results explicitly as stale; every run rebuilds the plan.
        label.Text='設定変更あり：表示中の一覧は旧条件です。再作成／再チェックしてください。';
    end
    function setEnabled(enabled)
        % Mirror the host busy lock across all batch fields and buttons.
        value='off'; if enabled, value='on'; end
        controls={distance,speed,cpa,planButton,checkButton,generateButton,folderButton,rowButton};
        for j=1:numel(controls), set(controls{j},'Enable',value); end
    end
    function selectRow(~,event)
        % Remember a clicked row; sorting is not enabled, so CSV order is stable.
        if ~isempty(event.Indices), selectedRow=event.Indices(1,1); end
    end
    function openBatch()
        % Open last completed batch/check folder; cancellation keeps its manifest.
        if isfolder(outputDir), winopen(outputDir); end
    end
    function openRow()
        % Open only a selected condition's successful output, not stale config.
        if isempty(selectedRow) || selectedRow>height(report), error('backgroundBatch:Select','結果の行を選択してください。'); end
        path=report.OutputDirectory(selectedRow);
        if strlength(path)==0 || ~isfolder(path), error('backgroundBatch:NoOutput','この条件に保存済みWAVはありません。'); end
        winopen(path);
    end
    function state = getState()
        % Return manifest and path for tests and scripted usage.
        state=struct('report',report,'outputDir',outputDir,'lastError',lastError);
    end
    function guard(callback)
        % Keep UI alive on global/plan errors; numerical row errors stay in CSV.
        try
            callback();
        catch exception
            lastError=exception.identifier; host.status({exception.identifier,exception.message});
        end
    end
end

function finishHost(host)
% Release host state via captured callbacks, also after errors/cancellation.
host.finish();
end
