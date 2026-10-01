tableextension 51100 "RV Transaction Header Ext" extends "LSC Transaction Header"
{
    fields
    {
        field(51104; "NCF Replacement Done"; Boolean)
        {
            Caption = 'NCF reemplazado (marca)';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(51102; "NCF antiguo"; Code[20])
        {
            Caption = 'NCF antiguo';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(51103; "NCF Reemplazado"; Code[20])
        {
            Caption = 'NCF Reemplazado';
            DataClassification = CustomerContent;
            Editable = false;
        }
        // Add changes to table fields here
        field(51100; "NCF Void Credit Memo"; Code[20])
        {
            FieldClass = FlowField;
            CalcFormula = lookup("RV Transaction Header"."Voided NCF Credit Memo" where(
                "Transaction No." = field("Transaction No."),
                "Store No." = field("Store No."),
                "POS Terminal No." = field("POS Terminal No."),
                "Receipt No." = field("Receipt No.")
             ));
            Caption = 'Voided NCF Credit Memo';
            Description = 'NCF of the credit memo generated when voiding a transaction.';
        }
        //Voided NCF
        field(51101; "Voided NCF"; Code[20])
        {
            FieldClass = FlowField;
            CalcFormula = lookup("RV Transaction Header"."Voided NCF" where(
                "Transaction No." = field("Transaction No."),
                "Store No." = field("Store No."),
                "POS Terminal No." = field("POS Terminal No."),
                "Receipt No." = field("Receipt No.")
             ));
            Caption = 'Voided NCF';
            Description = 'NCF of the transaction that was voided.';
        }
    }

    keys
    {
        // Add changes to keys here
    }

    fieldgroups
    {
        // Add changes to field groups here
    }

    var
        myInt: Integer;
}
