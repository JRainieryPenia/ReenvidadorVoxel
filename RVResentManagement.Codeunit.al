codeunit 51100 "RV Resent Management"
{
    trigger OnRun()
    begin

    end;

    var

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

}
