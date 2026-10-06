function app = dataset_generator(baseConfig, visible)
%DATASET_GENERATOR Open the MATLAB GUI for sequential acoustic dataset creation.
%   APP = DATASET_GENERATOR(CONFIG,VISIBLE) uses existing CONFIG as a template.
%   With no arguments, DEFAULT_CONFIG is used. VISIBLE defaults to 'on'.
%   APP exposes controls and callbacks for repeatable GUI smoke tests.
if nargin<1, baseConfig=default_config(); end
if nargin<2, visible='on'; end
schema=pipeline.condition_schema();
options=pipeline.default_options();
rows=pipeline.default_conditions(10,baseConfig);
cancelRequested=false; selection=[];
status=strings(height(rows),1);
inputFolder=fileparts(baseConfig.audio.inputFile);
found=dir(fullfile(inputFolder,'*.wav'));
sources=string(fullfile({found.folder},{found.name}))';
sources=unique([string(baseConfig.audio.inputFile);sources],'stable');
fig=uifigure('Name','救急車音響シミュレーション — データセット生成', ...
    'Position',[40 50 1450 850],'Visible',visible,'CloseRequestFcn',@closeRequested);
setappdata(fig,'Busy',false);
layout=uigridlayout(fig,[8 1]);
layout.RowHeight={44,42,225,30,'1x',32,52,54};
layout.Padding=[14 12 14 12]; layout.RowSpacing=8;
top=uigridlayout(layout,[1 8]);
top.ColumnWidth={100,80,120,95,90,120,'1x',120};
uilabel(top,'Text','生成する音源数');
count=uieditfield(top,'numeric','Value',height(rows),'Limits',[1 100000], ...
    'RoundFractionalValues','on');
generate=uibutton(top,'Text','設定行を生成','ButtonPushedFcn',@(~,~)generateRows());
uilabel(top,'Text','開始 Seed');
startSeed=uieditfield(top,'numeric','Value',baseConfig.obstacle.seed, ...
    'Limits',[0 2^32-1],'RoundFractionalValues','on');
seedButton=uibutton(top,'Text','Seed 自動割当','ButtonPushedFcn',@(~,~)assignSeeds());
uilabel(top,'Text','1行 = 最終受音WAV 1個（速度の符号で方向を指定）');
addSource=uibutton(top,'Text','WAV を追加','ButtonPushedFcn',@(~,~)browseSource());
destination=uigridlayout(layout,[1 7]);
destination.ColumnWidth={90,'1x',65,95,180,95,110};
uilabel(destination,'Text','保存先の親');
parent=uieditfield(destination,'text','Value',options.datasetParent);
browseParent=uibutton(destination,'Text','参照','ButtonPushedFcn',@(~,~)selectParent());
uilabel(destination,'Text','Dataset 名');
datasetName=uieditfield(destination,'text','Value',options.datasetName);
uilabel(destination,'Text','同名の処理');
collision=uidropdown(destination,'Items',{'Rename','Skip','Overwrite'},'Value','Rename');
panel=uipanel(layout,'Title','共通設定 — 全行または選択行へ適用');
commonGrid=uigridlayout(panel,[4 7]);
commonGrid.RowHeight={24,42,24,42};
commonGrid.ColumnWidth=repmat({'1x'},1,7);
fields=schema.names(2:end);
controls=struct();
common=rows(1,:);
for k=1:numel(fields)
    field=fields{k};
    block=floor((k-1)/7);
    col=mod(k-1,7)+1;
    label=uilabel(commonGrid,'Text',schema.labels{k+1});
    label.Layout.Row=1+2*block; label.Layout.Column=col;
    value=common.(field);
    if strcmp(field,'InputWAV')
        control=uidropdown(commonGrid,'Items',sourceLabels(), ...
            'ItemsData',cellstr(sources),'Value',char(value));
    elseif strcmp(field,'Profile')
        control=uidropdown(commonGrid,'Items',schema.profiles,'Value',char(value));
    elseif ismember(field,schema.logicalNames)
        control=uicheckbox(commonGrid,'Text','ON','Value',logical(value));
    else
        % NaN represents the absence of a ground plane, displayed explicitly.
        if isnan(value), value=0; end
        control=uieditfield(commonGrid,'numeric','Value',value);
        if strcmp(field,'GroundReflectionCoeff')&&isempty(pipeline.ground_plane_index(baseConfig))
            control.Enable='off'; control.Tooltip='ground平面がないため適用しません。';
        end
    end
    control.Layout.Row=2+2*block; control.Layout.Column=col;
    controls.(field)=control;
