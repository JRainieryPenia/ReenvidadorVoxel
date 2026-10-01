page 51100 "RV Transaction Register"
{
    PageType = Worksheet;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "RV Transaction Header";
    DeleteAllowed = false;
    InsertAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            group(GroupName)
            {
                field(Name; store)
                {
                    Caption = 'Store No.';
                    TableRelation = "LSC Store"."No.";
                    ToolTip = 'Select the store number to filter transactions.';
                    ApplicationArea = All;
                }
                field(FromDate; fromDate)
                {
                    ApplicationArea = All;
                    Caption = 'From Date';
                    ToolTip = 'Select the from date to filter transactions.';
                }
                field(ToDate; toDate)
                {
                    Caption = 'To Date';
                    ToolTip = 'Select the to date to filter transactions.';
                    ApplicationArea = All;

                }
                field(CreditMemoNoSeries; CreditMemoNoSeries)
                {
                    Caption = 'Credit Memo No. Series';
                    TableRelation = "No. Series".Code;
                    ToolTip = 'Select the number series for credit memos when voiding transactions.';
                    ApplicationArea = All;
                }
                field(DocumentNoRef; DocumentNoSeriesRef)
                {
                    Caption = 'Number Series Document Ref.';
                    TableRelation = "No. Series".Code;
                    ToolTip = 'Number series for resending Docs';
                    ApplicationArea = All;
                }
            }

            repeater(Transactions)
            {
                field("NCF Replacement Done"; Rec."NCF Replacement Done")
                {
                    ApplicationArea = All;
                    ToolTip = 'Indica que se reemplazó el NCF de la transacción original.';
                }
                field("Old NCF"; Rec."Old NCF")
                {
                    ApplicationArea = All;
                    ToolTip = 'Muestra el NCF anterior al reemplazo.';
                }
                field("Replacement NCF"; Rec."Replacement NCF")
                {
                    ApplicationArea = All;
                    ToolTip = 'Muestra el NCF asignado para el reenvío.';
                }
                field("Transaction No."; Rec."Transaction No.")
                {
                    ApplicationArea = All;
                    Caption = 'Transaction No.';
                    ToolTip = 'Displays the transaction number.';
                }

                field("Store No."; Rec."Store No.")
                {
                    ApplicationArea = All;
                    Caption = 'Store No.';
                    ToolTip = 'Displays the store number for the transaction.';
                }
                field("LSDX NCF"; Rec."LSDX NCF")
                {
                    ApplicationArea = All;
                    Caption = 'LSDX NCF';
                    ToolTip = 'Displays the LSDX NCF for the transaction.';
                }
                field("Voided NCF Credit Memo"; Rec."Voided NCF Credit Memo")
                {
                    ApplicationArea = All;
                    Caption = 'Voided NCF Credit Memo';
                    ToolTip = 'Displays the Voided NCF Credit Memo for the transaction.';
                }
                field("Affected NCF"; Rec."Voided NCF")
                {
                    ApplicationArea = All;
                    Caption = 'Previous NCF Voided';
                    ToolTip = 'NCF that was previously voided with the Voided NCF Credit memo';
                }
                field(Date; Rec.Date)
                {
                    ApplicationArea = All;
                    Caption = 'Date';
                    ToolTip = 'Displays the date of the transaction.';
                }
                field("Receipt No."; Rec."Receipt No.")
                {
                    ApplicationArea = All;
                    Caption = 'Receipt No.';
                    ToolTip = 'Displays the receipt number for the transaction.';
                }
                field("POS Terminal No."; Rec."POS Terminal No.")
                {
                    ApplicationArea = All;
                    Caption = 'POS Terminal No.';
                    ToolTip = 'Displays the POS terminal number for the transaction.';
                }
                //voided
                field("Voided"; Rec."Voided")
                {
                    ApplicationArea = All;
                    Caption = 'Voided';
                    ToolTip = 'Indicates whether the transaction has been voided.';
                }
                //Resent
                field("Resent"; Rec."Resent")
                {
                    ApplicationArea = All;
                    Caption = 'Resent';
                    ToolTip = 'Indicates whether the transaction has been resent.';
                }

            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RVReplaceNCF)
            {
                Caption = 'Reemplazar NCF por serie';
                ApplicationArea = All;
                Image = Change;
                ToolTip = 'Reemplaza los NCF seleccionados y guarda el NCF anterior y el nuevo en la transacción original.';

                trigger OnAction()
                var
                    SelectedRV: Record "RV Transaction Header";
                    SelectedTransactions: Record "LSC Transaction Header";
                    Management: Codeunit "RV Resent Management";
                begin
                    CurrPage.SetSelectionFilter(SelectedRV);
                    if not SelectedRV.FindSet() then
                        exit;
                    repeat
                        SelectedTransactions.Get(SelectedRV."Store No.", SelectedRV."POS Terminal No.", SelectedRV."Transaction No.");
                        SelectedTransactions.Mark(true);
                    until SelectedRV.Next() = 0;
                    SelectedTransactions.MarkedOnly(true);
                    Management.ReplaceSelectedNCF(SelectedTransactions);
                    CurrPage.Update(false);
                end;
            }
            action(RVDownloadCreditMemoXML)
            {
                Caption = 'Descargar XML de nota de crédito';
                ApplicationArea = All;
                Image = Download;
                ToolTip = 'Descarga el XML completo archivado para el NCF de la nota de crédito.';

                trigger OnAction()
                var
                    Management: Codeunit "RV Resent Management";
                begin
                    Management.DownloadCreditMemoXML(Rec."Voided NCF Credit Memo");
                end;
            }
            //Downlaod XML
            action("Download XML")
            {
                Caption = 'Download XML';
                Image = Download;
                ApplicationArea = All;
                trigger OnAction()
                var
                    efEncabezado: Record "EF Encabezado";
                    _TransactionHeader: Record "LSC Transaction Header";
                    efVoxelRequest: Codeunit "EF VoxelRequest";
                    lsdxSoapDocument: Codeunit "EF Soap Document";
                    util: codeunit "EF Utility Management";
                    Document: XmlDocument;
                    xml: Text;
                begin
                    _TransactionHeader.Reset();
                    _TransactionHeader.SetRange("Store No.", Rec."Store No.");
                    _TransactionHeader.SetRange("Receipt No.", Rec."Receipt No.");
                    _TransactionHeader.SetRange("POS Terminal No.", Rec."POS Terminal No.");
                    _TransactionHeader.SetRange("Transaction No.", Rec."Transaction No.");
                    if _TransactionHeader.FindFirst() and _TransactionHeader.GenerateEFHeader(EfEncabezado) then begin
                        xml := efVoxelRequest.CreateVoxelRequest(efEncabezado);
                        xml := VoxelTaxXML.ForResend(xml);
                        if XmlDocument.ReadFrom(xml, Document) then
                            lsdxSoapDocument.DownloadDocument(Document, _TransactionHeader."LSDX NCF" + '.xml');
                    end;
                end;
            }
            action("Load Transactions")
            {
                Caption = 'Load Transactions';
                Image = Import;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    LoadTransactions();
                end;
            }
            action("Clear Transactions")
            {
                Caption = 'Clear Transactions';
                Image = Delete;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    ClearTransaction();
                end;
            }

            //Void Transaction
            action("Void Transaction")
            {
                Caption = 'Void Transaction';
                Image = Delete;
                ApplicationArea = All;

                trigger OnAction()
                var
                    finished: Boolean;
                begin
                    VoidTransaction(Rec);
                end;
            }

            //Void Transaction Batch
            action("Void Transaction Batch")
            {
                Caption = 'Void Transaction Batch';
                Image = Delete;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    VoidTransactionBatch();
                end;
            }

            //Unmark Voided
            action("Unmark Voided")
            {
                Caption = 'Unmark Voided';
                Image = Edit;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    UnMarkVoided();
                end;
            }
            action("Unmark Send")
            {
                Caption = 'Unmark Send';
                Image = Edit;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    UnMarkSend();
                end;
            }
            //sent selected transactions
            action("Send Selected Transactions")
            {
                Caption = 'Resend Selected Transactions';
                Image = PostBatch;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    ResentVoideTransaction(Rec);
                    CurrPage.Update();
                end;
            }
            action("Void Selected Transactions")
            {
                Caption = 'Void Selected Transactions';
                Image = PostBatch;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    VoidSelectedTransactions();
                    CurrPage.Update();
                end;
            }
            action("Resend Selected Transactions NEW NCF")
            {
                Caption = 'Resend Selected Transactions New';
                Image = PostBatch;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    ResendTransactionBatch();
                    CurrPage.Update();
                end;
            }
            action("Resend Selected Transactions Same NCF")
            {
                Caption = 'Resend Selected Transactions';
                Image = PostBatch;
                ApplicationArea = All;

                trigger OnAction()
                begin
                    SendTransaction(Rec, false);
                    CurrPage.Update();
                end;
            }
        }

    }

    var
        VoxelTaxXML: Codeunit "RV Voxel Tax XML";
        AdministrationSetup: Record "EF Administration Setup";
        TransactionHeader: Record "LSC Transaction Header";
        NoSeries: Codeunit "No. Series";
        RVResentManagement: Codeunit "RV Resent Management";
        store: Code[10];
        fromDate: Date;
        toDate: Date;
        CreditMemoNoSeries: Code[10];
        nextNumber: Code[20];
        DocumentNoSeriesRef: Code[10];


    local procedure LoadTransactions()
    var
        rvTransactionHeader: Record "RV Transaction Header";

        ProgressDialog: Dialog;
        TotalCount: Integer;
        ProcessedCount: Integer;
    begin
        if (store = '') or (fromDate = 0D) or (toDate = 0D) then
            Error('Please provide Store No., From Date and To Date.');

        TransactionHeader.Reset();
        TransactionHeader.SetCurrentKey("Store No.", "POS Terminal No.", "Transaction No.");
        TransactionHeader.SetRange("Store No.", store);
        TransactionHeader.SetFilter(Date, '%1..%2', fromDate, toDate);
        TransactionHeader.SetFilter("LSDX NCF", '*E*');
        TotalCount := TransactionHeader.Count();

        if TotalCount = 0 then
            exit;

        ProcessedCount := 0;
        ProgressDialog.Open('Loading transactions...\\Processed #1####### of #2#######');
        ProgressDialog.Update(1, ProcessedCount);
        ProgressDialog.Update(2, TotalCount);

        if TransactionHeader.FindSet() then
            repeat
                // Here you would typically have code to process each transaction header,
                // such as sending it to an external system or performing calculations.
                if not rvTransactionHeader.Get(TransactionHeader."Store No.", TransactionHeader."POS Terminal No.", TransactionHeader."Transaction No.") then begin
                    rvTransactionHeader.Init();
                    rvTransactionHeader."Store No." := TransactionHeader."Store No.";
                    rvTransactionHeader."POS Terminal No." := TransactionHeader."POS Terminal No.";
                    rvTransactionHeader."Transaction No." := TransactionHeader."Transaction No.";
                    rvTransactionHeader."Receipt No." := TransactionHeader."Receipt No.";
                    rvTransactionHeader.Date := TransactionHeader.Date;
                    rvTransactionHeader."LSDX NCF" := TransactionHeader."LSDX NCF";
                    rvTransactionHeader.Insert();
                end else begin
                    rvTransactionHeader."LSDX NCF" := TransactionHeader."LSDX NCF";
                    rvTransactionHeader.Modify();
                end;

                ProcessedCount += 1;
                ProgressDialog.Update(1, ProcessedCount);
            until TransactionHeader.Next() = 0;

        ProgressDialog.Close();
        Rec.SetRange("Store No.", store);
        Rec.SetRange(Date, fromDate, toDate);
    end;


    local procedure ClearTransaction()
    var
        rvTransactionHeader: Record "RV Transaction Header";
    begin
        rvTransactionHeader.SetRange(Voided, false);
        rvTransactionHeader.SetRange(ReSent, false);
        rvTransactionHeader.SetRange("Voided NCF", '');
        rvTransactionHeader.SetRange("Voided NCF Credit Memo", '');
        rvTransactionHeader.SetRange("NCF Replacement Done", false);
        rvTransactionHeader.SetRange("Replacement NCF", '');
        rvTransactionHeader.DeleteAll();
    end;

    local procedure VoidTransaction(var Rec: Record "RV Transaction Header"): Boolean
    var
        efEncabezado: Record "EF Encabezado";
        TransactionHeader: Record "LSC Transaction Header";
        LSPosTerminal: Record "LSC POS Terminal";
        efVoxelRequest: Codeunit "EF VoxelRequest";
        LsEfSoapDocument: Codeunit "LSEF Soap Document";

        CreditMemoNCF: Code[20];
        ResultXML: Text;
        success: Boolean;
    begin
        if Rec."Voided" then
            exit(true);

        if not AdministrationSetup.Get() then
            exit(false);

        if (AdministrationSetup.Provider <> AdministrationSetup.Provider::Voxel) then
            exit(false);

        TransactionHeader.Reset();
        TransactionHeader.SetRange("Store No.", Rec."Store No.");
        TransactionHeader.SetRange("Receipt No.", Rec."Receipt No.");
        TransactionHeader.SetRange("POS Terminal No.", Rec."POS Terminal No.");
        TransactionHeader.SetRange("Transaction No.", Rec."Transaction No.");
        if CopyStr(TransactionHeader."LSDX NCF", 1, 3) = 'E34' then
            exit(true);

        if not LSPosTerminal.Get(Rec."POS Terminal No.") then
            exit(false);

        nextNumber := NoSeries.GetNextNo(LSPosTerminal."LSDXNCF Nota de Credito");

        if TransactionHeader.FindFirst() and Rec.GenerateEFHeader(nextNumber, TransactionHeader, efEncabezado) then begin
            ResultXML := efVoxelRequest.CreateVoxelRequest(efEncabezado);
            ResultXML := VoxelTaxXML.ForCancellation(ResultXML);
            success := LsEfSoapDocument.SendXmlElectronicDocument(ResultXML, nextNumber, false, CopyStr(efEncabezado.DocumentNo, 1, 20));
            if success then begin
                Rec."Voided" := true;
                Rec.ReSent := false;
                Rec."Voided NCF" := TransactionHeader."LSDX NCF";
                Rec."Voided NCF Credit Memo" := nextNumber;
                Rec.SetCreditMemoXML(ResultXML);
                Rec."Voided Date" := Today();
                Rec."XML Document Text" := CopyStr(ResultXML, 1, 2000);
                Rec.Modify();
            end;
        end;
        CurrPage.Update();
        exit(success);
    end;

    local procedure VoidTransactionBatch()
    var
        BatchTransactionHeader: Record "RV Transaction Header";
        ProgressDialog: Dialog;
        TotalCount: Integer;
        ProcessedCount: Integer;
        SuccessCount: Integer;
    begin
        CurrPage.SetSelectionFilter(BatchTransactionHeader);
        TotalCount := BatchTransactionHeader.Count();

        if TotalCount = 0 then
            exit;

        ProcessedCount := 0;
        SuccessCount := 0;
        ProgressDialog.Open('Voiding transactions...\\Processed #1####### of #2#######');
        ProgressDialog.Update(1, ProcessedCount);
        ProgressDialog.Update(2, TotalCount);

        if BatchTransactionHeader.FindSet() then
            repeat
                if VoidTransaction(BatchTransactionHeader) then
                    SuccessCount += 1;

                ProcessedCount += 1;
                ProgressDialog.Update(1, ProcessedCount);
            until (BatchTransactionHeader.Next() = 0);

        ProgressDialog.Close();
        CurrPage.Update();
        Message('%1 of %2 transactions were voided.', SuccessCount, TotalCount);
    end;

    local procedure UnMarkVoided()
    var
        rvTransactionheaderFilter: Record "RV Transaction Header";
    begin

        CurrPage.SetSelectionFilter(rvTransactionheaderFilter);
        if rvTransactionheaderFilter.findset() then
            repeat
                rvTransactionheaderFilter.TestField("Voided NCF Credit Memo", '');
                rvTransactionheaderFilter."Voided" := false;
                rvTransactionheaderFilter.Modify();
            until rvTransactionheaderFilter.Next() = 0;

        CurrPage.Update();
    end;

    local procedure UnMarkSend()
    var
        rvTransactionheaderFilter: Record "RV Transaction Header";
    begin

        CurrPage.SetSelectionFilter(rvTransactionheaderFilter);
        if rvTransactionheaderFilter.findset() then
            repeat
                rvTransactionheaderFilter.ReSent := false;
                rvTransactionheaderFilter.Modify();
            until rvTransactionheaderFilter.Next() = 0;

        CurrPage.Update();
    end;

    local procedure VoidSelectedTransactions()
    var
        efEncabezado: Record "EF Encabezado";
        rvTransactionHeader: Record "RV Transaction Header";
        RVResentManagement: Codeunit "RV Resent Management";
        Archived: Record "EF Archived Sent Request";
        TransactionHeader: Record "LSC Transaction Header";
        efVoxelRequest: Codeunit "EF VoxelRequest";
        LsEfSoapDocument: Codeunit "LSEF Soap Document";
        CreditMemoNCF: Code[20];
        ResultXML: Text;
        success: Boolean;
        counter: Integer;
        ReferenceNo: Code[20];
    begin

        CurrPage.SetSelectionFilter(rvTransactionHeader);

        if not AdministrationSetup.Get() then
            exit;

        if (AdministrationSetup.Provider <> AdministrationSetup.Provider::Voxel) then
            exit;

        if rvTransactionHeader.FindSet() then
            repeat
                counter += 1;
                TransactionHeader.Reset();
                TransactionHeader.SetRange("Store No.", rvTransactionHeader."Store No.");
                TransactionHeader.SetRange("Receipt No.", rvTransactionHeader."Receipt No.");
                TransactionHeader.SetRange("POS Terminal No.", rvTransactionHeader."POS Terminal No.");
                TransactionHeader.SetRange("Transaction No.", rvTransactionHeader."Transaction No.");

                nextNumber := rvTransactionHeader."Voided NCF Credit Memo";
                if not rvTransactionHeader.Voided then
                    if (CopyStr(TransactionHeader."LSDX NCF", 1, 3) <> 'E34') then
                        if TransactionHeader.FindFirst() and Rec.GenerateEFHeader(nextNumber, TransactionHeader, efEncabezado) then begin

                            ResultXML := efVoxelRequest.CreateVoxelRequest(efEncabezado);
                            ResultXML := VoxelTaxXML.ForCancellation(ResultXML);
                            ReferenceNo := RVResentManagement.CreateShortGuid();
                            ResultXML := RVResentManagement.UpdateReferenceNo(ResultXML, ReferenceNo);
                            Archived.Reset();
                            Archived.SetRange("Document No.", efEncabezado.DocumentNo);
                            if Archived.FindSet() then
                                Archived.DeleteAll();
                            efEncabezado.DocumentNo := ReferenceNo;
                            success := LsEfSoapDocument.SendXmlElectronicDocument(ResultXML, nextNumber, false, CopyStr(efEncabezado.DocumentNo, 1, 20));
                            if success then begin
                                rvTransactionHeader."Voided" := true;
                                rvTransactionHeader.ReSent := false;
                                rvTransactionHeader."Voided NCF" := TransactionHeader."LSDX NCF";
                                rvTransactionHeader."Voided NCF Credit Memo" := nextNumber;
                                rvTransactionHeader.SetCreditMemoXML(ResultXML);
                                rvTransactionHeader."Voided Date" := Today();
                                rvTransactionHeader."XML Document Text" := CopyStr(ResultXML, 1, 2000);
                                rvTransactionHeader.Modify();
                            end;
                        end;
            until rvTransactionHeader.Next() = 0;
    end;



    Procedure ResentVoideTransaction(var Rec: Record "RV Transaction Header")
    var
        __TransactionRegister: Record "LSC Transaction Header";
        Archived: Record "EF Archived Sent Request";
        LSCPosTerminal: Record "LSC POS Terminal";
        LSEFSoapDocument: Codeunit "LSEF Soap Document";
        NextNumber: Code[20];
        PreviousNumber: Code[20];
        NoSeries: Codeunit "No. Series";
        GuidText: Text;
        EfAdministrationSetup: Record "EF Administration Setup";
        XmlDocument: Text;
        TransactionNoCode: Code[20];
        ConfirmResendQst: Label 'Do you want to resend transaction %1 with NCF %2 to Voxel Offline Signer?', Comment = '%1 = Transaction No., %2 = Receipt No. (NCF)';
        SuccessMsg: Label 'Transaction %1 was successfully sent to Voxel Offline Signer.', Comment = '%1 = Transaction No.';
        ErrorMsg: Label 'An error occurred while sending transaction %1 to Voxel Offline Signer.\Error: %2', Comment = '%1 = Transaction No., %2 = Error message';
    begin
        if not EfAdministrationSetup.Get() then
            Error('Electronic invoice setup not found.');

        if not Confirm(ConfirmResendQst, false, Rec."Transaction No.", Rec."Receipt No.") then
            exit;

        __TransactionRegister.Reset();
        __TransactionRegister.SetRange("Store No.", Rec."Store No.");
        __TransactionRegister.SetRange("POS Terminal No.", Rec."POS Terminal No.");
        __TransactionRegister.SetRange("Transaction No.", Rec."Transaction No.");
        __TransactionRegister.SetRange("Receipt No.", Rec."Receipt No.");

        if not __TransactionRegister.FindFirst() then exit;
        RVResentManagement.PrepareReplacement(__TransactionRegister);
        NextNumber := __TransactionRegister."LSDX NCF";

        XmlDocument := LSEFSoapDocument.GetSalesPOSXML(__TransactionRegister);
        XmlDocument := VoxelTaxXML.ForResend(XmlDocument);
        GuidText := RVResentManagement.CreateShortGuid();
        XmlDocument := RVResentManagement.UpdateReferenceNo(XmlDocument, GuidText);


        if XmlDocument = '' then
            Error('Unable to generate XML document for transaction %1.', Rec."Transaction No.");

        TransactionNoCode := Format(Rec."Transaction No.");
        if LSEFSoapDocument.ReSendXmlElectronicDocument(XmlDocument, NextNumber, false, CopyStr(GuidText, 1, 20)) then begin
            Message(SuccessMsg, Rec."Transaction No.");
            RVResentManagement.MarkResent(__TransactionRegister, Rec);
            Archived.Reset();
            Archived.SetRange("Document No.", GuidText);
            if Archived.FindFirst() then begin
                __TransactionRegister."LSEF Security Code" := Archived."Security Code";
                __TransactionRegister."LSEF Stamped Date/Time" := Archived."Signed Date";
                __TransactionRegister.Modify(true);
            end;
        end else
            Message('No se confirmó el reenvío. Se conserva el NCF %1 para reintentar.', NextNumber);
        CurrPage.Update(false);
    end;

    local procedure ResendTransactionBatch()
    var
        BatchTransactionHeader: Record "RV Transaction Header";
        ProgressDialog: Dialog;
        TotalCount: Integer;
        ProcessedCount: Integer;
        SuccessCount: Integer;
    begin
        CurrPage.SetSelectionFilter(BatchTransactionHeader);
        TotalCount := BatchTransactionHeader.Count();

        if TotalCount = 0 then
            exit;

        ProcessedCount := 0;
        SuccessCount := 0;
        ProgressDialog.Open('Voiding transactions...\\Processed #1####### of #2#######');
        ProgressDialog.Update(1, ProcessedCount);
        ProgressDialog.Update(2, TotalCount);

        if BatchTransactionHeader.FindSet() then
            repeat
                if SendTransaction(BatchTransactionHeader, true) then
                    SuccessCount += 1;

                ProcessedCount += 1;
                ProgressDialog.Update(1, ProcessedCount);
            until (BatchTransactionHeader.Next() = 0);

        ProgressDialog.Close();
        CurrPage.Update();
        Message('%1 of %2 transactions were voided.', SuccessCount, TotalCount);
    end;

    local procedure SendTransaction(var Rec: Record "RV Transaction Header"; new: Boolean): Boolean
    var
        efEncabezado: Record "EF Encabezado";
        TransactionHeader: Record "LSC Transaction Header";
        Archived: Record "EF Archived Sent Request";
        LSPosTerminal: Record "LSC POS Terminal";
        efVoxelRequest: Codeunit "EF VoxelRequest";
        LsEfSoapDocument: Codeunit "LSEF Soap Document";
        ncfType: Code[3];
        CreditMemoNCF: Code[20];
        ResultXML: Text;
        success: Boolean;
        newReferenceNo: Code[20];
        previousNCF: Code[20];
    begin
        if Rec.ReSent and new then
            exit(true);

        if not AdministrationSetup.Get() then
            exit(false);

        if (AdministrationSetup.Provider <> AdministrationSetup.Provider::Voxel) then
            exit(false);

        TransactionHeader.Reset();
        TransactionHeader.SetRange("Store No.", Rec."Store No.");
        TransactionHeader.SetRange("Receipt No.", Rec."Receipt No.");
        TransactionHeader.SetRange("POS Terminal No.", Rec."POS Terminal No.");
        TransactionHeader.SetRange("Transaction No.", Rec."Transaction No.");



        if TransactionHeader.FindFirst() then begin
            if new then
                RVResentManagement.PrepareReplacement(TransactionHeader);

            if not TransactionHeader.GenerateEFHeader(efEncabezado) then
                exit(false);

            newReferenceNo := RVResentManagement.CreateShortGuid();
            ResultXML := efVoxelRequest.CreateVoxelRequest(efEncabezado);
            ResultXML := VoxelTaxXML.ForResend(ResultXML);
            efEncabezado.DocumentNo := newReferenceNo;
            success := LsEfSoapDocument.SendXmlElectronicDocument(ResultXML, TransactionHeader."LSDX NCF", false, CopyStr(efEncabezado.DocumentNo, 1, 20));
            if success then begin
                Archived.Reset();
                Archived.SetRange("Document No.", newReferenceNo);
                if Archived.FindFirst() then begin
                    TransactionHeader."LSEF Security Code" := Archived."Security Code";
                    TransactionHeader."LSEF Stamped Date/Time" := Archived."Signed Date";
                    TransactionHeader.Modify(true);
                end;
                RVResentManagement.MarkResent(TransactionHeader, Rec);
            end else
                exit(false);
        end;
        exit(success);
    end;

}
