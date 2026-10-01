table 51101 "RV NCF Log"
{
    Caption = 'RV NCF Log';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Store No."; Code[10])
        {
            Caption = 'Store No.';
        }
        field(2; "POS Terminal No."; Code[10])
        {
            Caption = 'POS Terminal No.';
        }
        field(3; "Transaction No."; Integer)
        {
            Caption = 'Transaction No.';
        }
        field(10; "Receipt No."; Code[20])
        {
            Caption = 'Receipt No.';
        }
        field(11; "Transaction Date"; Date)
        {
            Caption = 'Transaction Date';
        }
        field(20; "Old NCF"; Code[20])
        {
            Caption = 'Old NCF';
        }
        field(21; "Replacement NCF"; Code[20])
        {
            Caption = 'Replacement NCF';
        }
        field(22; "Current NCF"; Code[20])
        {
            Caption = 'Current NCF';
        }
        field(30; "Credit Memo NCF"; Code[20])
        {
            Caption = 'Credit Memo NCF (E34)';
        }
        field(31; "Affected NCF"; Code[20])
        {
            Caption = 'NCF Affected by Credit Memo';
        }
        field(40; "Replacement Logged At"; DateTime)
        {
            Caption = 'Replacement Logged At';
        }
        field(41; "Credit Memo Logged At"; DateTime)
        {
            Caption = 'Credit Memo Logged At';
        }
        field(50; "Last Updated At"; DateTime)
        {
            Caption = 'Last Updated At';
        }
        field(51; "User ID"; Code[50])
        {
            Caption = 'User ID';
        }
    }

    keys
    {
        key(Key1; "Store No.", "POS Terminal No.", "Transaction No.")
        {
            Clustered = true;
        }
        key(Key2; "Receipt No.")
        {
        }
        key(Key3; "Credit Memo NCF")
        {
        }
        key(Key4; "Old NCF")
        {
        }
    }
}
