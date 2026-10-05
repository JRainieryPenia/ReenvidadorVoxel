codeunit 51102 "RV Voxel Tax XML"
{
    // Estado compartido en la sesión: la página lo fija y las rutas de nota de crédito en otros codeunits lo respetan.
    SingleInstance = true;

    var
        UseCorrectedBase: Boolean;

    /// <summary>
    /// false (por defecto): la nota usa la base histórica (base + ITBIS) para igualar facturas enviadas con ese cálculo.
    /// true: la nota usa la base correcta de las líneas, para facturas cuyo XML enviado ya tenía la base correcta.
    /// </summary>
    procedure SetCorrectedBase(Corrected: Boolean)
    begin
        UseCorrectedBase := Corrected;
    end;

    procedure ForCancellation(XMLText: Text): Text
    begin
        // Por defecto: compatibilidad con las facturas históricas afectadas, no la regla fiscal.
        exit(SetModificationCode(SetSummaryBases(XMLText, not UseCorrectedBase), '1'));
    end;

    procedure ForResend(XMLText: Text): Text
    begin
        exit(SetSummaryBases(XMLText, false));
    end;

    /// <summary>
    /// Fuerza CodigoModificacion en la referencia de la nota de crédito (1 = anula el NCF modificado),
    /// sin depender del tipo por defecto del setup. Si el XML no tiene referencia, no hace nada.
    /// </summary>
    local procedure SetModificationCode(XMLText: Text; ModificationCode: Text) Result: Text
    var
        Document: XmlDocument;
        DOMNodes: XmlNodeList;
        DOMNode: XmlNode;
        DOMElement: XmlElement;
    begin
        if not XmlDocument.ReadFrom(XMLText, Document) then
            Error('El documento Voxel no contiene XML válido.');
        if Document.SelectNodes('/Transaction/References/Reference/PublicAdministration/DOM', DOMNodes) then
            foreach DOMNode in DOMNodes do begin
                DOMElement := DOMNode.AsXmlElement();
                DOMElement.SetAttribute('CodigoModificacion', ModificationCode);
            end;
        Document.WriteTo(Result);
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
