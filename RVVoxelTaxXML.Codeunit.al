codeunit 51102 "RV Voxel Tax XML"
{
    procedure ForCancellation(XMLText: Text): Text
    begin
        // Compatibility with the affected historical invoices, not the fiscal rule.
        exit(SetSummaryBases(XMLText, true));
    end;

    procedure ForResend(XMLText: Text): Text
    begin
        exit(SetSummaryBases(XMLText, false));
    end;

    local procedure SetSummaryBases(XMLText: Text; HistoricalBase: Boolean) Result: Text
    var
        Document: XmlDocument;
        SummaryTaxes: XmlNodeList;
        ProductTaxes: XmlNodeList;
        SummaryTax: XmlNode;
        ProductTax: XmlNode;
        SummaryElement: XmlElement;
        SummaryRate: Decimal;
        NetBase: Decimal;
        MatchingLines: Integer;
    begin
        if not XmlDocument.ReadFrom(XMLText, Document) then
            Error('El documento Voxel no contiene XML válido.');
        if not Document.SelectNodes('/Transaction/TaxSummary/Tax', SummaryTaxes) then
            Error('El XML Voxel no contiene TaxSummary/Tax.');
        if SummaryTaxes.Count() = 0 then
            Error('El XML Voxel no contiene impuestos resumidos.');
        Document.SelectNodes('/Transaction/ProductList/Product/Taxes/Tax', ProductTaxes);
        foreach SummaryTax in SummaryTaxes do
            if AttributeValue(SummaryTax, 'Type') = 'ITBIS' then begin
                SummaryRate := DecimalAttribute(SummaryTax, 'Rate');
                NetBase := 0;
                MatchingLines := 0;
                foreach ProductTax in ProductTaxes do
                    if AttributeValue(ProductTax, 'Type') = 'ITBIS' then
                        if DecimalAttribute(ProductTax, 'Rate') = SummaryRate then begin
                            NetBase += DecimalAttribute(ProductTax, 'Base');
                            MatchingLines += 1;
                        end;
                if MatchingLines = 0 then
                    Error('No hay líneas ITBIS para reconstruir la base de la tasa %1.', SummaryRate);
                // Rebuild from line bases, so repeated calls never add/subtract tax twice.
                // Exempt lines and other rates never contribute to this tax group.
                if HistoricalBase then
                    NetBase += DecimalAttribute(SummaryTax, 'Amount');
                SummaryElement := SummaryTax.AsXmlElement();
                SummaryElement.SetAttribute('Base', Format(Round(NetBase, 0.01), 0, '<Precision,2:2><Standard Format,9>'));
            end;
        Document.WriteTo(Result);
    end;

    local procedure AttributeValue(Node: XmlNode; AttributeName: Text): Text
    var
        Attribute: XmlNode;
    begin
        if not Node.SelectSingleNode('@' + AttributeName, Attribute) then
            Error('Falta el atributo %1 en un impuesto del XML Voxel.', AttributeName);
        exit(Attribute.AsXmlAttribute().Value());
    end;

    local procedure DecimalAttribute(Node: XmlNode; AttributeName: Text) Value: Decimal
    begin
        if not Evaluate(Value, AttributeValue(Node, AttributeName), 9) then
            Error('El atributo %1 no es un decimal XML válido.', AttributeName);
    end;
}
