page 51101 "RV Replace NCF"
{
    PageType = StandardDialog;
    Caption = 'Reemplazar NCF';

    layout
    {
        area(Content)
        {
            field(SeriesCode; SeriesCode)
            {
                ApplicationArea = All;
                Caption = 'Serie de NCF';
                TableRelation = "No. Series".Code;
                ToolTip = 'Especifica la serie que asignará los nuevos NCF a las transacciones seleccionadas.';
            }
        }
    }

    var
        SeriesCode: Code[20];

    procedure GetSeriesCode(): Code[20]
    begin
        exit(SeriesCode);
    end;
}
