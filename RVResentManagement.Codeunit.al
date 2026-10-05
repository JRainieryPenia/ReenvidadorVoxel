codeunit 51100 "RV Resent Management"
{
    trigger OnRun()
    begin

    end;

    var
        NCFLogMgt: Codeunit "RV NCF Log Mgt";
        LastFailureReason: Text;

    /// <summary>
    /// Valida que el setup permita enviar a Voxel (Online u Offline) y falla con el motivo exacto.
    /// Antes estos casos salían en silencio sin enviar nada.
    /// </summary>
    procedure CheckVoxelReady()
    var
        EFSetup: Record "EF Administration Setup";
    begin
        if not EFSetup.Get() then
            Error('No existe la configuración de Facturación Electrónica (EF Administration Setup).');
        if EFSetup.Provider <> EFSetup.Provider::Voxel then
            Error('El proveedor de Facturación Electrónica debe ser Voxel; actualmente es %1.', Format(EFSetup.Provider));
        if not EFSetup."LSEF Use Elec. Service On POS" then
            Error('"Use Elec. Service On POS" está desactivado en la configuración: el envío no se realiza (ni Online ni Offline).');
        if EFSetup."EF Voxel Mode" = EFSetup."EF Voxel Mode"::Offline then begin
            if EFSetup."Offline Signer URL Send(Voxel)" = '' then
                Error('Voxel Offline: falta "Offline Signer URL Send(Voxel)" en la configuración.');
        end else begin
            if EFSetup."URL de Envio (VOXEL)" = '' then
                Error('Voxel Online: falta "URL de Envio (VOXEL)" en la configuración.');
            if (EFSetup."Username(Voxel)" = '') or (EFSetup."Password(Voxel)" = '') then
                Error('Voxel Online: faltan "Username(Voxel)" o "Password(Voxel)" en la configuración.');
        end;
    end;

    /// <summary>
    /// Envía el XML a Voxel. Offline usa el transporte del POS. Online hace el POST aquí (mismo patrón que EF Bulk Credit Memo Handler)
    /// para poder devolver la respuesta real de Voxel en GetLastFailureReason, y solo da éxito si Voxel devolvió código de seguridad.
    /// No descarga request/response aunque "Downloads Requests/Response" esté activo: en lotes serían miles de archivos.
    /// </summary>
    procedure SendVoxelDocument(XMLText: Text; NCF: Code[20]; DocumentNo: Code[20]): Boolean
    var
        EFSetup: Record "EF Administration Setup";
        VoxelRequest: Codeunit "EF VoxelRequest";
        VoxelPOS: Codeunit "VOXEL POS";
        HttpManagement: Codeunit "EF HttpBuilder";
        ResponseText: Text;
        ResponseJson: JsonObject;
        InvoiceRef, NCFRef, Pdf, Qr, SignDate, SecurityCode : Text;
    begin
        LastFailureReason := '';
        CheckVoxelReady();
        EFSetup.Get();

        if EFSetup."EF Voxel Mode" = EFSetup."EF Voxel Mode"::Offline then begin
            exit(SendOffline(XMLText, NCF, DocumentNo));
        end;

        HttpManagement.Initialize("EF HttpMethods"::POST, EFSetup."URL de Envio (VOXEL)" + VoxelRequest.DocumentURL(NCF));
        HttpManagement.AddBody(XMLText);
        HttpManagement.SetContentType('text/xml;charset=utf-8');
        HttpManagement.AddBasicAuthentication(EFSetup."Username(Voxel)", EFSetup."Password(Voxel)");
        HttpManagement.AddRequestHeader('User-Agent', 'Dynamics 365');
        if not HttpManagement.SendRequest() then begin
            LastFailureReason := CopyStr('Voxel Online: error HTTP. ' + HttpManagement.GetResponseAsText(), 1, 1000);
            exit(false);
        end;

        ResponseText := HttpManagement.GetResponseAsText();
        if not ResponseJson.ReadFrom(ResponseText) then begin
            LastFailureReason := CopyStr('Voxel Online: la respuesta no es JSON. ' + ResponseText, 1, 1000);
            exit(false);
        end;
        VoxelRequest.ProssessJson(ResponseJson, InvoiceRef, NCFRef, Pdf, Qr, SignDate, SecurityCode);
        if SecurityCode = '' then begin
            LastFailureReason := CopyStr('Voxel Online respondió sin código de seguridad (rechazo). Respuesta: ' + ResponseText, 1, 1000);
            exit(false);
        end;
        exit(VoxelPOS.ProcessDocumentResponse(ResponseJson, NCF, DocumentNo, XMLText));
    end;

    /// <summary>
    /// Voxel Offline: mismo POST JSON que LSEF Voxel OfflineSigner.SendInvoice (posId, storeId, xmlBill), pero conservando
    /// el estado, el mensaje y la respuesta del signer para explicar el rechazo. Solo da éxito con billIdentifier (código de seguridad).
    /// </summary>
    local procedure SendOffline(XMLText: Text; NCF: Code[20]; DocumentNo: Code[20]): Boolean
    var
        EFSetup: Record "EF Administration Setup";
        OfflineSigner: Codeunit "LSEF Voxel OfflineSigner";
        HttpClientRequest: HttpClient;
        HttpRequestMessageInfo: HttpRequestMessage;
        HttpResponseMessageInfo: HttpResponseMessage;
        HttpContentInfo: HttpContent;
        HttpHeaderContent: HttpHeaders;
        ResponseText: Text;
        ResponseJson: JsonObject;
        Status, ResponseMessage, BillIdentifier, BillDate : Text;
    begin
        EFSetup.Get();
        HttpRequestMessageInfo.SetRequestUri(EFSetup."Offline Signer URL Send(Voxel)");
        HttpRequestMessageInfo.Method := 'POST';
        HttpContentInfo.WriteFrom(OfflineSigner.SetJson(EFSetup.PosID, EFSetup.StoreId, XMLText));
        HttpContentInfo.GetHeaders(HttpHeaderContent);
        HttpHeaderContent.Clear();
        HttpHeaderContent.Add('Content-Type', 'application/json');
        HttpRequestMessageInfo.Content(HttpContentInfo);
        HttpClientRequest.DefaultRequestHeaders.Add('User-Agent', 'Dynamics 365');
        HttpClientRequest.DefaultRequestHeaders.Add('Accept', 'application/json');

        if not HttpClientRequest.Send(HttpRequestMessageInfo, HttpResponseMessageInfo) then begin
            LastFailureReason := 'Voxel Offline: no hay conexión con el signer (' + EFSetup."Offline Signer URL Send(Voxel)" + '). ' + GetLastErrorText();
            exit(false);
        end;
        HttpResponseMessageInfo.Content.ReadAs(ResponseText);
        if not HttpResponseMessageInfo.IsSuccessStatusCode() then begin
            LastFailureReason := CopyStr(StrSubstNo('Voxel Offline: HTTP %1 %2. %3', HttpResponseMessageInfo.HttpStatusCode(), HttpResponseMessageInfo.ReasonPhrase(), ResponseText), 1, 1000);
            exit(false);
        end;
        if not ResponseJson.ReadFrom(ResponseText) then begin
            LastFailureReason := CopyStr('Voxel Offline: la respuesta no es JSON. ' + ResponseText, 1, 1000);
            exit(false);
        end;
        OfflineSigner.ProcessOfflineJson(ResponseJson, Status, ResponseMessage, BillIdentifier, BillDate);
        if BillIdentifier = '' then begin
            LastFailureReason := CopyStr(StrSubstNo('Voxel Offline respondió sin código de seguridad (estado: %1, mensaje: %2). Respuesta: %3', Status, ResponseMessage, ResponseText), 1, 1000);
            exit(false);
        end;
        exit(OfflineSigner.ProcessOfflinePOSDocumentResponse(ResponseJson, NCF, DocumentNo, XMLText));
    end;

    procedure GetLastFailureReason(): Text
    begin
        exit(LastFailureReason);
    end;

    procedure DownloadCreditMemoXML(CreditMemoNCF: Code[20])
    var
        Archived: Record "EF Archived Sent Request";
        RVTransaction: Record "RV Transaction Header";
        XMLStream: InStream;
        FileName: Text;
    begin
        if CreditMemoNCF = '' then
            Error('La transacción no tiene una nota de crédito asociada.');
        FileName := CreditMemoNCF + '.xml';
        RVTransaction.SetRange("Voided NCF Credit Memo", CreditMemoNCF);
        if RVTransaction.FindFirst() then begin
            if RVTransaction.Next() <> 0 then
                Error('La nota de crédito %1 está asociada a más de una transacción.', CreditMemoNCF);
            RVTransaction.FindFirst();
            RVTransaction.CalcFields("Credit Memo XML");
            if RVTransaction."Credit Memo XML".HasValue() then begin
                RVTransaction."Credit Memo XML".CreateInStream(XMLStream);
                DownloadFromStream(XMLStream, '', '', '', FileName);
                exit;
            end;
        end;
        Archived.SetRange("e-NCF", CreditMemoNCF);
        Archived.SetRange("Document Source Type", Archived."Document Source Type"::POS);
        if not Archived.FindFirst() then
            Error('No se encontró el XML archivado de la nota de crédito %1.', CreditMemoNCF);
        if Archived.Next() <> 0 then
            Error('Existe más de un documento archivado para el NCF %1. Revise el archivo de envíos.', CreditMemoNCF);
        Archived.FindFirst();
        Archived.CalcFields("XML File");
        if not Archived."XML File".HasValue() then
            Error('El documento archivado %1 no contiene XML.', CreditMemoNCF);
        Archived."XML File".CreateInStream(XMLStream);
        FileName := CreditMemoNCF + '.xml';
        DownloadFromStream(XMLStream, '', '', '', FileName);
    end;

    procedure ReplaceSelectedNCF(var Selected: Record "LSC Transaction Header")
    var
        ReplaceDialog: Page "RV Replace NCF";
        SeriesCode: Code[20];
        ReplacedCount: Integer;
    begin
        if Selected.IsEmpty() then
            Error('Seleccione al menos una transacción.');
        if ReplaceDialog.RunModal() <> Action::OK then
            exit;
        SeriesCode := ReplaceDialog.GetSeriesCode();
        if SeriesCode = '' then
            Error('Seleccione una serie de NCF.');
        if not Confirm('Se reemplazará el NCF de %1 transacciones usando la serie %2. ¿Desea continuar?', false, Selected.Count(), SeriesCode) then
            exit;
        if Selected.FindSet(true) then
            repeat
                ReplaceNCF(Selected, SeriesCode);
                ReplacedCount += 1;
            until Selected.Next() = 0;
        Message('Se reemplazaron los NCF de %1 transacciones.', ReplacedCount);
    end;

    procedure ReplaceNCF(var TransactionHeader: Record "LSC Transaction Header"; SeriesCode: Code[20])
    var
        ExistingTransaction: Record "LSC Transaction Header";
        RVTransaction: Record "RV Transaction Header";
        NumberSeries: Codeunit "No. Series";
        NewNCF: Code[20];
    begin
        if TransactionHeader.IsTemporary() then
            Error('El reemplazo requiere una transacción física.');
        TransactionHeader.LockTable();
        TransactionHeader.Get(TransactionHeader."Store No.", TransactionHeader."POS Terminal No.", TransactionHeader."Transaction No.");
        TransactionHeader.TestField("LSDX NCF");
        TransactionHeader.TestField("NCF Replacement Done", false);
        TransactionHeader.TestField("NCF antiguo", '');
        TransactionHeader.TestField("NCF Reemplazado", '');
        NewNCF := NumberSeries.GetNextNo(SeriesCode, WorkDate());
        if (NewNCF = '') or (NewNCF = TransactionHeader."LSDX NCF") then
            Error('La serie debe generar un NCF nuevo y no vacío.');
        if CopyStr(NewNCF, 1, 3) <> CopyStr(TransactionHeader."LSDX NCF", 1, 3) then
            Error('El nuevo NCF %1 debe conservar el tipo del NCF %2.', NewNCF, TransactionHeader."LSDX NCF");
        if StrLen(NewNCF) <> StrLen(TransactionHeader."LSDX NCF") then
            Error('El nuevo NCF %1 debe conservar la longitud del NCF %2.', NewNCF, TransactionHeader."LSDX NCF");
        ExistingTransaction.SetRange("LSDX NCF", NewNCF);
        if not ExistingTransaction.IsEmpty() then
            Error('El NCF %1 ya está asignado a otra transacción.', NewNCF);
        TransactionHeader."NCF antiguo" := TransactionHeader."LSDX NCF";
        TransactionHeader.Validate("LSDX NCF", NewNCF);
        TransactionHeader."NCF Reemplazado" := NewNCF;
        TransactionHeader."NCF Replacement Done" := true;
        TransactionHeader.Modify(true);
        EnsureRVTransaction(TransactionHeader, RVTransaction);
        RVTransaction."LSDX NCF" := NewNCF;
        RVTransaction.ReSent := false;
        RVTransaction.Modify(true);
        NCFLogMgt.UpdateLog(TransactionHeader."Store No.", TransactionHeader."POS Terminal No.", TransactionHeader."Transaction No.");
    end;

    procedure PrepareReplacement(var TransactionHeader: Record "LSC Transaction Header")
    var
        Terminal: Record "LSC POS Terminal";
        SeriesCode: Code[20];
    begin
        TransactionHeader.LockTable();
        TransactionHeader.Get(TransactionHeader."Store No.", TransactionHeader."POS Terminal No.", TransactionHeader."Transaction No.");
        if TransactionHeader."NCF Reemplazado" <> '' then begin
            TransactionHeader.TestField("NCF antiguo");
            TransactionHeader.TestField("LSDX NCF", TransactionHeader."NCF Reemplazado");
            if not TransactionHeader."NCF Replacement Done" then begin
                TransactionHeader."NCF Replacement Done" := true;
                TransactionHeader.Modify(true);
            end;
            exit;
        end;
        Terminal.Get(TransactionHeader."POS Terminal No.");
        case CopyStr(TransactionHeader."LSDX NCF", 1, 3) of
            'E31': SeriesCode := Terminal."LSDXNo. Serie NCF Cred. Fiscal";
            'E32': SeriesCode := Terminal."LSDXNo. Serie NCF Cons. Final";
            else Error('No hay una serie de reemplazo configurada para el tipo de NCF %1.', TransactionHeader."LSDX NCF");
        end;
        ReplaceNCF(TransactionHeader, SeriesCode);
    end;

    procedure MarkResent(TransactionHeader: Record "LSC Transaction Header"; var RVTransaction: Record "RV Transaction Header")
    begin
        EnsureRVTransaction(TransactionHeader, RVTransaction);
        RVTransaction."LSDX NCF" := TransactionHeader."LSDX NCF";
        RVTransaction.ReSent := true;
        RVTransaction.Modify(true);
    end;

    local procedure EnsureRVTransaction(TransactionHeader: Record "LSC Transaction Header"; var RVTransaction: Record "RV Transaction Header")
    begin
        if RVTransaction.Get(TransactionHeader."Store No.", TransactionHeader."POS Terminal No.", TransactionHeader."Transaction No.") then
            exit;
        RVTransaction.Init();
        RVTransaction."Store No." := TransactionHeader."Store No.";
        RVTransaction."POS Terminal No." := TransactionHeader."POS Terminal No.";
        RVTransaction."Transaction No." := TransactionHeader."Transaction No.";
        RVTransaction."Receipt No." := TransactionHeader."Receipt No.";
        RVTransaction.Date := TransactionHeader.Date;
        RVTransaction."LSDX NCF" := TransactionHeader."LSDX NCF";
        RVTransaction.Insert(true);
    end;

    procedure CreateShortGuid(): Text[20]
    var
        NewGuid: Guid;
        GuidText: Text;
    begin
        NewGuid := CreateGuid();
        GuidText := DelChr(Format(NewGuid), '=', '{}-');
        exit(CopyStr(GuidText, 1, 20));
    end;

    procedure ConvertToCreditMemo(FacturaComercialXml: Text; NewRefNumber: Text; CreditMemoNCF: Text; AffectedNCF: Text; CodigoModificacion: Text) ModifiedXml: Text
    var
        XmlDoc: XmlDocument;
        GeneralDataNode: XmlNode;
        ClientNode: XmlNode;
        AttributeNode: XmlNode;
        ReferencesElem: XmlElement;
        ReferenceElem: XmlElement;
        PublicAdminElem: XmlElement;
        DOMElem: XmlElement;
        GeneralDataElem: XmlElement;
        OriginalRef: Text;
        OriginalDate: Text;
    begin
        if not XmlDocument.ReadFrom(FacturaComercialXml, XmlDoc) then
            Error('Invalid XML text provided.');

        // Get GeneralData node and update attributes
        if not XmlDoc.SelectSingleNode('//GeneralData', GeneralDataNode) then
            Error('GeneralData node not found.');

        GeneralDataElem := GeneralDataNode.AsXmlElement();

        // Store original Ref and Date for References node
        if GeneralDataNode.SelectSingleNode('@Ref', AttributeNode) then
            OriginalRef := AttributeNode.AsXmlAttribute().Value();
        if GeneralDataNode.SelectSingleNode('@Date', AttributeNode) then
            OriginalDate := AttributeNode.AsXmlAttribute().Value();

        // Update GeneralData attributes
        GeneralDataElem.SetAttribute('Ref', NewRefNumber);
        GeneralDataElem.SetAttribute('Type', 'FacturaAbono');
        GeneralDataElem.SetAttribute('NCF', CreditMemoNCF);

        // Remove NCFExpirationDate attribute
        GeneralDataElem.RemoveAttribute('NCFExpirationDate');

        // Create References node structure
        ReferencesElem := XmlElement.Create('References');

        ReferenceElem := XmlElement.Create('Reference');
        ReferenceElem.SetAttribute('InvoiceRef', OriginalRef);
        ReferenceElem.SetAttribute('InvoiceNCF', AffectedNCF);
        ReferenceElem.SetAttribute('InvoiceRefDate', OriginalDate);

        PublicAdminElem := XmlElement.Create('PublicAdministration');

        DOMElem := XmlElement.Create('DOM');
        DOMElem.SetAttribute('CodigoModificacion', CodigoModificacion);
        DOMElem.SetAttribute('IndicadorNotaCredito', '0');

        PublicAdminElem.Add(DOMElem);
        ReferenceElem.Add(PublicAdminElem);
        ReferencesElem.Add(ReferenceElem);

        // Insert References node after Client node
        if XmlDoc.SelectSingleNode('//Client', ClientNode) then
            ClientNode.AsXmlElement().AddAfterSelf(ReferencesElem)
        else begin
            if not XmlDoc.SelectSingleNode('/Transaction/ProductList', ClientNode) then
                Error('No se encontró ProductList para insertar la referencia de la nota de crédito.');
            ClientNode.AsXmlElement().AddAfterSelf(ReferencesElem);
        end;

        XmlDoc.WriteTo(ModifiedXml);
    end;

    procedure ModifyTaxAmounts(XmlText: Text; TaxSummaryAmount: Decimal; TotalSummaryTax: Decimal) ModifiedXml: Text
    var
        XmlDoc: XmlDocument;
        TotalSummaryNode: XmlNode;
        TaxNode: XmlNode;
        AttributeNode: XmlNode;
        XmlElem: XmlElement;
        SubTotalValue: Text;
        ProductTaxNode: XmlNode;
        ProductTaxIndex: Integer;
        ProductTaxPath: Text;
    begin
        if not XmlDocument.ReadFrom(XmlText, XmlDoc) then
            Error('Invalid XML text provided.');

        // Force zero-tax mode in every product tax line.
        ProductTaxIndex := 1;
        repeat
            ProductTaxPath := StrSubstNo('(//ProductList/Product/Taxes/Tax)[%1]', ProductTaxIndex);
            if XmlDoc.SelectSingleNode(ProductTaxPath, ProductTaxNode) then begin
                XmlElem := ProductTaxNode.AsXmlElement();
                XmlElem.SetAttribute('Amount', '0.00');
                ProductTaxIndex += 1;
            end;
        until not XmlDoc.SelectSingleNode(ProductTaxPath, ProductTaxNode);

        TaxSummaryAmount := 0;
        TotalSummaryTax := 0;

        // Update TaxSummary/Tax Amount attribute
        if XmlDoc.SelectSingleNode('//TaxSummary/Tax', TaxNode) then begin
            XmlElem := TaxNode.AsXmlElement();
            XmlElem.SetAttribute('Amount', '0.00');
        end;

        // Update TotalSummary Tax attribute and set Total = SubTotal
        if XmlDoc.SelectSingleNode('//TotalSummary', TotalSummaryNode) then begin
            XmlElem := TotalSummaryNode.AsXmlElement();
            XmlElem.SetAttribute('Tax', Format(TotalSummaryTax, 0, '<Precision,2:2><Standard Format,9>'));

            // Keep Total aligned with SubTotal + Tax to avoid DGII mismatch validations.
            if TotalSummaryNode.SelectSingleNode('@SubTotal', AttributeNode) then begin
                SubTotalValue := AttributeNode.AsXmlAttribute().Value();
                XmlElem.SetAttribute('Total', SubTotalValue);
            end;
        end;

        XmlDoc.WriteTo(ModifiedXml);
    end;

    procedure UpdateReferenceNo(XmlText: Text; NewReferenceNo: Text) ModifiedXml: Text
    var
        XmlDoc: XmlDocument;
        GeneralDataNode: XmlNode;
        GeneralDataElem: XmlElement;
    begin
        if not XmlDocument.ReadFrom(XmlText, XmlDoc) then
            Error('Invalid XML text provided.');

        if not XmlDoc.SelectSingleNode('//GeneralData', GeneralDataNode) then
            Error('GeneralData node not found.');

        GeneralDataElem := GeneralDataNode.AsXmlElement();
        GeneralDataElem.SetAttribute('Ref', NewReferenceNo);

        XmlDoc.WriteTo(ModifiedXml);
    end;

    /// <summary>
    /// Genera el XML de la nota de crédito (E34) que se enviaría para la transacción, sin enviarlo,
    /// sin consumir NCF y sin modificar el registro. El NCF mostrado es el próximo disponible de la serie.
    /// </summary>
    procedure BuildCreditMemoXMLPreview(RVTransaction: Record "RV Transaction Header"; SeriesOverride: Code[20]; var CreditMemoXML: Text; var PreviewNCF: Code[20]): Boolean
    var
        TransactionHeader: Record "LSC Transaction Header";
        LSPosTerminal: Record "LSC POS Terminal";
        EFEncabezado: Record "EF Encabezado";
        EFVoxelRequest: Codeunit "EF VoxelRequest";
        VoxelTaxXML: Codeunit "RV Voxel Tax XML";
        NoSeries: Codeunit "No. Series";
        SeriesCode: Code[20];
    begin
        CreditMemoXML := '';
        TransactionHeader.SetRange("Store No.", RVTransaction."Store No.");
        TransactionHeader.SetRange("POS Terminal No.", RVTransaction."POS Terminal No.");
        TransactionHeader.SetRange("Transaction No.", RVTransaction."Transaction No.");
        if not TransactionHeader.FindFirst() then
            exit(false);
        if not LSPosTerminal.Get(TransactionHeader."POS Terminal No.") then
            exit(false);
        SeriesCode := SeriesOverride;
        if SeriesCode = '' then
            SeriesCode := LSPosTerminal."LSDXNCF Nota de Credito";
        if SeriesCode = '' then
            Error('NCF for Credit Memo is not configured on POS Terminal %1', LSPosTerminal."No.");

        PreviewNCF := CopyStr(NoSeries.PeekNextNo(SeriesCode, WorkDate()), 1, MaxStrLen(PreviewNCF));
        if not RVTransaction.GenerateEFHeader(PreviewNCF, TransactionHeader, EFEncabezado) then
            exit(false);

        CreditMemoXML := EFVoxelRequest.CreateVoxelRequest(EFEncabezado);
        CreditMemoXML := VoxelTaxXML.ForCancellation(CreditMemoXML);
        exit(CreditMemoXML <> '');
    end;

    local procedure BuildCreditMemoXMLForNCF(RVTransaction: Record "RV Transaction Header"; CreditMemoNCF: Code[20]; var CreditMemoXML: Text): Boolean
    var
        TransactionHeader: Record "LSC Transaction Header";
        EFEncabezado: Record "EF Encabezado";
        EFVoxelRequest: Codeunit "EF VoxelRequest";
        VoxelTaxXML: Codeunit "RV Voxel Tax XML";
    begin
        CreditMemoXML := '';
        TransactionHeader.SetRange("Store No.", RVTransaction."Store No.");
        TransactionHeader.SetRange("POS Terminal No.", RVTransaction."POS Terminal No.");
        TransactionHeader.SetRange("Transaction No.", RVTransaction."Transaction No.");
        if not TransactionHeader.FindFirst() then
            exit(false);
        if not RVTransaction.GenerateEFHeader(CreditMemoNCF, TransactionHeader, EFEncabezado) then
            exit(false);
        CreditMemoXML := VoxelTaxXML.ForCancellation(EFVoxelRequest.CreateVoxelRequest(EFEncabezado));
        exit(CreditMemoXML <> '');
    end;

    /// <summary>Lee el comprobante (código de seguridad y fecha de sello) archivado para el documento enviado.</summary>
    procedure GetSignature(DocumentNo: Code[20]; var SecurityCode: Text; var StampedAt: Text): Boolean
    var
        Archived: Record "EF Archived Sent Request";
    begin
        Archived.SetRange("Document No.", DocumentNo);
        Archived.SetFilter("Security Code", '<>%1', '');
        if not Archived.FindLast() then
            exit(false);
        SecurityCode := Format(Archived."Security Code");
        StampedAt := Format(Archived."Signed Date");
        exit(true);
    end;

    /// <summary>Guarda en la fila el comprobante de Voxel del documento recién enviado. No hace Modify.</summary>
    procedure StampSignature(var RVTransaction: Record "RV Transaction Header"; DocumentNo: Code[20])
    var
        SecurityCode: Text;
        StampedAt: Text;
    begin
        if GetSignature(DocumentNo, SecurityCode, StampedAt) then begin
            RVTransaction."Credit Memo Security Code" := CopyStr(SecurityCode, 1, MaxStrLen(RVTransaction."Credit Memo Security Code"));
            RVTransaction."Credit Memo Stamped At" := CopyStr(StampedAt, 1, MaxStrLen(RVTransaction."Credit Memo Stamped At"));
        end;
    end;

    /// <summary>
    /// Valida una fila contra el comprobante de Voxel (EF Archived Sent Request con el NCF de la nota y código de seguridad).
    /// Resultado: 1 = validada y marcada ahora, 2 = sin comprobante (si estaba marcada como anulada se desmarca),
    /// 3 = sin NCF de nota reservado, 4 = ya estaba validada.
    /// </summary>
    procedure SyncRow(var RVTransaction: Record "RV Transaction Header"; var Rebuilt: Boolean): Integer
    var
        Archived: Record "EF Archived Sent Request";
        TransactionHeader: Record "LSC Transaction Header";
        XMLStream: InStream;
        XMLOutStream: OutStream;
        CreditMemoXML: Text;
    begin
        Rebuilt := false;
        if RVTransaction.Voided and (RVTransaction."Credit Memo Security Code" <> '') then
            exit(4);
        if RVTransaction."Voided NCF Credit Memo" = '' then begin
            if RVTransaction.Voided then begin
                RVTransaction.Voided := false;
                RVTransaction.Modify();
            end;
            exit(3);
        end;

        Archived.SetRange("e-NCF", RVTransaction."Voided NCF Credit Memo");
        Archived.SetFilter("Security Code", '<>%1', '');
        if not Archived.FindLast() or not TransactionHeader.Get(RVTransaction."Store No.", RVTransaction."POS Terminal No.", RVTransaction."Transaction No.") then begin
            if RVTransaction.Voided then begin
                RVTransaction.Voided := false;
                RVTransaction.Modify();
            end;
            exit(2);
        end;

        // Si ya se reemplazó el NCF, la nota afectó el NCF antiguo.
        if RVTransaction."Voided NCF" = '' then
            if TransactionHeader."NCF antiguo" <> '' then
                RVTransaction."Voided NCF" := TransactionHeader."NCF antiguo"
            else
                RVTransaction."Voided NCF" := TransactionHeader."LSDX NCF";
        RVTransaction.Voided := true;
        RVTransaction.ReSent := false;
        RVTransaction."Voided Date" := Archived."Posting Date";
        RVTransaction."Credit Memo Security Code" := CopyStr(Format(Archived."Security Code"), 1, MaxStrLen(RVTransaction."Credit Memo Security Code"));
        RVTransaction."Credit Memo Stamped At" := CopyStr(Format(Archived."Signed Date"), 1, MaxStrLen(RVTransaction."Credit Memo Stamped At"));

        RVTransaction.CalcFields("Credit Memo XML");
        if not RVTransaction."Credit Memo XML".HasValue() then begin
            Archived.CalcFields("XML File");
            if Archived."XML File".HasValue() then begin
                Clear(RVTransaction."Credit Memo XML");
                RVTransaction."Credit Memo XML".CreateOutStream(XMLOutStream, TextEncoding::UTF8);
                Archived."XML File".CreateInStream(XMLStream, TextEncoding::UTF8);
                CopyStream(XMLOutStream, XMLStream);
            end else
                if BuildCreditMemoXMLForNCF(RVTransaction, RVTransaction."Voided NCF Credit Memo", CreditMemoXML) then begin
                    RVTransaction.SetCreditMemoXML(CreditMemoXML);
                    RVTransaction."XML Document Text" := CopyStr(CreditMemoXML, 1, 2000);
                    Rebuilt := true;
                end;
        end;
        RVTransaction.Modify();
        NCFLogMgt.UpdateLog(RVTransaction."Store No.", RVTransaction."POS Terminal No.", RVTransaction."Transaction No.");
        exit(1);
    end;

    /// <summary>
    /// Desmarca filas anuladas para poder reenviarlas, sin exigir que el NCF de la nota esté vacío.
    /// Busca el NCF de la nota (E34) en lo archivado de Voxel: con código de seguridad es una nota realmente emitida y la fila
    /// se conserva como anulada (se completa con el comprobante); sin código se desmarca. El NCF reservado se conserva para reutilizarlo.
    /// </summary>
    procedure UnmarkVoidedRows(var RVTransaction: Record "RV Transaction Header"; var Unmarked: Integer; var KeptWithProof: Integer)
    var
        Archived: Record "EF Archived Sent Request";
        Rebuilt: Boolean;
    begin
        Unmarked := 0;
        KeptWithProof := 0;
        if not RVTransaction.FindSet(true) then
            exit;
        repeat
            if RVTransaction.Voided then begin
                Archived.Reset();
                Archived.SetRange("e-NCF", RVTransaction."Voided NCF Credit Memo");
                Archived.SetFilter("Security Code", '<>%1', '');
                if (RVTransaction."Voided NCF Credit Memo" <> '') and not Archived.IsEmpty() then begin
                    SyncRow(RVTransaction, Rebuilt);
                    KeptWithProof += 1;
                end else begin
                    RVTransaction.Voided := false;
                    RVTransaction."Credit Memo Security Code" := '';
                    RVTransaction."Credit Memo Stamped At" := '';
                    RVTransaction.Modify();
                    Unmarked += 1;
                end;
            end;
        until RVTransaction.Next() = 0;
    end;

    /// <summary>
    /// Valida por comprobante de Voxel todas las filas con NCF de nota reservado: marca las que tienen código de seguridad
    /// y desmarca las marcadas como anuladas sin comprobante. No envía nada a Voxel.
    /// </summary>
    procedure SyncSentCreditMemos(var RVTransaction: Record "RV Transaction Header"; var Synced: Integer; var NoProof: Integer; var NoReservedNCF: Integer; var Rebuilt: Integer; var AlreadyOk: Integer; var Unmarked: Integer)
    var
        WasVoided: Boolean;
        RowRebuilt: Boolean;
    begin
        Synced := 0;
        NoProof := 0;
        NoReservedNCF := 0;
        Rebuilt := 0;
        AlreadyOk := 0;
        Unmarked := 0;
        if not RVTransaction.FindSet(true) then
            exit;
        repeat
            WasVoided := RVTransaction.Voided;
            case SyncRow(RVTransaction, RowRebuilt) of
                1:
                    begin
                        Synced += 1;
                        if RowRebuilt then
                            Rebuilt += 1;
                    end;
                2:
                    if WasVoided then
                        Unmarked += 1
                    else
                        NoProof += 1;
                3:
                    NoReservedNCF += 1;
                4:
                    AlreadyOk += 1;
            end;
        until RVTransaction.Next() = 0;
    end;

    procedure DownloadCreditMemoPreview(RVTransaction: Record "RV Transaction Header"; SeriesOverride: Code[20])
    var
        TempBlob: Codeunit "Temp Blob";
        XMLStream: InStream;
        XMLOutStream: OutStream;
        CreditMemoXML: Text;
        PreviewNCF: Code[20];
        FileName: Text;
    begin
        if not BuildCreditMemoXMLPreview(RVTransaction, SeriesOverride, CreditMemoXML, PreviewNCF) then
            Error('No se pudo generar el XML de la nota de crédito para la transacción %1.', RVTransaction."Transaction No.");
        TempBlob.CreateOutStream(XMLOutStream, TextEncoding::UTF8);
        XMLOutStream.WriteText(CreditMemoXML);
        TempBlob.CreateInStream(XMLStream, TextEncoding::UTF8);
        FileName := 'NC_' + RVTransaction."LSDX NCF" + '.xml';
        DownloadFromStream(XMLStream, '', '', '', FileName);
    end;

    /// <summary>
    /// Genera en un ZIP los XML de nota de crédito de las transacciones del filtro. Solo vista previa: no envía ni consume NCF.
    /// </summary>
    procedure DownloadCreditMemoPreviewZip(var RVTransaction: Record "RV Transaction Header"; SeriesOverride: Code[20])
    var
        DataCompression: Codeunit "Data Compression";
        TempBlobXML: Codeunit "Temp Blob";
        TempBlobZip: Codeunit "Temp Blob";
        XMLStream: InStream;
        XMLOutStream: OutStream;
        ZipStream: InStream;
        ZipOutStream: OutStream;
        Progress: Dialog;
        CreditMemoXML: Text;
        PreviewNCF: Code[20];
        Total: Integer;
        Processed: Integer;
        Generated: Integer;
        Failed: Integer;
        FileName: Text;
    begin
        Total := RVTransaction.Count();
        if Total = 0 then
            exit;
        if Total > 2000 then
            if not Confirm('Se generarán %1 XML en un solo ZIP (vista previa). Puede tardar y ocupar mucha memoria. ¿Continuar?', false, Total) then
                exit;

        DataCompression.CreateZipArchive();
        Progress.Open('Generando XML de notas de crédito...\Procesados #1######## de #2########');
        Progress.Update(2, Total);
        RVTransaction.FindSet();
        repeat
            Processed += 1;
            Clear(TempBlobXML);
            if BuildCreditMemoXMLPreview(RVTransaction, SeriesOverride, CreditMemoXML, PreviewNCF) then begin
                TempBlobXML.CreateOutStream(XMLOutStream, TextEncoding::UTF8);
                XMLOutStream.WriteText(CreditMemoXML);
                TempBlobXML.CreateInStream(XMLStream, TextEncoding::UTF8);
                DataCompression.AddEntry(XMLStream, 'NC_' + RVTransaction."LSDX NCF" + '.xml');
                Generated += 1;
            end else
                Failed += 1;
            if Processed mod 50 = 0 then
                Progress.Update(1, Processed);
        until RVTransaction.Next() = 0;
        Progress.Close();

        if Generated = 0 then
            Error('No se generó ningún XML.');

        TempBlobZip.CreateOutStream(ZipOutStream);
        DataCompression.SaveZipArchive(ZipOutStream);
        DataCompression.CloseZipArchive();
        TempBlobZip.CreateInStream(ZipStream);
        FileName := 'NotasCredito_Preview.zip';
        DownloadFromStream(ZipStream, '', '', '', FileName);
        Message('XML generados: %1. Con error: %2.', Generated, Failed);
    end;

}
