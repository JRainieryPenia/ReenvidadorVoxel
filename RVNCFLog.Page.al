page 51102 "RV NCF Log"
{
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    Caption = 'RV NCF Log';
    SourceTable = "RV NCF Log";
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Log)
            {
                field("Receipt No."; Rec."Receipt No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Receipt number of the POS transaction.';
                }
                field("Old NCF"; Rec."Old NCF")
                {
                    ApplicationArea = All;
                    ToolTip = 'NCF before the replacement.';
                }
                field("Replacement NCF"; Rec."Replacement NCF")
                {
                    ApplicationArea = All;
                    ToolTip = 'NCF assigned by the replacement.';
                }
                field("Credit Memo NCF"; Rec."Credit Memo NCF")
                {
                    ApplicationArea = All;
                    ToolTip = 'E34 credit memo that voided the original NCF.';
                }
                field("Affected NCF"; Rec."Affected NCF")
                {
                    ApplicationArea = All;
                    ToolTip = 'NCF that the credit memo affected.';
                }
                field("Current NCF"; Rec."Current NCF")
                {
                    ApplicationArea = All;
                    ToolTip = 'NCF currently on the transaction.';
                }
                field("Transaction Date"; Rec."Transaction Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Date of the POS transaction.';
                }
                field("Store No."; Rec."Store No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Store number.';
                }
                field("POS Terminal No."; Rec."POS Terminal No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'POS terminal number.';
                }
                field("Transaction No."; Rec."Transaction No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Transaction number.';
                }
                field("Replacement Logged At"; Rec."Replacement Logged At")
                {
                    ApplicationArea = All;
                    ToolTip = 'When the replacement was first logged.';
                }
                field("Credit Memo Logged At"; Rec."Credit Memo Logged At")
                {
                    ApplicationArea = All;
                    ToolTip = 'When the credit memo was first logged.';
                }
                field("User ID"; Rec."User ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'User who last updated the entry.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ExportToFile)
            {
                Caption = 'Export for Excel';
                ToolTip = 'Exports the filtered log (tab-delimited, opens in Excel) to reconcile replacements and E34 credit memos.';
                Image = ExportToExcel;
                ApplicationArea = All;

                trigger OnAction()
                var
                    NCFLog: Record "RV NCF Log";
                    NCFLogMgt: Codeunit "RV NCF Log Mgt";
                begin
                    NCFLog.CopyFilters(Rec);
                    NCFLogMgt.ExportToFile(NCFLog);
                end;
            }
        }
    }
}
