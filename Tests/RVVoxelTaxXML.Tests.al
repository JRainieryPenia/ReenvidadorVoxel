#if RV_TESTS
codeunit 51148 "RV Voxel Tax XML Tests"
{
    Subtype = Test;

    var
        TaxXML: Codeunit "RV Voxel Tax XML";

    [Test]
    procedure HistoricalMixedCancellation()
    var
        Result: Text;
    begin
        Result := TaxXML.ForCancellation(MixedInvoice('160.16'));
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Type="ITBIS"]/@Base', '188.99');
        AssertUnchangedAmounts(Result);
    end;

    [Test]
    procedure CorrectMixedResend()
    var
        Result: Text;
    begin
        Result := TaxXML.ForResend(MixedInvoice('188.99'));
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Type="ITBIS"]/@Base', '160.16');
        AssertUnchangedAmounts(Result);
    end;

    [Test]
    procedure RepeatedTransformsAreIdempotent()
    var
        Result: Text;
    begin
        Result := TaxXML.ForCancellation(TaxXML.ForCancellation(MixedInvoice('188.99')));
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Type="ITBIS"]/@Base', '188.99');
        Result := TaxXML.ForResend(TaxXML.ForResend(Result));
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Type="ITBIS"]/@Base', '160.16');
        AssertUnchangedAmounts(Result);
    end;

    [Test]
    procedure AllTaxableInvoice()
    var
        Source: Text;
    begin
        Source := '<Transaction><ProductList><Product><Taxes><Tax Type="ITBIS" Rate="18" Base="20169.49" Amount="3630.51"/></Taxes></Product></ProductList><TaxSummary><Tax Type="ITBIS" Rate="18" Base="23800.00" Amount="3630.51"/></TaxSummary><TotalSummary SubTotal="20169.49" Tax="3630.51" Total="23800.00"/></Transaction>';
        AssertAttribute(TaxXML.ForResend(Source), '/Transaction/TaxSummary/Tax/@Base', '20169.49');
        AssertAttribute(TaxXML.ForCancellation(TaxXML.ForResend(Source)), '/Transaction/TaxSummary/Tax/@Base', '23800.00');
    end;

    [Test]
    procedure SeparateTaxRates()
    var
        Source: Text;
        Result: Text;
    begin
        Source := '<Transaction><ProductList><Product><Taxes><Tax Type="ITBIS" Rate="18.00" Base="100.00" Amount="18.00"/></Taxes></Product><Product><Taxes><Tax Type="ITBIS" Rate="16" Base="200.00" Amount="32.00"/></Taxes></Product></ProductList><TaxSummary><Tax Type="ITBIS" Rate="18" Base="118.00" Amount="18.00"/><Tax Type="ITBIS" Rate="16" Base="232.00" Amount="32.00"/></TaxSummary></Transaction>';
        Result := TaxXML.ForResend(Source);
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Rate="18"]/@Base', '100.00');
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Rate="16"]/@Base', '200.00');
        Result := TaxXML.ForCancellation(Result);
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Rate="18"]/@Base', '118.00');
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Rate="16"]/@Base', '232.00');
    end;

    [Test]
    procedure ExemptOnlyIsPreserved()
    var
        Source: Text;
    begin
        Source := '<Transaction><ProductList><Product><Taxes><Tax Type="Exento" Rate="0" Base="75.45" Amount="0"/></Taxes></Product></ProductList><TaxSummary><Tax Type="Exento" Rate="0" Base="75.45" Amount="0"/></TaxSummary></Transaction>';
        AssertAttribute(TaxXML.ForCancellation(Source), '/Transaction/TaxSummary/Tax/@Base', '75.45');
        AssertAttribute(TaxXML.ForResend(Source), '/Transaction/TaxSummary/Tax/@Amount', '0');
    end;

    [Test]
    procedure MissingTaxLinesCannotBeGuessed()
    begin
        asserterror TaxXML.ForResend('<Transaction><ProductList/><TaxSummary><Tax Type="ITBIS" Rate="18" Base="118.00" Amount="18.00"/></TaxSummary></Transaction>');
        if StrPos(GetLastErrorText(), 'No hay líneas ITBIS') = 0 then
            Error('Se esperaba rechazar la base sin líneas de respaldo.');
    end;

    [Test]
    procedure CreditMemoWithoutClientHasReference()
    var
        Management: Codeunit "RV Resent Management";
        Result: Text;
    begin
        Result := Management.ConvertToCreditMemo(MixedInvoice('188.99'), 'REF-NC', 'E340000000001', 'E320000153206', '1');
        Result := TaxXML.ForCancellation(Result);
        AssertAttribute(Result, '/Transaction/GeneralData/@Type', 'FacturaAbono');
        AssertAttribute(Result, '/Transaction/References/Reference/@InvoiceNCF', 'E320000153206');
        AssertUnchangedAmounts(Result);
    end;

    local procedure MixedInvoice(SummaryBase: Text): Text
    begin
        exit('<Transaction><GeneralData Ref="00000P1001000342556" Type="FacturaConsumo" Date="2026-09-29" NCF="E320000153206" TaxIncluded="false"/>' +
            '<ProductList><Product><Taxes><Tax Type="ITBIS" Rate="18" Base="152.35" Amount="27.42"/></Taxes></Product>' +
            '<Product><Taxes><Tax Type="Exento" Rate="0" Base="30.00" Amount="0"/></Taxes></Product>' +
            '<Product><Taxes><Tax Type="Exento" Rate="0" Base="45.45" Amount="0"/></Taxes></Product>' +
            '<Product><Taxes><Tax Type="ITBIS" Rate="18" Base="7.81" Amount="1.41"/></Taxes></Product></ProductList>' +
            '<TaxSummary><Tax Type="ITBIS" Rate="18" Base="' + SummaryBase + '" Amount="28.83"/><Tax Type="Exento" Rate="0" Base="75.45" Amount="0"/></TaxSummary>' +
            '<TotalSummary SubTotal="235.61" Tax="28.83" Total="264.44"/></Transaction>');
    end;

    local procedure AssertUnchangedAmounts(Result: Text)
    begin
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Type="ITBIS"]/@Amount', '28.83');
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Type="Exento"]/@Base', '75.45');
        AssertAttribute(Result, '/Transaction/TaxSummary/Tax[@Type="Exento"]/@Amount', '0');
        AssertAttribute(Result, '/Transaction/TotalSummary/@SubTotal', '235.61');
        AssertAttribute(Result, '/Transaction/TotalSummary/@Tax', '28.83');
        AssertAttribute(Result, '/Transaction/TotalSummary/@Total', '264.44');
        AssertAttribute(Result, '/Transaction/ProductList/Product[1]/Taxes/Tax/@Base', '152.35');
        AssertAttribute(Result, '/Transaction/ProductList/Product[1]/Taxes/Tax/@Amount', '27.42');
    end;

    local procedure AssertAttribute(XMLText: Text; XPath: Text; Expected: Text)
    var
        Document: XmlDocument;
        Node: XmlNode;
    begin
        XmlDocument.ReadFrom(XMLText, Document);
        if not Document.SelectSingleNode(XPath, Node) then
            Error('No se encontró %1.', XPath);
        if Node.AsXmlAttribute().Value() <> Expected then
            Error('%1: esperado %2; obtenido %3.', XPath, Expected, Node.AsXmlAttribute().Value());
    end;
}
#endif
