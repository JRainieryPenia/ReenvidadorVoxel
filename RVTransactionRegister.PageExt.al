pageextension 51100 "RV Transaction Register Ext" extends "LSC Transaction Register"
{
    layout
    {
        // Add changes to page layout here
        addlast(Control1)
        {
            field("NCF Replacement Done"; Rec."NCF Replacement Done")
            {
                ApplicationArea = All;
                ToolTip = 'Indica que el NCF fue reemplazado; el reenvío reutiliza el NCF asignado.';
            }
            field("NCF antiguo"; Rec."NCF antiguo")
            {
                ApplicationArea = All;
                ToolTip = 'Muestra el NCF anterior al reemplazo por serie.';
            }
            field("NCF Reemplazado"; Rec."NCF Reemplazado")
            {
                ApplicationArea = All;
                ToolTip = 'Muestra el nuevo NCF asignado mediante el reemplazo por serie.';
            }
            field("NCF Void Credit Memo"; Rec."NCF Void Credit Memo")
            {
                ApplicationArea = All;
            }
            field("Voided NCF"; Rec."Voided NCF")
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        // Add changes to page actions here
        addlast("T&ransaction")
        {
            action(RVReplaceNCF)
            {
                Caption = 'Reemplazar NCF por serie';
                ApplicationArea = All;
                Image = Change;
                ToolTip = 'Reemplaza los NCF seleccionados y guarda el NCF anterior y el nuevo en cada transacción.';

                trigger OnAction()
                var
                    Selected: Record "LSC Transaction Header";
                begin
                    CurrPage.SetSelectionFilter(Selected);
                    RVResentManagement.ReplaceSelectedNCF(Selected);
                    CurrPage.Update(false);
                end;
            }
            action(LSEFDownloadXMLWithNoITBIS)
            {
                Caption = 'Descargar XML corregido para reenvío';
                ToolTip = 'Downloads the electronic fiscal XML document generated for this POS transaction.';
                ApplicationArea = All;
                Image = Download;
                trigger OnAction()
                var
                    SoapDocument: Codeunit "LSEF Soap Document";
                    EFSoapDocument: Codeunit "EF Soap Document";
                    XMLSourceToDownload: Text;
                    xmlDoc: XmlDocument;
                    XmlFilenameLbl: Label '%1.xml', Comment = '%1 = NCF';
                    InvalidTransLbl: Label 'Invalid Transaction %1, does not have a valid Electronic NCF', Comment = '%1 = Transaction Receipt No.';
                begin
                    if Rec."LSDX NCF" = '' then Error(InvalidTransLbl, Rec."Receipt No.");
                    if CopyStr(Rec."LSDX NCF", 1, 1) <> 'E' then Error(InvalidTransLbl, Rec."Receipt No.");
                    XMLSourceToDownload := SoapDocument.GetSalesPOSXML(Rec);
                    XMLSourceToDownload := VoxelTaxXML.ForResend(XMLSourceToDownload);
                    if XmlDocument.ReadFrom(XMLSourceToDownload, xmlDoc) then
                        EFSoapDocument.DownloadDocument(xmlDoc, StrSubstNo(XmlFilenameLbl, Rec."LSDX NCF"));
                end;
            }
            action(DownloadCreditMemoXML)
            {
                Caption = 'Descargar XML de nota de crédito';
                ToolTip = 'Descarga el XML completo archivado de la nota de crédito asociada.';
                ApplicationArea = All;
                Image = Download;
                trigger OnAction()
                begin
                    Rec.CalcFields("NCF Void Credit Memo");
                    RVResentManagement.DownloadCreditMemoXML(Rec."NCF Void Credit Memo");
                end;
            }
            action(DownloadCreditMemoXMLNoITBIS)
            {
                Caption = 'Descargar XML de nota de crédito archivada';
                ToolTip = 'Descarga la nota de crédito guardada con sus impuestos originales.';
                ApplicationArea = All;
                Image = Download;
                Visible = false;
                trigger OnAction()
                begin
                    Rec.CalcFields("NCF Void Credit Memo");
                    RVResentManagement.DownloadCreditMemoXML(Rec."NCF Void Credit Memo");
                end;
            }
            action(ManualCreditMemoResend)
            {
                ApplicationArea = All;
                Caption = 'Manual Resend Selected (Voxel Offline) Credit memo';
                ToolTip = 'Manually resend the transaction to Voxel Offline Signer service to obtain security code and stamped date/time.';
                Image = Redo;
                Enabled = Rec."Receipt No." <> '';

                trigger OnAction()
                var
                    SelectedTransHeader: Record "LSC Transaction Header";
                    RvTransactionRegister: Record "RV Transaction Header";
                    LSCPosTerminal: Record "LSC POS Terminal";
                    LSCTransactionHeader: Record "LSC Transaction Header";
                    LSEFSoapDocument: Codeunit "LSEF Soap Document";
                    CreditMemoNCF: Code[20];
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
                    CurrPage.SetSelectionFilter(SelectedTransHeader);
                    if SelectedTransHeader.FindSet() then
                        repeat
                            LSCTransactionHeader.Reset();
                            LSCTransactionHeader.SetRange("Transaction No.", SelectedTransHeader."Transaction No.");
                            LSCTransactionHeader.SetRange("Store No.", SelectedTransHeader."Store No.");
                            LSCTransactionHeader.SetRange("POS Terminal No.", SelectedTransHeader."POS Terminal No.");
                            LSCTransactionHeader.SetRange("Receipt No.", SelectedTransHeader."Receipt No.");
                            if LSCTransactionHeader.FindFirst() then begin
                                if RvTransactionRegister.Get(LSCTransactionHeader."Store No.", LSCTransactionHeader."POS Terminal No.", LSCTransactionHeader."Transaction No.") then
                                    RvTransactionRegister.TestField("Voided NCF Credit Memo", '');
                                XmlDocument := LSEFSoapDocument.GetSalesPOSXML(LSCTransactionHeader);
                                GuidText := RVResentManagement.CreateShortGuid();
                                LSCPosTerminal.Get(LSCTransactionHeader."POS Terminal No.");
                                if LSCPosTerminal."LSDXNCF Nota de Credito" = '' then
                                    Error('NCF for Credit Memo is not configure on pos Terminal %1', LSCPosTerminal."LSDXNCF Nota de Credito");

                                CreditMemoNCF := NoSeries.GetNextNo(LSCPosTerminal."LSDXNCF Nota de Credito");

                                XmlDocument := RVResentManagement.ConvertToCreditMemo(XmlDocument, GuidText, CreditMemoNCF, LSCTransactionHeader."LSDX NCF", '1');
                                XmlDocument := VoxelTaxXML.ForCancellation(XmlDocument);
                                if XmlDocument = '' then
                                    Error('Unable to generate XML document for transaction %1.', LSCTransactionHeader."Transaction No.");

                                TransactionNoCode := Format(LSCTransactionHeader."Transaction No.");
                                if LSEFSoapDocument.ReSendXmlElectronicDocument(XmlDocument, CreditMemoNCF, false, CopyStr(GuidText, 1, 20)) then begin
                                    RvTransactionRegister.Reset();
                                    RvTransactionRegister.SetRange("Transaction No.", LSCTransactionHeader."Transaction No.");
                                    RvTransactionRegister.SetRange("Store No.", LSCTransactionHeader."Store No.");
                                    RvTransactionRegister.SetRange("Receipt No.", LSCTransactionHeader."Receipt No.");
                                    RvTransactionRegister.SetRange("POS Terminal No.", LSCTransactionHeader."POS Terminal No.");
                                    if RvTransactionRegister.FindFirst() then begin
                                        RvTransactionRegister."Voided NCF Credit Memo" := CreditMemoNCF;
                                        RvTransactionRegister.SetCreditMemoXML(XmlDocument);
                                        RvTransactionRegister.Voided := true;
                                        RvTransactionRegister.ReSent := false;
                                        RvTransactionRegister."LSDX NCF" := LSCTransactionHeader."LSDX NCF";
                                        RvTransactionRegister."Voided Date" := Today();
                                        RvTransactionRegister."Voided NCF" := LSCTransactionHeader."LSDX NCF";
                                        RvTransactionRegister.Modify();
                                    end
                                    else begin
                                        RvTransactionRegister.Init();
                                        RvTransactionRegister."Transaction No." := LSCTransactionHeader."Transaction No.";
                                        RvTransactionRegister."Receipt No." := LSCTransactionHeader."Receipt No.";
                                        RvTransactionRegister."Store No." := LSCTransactionHeader."Store No.";
                                        RvTransactionRegister."POS Terminal No." := LSCTransactionHeader."POS Terminal No.";
                                        RvTransactionRegister.Date := Today();
                                        RvTransactionRegister."XML Document Text" := CopyStr(XmlDocument, 1, 2000);
                                        RvTransactionRegister."Voided NCF Credit Memo" := CreditMemoNCF;
                                        RvTransactionRegister.SetCreditMemoXML(XmlDocument);
                                        RvTransactionRegister.Voided := true;
                                        RvTransactionRegister.ReSent := false;
                                        RvTransactionRegister."Voided Date" := Today();
                                        RvTransactionRegister."Voided NCF" := LSCTransactionHeader."LSDX NCF";
                                        RvTransactionRegister."LSDX NCF" := LSCTransactionHeader."LSDX NCF";
                                        RvTransactionRegister.Insert();
                                    end;
                                    NCFLogMgt.UpdateLog(LSCTransactionHeader."Store No.", LSCTransactionHeader."POS Terminal No.", LSCTransactionHeader."Transaction No.");

                                end;
                            end;
                        until SelectedTransHeader.Next() = 0;
                    CurrPage.Update(false);
                end;
            }
            action(ResendFromTransactionHeader)
            {
                ApplicationArea = All;
                Caption = 'Manual Resend (Voxel Offline) New NCF';
                ToolTip = 'Manually resend the transaction to Voxel Offline Signer service to obtain security code and stamped date/time.';
                Image = SendTo;
                Enabled = Rec."Receipt No." <> '';

                trigger OnAction()
                var
                    RvTransactionRegister: Record "RV Transaction Header";
                    SelectedTransactionHeader: Record "LSC Transaction Header";
                    CurrentTransactionHeader: Record "LSC Transaction Header";
                    LSCPosTerminal: Record "LSC POS Terminal";
                    LSEFSoapDocument: Codeunit "LSEF Soap Document";
                    Archived: Record "EF Archived Sent Request";
                    NewNCF: Code[20];
                    PreviousNCF: Code[20];
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
                    CurrPage.SetSelectionFilter(SelectedTransactionHeader);
                    if SelectedTransactionHeader.FindSet() then
                        repeat
                            CurrentTransactionHeader.Reset();
                            CurrentTransactionHeader.SetRange("Store No.", SelectedTransactionHeader."Store No.");
                            CurrentTransactionHeader.SetRange("Transaction No.", SelectedTransactionHeader."Transaction No.");
                            CurrentTransactionHeader.SetRange("POS Terminal No.", SelectedTransactionHeader."POS Terminal No.");
                            CurrentTransactionHeader.SetRange("Receipt No.", SelectedTransactionHeader."Receipt No.");
                            if CurrentTransactionHeader.FindFirst() then begin
                                RVResentManagement.PrepareReplacement(CurrentTransactionHeader);
                                NewNCF := CurrentTransactionHeader."LSDX NCF";
                                XmlDocument := LSEFSoapDocument.GetSalesPOSXML(CurrentTransactionHeader);
                                XmlDocument := VoxelTaxXML.ForResend(XmlDocument);
                                GuidText := RVResentManagement.CreateShortGuid();
                                XmlDocument := RVResentManagement.UpdateReferenceNo(XmlDocument, GuidText);

                                if XmlDocument = '' then
                                    Error('Unable to generate XML document for transaction %1.', CurrentTransactionHeader."Transaction No.");

                                TransactionNoCode := Format(CurrentTransactionHeader."Transaction No.");
                                if LSEFSoapDocument.ReSendXmlElectronicDocument(XmlDocument, NewNCF, false, CopyStr(GuidText, 1, 20)) then begin

                                    RVResentManagement.MarkResent(CurrentTransactionHeader, RvTransactionRegister);
                                    Archived.Reset();
                                    Archived.SetRange("Document No.", GuidText);
                                    if Archived.FindFirst() then begin
                                        CurrentTransactionHeader."LSEF Security Code" := Archived."Security Code";
                                        CurrentTransactionHeader."LSEF Stamped Date/Time" := Archived."Signed Date";
                                        CurrentTransactionHeader.Modify(true);
                                    end;
                                end else
                                    Message('No se confirmó el reenvío de %1. Se conserva el NCF %2 para reintentar.', CurrentTransactionHeader."Receipt No.", NewNCF);
                            end;
                        until SelectedTransactionHeader.Next() = 0;
                    CurrPage.Update();
                end;
            }
        }
    }

    var
        VoxelTaxXML: Codeunit "RV Voxel Tax XML";
        RVResentManagement: Codeunit "RV Resent Management";
        NCFLogMgt: Codeunit "RV NCF Log Mgt";



}
