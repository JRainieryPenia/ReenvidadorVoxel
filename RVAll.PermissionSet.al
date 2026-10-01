permissionset 51100 "RV All"
{
    Assignable = true;
    Caption = 'Reenvidador Voxel - All';

    Permissions =
        table "RV Transaction Header" = X,
        tabledata "RV Transaction Header" = RIMD,
        codeunit "RV Resent Management" = X,
        codeunit "RV Replacement Upgrade" = X,
        codeunit "RV Voxel Tax XML" = X,
        codeunit "RV Excel Import" = X,
        codeunit "My Debug" = X,
        page "RV Transaction Register" = X,
        page "RV Replace NCF" = X,
        codeunit "RV NCF Log Mgt" = X,
        page "RV NCF Log" = X,
        table "RV NCF Log" = X,
        tabledata "RV NCF Log" = RIMD,
        tabledata "LSC Transaction Header" = RM,
        tabledata "EF Archived Sent Request" = RD,
        tabledata "EF Administration Setup" = R,
        tabledata "LSC POS Terminal" = R,
        tabledata "LSC Store" = R;
}