end
notice=uilabel(layout,'Text', ...
    'CPA欄 = x方向移動の横間隔。観測中の実際のCPAはmanifestへ記録。R = 地面のみ。RV = Receiver速度。');
notice.FontColor=[0.30 0.35 0.42];
conditions=uitable(layout,'ColumnName',[schema.labels,{'Status'}], ...
    'ColumnEditable',[false true(1,numel(schema.names)-1) false], ...
    'RowName',[],'CellSelectionCallback',@selectRows,'CellEditCallback',@editCell);
formats=repmat({'numeric'},1,numel(schema.names));
formats{2}=cellstr(sources)';
formats{6}=schema.profiles;
for logicalName=schema.logicalNames
    formats{strcmp(schema.names,logicalName{1})}='logical';
end
conditions.ColumnFormat=[formats,{'char'}];
conditions.ColumnWidth={45,240,100,110,110,165,115,115,85,100,65,65,90,65,65,100};
actions=uigridlayout(layout,[1 8]);
actions.Padding=[0 0 0 0];
actions.ColumnWidth={120,130,110,110,160,140,'1x',160};
applyAll=uibutton(actions,'Text','全行に適用','ButtonPushedFcn',@(~,~)applyCommon(false));
applySelected=uibutton(actions,'Text','選択行に適用','ButtonPushedFcn',@(~,~)applyCommon(true));
saveButton=uibutton(actions,'Text','Save Config','ButtonPushedFcn',@(~,~)saveDialog());
loadButton=uibutton(actions,'Text','Load Config','ButtonPushedFcn',@(~,~)loadDialog());
figuresCheck=uicheckbox(actions,'Text','各条件の図を保存','Value',options.writeFigures);
matCheck=uicheckbox(actions,'Text','物理量MATを保存','Value',options.writeMat);
uilabel(actions,'Text','設定・障害物Excelは全条件で保存');
previewButton=uibutton(actions,'Text','条件名を確認','ButtonPushedFcn',@(~,~)previewName());
execution=uigridlayout(layout,[1 4]);
execution.ColumnWidth={210,160,'1x',100};
runButton=uibutton(execution,'Text','データセット生成開始','FontWeight','bold', ...
    'ButtonPushedFcn',@(~,~)startBatch());
cancelButton=uibutton(execution,'Text','現在の条件の後で停止','Enable','off', ...
    'ButtonPushedFcn',@(~,~)requestCancel());
progress=uigauge(execution,'linear','Limits',[0 100],'Value',0, ...
    'MajorTicks',[0 25 50 75 100]);
counter=uilabel(execution,'Text',sprintf('0 / %d',height(rows)));
current=uilabel(layout,'Text','設定行を編集して開始してください。', ...
    'WordWrap','on','Interpreter','none');
refreshTable();
controls.Seed.Enable='off';
controls.Seed.Tooltip='全行・選択行への共通適用ではSeedを維持します。上部の自動割当または表で編集してください。';
app.Figure=fig;
app.Controls=struct('Count',count,'StartSeed',startSeed,'Common',controls, ...
    'Table',conditions,'Parent',parent,'DatasetName',datasetName,'Collision',collision, ...
    'SaveFigures',figuresCheck,'SaveMat',matCheck,'Run',runButton,'Cancel',cancelButton, ...
    'Progress',progress,'Counter',counter,'Current',current);
