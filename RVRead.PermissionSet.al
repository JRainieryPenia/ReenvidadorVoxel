permissionset 51101 "RV Read"
{
    Assignable = true;
    Caption = 'Reenvidador Voxel - Read';

    Permissions =
        table "RV Transaction Header" = X,
        tabledata "RV Transaction Header" = R,
        page "RV Transaction Register" = X,
        page "RV NCF Log" = X,
        table "RV NCF Log" = X,
        tabledata "RV NCF Log" = R,
        tabledata "LSC Transaction Header" = R,
        tabledata "EF Archived Sent Request" = R,
        tabledata "EF Administration Setup" = R,
        tabledata "LSC POS Terminal" = R,
        tabledata "LSC Store" = R;
}
