codeunit 51104 "RV NCF Log Mgt"
{
    Permissions = tabledata "RV NCF Log" = RIMD;

    /// <summary>
    /// Refresca la fila de conciliación de la transacción con los valores actuales de
    /// LSC Transaction Header (NCF antiguo / reemplazado) y RV Transaction Header (nota de crédito E34 y NCF afectado).
    /// Es idempotente: se puede llamar después de cada reemplazo o anulación.
    /// </summary>
    procedure UpdateLog(StoreNo: Code[10]; POSTerminalNo: Code[10]; TransactionNo: Integer)
    var
        NCFLog: Record "RV NCF Log";
        TransactionHeader: Record "LSC Transaction Header";
        RVTransaction: Record "RV Transaction Header";
        IsNew: Boolean;
    begin
        if not TransactionHeader.Get(StoreNo, POSTerminalNo, TransactionNo) then
            exit;

        IsNew := not NCFLog.Get(StoreNo, POSTerminalNo, TransactionNo);
        if IsNew then begin
            NCFLog.Init();
            NCFLog."Store No." := StoreNo;
            NCFLog."POS Terminal No." := POSTerminalNo;
            NCFLog."Transaction No." := TransactionNo;
        end;

        NCFLog."Receipt No." := TransactionHeader."Receipt No.";
        NCFLog."Transaction Date" := TransactionHeader.Date;
        NCFLog."Current NCF" := TransactionHeader."LSDX NCF";

        if (TransactionHeader."NCF antiguo" <> '') or (TransactionHeader."NCF Reemplazado" <> '') then begin
            if NCFLog."Replacement Logged At" = 0DT then
                NCFLog."Replacement Logged At" := CurrentDateTime();
            NCFLog."Old NCF" := TransactionHeader."NCF antiguo";
            NCFLog."Replacement NCF" := TransactionHeader."NCF Reemplazado";
        end;

        if RVTransaction.Get(StoreNo, POSTerminalNo, TransactionNo) then
            if RVTransaction.Voided and (RVTransaction."Voided NCF Credit Memo" <> '') then begin
                if NCFLog."Credit Memo Logged At" = 0DT then
                    NCFLog."Credit Memo Logged At" := CurrentDateTime();
                NCFLog."Credit Memo NCF" := RVTransaction."Voided NCF Credit Memo";
                NCFLog."Affected NCF" := RVTransaction."Voided NCF";
            end;

        NCFLog."Last Updated At" := CurrentDateTime();
        NCFLog."User ID" := CopyStr(UserId(), 1, MaxStrLen(NCFLog."User ID"));
        if IsNew then
            NCFLog.Insert()
        else
            NCFLog.Modify();
    end;

    /// <summary>Exporta la tabla de log (con el filtro recibido) a un archivo delimitado por tabs, abrible en Excel. Escala a decenas de miles de filas.</summary>
    procedure ExportToFile(var NCFLog: Record "RV NCF Log")
    var
        TempBlob: Codeunit "Temp Blob";
        Builder: TextBuilder;
        OutStr: OutStream;
        InStr: InStream;
        Tab: Text[1];
        FileName: Text;
    begin
        if not NCFLog.FindSet() then
            Error(NothingToExportErr);
        Tab[1] := 9;
        Builder.AppendLine('Store No.' + Tab + 'POS Terminal No.' + Tab + 'Transaction No.' + Tab + 'Receipt No.' + Tab + 'Transaction Date' + Tab +
            'Old NCF' + Tab + 'Replacement NCF' + Tab + 'Current NCF' + Tab + 'Credit Memo NCF (E34)' + Tab + 'NCF Affected by Credit Memo' + Tab +
            'Replacement Logged At' + Tab + 'Credit Memo Logged At' + Tab + 'User ID');
        repeat
            Builder.AppendLine(NCFLog."Store No." + Tab + NCFLog."POS Terminal No." + Tab + Format(NCFLog."Transaction No.", 0, 9) + Tab +
                NCFLog."Receipt No." + Tab + Format(NCFLog."Transaction Date", 0, 9) + Tab +
                NCFLog."Old NCF" + Tab + NCFLog."Replacement NCF" + Tab + NCFLog."Current NCF" + Tab +
                NCFLog."Credit Memo NCF" + Tab + NCFLog."Affected NCF" + Tab +
                Format(NCFLog."Replacement Logged At", 0, 9) + Tab + Format(NCFLog."Credit Memo Logged At", 0, 9) + Tab + NCFLog."User ID");
        until NCFLog.Next() = 0;

        TempBlob.CreateOutStream(OutStr, TextEncoding::UTF8);
        OutStr.WriteText(Builder.ToText());
        TempBlob.CreateInStream(InStr, TextEncoding::UTF8);
        FileName := 'RV_NCF_Log.txt';
        DownloadFromStream(InStr, '', '', '', FileName);
    end;

    var
        NothingToExportErr: Label 'There are no log entries to export.';
}