app.getRows=@getRows;
app.generateRows=@generateRows;
app.applyAll=@()applyCommon(false);
app.applySelected=@()applyCommon(true);
app.assignSeeds=@assignSeeds;
app.saveConfig=@saveFile;
app.loadConfig=@loadFile;
app.run=@startBatch;
fig.UserData=app;

    function value=getRows()
        value=rows;
    end

    function value=isCancelled()
        value=cancelRequested;
    end

    function labels=sourceLabels()
        labels=cell(size(sources));
        for j=1:numel(sources)
            [~,stem,ext]=fileparts(sources(j));
            labels{j}=sprintf('%s%s (%d)',stem,ext,j);
        end
    end

    function refreshTable()
        data=table2cell(rows);
        for j=[2 6]
            data(:,j)=cellstr(string(rows.(schema.names{j})));
        end
        conditions.Data=[data,cellstr(status)];
        count.Value=height(rows);
        conditions.ColumnFormat{2}=cellstr(sources)';
        if ~getappdata(fig,'Busy')
            counter.Text=sprintf('0 / %d',height(rows));
        end
    end

    function generateRows()
        if getappdata(fig,'Busy'), return; end
        rows=pipeline.default_conditions(count.Value,baseConfig);
        status=strings(height(rows),1); selection=[];
        refreshTable();
        current.Text='行を生成しました。共通設定は「全行に適用」で反映します。';
    end

    function selectRows(~,event)
        if isempty(event.Indices), selection=[]; else, selection=unique(event.Indices(:,1)); end
    end

    function editCell(~,event)
        if getappdata(fig,'Busy'), refreshTable(); return; end
        i=event.Indices(1); j=event.Indices(2);
        if j>numel(schema.names), return; end
        field=schema.names{j}; value=event.NewData;
        try
            if ismember(field,{'InputWAV','Profile'}), value=string(value); end
            rows.(field)(i)=value;
            status(i)="";
        catch exception
            current.Text=exception.message;
        end
        refreshTable();
    end

    function applyCommon(selectedOnly)
        if getappdata(fig,'Busy'), return; end
        indices=(1:height(rows))';
        if selectedOnly, indices=selection; end
        if isempty(indices), current.Text='適用する行をテーブルで選択してください。'; return; end
        commonRow=rows(1,:);
        for j=1:numel(fields)
            field=fields{j};
            value=controls.(field).Value;
            if ismember(field,{'InputWAV','Profile'}), value=string(value); end
            if strcmp(field,'GroundReflectionCoeff')&&isempty(pipeline.ground_plane_index(baseConfig))
                value=NaN;
            end
            commonRow.(field)=value;
        end
        rows=pipeline.apply_common(rows,commonRow,indices);
        status(indices)=""; refreshTable();
    end

    function assignSeeds()
        if getappdata(fig,'Busy'), return; end
        try
            rows=pipeline.assign_seeds(rows,startSeed.Value);
            status(:)=""; refreshTable();
        catch exception
            current.Text=exception.message;
        end
    end

    function opts=getOptions()
        opts=options;
        opts.datasetParent=parent.Value;
        opts.datasetName=datasetName.Value;
        opts.collisionPolicy=collision.Value;
        opts.writeFigures=figuresCheck.Value;
        opts.writeMat=matCheck.Value;
    end

    function saveFile(filename)
        pipeline.save_dataset_config(filename,rows,baseConfig,getOptions());
        current.Text=['設定を保存しました: ',char(filename)];
    end

    function loadFile(filename)
        if getappdata(fig,'Busy'), return; end
        [rows,baseConfig,options]=pipeline.load_dataset_config(filename);
        sources=unique([sources;string(rows.InputWAV)],'stable');
        controls.InputWAV.Items=sourceLabels();
        controls.InputWAV.ItemsData=cellstr(sources);
        for j=1:numel(fields)
            field=fields{j}; value=rows.(field)(1);
            if ismember(field,{'InputWAV','Profile'}), value=char(value); end
            if isnumeric(value)&&isnan(value), value=0; end
            controls.(field).Value=value;
        end
        if isempty(pipeline.ground_plane_index(baseConfig))
            controls.GroundReflectionCoeff.Enable='off';
        else
            controls.GroundReflectionCoeff.Enable='on';
        end
        parent.Value=options.datasetParent; datasetName.Value=options.datasetName;
        collision.Value=options.collisionPolicy;
        figuresCheck.Value=options.writeFigures; matCheck.Value=options.writeMat;
        status=strings(height(rows),1); selection=[];
        refreshTable();
        current.Text=['設定を読み込みました: ',char(filename)];
    end

    function saveDialog()
        [file,folder]=uiputfile('*.mat','Save dataset config','dataset_config.mat');
        if isequal(file,0), return; end
        try
            saveFile(fullfile(folder,file));
        catch exception
            current.Text=exception.message;
        end
    end

    function loadDialog()
        [file,folder]=uigetfile('*.mat','Load dataset config');
        if isequal(file,0), return; end
        try
            loadFile(fullfile(folder,file));
        catch exception
            current.Text=exception.message;
        end
    end

    function browseSource()
        [file,folder]=uigetfile('*.wav','入力WAVを追加','MultiSelect','on');
        if isequal(file,0), return; end
        added=string(fullfile(folder,cellstr(file)));
        sources=unique([sources;added(:)],'stable');
        controls.InputWAV.Items=sourceLabels();
        controls.InputWAV.ItemsData=cellstr(sources);
        refreshTable();
    end

    function selectParent()
        folder=uigetdir(parent.Value,'データセット保存先の親フォルダ');
        if ~isequal(folder,0), parent.Value=folder; end
    end

    function previewName()
        index=1;
        if ~isempty(selection), index=selection(1); end
        try
            config=pipeline.row_to_config(rows(index,:),baseConfig);
            current.Text=char(pipeline.build_experiment_name(config));
        catch exception
            current.Text=sprintf('行 %d: %s',index,exception.message);
        end
    end

    function [manifest,attempts]=startBatch()
        manifest=table(); attempts=table();
        if getappdata(fig,'Busy'), return; end
        opts=getOptions();
        try
            pipeline.validate_config(rows,opts);
            if strcmp(opts.collisionPolicy,'Overwrite') && strcmp(fig.Visible,'on')
                answer=uiconfirm(fig, ...
                    '同名の既存結果を _history へ退避して置き換えます。続行しますか？', ...
                    'Overwrite の確認','Options',{'実行','キャンセル'}, ...
                    'DefaultOption',2,'CancelOption',2);
                if ~strcmp(answer,'実行'), return; end
            end
            setappdata(fig,'Busy',true); cancelRequested=false;
            previousHandles=findall(fig,'-property','Enable');
            previousStates=get(previousHandles,'Enable');
            cleanup=onCleanup(@()restoreControls(fig,previousHandles,previousStates));
            setBusy(true);
            opts.progressFcn=@updateProgress;
            opts.cancelFcn=@isCancelled;
            [manifest,attempts]=pipeline.run_batch(rows,baseConfig,opts);
            current.Text=sprintf('成功 %d / 失敗 %d / スキップ %d / 中止 %d。manifest: %s', ...
                nnz(status=="SUCCESS"),nnz(status=="FAILED"), ...
                nnz(status=="SKIPPED"),nnz(status=="CANCELLED"), ...
                fullfile(opts.datasetParent,opts.datasetName,'dataset_manifest.xlsx'));
        catch exception
            current.Text=['実行エラー: ',exception.message];
            if nargout>0, rethrow(exception); end
        end
    end

    function updateProgress(event)
        progress.Value=100*event.completed/event.total;
        counter.Text=sprintf('%d / %d',event.completed,event.total);
        status(event.row)=event.status;
        refreshTable();
        current.Text=char(event.status+": "+event.name+" "+event.message);
        drawnow;
    end

    function requestCancel()
        cancelRequested=true;
        current.Text='停止予約済みです。現在のシミュレーション完了後に停止します。';
    end

    function setBusy(value)
        state='on'; if value, state='off'; end
        handles=[count,startSeed,generate,seedButton,addSource,parent,browseParent, ...
            datasetName,collision,applyAll,applySelected,saveButton,loadButton, ...
            figuresCheck,matCheck,previewButton,runButton];
        for h=handles, h.Enable=state; end
        for j=1:numel(fields), controls.(fields{j}).Enable=state; end
        controls.Seed.Enable='off';
        if isempty(pipeline.ground_plane_index(baseConfig))
            controls.GroundReflectionCoeff.Enable='off';
        end
        conditions.Enable=state;
        if value, cancelButton.Enable='on'; else, cancelButton.Enable='off'; end
    end

    function closeRequested(~,~)
        if getappdata(fig,'Busy'), requestCancel(); else, delete(fig); end
    end
end

function restoreControls(fig,handles,states)
%RESTORECONTROLS Restore captured handle states after success/error/interrupt.
if ~isvalid(fig), return; end
setappdata(fig,'Busy',false);
for k=1:numel(handles)
    if isvalid(handles(k)), handles(k).Enable=states{k}; end
end
end
