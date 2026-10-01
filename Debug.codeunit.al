codeunit 51149 "My Debug"
{
    Permissions = tabledata "Activity Log" = RIDM;
    trigger OnRun()
    begin

    end;

    var
        myInt: Integer;

    [EventSubscriber(ObjectType::Table, Database::"LSC POS Trans. Line", 'OnAfterInsertLine', '', false, false)]
    local procedure Debug(var POSTransaction: Record "LSC POS Transaction"; var Rec: Record "LSC POS Trans. Line")
    var
        ActivityLog: Record "Activity Log";
        RecordCount: Integer;
        LastError: Text;
    begin
        LastError := GetLastErrorText();
        Clear(ActivityLog);

        ActivityLog.Init();
        ActivityLog."Record ID" := POSTransaction.RecordId;
        ActivityLog."Activity Date" := CreateDateTime(Today(), Time());
        ActivityLog."Activity Message" := CopyStr(LastError, 1, 250);
        ActivityLog.Insert();
    end;
}