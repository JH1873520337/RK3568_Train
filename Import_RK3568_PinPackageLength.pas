{******************************************************************************
  Import_RK3568_PinPackageLength.pas

  Altium Designer 22 DelphiScript
  Updates every RK3568 multipart component placed on SOC_*.SchDoc sheets in
  the focused project. Pin package lengths are read from a CSV file.
******************************************************************************}

const
    CsvFile = 'E:\AD_Project\RK3568_train\RK3568_train\RK3568_PinPackageLength_A1.csv';
    TargetDocumentText = 'SOC_';
    TargetLibraryText  = 'RK3568';

function TrimQuotes(S : String) : String;
begin
    Result := Trim(S);
    if (Length(Result) >= 2) and (Result[1] = '"') and
       (Result[Length(Result)] = '"') then
        Result := Copy(Result, 2, Length(Result) - 2);
end;

function LookupLength(PinId : String; Map : TStringList) : String;
var
    I : Integer;
    Key : String;
begin
    Result := '';
    Key := UpperCase(Trim(PinId));
    for I := 0 to Map.Count - 1 do
        if SameText(Map.Names[I], Key) then begin
            Result := Map.ValueFromIndex[I];
            Exit;
        end;
end;

function IsTargetComponent(Comp : ISch_Component) : Boolean;
begin
    Result := Pos(TargetLibraryText, UpperCase(Comp.LibReference)) > 0;
end;

procedure UpdateComponentPins(Comp : ISch_Component; Map : TStringList;
                              var Updated : Integer; var Missing : Integer);
var
    PinIterator : ISch_Iterator;
    Pin : ISch_Pin;
    PinId, LenText : String;
    LenCoord : TCoord;
begin
    PinIterator := Comp.SchIterator_Create;
    try
        PinIterator.AddFilter_ObjectSet(MkSet(ePin));
        Pin := PinIterator.FirstSchObject;
        while Pin <> nil do begin
            PinId := UpperCase(Trim(Pin.Designator));
            LenText := LookupLength(PinId, Map);
            if LenText <> '' then begin
                SchServer.RobotManager.SendMessage(Pin.I_ObjectAddress,
                    c_BroadCast, SCHM_BeginModify, c_NoEventData);
                StringToCoordUnit(LenText, LenCoord, eImperial);
                Pin.PinPackageLength := LenCoord;
                SchServer.RobotManager.SendMessage(Pin.I_ObjectAddress,
                    c_BroadCast, SCHM_EndModify, c_NoEventData);
                Inc(Updated);
            end else
                Inc(Missing);
            Pin := PinIterator.NextSchObject;
        end;
    finally
        Comp.SchIterator_Destroy(PinIterator);
    end;
end;

procedure UpdateSchematic(SchDoc : ISch_Document; Map : TStringList;
                          var ComponentCount : Integer; var Updated : Integer;
                          var Missing : Integer);
var
    CompIterator : ISch_Iterator;
    Comp : ISch_Component;
    ThisSheetComponents : Integer;
begin
    ThisSheetComponents := 0;
    SchServer.ProcessControl.PreProcess(SchDoc, '');
    try
        CompIterator := SchDoc.SchIterator_Create;
        try
            CompIterator.AddFilter_ObjectSet(MkSet(eSchComponent));
            Comp := CompIterator.FirstSchObject;
            while Comp <> nil do begin
                if IsTargetComponent(Comp) then begin
                    Inc(ComponentCount);
                    Inc(ThisSheetComponents);
                    UpdateComponentPins(Comp, Map, Updated, Missing);
                end;
                Comp := CompIterator.NextSchObject;
            end;
        finally
            SchDoc.SchIterator_Destroy(CompIterator);
        end;
    finally
        SchServer.ProcessControl.PostProcess(SchDoc, '');
    end;

    if ThisSheetComponents > 0 then
        SchDoc.GraphicallyInvalidate;
end;

procedure Run;
var
    Csv, Map, Parts : TStringList;
    Line, PinId, LenText, FullPath, FileNameUpper : String;
    I, DocIndex : Integer;
    Updated, Missing, ComponentCount, SheetCount : Integer;
    Project : IProject;
    LogicalDoc : IDocument;
    ServerDoc : IServerDocument;
    SchDoc : ISch_Document;
begin
    Csv := TStringList.Create;
    Map := TStringList.Create;
    Parts := TStringList.Create;
    try
        if not FileExists(CsvFile) then begin
            ShowMessage('CSV file not found:' + #13#10 + CsvFile);
            Exit;
        end;

        Csv.LoadFromFile(CsvFile);
        Map.NameValueSeparator := '=';
        for I := 1 to Csv.Count - 1 do begin
            Line := Trim(Csv[I]);
            if Line = '' then Continue;
            Parts.CommaText := Line;
            if Parts.Count < 2 then Continue;
            PinId := UpperCase(TrimQuotes(Parts[0]));
            LenText := TrimQuotes(Parts[1]);
            if PinId <> '' then Map.Values[PinId] := LenText;
        end;

        Project := GetWorkspace.DM_FocusedProject;
        if Project = nil then begin
            ShowMessage('Open and focus the RK3568 PCB project first.');
            Exit;
        end;

        Updated := 0;
        Missing := 0;
        ComponentCount := 0;
        SheetCount := 0;

        for DocIndex := 0 to Project.DM_LogicalDocumentCount - 1 do begin
            LogicalDoc := Project.DM_LogicalDocuments(DocIndex);
            if LogicalDoc = nil then Continue;
            FullPath := LogicalDoc.DM_FullPath;
            FileNameUpper := UpperCase(ExtractFileName(FullPath));
            if UpperCase(ExtractFileExt(FullPath)) <> '.SCHDOC' then Continue;
            if Pos(TargetDocumentText, FileNameUpper) = 0 then Continue;

            SchDoc := SchServer.GetSchDocumentByPath(FullPath);
            if SchDoc = nil then begin
                ServerDoc := Client.OpenDocument('SCH', FullPath);
                if ServerDoc <> nil then
                    Client.ShowDocument(ServerDoc);
                SchDoc := SchServer.GetSchDocumentByPath(FullPath);
            end;

            if SchDoc <> nil then begin
                Inc(SheetCount);
                UpdateSchematic(SchDoc, Map, ComponentCount, Updated, Missing);
            end;
        end;

        ShowMessage('RK3568 project-wide package length update finished.' + #13#10 +
                    'Project: ' + Project.DM_ProjectFileName + #13#10 +
                    'Logical documents: ' + IntToStr(Project.DM_LogicalDocumentCount) + #13#10 +
                    'SOC sheets scanned: ' + IntToStr(SheetCount) + #13#10 +
                    'RK3568 parts found: ' + IntToStr(ComponentCount) + #13#10 +
                    'Pins updated: ' + IntToStr(Updated) + #13#10 +
                    'Pins not found in CSV: ' + IntToStr(Missing));
    finally
        Parts.Free;
        Map.Free;
        Csv.Free;
    end;
end;

begin
    Run;
end.
