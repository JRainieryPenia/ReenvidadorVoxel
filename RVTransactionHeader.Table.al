table 51100 "RV Transaction Header"
{
    DataClassification = CustomerContent;

    fields
    {
        field(51108; "NCF Replacement Done"; Boolean)
        {
            Caption = 'NCF reemplazado (marca)';
            FieldClass = FlowField;
            CalcFormula = lookup("LSC Transaction Header"."NCF Replacement Done" where("Store No." = field("Store No."), "POS Terminal No." = field("POS Terminal No."), "Transaction No." = field("Transaction No.")));
            Editable = false;
        }
        field(51109; "Old NCF"; Code[20])
        {
            Caption = 'NCF antiguo';
            FieldClass = FlowField;
            CalcFormula = lookup("LSC Transaction Header"."NCF antiguo" where("Store No." = field("Store No."), "POS Terminal No." = field("POS Terminal No."), "Transaction No." = field("Transaction No.")));
            Editable = false;
        }
        field(51110; "Replacement NCF"; Code[20])
        {
            Caption = 'NCF Reemplazado';
            FieldClass = FlowField;
            CalcFormula = lookup("LSC Transaction Header"."NCF Reemplazado" where("Store No." = field("Store No."), "POS Terminal No." = field("POS Terminal No."), "Transaction No." = field("Transaction No.")));
            Editable = false;
        }
        field(51107; "Credit Memo XML"; Blob)
        {
            Caption = 'XML completo de nota de crédito';
            DataClassification = CustomerContent;
        }
        field(5; "Transaction No."; Integer)
        {
            Caption = 'Transaction No.';
            DataClassification = CustomerContent;
        }
        field(15; "Receipt No."; Code[20])
        {
            Caption = 'Receipt No.';
            DataClassification = CustomerContent;
        }
        field(20; "Store No."; Code[10])
        {
            Caption = 'Store No.';
            TableRelation = "LSC Store"."No.";
            DataClassification = CustomerContent;
        }
        field(25; "POS Terminal No."; Code[10])
        {
            Caption = 'POS Terminal No.';
            TableRelation = "LSC POS Terminal"."No.";
            ValidateTableRelation = false;
            DataClassification = CustomerContent;
        }
        field(35; Date; Date)
        {
            Caption = 'Date';
            DataClassification = CustomerContent;
        }

        field(51100; "LSDX NCF"; Code[20])
        {
            DataClassification = EndUserIdentifiableInformation;
            Caption = 'NCF';
            Description = 'DX-Guardar el NCF que proviene de Supermarket Application.';
        }
        field(51101; Voided; Boolean)
        {
            DataClassification = CustomerContent;
            Caption = 'Voided';
            Description = 'Indicates whether the transaction is voided.';
        }
        field(51102; "Voided Date"; Date)
        {
            DataClassification = CustomerContent;
            Caption = 'Voided Date';
            Description = 'The date when the transaction was voided.';
        }
        field(51103; ReSent; Boolean)
        {
            DataClassification = CustomerContent;
            Caption = 'ReSent';
            Description = 'Indicates whether the transaction has been sent to the external system.';
        }
        field(51104; "Voided NCF"; Code[20])
        {
            DataClassification = EndUserIdentifiableInformation;
            Caption = 'Voided NCF';
            Description = 'NCF assigned when a transaction is voided.';
        }
        field(51105; "Voided NCF Credit Memo"; Code[20])
        {
            DataClassification = EndUserIdentifiableInformation;
            Caption = 'Voided NCF Credit Memo';
            Description = 'NCF of the credit memo generated when voiding a transaction.';
        }
        field(51106; "XML Document Text"; Text[2000])
        {
            DataClassification = CustomerContent;
            Caption = 'XML Document Text';
            Description = 'Contains the XML document generated for the transaction.';
        }
    }

    keys
    {
        key(Key1; "Store No.", "POS Terminal No.", "Transaction No.")
        {
            Clustered = true;
        }
    }

    procedure SetCreditMemoXML(XMLText: Text)
    var
        XMLStream: OutStream;
    begin
        Clear("Credit Memo XML");
        "Credit Memo XML".CreateOutStream(XMLStream, TextEncoding::UTF8);
        XMLStream.WriteText(XMLText);
    end;

    procedure GenerateEFHeader(CreditMemoNCF: Code[20]; TransactionHeader: Record "LSC Transaction Header"; var EFEncabezado: Record "EF Encabezado" temporary): Boolean
    var
        CompanyInformation: Record "Company Information";
        Currency: Record Currency;
        CustomerBuyer: Record Customer;
        _efEncabezado: Record "EF Encabezado";
        Item: Record Item;
        PaymentTerms: Record "Payment Terms";

        ServiceZone: Record "Service Zone";
        CurrencyFactor, CurrencyFactorOriginalVoxel : Decimal;
        Itbis1: Decimal;
        Itbis2: Decimal;
        Itbis3: Decimal;
        MontoExento: Decimal;
        MontoGrabado1: Decimal;
        MontoGrabado2: Decimal;
        MontoGrabado3: Decimal;
        MontoGrabadoTotal: Decimal;
        MontoTotal: Decimal;
        NoInvoiceAmount: Decimal;
        PeriodAmount: Decimal;
        TotalItbis1: Decimal;
        TotalItbis2: Decimal;
        TotalItbis3: Decimal;
        ValuePayable: Decimal;
        VatAmountTotalAnotherCurrency: Decimal;
        ItemLines: Integer;
        IndicadorBienoServicioValue: Text[1];
        HasItbis1Lines: Boolean;
        HasItbis2Lines: Boolean;
        HasItbis3Lines: Boolean;
        HasExentoLines: Boolean;
        EFFormasdePago: record "EF Form Type";
        EFTelefonoEmisor: record "EF Telefono Emisor";
        DxDgiiRncDatabaseEmisor: record "DXDGII-RNC Database";
        DxDgiiRncDatabaseComprador: record "DXDGII-RNC Database";
        EFImpAdicionalesEncab: record "EF Imp. Adicionales - Encab.";
        PosTransLineBuffer: Record "LSC POS Trans. Line" temporary;
        EFDetalleBienesoServicios: record "EF Detalle Bienes o Servicios";
        EFCodigosItem: record "EF Codigos Item";
        EFSubcantidad: record "EF Subcantidad";
        EFSubDescuento: record "EF SubDescuento";
        EFImpuestosAdicionalesDBS: record "EF Impuestos Adicionales - DBS";
        EFSubTotalesInformativos: record "EF SubTotales Informativos";
        EFPaginacion: record "EF Paginacion";
        EFInformacionReferencia: RECORD "EF Informacion Referencia";
        //---
        AffectedTransactionHeader: Record "LSC Transaction Header";
        LscTransSalesEntry: Record "LSC Trans. Sales Entry";
        LscTransPaymentEntry: Record "LSC Trans. Payment Entry";
        LscTransPaymentEntry2: Record "LSC Trans. Payment Entry";
        LsdxTenderTypesRelation: Record "LSDXTender Types Relation";
        VatPostingSetup: Record "VAT Posting Setup";

        NoNcfErr: Label 'Receipt %1 does not have eNCF on Transaction %2 For Terminal %3', Comment = '%1 = Receipt No., %2 = Transacton No., %3 = Termninal No.';
        ecfType: Code[2];
        CurrencyExchangeRate: Record "Currency Exchange Rate";
        Setup: Record "EF Administration Setup";
        NcfSetup: Record "DXNCF Setup";
        rLSDXPoSSetup: RECORD "LSDX POS SETUP";
        Utilities: Codeunit "EF Utility Management";
        ValidLinesCount: Integer;
        NoSalesEntriesErr: Label 'Transaction %1: No sales entries found. Cannot generate electronic document.', Comment = '%1 = Receipt No.';
        NoValidSalesEntriesErr: Label 'Transaction %1: No valid sales entries found. All lines have zero amount. Cannot generate electronic document.', Comment = '%1 = Receipt No.';
    begin
        Utilities.ClearEFTablesByDocument(TransactionHeader."Receipt No.");
        if Setup.Get() then;
        if TransactionHeader."LSDX NCF" = '' then
            Error(NoNcfErr, TransactionHeader."Receipt No.", TransactionHeader."Transaction No.", TransactionHeader."POS Terminal No.");

        if not rLSDXPoSSetup.Get() then exit;

        // Validate that there are sales entries
        LscTransSalesEntry.SetCurrentKey("Store No.", "POS Terminal No.", "Transaction No.");
        LscTransSalesEntry.SetRange("Store No.", TransactionHeader."Store No.");
        LscTransSalesEntry.SetRange("POS Terminal No.", TransactionHeader."POS Terminal No.");
        LscTransSalesEntry.SetRange("Transaction No.", TransactionHeader."Transaction No.");
        if not LscTransSalesEntry.FindSet() then
            Error(NoSalesEntriesErr, TransactionHeader."Receipt No.");

        // Nota: Se permite generar documentos electrónicos con monto 0 para devoluciones y ventas
        // La validación de montos cero fue removida para soportar estos escenarios

        CompanyInformation.Get();

        if CompanyInformation."VAT Registration No." <> '' then begin
            DxDgiiRncDatabaseEmisor.Reset();
            DxDgiiRncDatabaseEmisor.SetCurrentKey(RNC);
            DxDgiiRncDatabaseEmisor.Get(CompanyInformation."VAT Registration No.");
        end;
        CompanyInformation.CalcFields("EF DR County Code", "EF DR Township Code");
        if TransactionHeader."Customer No." <> '' then begin
            Clear(CustomerBuyer);
            if CustomerBuyer.Get(TransactionHeader."Customer No.") then;
            if ServiceZone.Get(CustomerBuyer."Service Zone Code") then;
            if DxDgiiRncDatabaseComprador.Get(CustomerBuyer."VAT Registration No.") then;
            //T20260216.0026 -
            if CustomerBuyer."Payment Terms Code" <> '' then
                PaymentTerms.Get(CustomerBuyer."Payment Terms Code");
            //T20260216.0026 +

            CustomerBuyer.CalcFields("EF DR County Code", "EF DR Township Code");
        end;

        CurrencyFactor := 1;
        //T20260319.0013 -
        CurrencyFactor := 1;
        IF TransactionHeader."Trans. Currency" <> '' THEN BEGIN
            // EF-VOXEL
            if Setup.Provider = Setup.Provider::Voxel then begin
                CurrencyFactor := 1;
                CurrencyFactorOriginalVoxel := 1 / TransactionHeader."Currency Factor";
            end
            else
                CurrencyFactor := TransactionHeader."Currency Factor";
            //T20260330.0001 - Asignar currency factor desde la cabecera si el currency factor de la línea es 0 para evitar división por 0

            if CurrencyFactor = 0 then begin
                CurrencyFactor := 1;
                // Log para identificar que falta una configuración en las Currencies
                Message('El Currency Factor es 0 para la moneda %1. Verifique la configuración en la tabla Currencies.', TransactionHeader."Trans. Currency");
            end;
            // EF-VOXEL
        END;
        //T20260319.0013 +
        _efEncabezado.Reset();
        _efEncabezado.SetRange(DocumentNo, CopyStr((CreditMemoNCF + TransactionHeader."Receipt No."), 1, 20));
        if not _efEncabezado.IsEmpty() then
            _efEncabezado.DeleteAll(true);

        EFEncabezado.Init();
        EFEncabezado.DocumentNo := CopyStr((CreditMemoNCF + TransactionHeader."Receipt No."), 1, 20);
        EFEncabezado.Version := '1.0';
        ecfType := CopyStr(CreditMemoNCF, 2, 2);
        Evaluate(EFEncabezado.TipoeCF, ecfType);

        EFEncabezado.eNCF := CopyStr(CreditMemoNCF, 1, MaxStrLen(EFEncabezado.eNCF));
        EFEncabezado.FechaVencimientoSecuencia := TransactionHeader."LSDX Fecha Expiracion NCF";

        if TransactionHeader."Sale Is Return Sale" then begin
            AffectedTransactionHeader.Reset();
            AffectedTransactionHeader.SetRange("Receipt No.", TransactionHeader."Retrieved from Receipt No.");
            if AffectedTransactionHeader.FindFirst() then
                EFEncabezado.IndicadorNotaCredito := (TransactionHeader.Date - AffectedTransactionHeader.Date) > 30;
        end;

        EFEncabezado.IndicadorEnvioDiferido := true;
        EFEncabezado.IndicadorMontoGravado := false;
        EFEncabezado.TipoIngresos := 1; //TODO: De donde se debe tomar este valor?

        //TODO: Para este valor deberiamos buscar la linea con monto mayor.
        Clear(LscTransPaymentEntry);
        LscTransPaymentEntry.SETRANGE("Store No.", TransactionHeader."Store No.");
        LscTransPaymentEntry.SETRANGE("POS Terminal No.", TransactionHeader."POS Terminal No.");
        LscTransPaymentEntry.SETRANGE("Transaction No.", TransactionHeader."Transaction No.");

        Clear(LsdxTenderTypesRelation);
        //T20250512.0009 -
        if not LscTransPaymentEntry.FindFirst() then begin
            CLEAR(LsdxTenderTypesRelation);
            LsdxTenderTypesRelation.SetRange("Tender Type Code", LscTransPaymentEntry."Tender Type");
            if LsdxTenderTypesRelation.FindFirst() then
                EFEncabezado.TipoPago := LsdxTenderTypesRelation."LSEF Payment Type".AsInteger();
        end ELSE begin
            //T20250512.0009 -
            LsdxTenderTypesRelation.SetRange("Tender Type Code", LscTransPaymentEntry."Tender Type");
            if LsdxTenderTypesRelation.FindFirst() then
                EFEncabezado.TipoPago := LsdxTenderTypesRelation."LSEF Payment Type".AsInteger();
            //T20250512.0009 +              
        end;

        if EFEncabezado.TipoPago = 0 then
            Error('Medio de pago no registrado %1 en la relacion de medios de pago', LscTransPaymentEntry."Tender Type");

        //T20260216.0026 - Homologacion campos comprador en blanco
        EFEncabezado.FechaLimitePago := TransactionHeader.Date;
        if not Setup."Send Payment Terms Blank" then
            EFEncabezado.TerminoPago := copystr(PaymentTerms.Description, 1, MaxStrLen(EFEncabezado.TerminoPago));


        IF Setup.Provider = Setup.Provider::Voxel THEN
            EFEncabezado.FechaLimitePago := CALCDATE(PaymentTerms."Due Date Calculation", TransactionHeader.Date);

        Clear(LscTransPaymentEntry);
        LscTransPaymentEntry.SETRANGE("Store No.", TransactionHeader."Store No.");
        LscTransPaymentEntry.SETRANGE("POS Terminal No.", TransactionHeader."POS Terminal No.");
        LscTransPaymentEntry.SETRANGE("Transaction No.", TransactionHeader."Transaction No.");
        LscTransPaymentEntry.SetRange("Change Line", false);
        if LscTransPaymentEntry.FindSet() then
            repeat
                clear(LsdxTenderTypesRelation);
                LsdxTenderTypesRelation.SetRange("Tender Type Code", LscTransPaymentEntry."Tender Type");
                if LsdxTenderTypesRelation.FindFirst() then begin
                    Clear(EFFormasdePago);
                    EFFormasdePago.DocumentNo := EFEncabezado.DocumentNo;
                    EFFormasdePago.FormaPago := LsdxTenderTypesRelation."LSEF Payment Type Form";

                    if not EFFormasdePago.FindFirst() then begin
                        LscTransPaymentEntry2.SETRANGE("Store No.", TransactionHeader."Store No.");
                        LscTransPaymentEntry2.SETRANGE("POS Terminal No.", TransactionHeader."POS Terminal No.");
                        LscTransPaymentEntry2.SETRANGE("Transaction No.", TransactionHeader."Transaction No.");
                        LscTransPaymentEntry2.SETRANGE("Tender Type", LscTransPaymentEntry."Tender Type");
                        LscTransPaymentEntry2.SETRANGE("Change Line", TRUE);

                        if LscTransPaymentEntry2.FindFirst() then begin
                            EFFormasdePago.isPosTrans := TRUE;
                            EFFormasdePago.MontoPago := (Abs(LscTransPaymentEntry."Amount Tendered") - Abs(LscTransPaymentEntry2."Amount Tendered")) / CurrencyFactor;
                            EFFormasdePago."Line No." := LscTransPaymentEntry."Line No.";
                        end
                        else begin
                            EFFormasdePago."Line No." := LscTransPaymentEntry."Line No.";
                            EFFormasdePago.MontoPago := Abs(LscTransPaymentEntry."Amount Tendered") / CurrencyFactor;
                        end;
                        EFFormasdePago.Insert(true);
                    end;
                end;
            until LscTransPaymentEntry.Next() = 0;


        //Area Emisor
        EFEncabezado.RNCEmisor := CopyStr(CompanyInformation."VAT Registration No.", 1, MaxStrLen(EFEncabezado.RNCEmisor));
        EFEncabezado.RazonSocialEmisor := CopyStr(DxDgiiRncDatabaseEmisor."Nombre/Razon Social", 1, MaxStrLen(EFEncabezado.RazonSocialEmisor));
        EFEncabezado.NombreComercial := CompanyInformation.Name;
        EFEncabezado.DireccionEmisor := CompanyInformation.Address;
        EFEncabezado.Municipio := CopyStr(CompanyInformation."EF DR Township Code", 1, MaxStrLen(EFEncabezado.Municipio));
        EFEncabezado.Provincia := CopyStr(CompanyInformation."EF DR County Code", 1, MaxStrLen(EFEncabezado.Provincia));
        EFEncabezado.PaisOrigen := CompanyInformation."Country/Region Code"; // EF-VOXEL

        // Tabla Telefono Emisor
        clear(EFTelefonoEmisor);
        EFTelefonoEmisor.DocumentNo := EFEncabezado.DocumentNo;
        EFTelefonoEmisor.TelefonoEmisor := CompanyInformation."Phone No.";
        EFTelefonoEmisor.Insert(true);

        clear(EFTelefonoEmisor);
        EFTelefonoEmisor.DocumentNo := EFEncabezado.DocumentNo;
        EFTelefonoEmisor.TelefonoEmisor := CompanyInformation."Phone No. 2";
        EFTelefonoEmisor.Insert(true);

        EFEncabezado.CorreoEmisor := CompanyInformation."E-Mail";
        EFEncabezado.WebSite := CopyStr(CompanyInformation."Home Page", 1, MaxStrLen(EFEncabezado.WebSite));
        EFEncabezado.ActividadEconomica := DxDgiiRncDatabaseEmisor."Area Negocio";
        EFEncabezado.CodigoVendedor := TransactionHeader."Staff ID";
        //TODO: Este campo no se puede enviar, ya que tiene letras y el XML solo permite numeros.
        EFEncabezado.NumeroFacturaInterna := TransactionHeader."Receipt No.";
        EFEncabezado.NumeroPedidoInterno := TransactionHeader."Receipt No.";
        EFEncabezado.FechaEmision := TransactionHeader.Date;
        EFEncabezado.ZonaVenta := ServiceZone.Code;
        EFEncabezado.RutaVenta := '';

        IF NcfSetup.GET() THEN;
        IF TransactionHeader."Customer No." <> '' THEN BEGIN


            //T20251031.0005 -
            if (rLSDXPoSSetup."Customer NCF PRIO") and (CustomerBuyer."VAT Registration No." <> '') then begin
                EFEncabezado.RNCComprador := COPYSTR(CustomerBuyer."VAT Registration No.", 1, MAXSTRLEN(EFEncabezado.RNCComprador));
                //T20251031.0005 +
                EFEncabezado.RazonSocialComprador := COPYSTR(CustomerBuyer."DxRazon Social", 1, MAXSTRLEN(EFEncabezado.RazonSocialComprador));
            end;
            //T20251031.0005 -
            if not (rLSDXPoSSetup."Customer NCF PRIO") and (TransactionHeader."LSDX Tipo Doc. Fiscal" = TransactionHeader."LSDX Tipo Doc. Fiscal"::"Valid for Fiscal Credit") then
                if (CustomerBuyer."VAT Registration No." = '') and (TransactionHeader."LSDX RNC/Cedula" <> '') then begin
                    EFEncabezado.RNCComprador := COPYSTR(TransactionHeader."LSDX RNC/Cedula", 1, MAXSTRLEN(EFEncabezado.RNCComprador));
                    EFEncabezado.RazonSocialComprador := COPYSTR(TransactionHeader."LSDX Razon Social", 1, MAXSTRLEN(EFEncabezado.RazonSocialComprador));
                end
                else if (CustomerBuyer."VAT Registration No." <> '') and (TransactionHeader."LSDX RNC/Cedula" = '') then begin
                    EFEncabezado.RNCComprador := COPYSTR(CustomerBuyer."VAT Registration No.", 1, MAXSTRLEN(EFEncabezado.RNCComprador));
                    EFEncabezado.RazonSocialComprador := COPYSTR(CustomerBuyer."DxRazon Social", 1, MAXSTRLEN(EFEncabezado.RazonSocialComprador));
                end;

            //T20251031.0005 +



            //T20251031.0005 -
            if not (rLSDXPoSSetup."Customer NCF PRIO") and (TransactionHeader."LSDX Tipo Doc. Fiscal" = TransactionHeader."LSDX Tipo Doc. Fiscal"::"Credit Note") then
                if (CustomerBuyer."VAT Registration No." = '') and (TransactionHeader."LSDX RNC/Cedula" <> '') then begin
                    EFEncabezado.RNCComprador := COPYSTR(TransactionHeader."LSDX RNC/Cedula", 1, MAXSTRLEN(EFEncabezado.RNCComprador));
                    EFEncabezado.RazonSocialComprador := COPYSTR(TransactionHeader."LSDX Razon Social", 1, MAXSTRLEN(EFEncabezado.RazonSocialComprador));
                end
                else if (CustomerBuyer."VAT Registration No." <> '') and (TransactionHeader."LSDX RNC/Cedula" = '') then begin
                    EFEncabezado.RNCComprador := COPYSTR(CustomerBuyer."VAT Registration No.", 1, MAXSTRLEN(EFEncabezado.RNCComprador));
                    EFEncabezado.RazonSocialComprador := COPYSTR(CustomerBuyer."DxRazon Social", 1, MAXSTRLEN(EFEncabezado.RazonSocialComprador));
                end
                else if (CustomerBuyer."VAT Registration No." = '') and (TransactionHeader."LSDX RNC/Cedula" = '') then begin
                    EFEncabezado.RNCComprador := '00000000000';
                    EFEncabezado.RazonSocialComprador := 'Contado menor 250k';
                end;
            //T20251031.0005 +


            //T20251031.0005 -
            if not (rLSDXPoSSetup."Customer NCF PRIO") and (TransactionHeader."LSDX Tipo Doc. Fiscal" = TransactionHeader."LSDX Tipo Doc. Fiscal"::"Final Consumer") then
                if (CustomerBuyer."VAT Registration No." = '') and (TransactionHeader."LSDX RNC/Cedula" <> '') then begin
                    EFEncabezado.RNCComprador := COPYSTR(TransactionHeader."LSDX RNC/Cedula", 1, MAXSTRLEN(EFEncabezado.RNCComprador));
                    EFEncabezado.RazonSocialComprador := COPYSTR(TransactionHeader."LSDX Razon Social", 1, MAXSTRLEN(EFEncabezado.RazonSocialComprador));
                end
                else if (CustomerBuyer."VAT Registration No." <> '') and (TransactionHeader."LSDX RNC/Cedula" = '') then begin
                    EFEncabezado.RNCComprador := COPYSTR(CustomerBuyer."VAT Registration No.", 1, MAXSTRLEN(EFEncabezado.RNCComprador));
                    EFEncabezado.RazonSocialComprador := COPYSTR(CustomerBuyer."DxRazon Social", 1, MAXSTRLEN(EFEncabezado.RazonSocialComprador));
                end
                else if (CustomerBuyer."VAT Registration No." = '') and (TransactionHeader."LSDX RNC/Cedula" = '') then begin
                    EFEncabezado.RNCComprador := '00000000000';
                    EFEncabezado.RazonSocialComprador := 'Contado menor 250k';
                end;
            //T20251031.0005 +


            //TODO: VALIDAR DE DONDE SE VA A TOMAR ESTE VALOR IdentificadorExtranjero
            // Corresponde al número de identificación cuando el comprador es extranjero y no tiene RNC/Cédula.
            //EFEncabezado.IdentificadorExtranjero := '';
            if (Setup.Provider = Setup.Provider::Voxel) and (EFEncabezado.TipoeCF = EFEncabezado.TipoeCF::"E34 Credit Memo") then
                EFEncabezado.IdentificadorExtranjero := CustomerBuyer."VAT Registration No."
            else
                EFEncabezado.IdentificadorExtranjero := '';

            //T20251031.0005 -
            // IF DxDgiiRncDatabaseComprador."Nombre/Razon Social" <> '' THEN   //JK24-
            //     EFEncabezado.RazonSocialComprador := DxDgiiRncDatabaseComprador."Nombre/Razon Social"
            // ELSE begin
            //     // if not (rLSDXPoSSetup."Customer NCF PRIO") and (TransactionHeader."LSDX Tipo Doc. Fiscal" = TransactionHeader."LSDX Tipo Doc. Fiscal"::"Valid for Fiscal Credit") then
            //     //     if (CustomerBuyer.Name <> '') and (CustomerBuyer."DxRazon Social" <> '') then
            //     //         //  EFEncabezado.RazonSocialComprador := CustomerBuyer."DxRazon Social"
            //     //         ELSE
            //     //         if (EFEncabezado.RazonSocialComprador = '') and (TransactionHeader."LSDX Razon Social" = '') then
            //     //             EFEncabezado.RazonSocialComprador := CustomerBuyer."DxRazon Social"//jk24-


            // end;
            //T20251031.0005 +

            //T20260216.0026 - Homologacion campos comprador en blanco
            if not Setup."Send Buyer Phone Blank" then
                EFEncabezado.ContactoComprador := CustomerBuyer."Phone No.";
            //EFEncabezado.CorreoComprador := CustomerBuyer."E-Mail"; //4840
            if not Setup."Send Buyer Address Blank" then
                EFEncabezado.DireccionComprador := CustomerBuyer.Address;
            if not Setup."Send Municipality Blank" then begin
                EFEncabezado.MunicipioComprador := CustomerBuyer."EF DR Township Code";
                EFEncabezado.ProvinciaComprador := CustomerBuyer."EF DR County Code";
            end;
            EFEncabezado.PaisComprador := CustomerBuyer."Country/Region Code"; // EF-VOXEL

            IF NcfSetup.GET() THEN;
            IF ((TransactionHeader."LSDX Tipo Doc. Fiscal" IN [TransactionHeader."LSDX Tipo Doc. Fiscal"::"Final Consumer", TransactionHeader."LSDX Tipo Doc. Fiscal"::"Credit U. Final"])
                  AND (ABS(TransactionHeader."Gross Amount") < NcfSetup."Max Amount without RNC/Cedula")) THEN BEGIN // TEMPORAL SOLO PARA PRUEBA
                IF (TransactionHeader."LSDX Tipo Doc. Fiscal" IN [TransactionHeader."LSDX Tipo Doc. Fiscal"::"Final Consumer", TransactionHeader."LSDX Tipo Doc. Fiscal"::"Credit U. Final"]) THEN BEGIN
                    EFEncabezado.RNCComprador := '00000000000';
                    EFEncabezado.RazonSocialComprador := 'Contado menor 250k';
                END;
            END;
            TransactionHeader."LSDXTIpo NCF" := CustomerBuyer."DxTipo NCF";

        END ELSE BEGIN
            // Escenario cuando no hay Customer No. asignado
            IF (TransactionHeader."LSDX Tipo Doc. Fiscal" = TransactionHeader."LSDX Tipo Doc. Fiscal"::"Final Consumer") AND (ABS(TransactionHeader."Gross Amount") >= NcfSetup."Max Amount without RNC/Cedula") THEN BEGIN
                // Consumidor Final con monto >= 250k requiere información del cliente
                EFEncabezado.RNCComprador := TransactionHeader."LSDX RNC/Cedula";
                EFEncabezado.RazonSocialComprador := TransactionHeader."LSDX Razon Social";
                if TransactionHeader."LSDX Tipo Identificacion" = TransactionHeader."LSDX Tipo Identificacion"::Passport then
                    EFEncabezado.IdentificadorExtranjero := Format(TransactionHeader."LSDX Tipo Identificacion");
            END
            ELSE BEGIN
                // Consumidor Final con monto < 250k o cualquier otro tipo sin cliente
                IF (TransactionHeader."LSDX Tipo Doc. Fiscal" = TransactionHeader."LSDX Tipo Doc. Fiscal"::"Final Consumer") THEN BEGIN
                    EFEncabezado.RNCComprador := '00000000000';
                    EFEncabezado.RazonSocialComprador := 'Contado menor 250k';
                    TransactionHeader."LSDXTipo NCF" := 'E32';
                END
                ELSE BEGIN
                    // Otros tipos de documento fiscal sin cliente
                    EFEncabezado.RNCComprador := TransactionHeader."LSDX RNC/Cedula";
                    EFEncabezado.RazonSocialComprador := TransactionHeader."LSDX Razon Social";
                END;
            END;
        END;

        //RLJK24-
        IF EFEncabezado.RNCComprador <> '' THEN
            EFEncabezado.RNCComprador := DELCHR(EFEncabezado.RNCComprador, '=', '-');
        //RLJK24+

        // Area Informaciones Adicionales

        // Area Transporte

        //Area Totales
        MontoGrabadoTotal := 0;
        MontoGrabado1 := 0;
        MontoGrabado2 := 0;
        MontoGrabado3 := 0;
        Itbis1 := 0;
        Itbis2 := 0;
        Itbis3 := 0;
        Clear(LscTransSalesEntry);
        LscTransSalesEntry.SetCurrentKey("Store No.", "POS Terminal No.", "Transaction No.");
        LscTransSalesEntry.SetRange("Store No.", TransactionHeader."Store No.");
        LscTransSalesEntry.SetRange("POS Terminal No.", TransactionHeader."POS Terminal No.");
        LscTransSalesEntry.SetRange("Transaction No.", TransactionHeader."Transaction No.");
        LscTransSalesEntry.SetFilter("LSEF Tax Indicator", '<>%1', LscTransSalesEntry."LSEF Tax Indicator"::"Exento (E)");
        if LscTransSalesEntry.FindSet() then begin
            LscTransSalesEntry.CalcSums("Net Amount");
            MontoGrabadoTotal := Abs(LscTransSalesEntry."Net Amount");
        end;

        EFEncabezado.MontoGravadoTotal := Abs(MontoGrabadoTotal) / CurrencyFactor;

        clear(LscTransSalesEntry);
        LscTransSalesEntry.SetCurrentKey("Store No.", "POS Terminal No.", "Transaction No.");
        LscTransSalesEntry.SetRange("Store No.", TransactionHeader."Store No.");
        LscTransSalesEntry.SetRange("POS Terminal No.", TransactionHeader."POS Terminal No.");
        LscTransSalesEntry.SetRange("Transaction No.", TransactionHeader."Transaction No.");
        if LscTransSalesEntry.FindSet() then
            repeat
                if VatPostingSetup.Get(LscTransSalesEntry."VAT Bus. Posting Group", LscTransSalesEntry."VAT Prod. Posting Group") then;

                case LscTransSalesEntry."LSEF Tax Indicator" of
                    LscTransSalesEntry."LSEF Tax Indicator"::"ITBIS 1 (18%)":
                        begin
                            HasItbis1Lines := true;
                            MontoGrabado1 += Abs(LscTransSalesEntry."Net Amount");
                            Itbis1 := Abs(VatPostingSetup."VAT %");
                            TotalItbis1 += Abs(LscTransSalesEntry."VAT Amount");
                        end;
                    LscTransSalesEntry."LSEF Tax Indicator"::"ITBIS 2 (16%)":
                        begin
                            HasItbis2Lines := true;
                            MontoGrabado2 += Abs(LscTransSalesEntry."Net Amount");
                            Itbis2 := Abs(VatPostingSetup."VAT %");
                            TotalItbis2 += Abs(LscTransSalesEntry."VAT Amount");
                        end;
                    LscTransSalesEntry."LSEF Tax Indicator"::"ITBIS 3 (0%)":
                        begin
                            HasItbis3Lines := true;
                            MontoGrabado3 += Abs(LscTransSalesEntry."Net Amount");
                            Itbis3 := Abs(VatPostingSetup."VAT %");
                            TotalItbis3 += Abs(LscTransSalesEntry."VAT Amount");
                        end;
                    LscTransSalesEntry."LSEF Tax Indicator"::"Exento (E)":
                        begin
                            HasExentoLines := true;
                            MontoExento += Abs(LscTransSalesEntry."Net Amount");
                        end;
                end;
            until LscTransSalesEntry.Next() = 0;

        // Asignar montos gravados si existen líneas con ese indicador (incluso si el monto es 0)
        if HasItbis1Lines then begin
            EFEncabezado.MontoGravadoI1 := Abs(MontoGrabado1) / CurrencyFactor;
            EFEncabezado.ITBIS1 := Abs(Itbis1);
            EFEncabezado.TotalITBIS1 := Abs(TotalItbis1) / CurrencyFactor;
        end;
        if HasItbis2Lines then begin
            EFEncabezado.MontoGravadoI2 := Abs(MontoGrabado2) / CurrencyFactor;
            EFEncabezado.ITBIS2 := Abs(Itbis2);
            EFEncabezado.TotalITBIS2 := Abs(TotalItbis2) / CurrencyFactor;
        end;
        if HasItbis3Lines then begin
            EFEncabezado.MontoGravadoI3 := Abs(MontoGrabado3) / CurrencyFactor;
            EFEncabezado.ITBIS3 := Abs(Itbis3);
            EFEncabezado.TotalITBIS3 := Abs(TotalItbis3) / CurrencyFactor;
        end;
        if HasExentoLines then
            EFEncabezado.MontoExento := Abs(MontoExento) / CurrencyFactor;
        // Calcular total ITBIS solo si hay líneas gravadas
        if HasItbis1Lines or HasItbis2Lines or HasItbis3Lines then
            EFEncabezado.TotalITBIS := Abs((TotalItbis1) + TotalItbis2 + TotalItbis3) / CurrencyFactor;

        // Asignar flags booleanos para soportar montos 0 en devoluciones
        EFEncabezado.HasItbis1Lines := HasItbis1Lines;
        EFEncabezado.HasItbis2Lines := HasItbis2Lines;
        EFEncabezado.HasItbis3Lines := HasItbis3Lines;
        EFEncabezado.HasExentoLines := HasExentoLines;

        EFEncabezado.MontoImpuestoAdicional := 0;

        if TransactionHeader."LSEF Applies for ISC" then begin
            Clear(LscTransSalesEntry);
            LscTransSalesEntry.SetCurrentKey("Store No.", "POS Terminal No.", "Transaction No.");
            LscTransSalesEntry.SetRange("Store No.", TransactionHeader."Store No.");
            LscTransSalesEntry.SetRange("POS Terminal No.", TransactionHeader."POS Terminal No.");
            LscTransSalesEntry.SetRange("Transaction No.", TransactionHeader."Transaction No.");
            LscTransSalesEntry.SetRange("LSEF Applies for ISC", true);
            if LscTransSalesEntry.Find('-') then
                repeat
                    Clear(Item);
                    if Item.Get(LscTransSalesEntry."Item No.") then begin
                        clear(EFImpAdicionalesEncab);
                        EFImpAdicionalesEncab.DocumentNo := EFEncabezado.DocumentNo;
                        EFImpAdicionalesEncab.TipoImpuesto := Item."EF Tax Type";
                        EFImpAdicionalesEncab.TasaImpuestoAdicional := Abs(0) / CurrencyFactor;
                        EFImpAdicionalesEncab.MontoImpSelecConsumoEspecifico := Abs(0) / CurrencyFactor;
                        EFImpAdicionalesEncab.MontoImpSelConsumoAdvalorem := Abs(0) / CurrencyFactor;
                        EFImpAdicionalesEncab.OtrosImpuestosAdicionales := Abs(0) / CurrencyFactor;

                        // En Divisa
                        EFImpAdicionalesEncab.TipoImpuestoOtraMoneda := Item."EF Tax Type";
                        EFImpAdicionalesEncab.TasaImpuestoAdicionalOMoneda := Abs(0);
                        EFImpAdicionalesEncab.MontoImpSelecConsumoEspOMoneda := Abs(0);
                        EFImpAdicionalesEncab.MontoImpSelConsumoAdOtraMoneda := Abs(0);
                        EFImpAdicionalesEncab.OtrosImpuestosAdicionalOMoneda := Abs(0);
                        EFImpAdicionalesEncab.Insert(true);
                    end;
                until LscTransSalesEntry.Next() = 0;
        end;

        MontoTotal := Abs((MontoGrabadoTotal + MontoExento + (TotalItbis1 + TotalItbis2 + TotalItbis3)));
        EFEncabezado.MontoTotal := Abs(MontoTotal) / CurrencyFactor;

        Clear(LscTransSalesEntry);
        LscTransSalesEntry.SetCurrentKey("Store No.", "POS Terminal No.", "Transaction No.");
        LscTransSalesEntry.SetRange("Store No.", TransactionHeader."Store No.");
        LscTransSalesEntry.SetRange("POS Terminal No.", TransactionHeader."POS Terminal No.");
        LscTransSalesEntry.SetRange("Transaction No.", TransactionHeader."Transaction No.");
        LscTransSalesEntry.SetRange("Net Amount", 0);
        if LscTransSalesEntry.Find('-') then
            repeat
                Clear(Item);
                if Item.Get(LscTransSalesEntry."Item No.") then
                    NoInvoiceAmount += Abs(Item."Unit Price") * Abs(LscTransSalesEntry.Quantity);
            until LscTransSalesEntry.Next() = 0;

        EFEncabezado.MontoNoFacturable := Abs(NoInvoiceAmount) / CurrencyFactor;
        PeriodAmount := Abs(MontoTotal + NoInvoiceAmount);
        EFEncabezado.MontoPeriodo := Abs(PeriodAmount) / CurrencyFactor;
        EFEncabezado.SaldoAnterior := Abs(0);
        EFEncabezado.MontoAvancePago := Abs(0);
        ValuePayable := Abs(MontoTotal + EFEncabezado.MontoAvancePago);
        EFEncabezado.ValorPagar := Abs(ValuePayable) / CurrencyFactor;

        //Otra Moneda Area
        if TransactionHeader."Trans. Currency" <> '' then begin

            if Currency.Get(TransactionHeader."Trans. Currency") then;

            EFEncabezado.TipoMoneda := Currency."EF Currency Type";
            //EFEncabezado.TipoCambio := 1 / CurrencyFactorOriginal; // EF-VOXEL
            //T20250610.0007 -
            if (Setup.Provider = Setup.Provider::Voxel) then
                EFEncabezado.TipoCambio := 1 // EF-VOXEL
            else
                EFEncabezado.TipoCambio := 1;
            //T20250610.0007 + 
            EFEncabezado.MontoGravadoTotalOtraMoneda := Abs(MontoGrabadoTotal);
            EFEncabezado.MontoGravado1OtraMoneda := Abs(MontoGrabado1);
            EFEncabezado.MontoGravado2OtraMoneda := Abs(MontoGrabado2);
            EFEncabezado.MontoGravado3OtraMoneda := Abs(MontoGrabado3);
            EFEncabezado.MontoExentoOtraMoneda := Abs(MontoExento);

            VatAmountTotalAnotherCurrency := Abs(TotalItbis1 + TotalItbis2 + TotalItbis3);
            EFEncabezado.TotalITBISOtraMoneda := Abs(VatAmountTotalAnotherCurrency);
            EFEncabezado.TotalITBIS1OtraMoneda := Abs(TotalItbis1);
            EFEncabezado.TotalITBIS2OtraMoneda := Abs(TotalItbis2);
            EFEncabezado.TotalITBIS3OtraMoneda := Abs(TotalItbis3);
            EFEncabezado.MontoTotalOtraMoneda := Abs(MontoTotal);
        end;

        //T20250512.0009 - VOXEL MANEJA LA MONEDA COMO CODIGO Y NO POR ID
        if Setup.Provider = Setup.Provider::Voxel then BEGIN
            If EFEncabezado.TipoMoneda = '13' then begin
                EFEncabezado.TipoMoneda := 'DOP'; // EF-VOXEL
            end;
        END;
        EFEncabezado.TipoMoneda := '';
        //T20250512.0009 + VOXEL MANEJA LA MONEDA COMO CODIGO Y NO POR ID

        Clear(LscTransSalesEntry);
        LscTransSalesEntry.SetCurrentKey("Store No.", "POS Terminal No.", "Transaction No.");
        LscTransSalesEntry.SetRange("Store No.", TransactionHeader."Store No.");
        LscTransSalesEntry.SetRange("POS Terminal No.", TransactionHeader."POS Terminal No.");
        LscTransSalesEntry.SetRange("Transaction No.", TransactionHeader."Transaction No.");
        ItemLines := 0;
        if LscTransSalesEntry.Find('-') then
            repeat
                Clear(Item);
                if Item.Get(LscTransSalesEntry."Item No.") then;
                clear(EFDetalleBienesoServicios);
                ItemLines += 1;
                EFDetalleBienesoServicios.DocumentNo := EFEncabezado.DocumentNo;
                EFDetalleBienesoServicios.DocumentLineNo := LscTransSalesEntry."Line No.";
                EFDetalleBienesoServicios.NumeroLinea := ItemLines;


                // EF-Voxel
                IF LscTransSalesEntry."Net Amount" <> 0 THEN begin
                    vatPostingSetup.reset();
                    if vatPostingSetup.Get(LscTransSalesEntry."VAT Bus. Posting Group", LscTransSalesEntry."VAT Prod. Posting Group") then
                        EFDetalleBienesoServicios."% ITBIS" := vatPostingSetup."VAT %";
                end;
                EFDetalleBienesoServicios.SupplierSKU := LscTransSalesEntry."Item No.";
                if ABS(LscTransSalesEntry."Discount Amount") <> 0 then begin
                    if (LscTransSalesEntry.Quantity <> 0) and (LscTransSalesEntry.Price <> 0) then
                        EFDetalleBienesoServicios."% Descuento" := ABS(((ABS(LscTransSalesEntry."Discount Amount") / LscTransSalesEntry.Quantity) / LscTransSalesEntry.Price) * 100)
                    else
                        EFDetalleBienesoServicios."% Descuento" := 0;
                end else
                    EFDetalleBienesoServicios."% Descuento" := 0;
                // EF-Voxel

                // CODIGOS ITEMS
                clear(EFCodigosItem);
                EFCodigosItem.DocumentNo := EFEncabezado.DocumentNo;
                EFCodigosItem.DocumentLineNo := EFDetalleBienesoServicios.DocumentLineNo;
                EFCodigosItem.CodigoItem := LscTransSalesEntry."Item No.";
                EFCodigosItem.TipoCodigo := 'Interna';
                EFCodigosItem.Insert(true);
                EFDetalleBienesoServicios."EF Inv. Tax Indicator" := LscTransSalesEntry."LSEF Tax Indicator";
                EFDetalleBienesoServicios.IndicadorFacturacion := LscTransSalesEntry."LSEF Tax Indicator".AsInteger();
                EFDetalleBienesoServicios."EF Inv. Tax Indicator" := LscTransSalesEntry."LSEF Tax Indicator";
                if not (EFDetalleBienesoServicios."EF Inv. Tax Indicator" in [Enum::"EF Invoice Tax Indicator Type"::"Exento (E)", Enum::"EF Invoice Tax Indicator Type"::"ITBIS 1 (18%)", Enum::"EF Invoice Tax Indicator Type"::"ITBIS 2 (16%)", Enum::"EF Invoice Tax Indicator Type"::"ITBIS 3 (0%)"]) then
                    EFDetalleBienesoServicios."EF Inv. Tax Indicator" := VatPostingSetup."EF Tax Indicator";

                EFDetalleBienesoServicios.TestField("EF Inv. Tax Indicator");
                EFDetalleBienesoServicios.NombreItem := CopyStr(Item.Description, 1, MaxStrLen(EFDetalleBienesoServicios.NombreItem));
                if Item.Type = "Item Type"::Inventory then
                    IndicadorBienoServicioValue := Format(1)
                else
                    IndicadorBienoServicioValue := Format(2);
                EFDetalleBienesoServicios.IndicadorBienoServicio := IndicadorBienoServicioValue;
                EFDetalleBienesoServicios.DescripcionItem := Item."Description 2";
                EFDetalleBienesoServicios.CantidadItem := Abs(LscTransSalesEntry.Quantity);
                EFDetalleBienesoServicios.UnidadMedida := LscTransSalesEntry."LSEF UOM Type";
                EFDetalleBienesoServicios.NetAmount := Abs(LscTransSalesEntry."Net Amount") / CurrencyFactor;
                EFDetalleBienesoServicios.VatAmount := Abs(LscTransSalesEntry."VAT Amount") / CurrencyFactor;

                if LscTransSalesEntry."LSEF Applies for ISC" then begin
                    EFDetalleBienesoServicios.CantidadReferencia := 0;
                    EFDetalleBienesoServicios.UnidadReferencia := '';

                    // TablaSubcantidad
                    // ESTA AREA NO ESTA IMPLEMENTADA
                    clear(EFSubcantidad);
                    EFSubcantidad.Init();
                    EFSubcantidad.DocumentNo := EFEncabezado.DocumentNo;
                    EFSubcantidad.DocumentLineNo := EFDetalleBienesoServicios.DocumentLineNo;
                    EFSubcantidad.Insert(true);

                    EFDetalleBienesoServicios.GradosAlcohol := 0;
                    EFDetalleBienesoServicios.PrecioUnitarioReferencia := 0;

                end;

                EFDetalleBienesoServicios.PrecioUnitarioItem := Abs(LscTransSalesEntry."Net Price") / CurrencyFactor;

                if (Abs(LscTransSalesEntry."Discount Amount") > 0) then begin


                    EFDetalleBienesoServicios.DescuentoMonto := Abs(LscTransSalesEntry."Discount Amount") / CurrencyFactor;

                    clear(EFSubDescuento);
                    EFSubDescuento.DocumentNo := EFDetalleBienesoServicios.DocumentNo;
                    EFSubDescuento.DocumentLineNo := EFDetalleBienesoServicios.DocumentLineNo;
                    EFSubDescuento.TipoSubDescuento := '$';
                    EFSubDescuento.SubDescuentoPorcentaje := 0;
                    EFSubDescuento.MontoSubDescuento := Abs(LscTransSalesEntry."Discount Amount") / CurrencyFactor;
                    EFSubDescuento.Insert(true);
                end;

                // Tabla SubRecargo
                // clear(EFSubRecargo);
                // EFSubRecargo.Init();
                // EFSubRecargo.DocumentNo := EFEncabezado.DocumentNo;
                // EFSubRecargo.Insert(true);

                // Tabla Impuesto Adicional
                if LscTransSalesEntry."LSEF Applies for ISC" then begin
                    clear(EFImpuestosAdicionalesDBS);
                    EFImpuestosAdicionalesDBS.DocumentNo := EFDetalleBienesoServicios.DocumentNo;
                    EFImpuestosAdicionalesDBS.DocumentLineNo := EFDetalleBienesoServicios.DocumentLineNo;
                    EFImpuestosAdicionalesDBS.Init();
                    EFImpuestosAdicionalesDBS.Insert(true);
                end;

                if TransactionHeader."Trans. Currency" <> '' then begin
                    EFDetalleBienesoServicios.PrecioOtraMoneda := Abs(LscTransSalesEntry.Price);
                    EFDetalleBienesoServicios.DescuentoOtraMoneda := Abs(LscTransSalesEntry."Discount Amount");
                    EFDetalleBienesoServicios.RecargoOtraMoneda := Abs(0);
                    EFDetalleBienesoServicios.MontoItemOtraMoneda := Abs(LscTransSalesEntry."Net Amount");
                end;

                EFDetalleBienesoServicios.MontoItem := Abs(LscTransSalesEntry."Net Amount") / CurrencyFactor;
                EFDetalleBienesoServicios.Insert(true);
            until LscTransSalesEntry.Next() = 0;

        clear(EFSubTotalesInformativos);
        EFSubTotalesInformativos.DocumentNo := EFEncabezado.DocumentNo;
        EFSubTotalesInformativos.NumeroSubTotal := 1;
        EFSubTotalesInformativos.DescripcionSubtotal := 'Montos Factura';
        EFSubTotalesInformativos.Orden := 1;

        EFSubTotalesInformativos.SubTotalMontoGravadoTotal := Abs((MontoGrabado1 + MontoGrabado2 + MontoGrabado3)) / CurrencyFactor;
        EFSubTotalesInformativos.SubTotalMontoGravadoI1 := Abs(MontoGrabado1) / CurrencyFactor;
        EFSubTotalesInformativos.SubTotalMontoGravadoI2 := Abs(MontoGrabado2) / CurrencyFactor;
        EFSubTotalesInformativos.SubTotalMontoGravadoI3 := Abs(MontoGrabado3) / CurrencyFactor;
        EFSubTotalesInformativos.SubTotaITBIS := Abs((TotalItbis1 + TotalItbis2 + TotalItbis3)) / CurrencyFactor;
        EFSubTotalesInformativos.SubTotaITBIS1 := Abs(TotalItbis1) / CurrencyFactor;
        EFSubTotalesInformativos.SubTotaITBIS2 := Abs(TotalItbis2) / CurrencyFactor;
        EFSubTotalesInformativos.SubTotaITBIS3 := Abs(TotalItbis3) / CurrencyFactor;

        EFSubTotalesInformativos.SubTotalImpuestoAdicional := 0;

        EFSubTotalesInformativos.SubTotalExento := Abs(MontoExento) / CurrencyFactor;
        EFSubTotalesInformativos.MontoSubTotal := Abs(((MontoGrabado1 + MontoGrabado2 + MontoGrabado3) + (TotalItbis1 + TotalItbis2 + TotalItbis3) + MontoExento)) / CurrencyFactor;
        EFSubTotalesInformativos.Lineas := 1;
        EFSubTotalesInformativos.Insert(true);

        //Area Descuento Recargos
        // clear(EFDescuentosORecargos);
        // EFDescuentosORecargos.Init();
        // EFDescuentosORecargos.DocumentNo := EFEncabezado.DocumentNo;
        // EFDescuentosORecargos.Insert(true);

        // Area Paginacion
        clear(EFPaginacion);
        EFPaginacion.DocumentNo := EFEncabezado.DocumentNo;
        EFPaginacion.Init();
        EFPaginacion.Insert(true);

        //Area Informacion Referencia
        if CreditMemoNCF <> '' then begin
            Clear(EFInformacionReferencia);
            EFInformacionReferencia.DocumentNo := EFEncabezado.DocumentNo;
            EFInformacionReferencia.NCFModificado := CopyStr(TransactionHeader."LSDX NCF", 1, MaxStrLen(EFInformacionReferencia.NCFModificado));
            EFInformacionReferencia.RNCOtroContribuyente := '';

            EFInformacionReferencia.RazonModificacion := '';

            EFInformacionReferencia.FechaNCFModificado := TransactionHeader.Date;
            EFInformacionReferencia.CodigoModificacion := Setup."LSEF Def. NC Modification Type";

            // EF - VOXEL
            EFInformacionReferencia.AffectedDocumentNo := TransactionHeader."Receipt No.";
            EFInformacionReferencia."TASA Cambio" := 1;
            // EF - VOXEL
        end;

        EFInformacionReferencia.Insert(true);

        EFEncabezado.Insert(true);

        exit(true);

    end;

}
