codeunit 51103 "RV Excel Import"
{
    // Mismo formato que "Import from Excel" de EF Bulk Credit Memo Worksheet:
    // fila 1 = encabezado, columna A = documento (desde la fila 2).
    // Cada valor se busca como Receipt No. (indexado) o como e-NCF (LSDX NCF).

    procedure ImportFromExcel()
    var
        ExcelBuffer: Record "Excel Buffer" temporary;
        InStream: InStream;
        FileName: Text;
        SheetName: Text;
    begin
        if not UploadIntoStream(SelectFileLbl, '', ExcelFilterLbl, FileName, InStream) then
            Error(NoFileSelectedErr);

        SheetName := ExcelBuffer.SelectSheetsNameStream(InStream);
        if SheetName = '' then
            Error(InvalidFileErr);

        ExcelBuffer.OpenBookStream(InStream, SheetName);
        ExcelBuffer.ReadSheet();
        ProcessBuffer(ExcelBuffer);
    end;

    procedure DownloadImportTemplate()
    var
        ExcelBuffer: Record "Excel Buffer" temporary;
    begin
        ExcelBuffer.NewRow();
        ExcelBuffer.AddColumn('Affected Document No.', false, '', true, false, false, '', ExcelBuffer."Cell Type"::Text);
        ExcelBuffer.NewRow();
        ExcelBuffer.AddColumn('E310000000001', false, '', false, false, false, '', ExcelBuffer."Cell Type"::Text);
        ExcelBuffer.NewRow();
        ExcelBuffer.AddColumn('E310000000002', false, '', false, false, false, '', ExcelBuffer."Cell Type"::Text);
        ExcelBuffer.CreateNewBook(TemplateSheetNameLbl);
        ExcelBuffer.WriteSheet(TemplateSheetNameLbl, CompanyName(), UserId());
        ExcelBuffer.CloseBook();
        ExcelBuffer.SetFriendlyFilename('RVTransactions_ImportTemplate.xlsx');
        ExcelBuffer.OpenExcel();
    end;

    local procedure ProcessBuffer(var ExcelBuffer: Record "Excel Buffer" temporary)
    var
        RVHeader: Record "RV Transaction Header";
        TransHeader: Record "LSC Transaction Header";
        NCFIndex: Dictionary of [Text, Text];
        Progress: Dialog;
        DocumentNo: Text;
        Total: Integer;
        Processed: Integer;
        Created: Integer;
        Existing: Integer;
        NotFound: Integer;
        Found: Boolean;
        NCFIndexLoaded: Boolean;
        FirstNotFound: Text;
    begin
        ExcelBuffer.Reset();
        ExcelBuffer.SetRange("Column No.", 1);
        ExcelBuffer.SetFilter("Row No.", '>1');
        Total := ExcelBuffer.Count();
        if Total = 0 then
            Error(EmptyFileErr);

        Progress.Open(ProgressLbl);
        Progress.Update(2, Total);

        ExcelBuffer.FindSet();
        repeat
            Processed += 1;
            DocumentNo := DelChr(ExcelBuffer."Cell Value as Text", '<>', ' ');
            if DocumentNo <> '' then begin
                Found := FindByReceiptNo(TransHeader, CopyStr(DocumentNo, 1, MaxStrLen(TransHeader."Receipt No.")));
                if not Found then begin
                    if not NCFIndexLoaded then begin
                        LoadNCFIndex(NCFIndex);
                        NCFIndexLoaded := true;
                    end;
                    Found := FindByNCF(NCFIndex, DocumentNo, TransHeader);
                end;

                if not Found then begin
                    NotFound += 1;
                    if FirstNotFound = '' then
                        FirstNotFound := DocumentNo;
                end else
                    if RVHeader.Get(TransHeader."Store No.", TransHeader."POS Terminal No.", TransHeader."Transaction No.") then
                        Existing += 1
                    else begin
                        RVHeader.Init();
                        RVHeader."Store No." := TransHeader."Store No.";
                        RVHeader."POS Terminal No." := TransHeader."POS Terminal No.";
                        RVHeader."Transaction No." := TransHeader."Transaction No.";
                        RVHeader."Receipt No." := TransHeader."Receipt No.";
                        RVHeader.Date := TransHeader.Date;
                        RVHeader."LSDX NCF" := TransHeader."LSDX NCF";
                        RVHeader.Insert();
                        Created += 1;
                    end;
            end;

            if Processed mod 500 = 0 then
                Progress.Update(1, Processed);
            if Processed mod 2000 = 0 then
                Commit();
        until ExcelBuffer.Next() = 0;

        Progress.Close();
        Message(ImportResultMsg, Created, Existing, NotFound, FirstNotFound);
    end;

    local procedure FindByReceiptNo(var TransHeader: Record "LSC Transaction Header"; ReceiptNo: Code[20]): Boolean
    begin
        TransHeader.Reset();
        TransHeader.SetCurrentKey("Receipt No.", Date);
        TransHeader.SetRange("Receipt No.", ReceiptNo);
        exit(TransHeader.FindFirst());
    end;

    local procedure LoadNCFIndex(var NCFIndex: Dictionary of [Text, Text])
    var
        TransHeader: Record "LSC Transaction Header";
    begin
        // LSDX NCF no tiene índice: se recorre una sola vez, no una vez por fila.
        TransHeader.SetLoadFields("Store No.", "POS Terminal No.", "Transaction No.", "LSDX NCF");
        TransHeader.SetFilter("LSDX NCF", '<>%1', '');
        if TransHeader.FindSet() then
            repeat
                if not NCFIndex.ContainsKey(TransHeader."LSDX NCF") then
                    NCFIndex.Add(TransHeader."LSDX NCF",
                        TransHeader."Store No." + '|' + TransHeader."POS Terminal No." + '|' + Format(TransHeader."Transaction No.", 0, 9));
            until TransHeader.Next() = 0;
    end;

    local procedure FindByNCF(var NCFIndex: Dictionary of [Text, Text]; NCF: Text; var TransHeader: Record "LSC Transaction Header"): Boolean
    var
        IndexValue: Text;
        Parts: List of [Text];
        TransactionNo: Integer;
    begin
        if not NCFIndex.Get(NCF, IndexValue) then
            exit(false);
        Parts := IndexValue.Split('|');
        Evaluate(TransactionNo, Parts.Get(3));
        TransHeader.Reset();
        exit(TransHeader.Get(CopyStr(Parts.Get(1), 1, 10), CopyStr(Parts.Get(2), 1, 10), TransactionNo));
    end;

    var
        SelectFileLbl: Label 'Select Excel File';
        ExcelFilterLbl: Label 'Excel Files (*.xlsx)|*.xlsx';
        NoFileSelectedErr: Label 'No file was selected.';
        InvalidFileErr: Label 'The selected file is not a valid Excel file.';
        EmptyFileErr: Label 'The Excel file has no data rows.';
        TemplateSheetNameLbl: Label 'Import Template';
        ProgressLbl: Label 'Importing transactions...\Processed #1######## of #2########';
        ImportResultMsg: Label 'Import completed. Created: %1, Already loaded: %2, Not found: %3. First not found: %4';
}
