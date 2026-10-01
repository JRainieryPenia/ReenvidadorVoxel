codeunit 51101 "RV Replacement Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerCompany()
    var
        TransactionHeader: Record "LSC Transaction Header";
    begin
        TransactionHeader.SetRange("NCF Replacement Done", false);
        TransactionHeader.SetFilter("NCF antiguo", '<>%1', '');
        TransactionHeader.SetFilter("NCF Reemplazado", '<>%1', '');
        if TransactionHeader.FindSet(true) then
            repeat
                if TransactionHeader."LSDX NCF" = TransactionHeader."NCF Reemplazado" then begin
                    TransactionHeader."NCF Replacement Done" := true;
                    TransactionHeader.Modify(false);
                end;
            until TransactionHeader.Next() = 0;
    end;
}
